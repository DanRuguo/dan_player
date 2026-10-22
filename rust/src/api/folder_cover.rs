//! Local artwork fallback. Discovery never modifies audio or image files.
use super::*;
use sha2::{Digest, Sha256};

const NAMES: &[&str] = &["cover", "folder", "front", "album", "albumart"];
const EXTENSIONS: &[&str] = &["jpg", "jpeg", "png", "webp", "bmp", "gif"];
const MAX_BYTES: u64 = 20 * 1024 * 1024;

fn candidate_name(path: &Path) -> bool {
    let stem = path.file_stem().unwrap_or_default().to_string_lossy();
    let extension = path.extension().unwrap_or_default().to_string_lossy();
    NAMES.iter().any(|name| stem.eq_ignore_ascii_case(name))
        && EXTENSIONS
            .iter()
            .any(|ext| extension.eq_ignore_ascii_case(ext))
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

/// The scanner already enumerated this directory. Stat only named artwork,
/// once per directory, without decoding images or rereading unchanged tags.
pub(super) fn stamp(entries: &[fs::DirEntry]) -> Option<String> {
    let mut records = Vec::new();
    for entry in entries {
        let path = entry.path();
        if !candidate_name(&path) {
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

/// Fixed candidate count and bounded bytes; a damaged preferred image does
/// not hide a valid later candidate. Existing embedded artwork stays first.
pub(super) fn picture(audio: &Path, width: u32, height: u32) -> Option<Vec<u8>> {
    if !audio.is_file() {
        return None;
    }
    let directory = audio.parent()?;
    for name in NAMES {
        for extension in EXTENSIONS {
            let candidate = directory.join(format!("{name}.{extension}"));
            let Some(metadata) = regular_metadata(&candidate) else {
                continue;
            };
            if metadata.len() == 0 || metadata.len() > MAX_BYTES {
                continue;
            }
            let Ok(file) = fs::File::open(&candidate) else {
                continue;
            };
            let mut bytes = Vec::new();
            if file.take(MAX_BYTES + 1).read_to_end(&mut bytes).is_err()
                || bytes.len() as u64 > MAX_BYTES
            {
                continue;
            }
            if let Some(picture) = resize_picture(&bytes, width, height) {
                return Some(picture);
            }
        }
    }
    None
}
