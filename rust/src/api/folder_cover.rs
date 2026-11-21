//! Local artwork fallback. Discovery never modifies audio or image files.
use super::*;
use sha2::{Digest, Sha256};
use std::collections::HashSet;

const NAMES: &[&str] = &[
    "cover",
    "folder",
    "front",
    "frontcover",
    "album",
    "albumcover",
    "albumart",
    "coverart",
    "artwork",
    "art",
];
const EXTENSIONS: &[&str] = &["jpg", "jpeg", "png", "webp", "bmp", "gif"];
const MAX_BYTES: u64 = 20 * 1024 * 1024;
const MAX_WMP_SCAN_ENTRIES: usize = 2048;

fn is_supported_image_extension(extension: &str) -> bool {
    EXTENSIONS
        .iter()
        .any(|ext| extension.eq_ignore_ascii_case(ext))
}

fn is_wmp_large_cover_stem(stem: &str) -> bool {
    let lower = stem.to_ascii_lowercase();
    lower.starts_with("albumart_") && lower.ends_with("_large")
}

fn is_named_cover_stem(stem: &str) -> bool {
    NAMES.iter().any(|name| stem.eq_ignore_ascii_case(name))
        || is_wmp_large_cover_stem(stem)
}

fn candidate_name(path: &Path, audio_stems: &HashSet<String>) -> bool {
    let extension = path.extension().unwrap_or_default().to_string_lossy();
    if !is_supported_image_extension(&extension) {
        return false;
    }
    let stem = path.file_stem().unwrap_or_default().to_string_lossy();
    if stem.is_empty() {
        return false;
    }
    if is_named_cover_stem(&stem) {
        return true;
    }
    audio_stems.contains(&stem.to_lowercase())
}

fn regular_metadata(path: &Path) -> Option<fs::Metadata> {
    let metadata = fs::symlink_metadata(path).ok()?;
    if !metadata.is_file() {
        return None;
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        // Do not follow image symlinks, cloud placeholders or other reparse points.
        if metadata.file_attributes() & 0x400 != 0 {
            return None;
        }
    }
    Some(metadata)
}

fn decode_candidate(candidate: &Path, width: u32, height: u32) -> Option<Vec<u8>> {
    let metadata = regular_metadata(candidate)?;
    if metadata.len() == 0 || metadata.len() > MAX_BYTES {
        return None;
    }
    let file = fs::File::open(candidate).ok()?;
    let mut bytes = Vec::new();
    if file.take(MAX_BYTES + 1).read_to_end(&mut bytes).is_err()
        || bytes.len() as u64 > MAX_BYTES
    {
        return None;
    }
    resize_picture(&bytes, width, height)
}

/// The scanner already enumerated this directory. Stat only named artwork and
/// track-stem sidecars, once per directory, without decoding images or
/// rereading unchanged tags.
pub(super) fn stamp(entries: &[fs::DirEntry]) -> Option<String> {
    let mut audio_stems = HashSet::new();
    for entry in entries {
        let path = entry.path();
        let ext = path
            .extension()
            .unwrap_or_default()
            .to_string_lossy()
            .to_ascii_lowercase();
        if SUPPORT_FORMAT.contains_key(ext.as_str()) {
            let stem = path.file_stem().unwrap_or_default().to_string_lossy();
            if !stem.is_empty() {
                audio_stems.insert(stem.to_lowercase());
            }
        }
    }
    let mut records = Vec::new();
    for entry in entries {
        let path = entry.path();
        if !candidate_name(&path, &audio_stems) {
            continue;
        }
        let Some(metadata) = regular_metadata(&path) else {
            continue;
        };
        let Ok(modified) = metadata.modified() else {
            continue;
        };
        records.push((
            entry.file_name().to_string_lossy().to_lowercase(),
            metadata.len(),
            modified
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos(),
        ));
    }
    if records.is_empty() {
        return None;
    }
    records.sort();
    let bytes = serde_json::to_vec(&records).ok()?;
    Some(format!("{:x}", Sha256::digest(bytes)))
}

/// Fixed candidate priority and bounded bytes; a damaged preferred image does
/// not hide a valid later candidate. Existing embedded artwork stays first.
///
/// Order: exact per-track sidecar (`<track>.<ext>`) -> ordered front-cover
/// names (`cover`, `folder`, `front`, `frontcover`, `album`, `albumcover`,
/// `albumart`, `coverart`, `artwork`, `art`) -> Windows Media Player
/// `AlbumArt_{...}_Large.<ext>`. Non-front scans (back, booklet, obi, disc,
/// small thumbnails) are never picked as album covers.
pub(super) fn picture(audio: &Path, width: u32, height: u32) -> Option<Vec<u8>> {
    if !audio.is_file() {
        return None;
    }
    let directory = audio.parent()?;
    if let Some(stem) = audio.file_stem().and_then(|s| s.to_str()) {
        if !stem.is_empty() {
            for extension in EXTENSIONS {
                let candidate = directory.join(format!("{stem}.{extension}"));
                if let Some(picture) = decode_candidate(&candidate, width, height) {
                    return Some(picture);
                }
            }
        }
    }
    for name in NAMES {
        for extension in EXTENSIONS {
            let candidate = directory.join(format!("{name}.{extension}"));
            if let Some(picture) = decode_candidate(&candidate, width, height) {
                return Some(picture);
            }
        }
    }
    // Bounded read-only fallback for Windows Media Player large artwork files.
    let Ok(read_dir) = fs::read_dir(directory) else {
        return None;
    };
    let mut wmp_candidates = Vec::new();
    for entry in read_dir.take(MAX_WMP_SCAN_ENTRIES).flatten() {
        let path = entry.path();
        let ext = path.extension().unwrap_or_default().to_string_lossy();
        if !is_supported_image_extension(&ext) {
            continue;
        }
        let stem = path.file_stem().unwrap_or_default().to_string_lossy();
        if is_wmp_large_cover_stem(&stem) {
            wmp_candidates.push(path);
        }
    }
    wmp_candidates.sort();
    for candidate in wmp_candidates {
        if let Some(picture) = decode_candidate(&candidate, width, height) {
            return Some(picture);
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    fn solid_png(color: [u8; 4]) -> Vec<u8> {
        let pixels = image::RgbaImage::from_pixel(6, 6, image::Rgba(color));
        let mut output = Cursor::new(Vec::new());
        image::DynamicImage::ImageRgba8(pixels)
            .write_to(&mut output, image::ImageFormat::Png)
            .unwrap();
        output.into_inner()
    }

    fn first_pixel(encoded: &[u8]) -> [u8; 4] {
        image::load_from_memory(encoded)
            .unwrap()
            .to_rgba8()
            .get_pixel(0, 0)
            .0
    }

    #[test]
    fn extended_front_covers_track_sidecar_and_wmp_large_work_while_rejecting_back_scans() {
        let nonce = std::time::SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!(
            "dan_player_folder_cover_s2_{}_{}",
            std::process::id(),
            nonce
        ));
        fs::create_dir_all(&dir).unwrap();
        let track = dir.join("01 Night Drive.wav");
        fs::write(&track, b"RIFF\x00\x00\x00\x00WAVE").unwrap();

        let green = solid_png([0, 200, 0, 255]);
        let blue = solid_png([0, 0, 220, 255]);
        let yellow = solid_png([240, 220, 0, 255]);
        let red = solid_png([220, 0, 0, 255]);

        // Non-front scans and WMP Small thumbnails must never be picked.
        fs::write(dir.join("back.png"), &red).unwrap();
        fs::write(dir.join("booklet.png"), &red).unwrap();
        fs::write(dir.join("obi.png"), &red).unwrap();
        fs::write(dir.join("AlbumArt_{1234}_Small.png"), &red).unwrap();
        assert!(picture(&track, 32, 32).is_none());
        let entries_before: Vec<_> = fs::read_dir(&dir).unwrap().flatten().collect();
        assert!(stamp(&entries_before).is_none());

        // WMP Large cover works as fallback when no front cover exists.
        fs::write(dir.join("AlbumArt_{1234}_Large.png"), &yellow).unwrap();
        let selected = picture(&track, 32, 32).unwrap();
        assert_eq!(first_pixel(&selected), [240, 220, 0, 255]);
        let entries_wmp: Vec<_> = fs::read_dir(&dir).unwrap().flatten().collect();
        let stamp_wmp = stamp(&entries_wmp);
        assert!(stamp_wmp.is_some());

        // Expanded front-cover name (`artwork.png`) wins over WMP Large.
        fs::write(dir.join("artwork.png"), &blue).unwrap();
        let selected = picture(&track, 32, 32).unwrap();
        assert_eq!(first_pixel(&selected), [0, 0, 220, 255]);
        let entries_art: Vec<_> = fs::read_dir(&dir).unwrap().flatten().collect();
        let stamp_art = stamp(&entries_art);
        assert_ne!(stamp_art, stamp_wmp);

        // Exact track-stem sidecar wins over generic folder cover.
        fs::write(dir.join("01 Night Drive.png"), &green).unwrap();
        let selected = picture(&track, 32, 32).unwrap();
        assert_eq!(first_pixel(&selected), [0, 200, 0, 255]);
        let entries_sidecar: Vec<_> = fs::read_dir(&dir).unwrap().flatten().collect();
        let stamp_sidecar = stamp(&entries_sidecar);
        assert_ne!(stamp_sidecar, stamp_art);

        fs::remove_dir_all(dir).unwrap();
    }
}
