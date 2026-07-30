use std::{
    any::Any,
    collections::HashSet,
    fs::{self},
    io::{self, Cursor, Write},
    panic::{catch_unwind, AssertUnwindSafe},
    path::{Path, PathBuf},
    time::{Duration, UNIX_EPOCH},
};

use image::imageops;
use lofty::config::WriteOptions;
use lofty::file::FileType;
use lofty::picture::{Picture, PictureType};
use lofty::prelude::{Accessor, AudioFile, ItemKey, TaggedFileExt};
use lofty::tag::{Tag, TagExt, TagType};
use rayon::prelude::*;
use windows::{
    core::Interface,
    core::HSTRING,
    Storage::{
        FileProperties::ThumbnailMode,
        StorageFile,
        Streams::{DataReader, IInputStream},
    },
    Win32::System::Com::{CoInitializeEx, CoUninitialize, COINIT_MULTITHREADED},
};

use crate::frb_generated::StreamSink;

use super::logger::log_to_dart;

struct ComApartment(bool);

impl ComApartment {
    fn multithreaded() -> Self {
        Self(unsafe { CoInitializeEx(None, COINIT_MULTITHREADED).is_ok() })
    }
}

impl Drop for ComApartment {
    fn drop(&mut self) {
        if self.0 {
            unsafe { CoUninitialize() };
        }
    }
}

/// K: extension, V: can read tags by using Lofty
static SUPPORT_FORMAT: phf::Map<&'static str, bool> = phf::phf_map! {
    "mp3" => true, "mp2" => false, "mp1" => false,
    "ogg" => true,
    "wav" => true, "wave" => true,
    "aif" => true, "aiff" => true, "aifc" => true,
    // 通过 Windows 系统支持
    "asf" => false, "wma" => false,
    "aac" => true, "adts" => true,
    "m4a" => true,
    "ac3" => false,
    "amr" => false, "3ga" => false,
    "flac" => true,
    "mpc" => true,
    // 插件支持
    "mid" => false,
    "wv" => true, "wvc" => true,
    "opus" => true,
    "dsf" => false, "dff" => false,
    "ape" => true,
};

const INDEX_VERSION: u64 = 112;

fn sibling_path(path: &Path, suffix: &str) -> PathBuf {
    let mut value = path.as_os_str().to_os_string();
    value.push(suffix);
    PathBuf::from(value)
}

fn read_index_json(index_path: &Path) -> anyhow::Result<(serde_json::Value, bool)> {
    let backup_path = sibling_path(index_path, ".bak");
    let mut target_error = None;

    for (candidate, is_backup) in [(index_path, false), (backup_path.as_path(), true)] {
        match fs::read(candidate)
            .map_err(anyhow::Error::from)
            .and_then(|bytes| serde_json::from_slice(&bytes).map_err(anyhow::Error::from))
        {
            Ok(index) => {
                if is_backup {
                    log_to_dart("index.json is damaged; recovered from index.json.bak".to_string());
                }
                return Ok((index, is_backup));
            }
            Err(error) if !is_backup => target_error = Some(error),
            Err(_) => {}
        }
    }

    Err(target_error.unwrap_or_else(|| anyhow::anyhow!("audio index does not exist")))
}

fn write_index_json(
    index_path: &Path,
    index: &serde_json::Value,
    preserve_backup: bool,
) -> io::Result<()> {
    if let Some(parent) = index_path.parent() {
        fs::create_dir_all(parent)?;
    }

    let temporary_path = sibling_path(index_path, ".tmp");
    let backup_path = sibling_path(index_path, ".bak");
    {
        let mut temporary = fs::File::create(&temporary_path)?;
        temporary.write_all(index.to_string().as_bytes())?;
        temporary.sync_all()?;
    }

    let target_is_valid = fs::read(index_path)
        .ok()
        .and_then(|bytes| serde_json::from_slice::<serde_json::Value>(&bytes).ok())
        .is_some();
    let keep_existing_backup =
        preserve_backup || (index_path.exists() && !target_is_valid && backup_path.exists());

    if keep_existing_backup {
        if index_path.exists() {
            fs::remove_file(index_path)?;
        }
    } else if index_path.exists() {
        if backup_path.exists() {
            fs::remove_file(&backup_path)?;
        }
        fs::rename(index_path, &backup_path)?;
    }

    if let Err(error) = fs::rename(&temporary_path, index_path) {
        if !index_path.exists() && backup_path.exists() {
            let _ = fs::copy(&backup_path, index_path);
        }
        let _ = fs::remove_file(&temporary_path);
        return Err(error);
    }

    Ok(())
}

pub struct IndexActionState {
    /// completed / total
    pub progress: f64,

    /// describe action state
    pub message: String,
}

pub fn update_audio_metadata(
    path: String,
    file_name: String,
    title: String,
    artist: String,
    album: String,
    picture_path: Option<String>,
) -> anyhow::Result<String> {
    let old_path = PathBuf::from(&path);
    if !old_path.exists() {
        anyhow::bail!("audio file does not exist");
    }

    let sanitized_name = sanitize_file_name(&file_name)?;
    let extension = old_path
        .extension()
        .map(|value| value.to_string_lossy().to_string())
        .unwrap_or_default();
    let mut target_name = sanitized_name;
    match Path::new(&target_name).extension() {
        Some(requested) if !extension.is_empty() => {
            if !requested.to_string_lossy().eq_ignore_ascii_case(&extension) {
                anyhow::bail!("renaming cannot change the audio file extension");
            }
        }
        None if !extension.is_empty() => {
            target_name.push('.');
            target_name.push_str(&extension);
        }
        _ => {}
    }

    let parent = old_path
        .parent()
        .ok_or_else(|| anyhow::anyhow!("audio file has no parent folder"))?;
    let new_path = parent.join(target_name);

    if new_path != old_path && new_path.exists() {
        anyhow::bail!("target file already exists");
    }

    write_metadata_safely(&old_path, &title, &artist, &album, picture_path.as_deref())?;

    if new_path != old_path {
        fs::rename(&old_path, &new_path)
            .map_err(|err| anyhow::anyhow!("failed to rename audio file: {}", err))?;
    }

    Ok(new_path.to_string_lossy().to_string())
}

fn ensure_tag(tagged_file: &mut lofty::file::TaggedFile, tag_type: TagType) -> anyhow::Result<()> {
    if tagged_file.contains_tag_type(tag_type) {
        return Ok(());
    }

    tagged_file.insert_tag(Tag::new(tag_type));
    if tagged_file.contains_tag_type(tag_type) {
        return Ok(());
    }

    anyhow::bail!("audio format does not support writable tags");
}

fn write_metadata_safely(
    path: &Path,
    title: &str,
    artist: &str,
    album: &str,
    picture_path: Option<&str>,
) -> anyhow::Result<()> {
    let result = catch_unwind(AssertUnwindSafe(|| {
        write_metadata_with_existing_tag(path, title, artist, album, picture_path)
    }));

    match result {
        Ok(Ok(())) => Ok(()),
        Ok(Err(err)) => {
            log_to_dart(format!(
                "failed to update existing audio tags, rewriting primary tag: {}",
                err
            ));
            write_metadata_with_fresh_tag_guarded(path, title, artist, album, picture_path, &err)
        }
        Err(payload) => {
            let panic_message = panic_payload_to_string(payload.as_ref());
            log_to_dart(format!(
                "audio tag writer panicked, rewriting primary tag: {}",
                panic_message
            ));
            write_metadata_with_fresh_tag_guarded(
                path,
                title,
                artist,
                album,
                picture_path,
                &anyhow::anyhow!(panic_message),
            )
        }
    }
}

fn write_metadata_with_existing_tag(
    path: &Path,
    title: &str,
    artist: &str,
    album: &str,
    picture_path: Option<&str>,
) -> anyhow::Result<()> {
    let mut tagged_file = lofty::read_from_path(path)
        .map_err(|err| anyhow::anyhow!("failed to read audio tags: {}", err))?;
    let tag_type = tagged_file.primary_tag_type();
    ensure_tag(&mut tagged_file, tag_type)?;

    {
        let tag = tagged_file
            .primary_tag_mut()
            .ok_or_else(|| anyhow::anyhow!("failed to create writable tag"))?;
        apply_tag_values(tag, title, artist, album, picture_path)?;
    }

    tagged_file
        .save_to_path(path, WriteOptions::default().respect_read_only(false))
        .map_err(|err| anyhow::anyhow!("failed to write audio tags: {}", err))?;

    Ok(())
}

fn write_metadata_with_fresh_tag_guarded(
    path: &Path,
    title: &str,
    artist: &str,
    album: &str,
    picture_path: Option<&str>,
    original_err: &anyhow::Error,
) -> anyhow::Result<()> {
    let result = catch_unwind(AssertUnwindSafe(|| {
        write_metadata_with_fresh_tag(path, title, artist, album, picture_path)
    }));

    match result {
        Ok(Ok(())) => Ok(()),
        Ok(Err(fallback_err)) => anyhow::bail!(
            "failed to write audio tags: {}; fallback failed: {}",
            original_err,
            fallback_err
        ),
        Err(payload) => anyhow::bail!(
            "failed to write audio tags: {}; fallback panicked: {}",
            original_err,
            panic_payload_to_string(payload.as_ref())
        ),
    }
}

fn write_metadata_with_fresh_tag(
    path: &Path,
    title: &str,
    artist: &str,
    album: &str,
    picture_path: Option<&str>,
) -> anyhow::Result<()> {
    let file_type = FileType::from_path(path)
        .ok_or_else(|| anyhow::anyhow!("unknown or unsupported audio format"))?;
    let mut tag = Tag::new(file_type.primary_tag_type());
    apply_tag_values(&mut tag, title, artist, album, picture_path)?;
    tag.save_to_path(path, WriteOptions::default().respect_read_only(false))
        .map_err(|err| anyhow::anyhow!("failed to write clean audio tag: {}", err))?;
    Ok(())
}

fn apply_tag_values(
    tag: &mut Tag,
    title: &str,
    artist: &str,
    album: &str,
    picture_path: Option<&str>,
) -> anyhow::Result<()> {
    tag.set_title(title.to_string());
    tag.set_artist(artist.to_string());
    tag.set_album(album.to_string());

    if let Some(pic_path) = picture_path.filter(|value| !value.trim().is_empty()) {
        let mut pic_file = fs::File::open(pic_path)
            .map_err(|err| anyhow::anyhow!("failed to open album image: {}", err))?;
        let mut picture = Picture::from_reader(&mut pic_file)
            .map_err(|err| anyhow::anyhow!("failed to parse album image: {}", err))?;
        picture.set_pic_type(PictureType::CoverFront);
        tag.remove_picture_type(PictureType::CoverFront);
        tag.push_picture(picture);
    }

    Ok(())
}

fn panic_payload_to_string(payload: &(dyn Any + Send)) -> String {
    if let Some(message) = payload.downcast_ref::<&str>() {
        return message.to_string();
    }
    if let Some(message) = payload.downcast_ref::<String>() {
        return message.clone();
    }
    "unknown panic".to_string()
}

fn sanitize_file_name(file_name: &str) -> anyhow::Result<String> {
    let sanitized: String = file_name
        .chars()
        .map(|ch| match ch {
            '<' | '>' | ':' | '"' | '/' | '\\' | '|' | '?' | '*' => '_',
            _ if ch.is_control() => '_',
            _ => ch,
        })
        .collect();
    let sanitized = sanitized.trim().trim_end_matches(['.', ' ']).to_string();
    if sanitized.is_empty() {
        anyhow::bail!("file name cannot be empty");
    }

    Ok(sanitized)
}

fn ordered_tags(tagged_file: &lofty::file::TaggedFile) -> Vec<&Tag> {
    let primary_type = tagged_file.primary_tag_type();
    let mut tags = Vec::with_capacity(tagged_file.tags().len());
    if let Some(primary) = tagged_file.primary_tag() {
        tags.push(primary);
    }
    tags.extend(
        tagged_file
            .tags()
            .iter()
            .filter(|tag| tag.tag_type() != primary_type),
    );
    tags
}

fn text_from_tag(tag: &Tag, key: &ItemKey) -> Option<String> {
    let mut values = Vec::new();
    for value in tag.get_strings(key) {
        let value = value.trim();
        if !value.is_empty() && !values.contains(&value) {
            values.push(value);
        }
    }
    (!values.is_empty()).then(|| values.join("/"))
}

#[cfg(test)]
fn first_tag_text(tags: &[&Tag], key: &ItemKey) -> Option<String> {
    tags.iter().find_map(|tag| text_from_tag(tag, key))
}

fn first_tag_text_with_source(tags: &[&Tag], key: &ItemKey) -> Option<(String, TagType)> {
    tags.iter()
        .find_map(|tag| text_from_tag(tag, key).map(|value| (value, tag.tag_type())))
}

fn artist_from_tags_with_source(tags: &[&Tag]) -> (String, Option<TagType>) {
    first_tag_text_with_source(tags, &ItemKey::TrackArtist)
        .or_else(|| first_tag_text_with_source(tags, &ItemKey::AlbumArtist))
        .or_else(|| first_tag_text_with_source(tags, &ItemKey::Composer))
        .map_or_else(
            || ("UNKNOWN".to_string(), None),
            |(value, source)| (value, Some(source)),
        )
}

fn metadata_is_missing(value: &str) -> bool {
    value.trim().is_empty() || value.eq_ignore_ascii_case("UNKNOWN")
}

fn text_looks_misdecoded(value: &str) -> bool {
    if value.contains('\u{FFFD}') || value.chars().any(|ch| ('\u{80}'..='\u{9F}').contains(&ch)) {
        return true;
    }
    let non_whitespace = value.chars().filter(|ch| !ch.is_whitespace()).count();
    if non_whitespace < 4 {
        return false;
    }
    let latin1_supplement = value
        .chars()
        .filter(|ch| ('\u{A0}'..='\u{FF}').contains(ch))
        .count();
    latin1_supplement >= 3 && latin1_supplement * 3 >= non_whitespace
}

#[derive(Debug)]
struct Audio {
    title: String,
    artist: String,
    album: String,
    track: Option<u32>,
    /// in secs
    duration: u64,
    /// kbps
    bitrate: Option<u32>,
    sample_rate: Option<u32>,
    /// absolute path
    path: String,
    /// secs since UNIX_EPOCH
    modified: u64,
    /// secs since UNIX_EPOCH
    created: u64,
    /// 标签获取方式
    by: Option<String>,
    /// Selected text came from a legacy or visibly misdecoded tag.
    needs_windows_text_fallback: bool,
}

impl Audio {
    fn new_with_path(path: impl AsRef<Path>, by: Option<String>) -> Option<Self> {
        let path = path.as_ref();
        Some(Audio {
            title: path.file_name()?.to_string_lossy().to_string(),
            artist: "UNKNOWN".to_string(),
            album: "UNKNOWN".to_string(),
            track: None,
            duration: 0,
            bitrate: None,
            sample_rate: None,
            path: path.to_string_lossy().to_string(),
            modified: 0,
            created: 0,
            by,
            needs_windows_text_fallback: false,
        })
    }

    fn to_json_value(&self) -> serde_json::Value {
        serde_json::json!({
            "title": self.title,
            "artist": self.artist,
            "album": self.album,
            "track": self.track,
            "duration": self.duration,
            "bitrate": self.bitrate,
            "sample_rate": self.sample_rate,
            "path": self.path,
            "modified": self.modified,
            "created": self.created,
            "by": self.by
        })
    }

    /// 不支持：None  
    /// Lofty 能获取到信息：read_by_lofty  
    /// 不能的话：read_by_win_music_properties  
    /// 再不能的话：title: filename 代替
    fn read_from_path(path: impl AsRef<Path>) -> Option<Self> {
        let path = path.as_ref();
        let lofty_support: bool =
            *SUPPORT_FORMAT.get(&path.extension()?.to_ascii_lowercase().to_string_lossy())?;

        let file_metadata = match fs::metadata(path) {
            Ok(val) => val,
            Err(err) => {
                log_to_dart(err.to_string());
                return None;
            }
        };
        let modified = file_metadata
            .modified()
            .unwrap_or(UNIX_EPOCH)
            .duration_since(UNIX_EPOCH)
            .unwrap_or(Duration::ZERO)
            .as_secs();
        let created = file_metadata
            .created()
            .unwrap_or(UNIX_EPOCH)
            .duration_since(UNIX_EPOCH)
            .unwrap_or(Duration::ZERO)
            .as_secs();

        if lofty_support {
            if let Some(mut value) = Self::read_by_lofty(path, modified, created) {
                if value.needs_windows_text_fallback
                    || metadata_is_missing(&value.artist)
                    || metadata_is_missing(&value.album)
                {
                    if let Ok(windows_value) =
                        Self::read_by_win_music_properties(path, modified, created)
                    {
                        let prefer_windows = value.needs_windows_text_fallback;
                        let mut used_windows = false;
                        if prefer_windows && !metadata_is_missing(&windows_value.title) {
                            value.title = windows_value.title;
                            used_windows = true;
                        }
                        if (prefer_windows || metadata_is_missing(&value.artist))
                            && !metadata_is_missing(&windows_value.artist)
                        {
                            value.artist = windows_value.artist;
                            used_windows = true;
                        }
                        if (prefer_windows || metadata_is_missing(&value.album))
                            && !metadata_is_missing(&windows_value.album)
                        {
                            value.album = windows_value.album;
                            used_windows = true;
                        }
                        if used_windows {
                            value.by = Some("Lofty+Windows".to_string());
                        }
                    }
                }
                return Some(value);
            }

            match Self::read_by_win_music_properties(path, modified, created) {
                Ok(value) => Some(value),
                Err(err) => {
                    log_to_dart(format!("{:?}: {}", path, err));
                    Self::new_with_path(path, None)
                }
            }
        } else {
            match Self::read_by_win_music_properties(path, modified, created) {
                Ok(value) => Some(value),
                Err(err) => {
                    log_to_dart(format!("{:?}: {}", path, err));
                    Self::new_with_path(path, None)
                }
            }
        }
    }

    /// 使用 lofty 获取音乐标签。只在文件名不正确、没有标签或包含不支持的编码时返回 None
    fn read_by_lofty(path: impl AsRef<Path>, modified: u64, created: u64) -> Option<Self> {
        let path = path.as_ref();
        let tagged_file = match lofty::read_from_path(path) {
            Ok(val) => val,
            Err(err) => {
                log_to_dart(format!("{:?}: {}", path, err));
                return None;
            }
        };

        let properties = tagged_file.properties();

        let tags = ordered_tags(&tagged_file);
        let (title, title_source) = first_tag_text_with_source(&tags, &ItemKey::TrackTitle)
            .map_or_else(
                || {
                    (
                        path.file_name().unwrap().to_string_lossy().to_string(),
                        None,
                    )
                },
                |(value, source)| (value, Some(source)),
            );
        let (artist, artist_source) = artist_from_tags_with_source(&tags);
        let (album, album_source) = first_tag_text_with_source(&tags, &ItemKey::AlbumTitle)
            .map_or_else(
                || ("UNKNOWN".to_string(), None),
                |(value, source)| (value, Some(source)),
            );
        let track = tags.iter().find_map(|tag| tag.track());
        let uses_id3v1 = [title_source, artist_source, album_source]
            .into_iter()
            .flatten()
            .any(|source| source == TagType::Id3v1);
        let needs_windows_text_fallback = uses_id3v1
            || text_looks_misdecoded(&title)
            || text_looks_misdecoded(&artist)
            || text_looks_misdecoded(&album);

        Some(Audio {
            title,
            artist,
            album,
            track,
            duration: properties.duration().as_secs(),
            bitrate: properties.audio_bitrate(),
            sample_rate: properties.sample_rate(),
            path: path.to_string_lossy().to_string(),
            modified,
            created,
            by: Some("Lofty".to_string()),
            needs_windows_text_fallback,
        })
    }

    /// 使用 Windows Api 获取音乐标签。会因为各种原因返回 Err
    fn read_by_win_music_properties(
        path: impl AsRef<Path>,
        modified: u64,
        created: u64,
    ) -> Result<Self, windows::core::Error> {
        let _apartment = ComApartment::multithreaded();
        let path = path.as_ref();
        let storage_file = StorageFile::GetFileFromPathAsync(&HSTRING::from(path))?.get()?;
        let music_properties = storage_file
            .Properties()?
            .GetMusicPropertiesAsync()?
            .get()?;

        let duration: Duration = music_properties.Duration()?.into();

        let mut title = music_properties
            .Title()
            .or_else(|_| storage_file.Name())?
            .to_string();
        if title.is_empty() {
            title = storage_file.Name()?.to_string();
        }

        let mut artist = music_properties
            .Artist()
            .unwrap_or(HSTRING::from("UNKNOWN"))
            .to_string();
        if artist.is_empty() {
            artist = "UNKNOWN".to_string();
        }

        let mut album = music_properties
            .Album()
            .unwrap_or(HSTRING::from("UNKNOWN"))
            .to_string();
        if album.is_empty() {
            album = "UNKNOWN".to_string();
        }

        Ok(Audio {
            title,
            artist,
            album,
            track: Some(music_properties.TrackNumber()?),
            duration: duration.as_secs(),
            bitrate: Some(music_properties.Bitrate()? / 1000),
            sample_rate: None,
            path: path.to_string_lossy().to_string(),
            modified,
            created,
            by: Some("Windows".to_string()),
            needs_windows_text_fallback: false,
        })
    }
}

#[derive(Debug)]
struct AudioFolder {
    path: String,
    /// secs since UNIX_EPOCH
    modified: u64,
    /// biggest created in audios. secs since UNIX_EPOCH
    latest: u64,
    audios: Vec<Audio>,
}

impl AudioFolder {
    fn to_json_value(&self) -> serde_json::Value {
        let mut audios_json: Vec<serde_json::Value> = vec![];
        for audio in &self.audios {
            audios_json.push(audio.to_json_value());
        }

        serde_json::json!({
            "path": self.path,
            "modified": self.modified,
            "latest": self.latest,
            "audios": audios_json,
        })
    }

    /// 扫描路径为 path 的文件夹
    fn read_from_folder(path: impl AsRef<Path>) -> Result<AudioFolder, io::Error> {
        let path = path.as_ref();

        let dir = match fs::read_dir(path) {
            Ok(val) => val,
            Err(err) => {
                log_to_dart(format!("{:?}: {}", path, err));
                return Err(err);
            }
        };

        let paths: Vec<PathBuf> = dir
            .filter_map(Result::ok)
            .filter(|entry| entry.file_type().is_ok_and(|kind| kind.is_file()))
            .map(|entry| entry.path())
            .collect();
        let audios: Vec<Audio> = paths.par_iter().filter_map(Audio::read_from_path).collect();
        let latest = audios.iter().map(|audio| audio.created).max().unwrap_or(0);

        if !audios.is_empty() {
            return Ok(AudioFolder {
                path: path.to_string_lossy().to_string(),
                modified: fs::metadata(path)?
                    .modified()?
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or(Duration::ZERO)
                    .as_secs(),
                latest,
                audios,
            });
        }

        Err(io::Error::new(
            io::ErrorKind::NotFound,
            path.to_string_lossy() + " has no music.",
        ))
    }

    /// 扫描路径为 path 的文件夹及其所有子文件夹。
    fn read_from_folder_recursively(
        folder: impl AsRef<Path>,
        result: &mut Vec<Self>,
        scaned_count: &mut u64,
        total_count: &mut u64,
        scaned_folders: &mut HashSet<String>,
        sink: &StreamSink<IndexActionState>,
    ) -> Result<(), io::Error> {
        let folder = folder.as_ref();
        if scaned_folders.contains(&folder.to_string_lossy().to_string()) {
            return Ok(());
        }

        let dir = match fs::read_dir(folder) {
            Ok(val) => val,
            Err(err) => {
                log_to_dart(format!("{:?}: {}", folder, err));
                return Ok(());
            }
        };

        let _ = sink.add(IndexActionState {
            progress: *scaned_count as f64 / *total_count as f64,
            message: String::from("正在扫描 ") + &folder.to_string_lossy(),
        });

        scaned_folders.insert(folder.to_string_lossy().to_string());
        let mut subdirectories = Vec::new();
        let mut files = Vec::new();
        for item in dir {
            let entry = match item {
                Ok(value) => value,
                Err(err) => {
                    log_to_dart(err.to_string());
                    continue;
                }
            };
            match entry.file_type() {
                Ok(kind) if kind.is_dir() => subdirectories.push(entry.path()),
                Ok(kind) if kind.is_file() => files.push(entry.path()),
                Ok(_) => {}
                Err(err) => log_to_dart(err.to_string()),
            }
        }

        let audios: Vec<Audio> = files.par_iter().filter_map(Audio::read_from_path).collect();
        let latest = audios.iter().map(|audio| audio.created).max().unwrap_or(0);

        for subdirectory in subdirectories {
            *total_count += 1;
            let _ = Self::read_from_folder_recursively(
                subdirectory,
                result,
                scaned_count,
                total_count,
                scaned_folders,
                sink,
            );
        }

        if !audios.is_empty() {
            if let Ok(metadata) = fs::metadata(folder) {
                if let Ok(modified) = metadata.modified() {
                    result.push(AudioFolder {
                        path: folder.to_string_lossy().to_string(),
                        modified: modified
                            .duration_since(UNIX_EPOCH)
                            .unwrap_or(Duration::ZERO)
                            .as_secs(),
                        latest,
                        audios,
                    });
                }
            }
        }

        *scaned_count += 1;
        let _ = sink.add(IndexActionState {
            progress: *scaned_count as f64 / *total_count as f64,
            message: String::new(),
        });

        Ok(())
    }
}

fn _get_picture_by_windows(path: &String) -> Result<Vec<u8>, windows::core::Error> {
    let _apartment = ComApartment::multithreaded();
    let file = StorageFile::GetFileFromPathAsync(&HSTRING::from(path))?.get()?;
    let thumbnail = file
        .GetThumbnailAsyncOverloadDefaultSizeDefaultOptions(ThumbnailMode::MusicView)?
        .get()?;

    let size = thumbnail.Size()? as u32;
    let stream: IInputStream = thumbnail.cast()?;

    let mut buffer = vec![0u8; size as usize];
    let data_reader = DataReader::CreateDataReader(&stream)?;
    data_reader.LoadAsync(size)?.get()?;
    data_reader.ReadBytes(&mut buffer)?;

    data_reader.Close()?;
    stream.Close()?;

    Ok(buffer)
}

fn resize_picture(pic: &[u8], width: u32, height: u32) -> Option<Vec<u8>> {
    let loaded_pic = image::load_from_memory(pic).ok()?;
    let width = width.max(1);
    let height = height.max(1);
    let pic_ratio = loaded_pic.width() as f32 / loaded_pic.height() as f32;
    let (result_width, result_height) = if pic_ratio > 1.0 {
        (width, (width as f32 / pic_ratio).round().max(1.0) as u32)
    } else {
        ((height as f32 * pic_ratio).round().max(1.0) as u32, height)
    };
    let resized_img = imageops::resize(
        &loaded_pic,
        result_width,
        result_height,
        imageops::FilterType::Triangle,
    );
    let mut output = Cursor::new(Vec::new());
    resized_img
        .write_to(&mut output, image::ImageFormat::Png)
        .ok()?;
    Some(output.into_inner())
}

fn _get_picture_by_lofty(path: &String, width: u32, height: u32) -> Option<Vec<u8>> {
    if let Ok(tagged_file) = lofty::read_from_path(path) {
        let tags = ordered_tags(&tagged_file);
        for front_cover_only in [true, false] {
            for tag in &tags {
                for picture in tag.pictures() {
                    let is_front_cover = picture.pic_type() == PictureType::CoverFront;
                    if is_front_cover != front_cover_only {
                        continue;
                    }
                    if let Some(resized) = resize_picture(picture.data(), width, height) {
                        return Some(resized);
                    }
                }
            }
        }
    }

    None
}

/// for Flutter  
/// 如果无法通过 Lofty 获取则通过 Windows 获取
pub fn get_picture_from_path(path: String, width: u32, height: u32) -> Option<Vec<u8>> {
    if let Some(pic) = _get_picture_by_lofty(&path, width, height) {
        return Some(pic);
    }

    match _get_picture_by_windows(&path) {
        Ok(pic) => resize_picture(&pic, width, height),
        Err(err) => {
            log_to_dart(format!("fail to get pic: {}", err));
            None
        }
    }
}

fn _get_lyric_from_lofty(path: &String) -> Option<String> {
    if let Ok(tagged_file) = lofty::read_from_path(path) {
        for tag in ordered_tags(&tagged_file) {
            if let Some(lyric) = tag
                .get(&ItemKey::Lyrics)
                .and_then(|item| item.value().text())
                .filter(|value| !value.trim().is_empty())
            {
                return Some(lyric.to_string());
            }
        }
    }

    None
}

fn _get_lyric_from_lrc_file(path: &String) -> anyhow::Result<String> {
    let mut lrc_file_path = PathBuf::from(path);
    lrc_file_path.set_extension("lrc");

    let lrc_bytes = fs::read(lrc_file_path)?;

    let is_le = lrc_bytes.starts_with(&[0xFF, 0xFE]);
    let is_utf16 = (is_le || lrc_bytes.starts_with(&[0xFE, 0xFF])) && lrc_bytes.len() % 2 == 0;

    if is_utf16 {
        let convert_fn = match is_le {
            true => u16::from_le_bytes,
            false => u16::from_be_bytes,
        };

        let mut u16_bytes: Vec<u16> = vec![];
        let mut chunk_iter = lrc_bytes.chunks_exact(2);
        chunk_iter.next();

        for chunk in chunk_iter {
            u16_bytes.push(convert_fn([chunk[0], chunk[1]]));
        }
        return Ok(String::from_utf16(&u16_bytes)?);
    }

    Ok(String::from_utf8(lrc_bytes)?)
}

/// for Flutter   
/// 只支持读取 ID3V2, VorbisComment, Mp4Ilst 存储的内嵌歌词
/// 以及相同目录相同文件名的 .lrc 外挂歌词（utf-8 or utf-16）
pub fn get_lyric_from_path(path: String) -> Option<String> {
    _get_lyric_from_lofty(&path).or_else(|| match _get_lyric_from_lrc_file(&path) {
        Ok(val) => Some(val),
        Err(err) => {
            log_to_dart(format!("fail to get lrc: {err}"));
            None
        }
    })
}

/// for Flutter  
/// 扫描给定路径下所有子文件夹（包括自己）的音乐文件并把索引保存在 index_path/index.json。
pub fn build_index_from_folders_recursively(
    folders: Vec<String>,
    index_path: String,
    sink: StreamSink<IndexActionState>,
) -> Result<(), io::Error> {
    let mut audio_folders: Vec<AudioFolder> = vec![];
    let mut scaned: u64 = 0;
    let mut total: u64 = folders.len() as u64;
    let mut scaned_folders: HashSet<String> = HashSet::new();

    for item in &folders {
        let _ = AudioFolder::read_from_folder_recursively(
            Path::new(item),
            &mut audio_folders,
            &mut scaned,
            &mut total,
            &mut scaned_folders,
            &sink,
        );
    }

    let mut audio_folders_json: Vec<serde_json::Value> = vec![];
    for item in &audio_folders {
        audio_folders_json.push(item.to_json_value());
    }
    let json_value = serde_json::json!({
        "version": INDEX_VERSION,
        "folders": audio_folders_json,
    });

    let mut index_path = PathBuf::from(index_path);
    index_path.push("index.json");
    write_index_json(&index_path, &json_value, false)?;

    Ok(())
}

fn _update_index_below_1_1_0(
    index: &serde_json::Value,
    index_path: &Path,
    sink: &StreamSink<IndexActionState>,
) -> Result<(), io::Error> {
    let mut audio_folders_json: Vec<serde_json::Value> = vec![];
    let folders = index.as_array().ok_or_else(|| {
        io::Error::new(io::ErrorKind::InvalidData, "legacy index must be an array")
    })?;
    let total = folders.len().max(1);
    for item in folders {
        let Some(path) = item["path"].as_str() else {
            continue;
        };
        let _ = sink.add(IndexActionState {
            progress: audio_folders_json.len() as f64 / total as f64,
            message: String::from("正在扫描 ") + path,
        });
        let folder_path = Path::new(path);
        if let Ok(audio_folder) = AudioFolder::read_from_folder(folder_path) {
            audio_folders_json.push(audio_folder.to_json_value());
            let _ = sink.add(IndexActionState {
                progress: audio_folders_json.len() as f64 / total as f64,
                message: String::new(),
            });
        }
    }
    write_index_json(
        index_path,
        &serde_json::json!({
            "version": INDEX_VERSION,
            "folders": audio_folders_json,
        }),
        false,
    )?;

    Ok(())
}

fn _rebuild_versioned_index(
    index: &serde_json::Value,
    index_path: &Path,
    sink: &StreamSink<IndexActionState>,
) -> Result<(), io::Error> {
    let folders = index["folders"].as_array().ok_or_else(|| {
        io::Error::new(io::ErrorKind::InvalidData, "index folders must be an array")
    })?;
    let mut audio_folders_json = Vec::with_capacity(folders.len());
    let total = folders.len().max(1);

    for item in folders {
        let Some(path) = item["path"].as_str() else {
            continue;
        };
        let _ = sink.add(IndexActionState {
            progress: audio_folders_json.len() as f64 / total as f64,
            message: String::from("正在重新读取歌曲信息 ") + path,
        });
        if let Ok(audio_folder) = AudioFolder::read_from_folder(path) {
            audio_folders_json.push(audio_folder.to_json_value());
        }
    }

    write_index_json(
        index_path,
        &serde_json::json!({
            "version": INDEX_VERSION,
            "folders": audio_folders_json,
        }),
        false,
    )?;
    let _ = sink.add(IndexActionState {
        progress: 1.0,
        message: String::new(),
    });
    Ok(())
}

/// for Flutter   
/// 读取 index_path/index.json，检查更新。不可能重新读取被修改的文件夹下所有的音乐标签，这样太耗时。  
///
/// [LOWEST_VERSION] 指定可以继承的 index 的最低版本。
/// 如果 index version < [LOWEST_VERSION] 或者是 index 根本没有 version 再或者格式不符合要求，就转到
/// [_update_index_below_1_1_0] 更新 index；
/// 如果 index version >= [LOWEST_VERSION] 则进行更新。
///
/// 如果文件夹不存在，删除记录。  
/// 如果文件夹被修改（再次读取到的 modified > 记录的 modified），就更新它。没有则跳过它
/// 1. 遍历该文件夹索引，判断文件是否存在，不存在则删除记录
/// 2. 遍历该文件夹索引，如果文件被修改（再次读取到的 modified > 记录的 modified），重新读取标签；没有则跳过它
/// 3. 遍历该文件夹，添加新增（读取到的 created > 记录的 latest）的音乐文件
pub fn update_index(index_path: String, sink: StreamSink<IndexActionState>) -> anyhow::Result<()> {
    let mut index_path = PathBuf::from(index_path);
    index_path.push("index.json");
    let (mut index, recovered_from_backup) = read_index_json(&index_path)?;

    let Some(version) = index["version"].as_u64() else {
        if index.is_array() {
            return Ok(_update_index_below_1_1_0(&index, &index_path, &sink)?);
        }
        return Ok(_rebuild_versioned_index(&index, &index_path, &sink)?);
    };
    if version < INDEX_VERSION {
        return Ok(_rebuild_versioned_index(&index, &index_path, &sink)?);
    }

    let schema_is_valid = index["folders"].as_array().is_some_and(|folders| {
        folders.iter().all(|folder| {
            folder["path"].as_str().is_some()
                && folder["latest"].as_u64().is_some()
                && folder["modified"].as_u64().is_some()
                && folder["audios"].as_array().is_some_and(|audios| {
                    audios.iter().all(|audio| {
                        audio["path"].as_str().is_some() && audio["modified"].as_u64().is_some()
                    })
                })
        })
    });
    if !schema_is_valid {
        return Ok(_rebuild_versioned_index(&index, &index_path, &sink)?);
    }

    let folders = index["folders"]
        .as_array_mut()
        .ok_or_else(|| anyhow::anyhow!("index folders must be an array"))?;
    // 删除访问不到的文件夹的记录
    folders.retain(|item| {
        item["path"]
            .as_str()
            .is_some_and(|path| Path::new(path).exists())
    });

    let mut updated = 0;
    let total = folders.len().max(1);

    for folder_item in folders.iter_mut() {
        let Some(folder_path) = folder_item["path"].as_str().map(str::to_string) else {
            continue;
        };
        let Some(latest) = folder_item["latest"].as_u64() else {
            continue;
        };
        let Some(old_folder_modified) = folder_item["modified"].as_u64() else {
            continue;
        };

        let new_folder_modified = match fs::metadata(&folder_path) {
            Ok(value) => match value.modified() {
                Ok(value) => value
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or(Duration::ZERO)
                    .as_secs(),
                Err(_) => continue,
            },
            Err(_) => continue,
        };

        let _ = sink.add(IndexActionState {
            progress: updated as f64 / total as f64,
            message: String::from("正在更新 ") + &folder_path,
        });

        folder_item["modified"] = serde_json::json!(new_folder_modified.max(old_folder_modified));

        // 删除访问不到的文件的记录
        let Some(audios) = folder_item["audios"].as_array_mut() else {
            continue;
        };
        audios.retain(|item| {
            item["path"]
                .as_str()
                .is_some_and(|path| Path::new(path).exists())
        });

        let changed_paths: Vec<(usize, PathBuf)> = audios
            .iter()
            .enumerate()
            .filter_map(|(index, audio_item)| {
                let old_modified = audio_item["modified"].as_u64()?;
                let audio_path = PathBuf::from(audio_item["path"].as_str()?);
                let new_modified = fs::metadata(&audio_path)
                    .ok()?
                    .modified()
                    .ok()?
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or(Duration::ZERO)
                    .as_secs();
                (new_modified > old_modified).then_some((index, audio_path))
            })
            .collect();
        let changed: Vec<(usize, Option<Audio>)> = changed_paths
            .par_iter()
            .map(|(index, path)| (*index, Audio::read_from_path(path)))
            .collect();
        for (index, audio) in changed {
            if let Some(audio) = audio {
                audios[index] = audio.to_json_value();
            }
        }

        // 添加新增的音乐文件
        let mut new_latest: u64 = latest;
        let known_paths: HashSet<PathBuf> = audios
            .iter()
            .filter_map(|audio| audio["path"].as_str().map(PathBuf::from))
            .collect();
        let dir = match fs::read_dir(folder_path) {
            Ok(value) => value,
            Err(_) => continue,
        };
        let candidates: Vec<(PathBuf, u64)> = dir
            .filter_map(Result::ok)
            .filter(|entry| entry.file_type().is_ok_and(|kind| kind.is_file()))
            .filter_map(|entry| {
                let path = entry.path();
                if known_paths.contains(&path) {
                    return None;
                }
                let created = entry
                    .metadata()
                    .ok()?
                    .created()
                    .ok()?
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or(Duration::ZERO)
                    .as_secs();
                Some((path, created))
            })
            .collect();
        let new_audios: Vec<(u64, Option<Audio>)> = candidates
            .par_iter()
            .map(|(path, created)| (*created, Audio::read_from_path(path)))
            .collect();
        for (created, audio) in new_audios {
            if let Some(audio) = audio {
                new_latest = new_latest.max(created);
                audios.push(audio.to_json_value());
            }
        }

        folder_item["latest"] = serde_json::json!(new_latest);

        updated += 1;
        let _ = sink.add(IndexActionState {
            progress: updated as f64 / total as f64,
            message: String::new(),
        });
    }

    folders.retain(|folder| {
        folder["audios"]
            .as_array()
            .is_some_and(|audios| !audios.is_empty())
    });
    write_index_json(&index_path, &index, recovered_from_backup)?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn metadata_falls_through_empty_leading_tag() {
        let empty = Tag::new(TagType::Id3v1);
        let mut rich = Tag::new(TagType::Id3v2);
        rich.insert_text(ItemKey::TrackArtist, "松本文紀".to_string());
        rich.insert_text(
            ItemKey::AlbumTitle,
            "ATRI -My Dear Moments- (Original Soundtrack)".to_string(),
        );
        let tags = vec![&empty, &rich];

        assert_eq!(artist_from_tags_with_source(&tags).0, "松本文紀");
        assert_eq!(
            first_tag_text(&tags, &ItemKey::AlbumTitle).as_deref(),
            Some("ATRI -My Dear Moments- (Original Soundtrack)")
        );
    }

    #[test]
    fn composer_is_used_when_track_artist_is_missing() {
        let mut tag = Tag::new(TagType::Id3v2);
        tag.insert_text(ItemKey::Composer, "作曲者".to_string());
        assert_eq!(artist_from_tags_with_source(&[&tag]).0, "作曲者");
    }

    #[test]
    fn detects_mojibake_without_rejecting_valid_unicode() {
        assert!(text_looks_misdecoded("³àÎ²¤Ò¤«¤ë"));
        assert!(text_looks_misdecoded("ËÉ±¾ÎÄ¼o"));
        assert!(!text_looks_misdecoded("赤尾ひかる"));
        assert!(!text_looks_misdecoded("松本文紀"));
    }

    #[test]
    fn cover_resize_always_returns_valid_png() {
        let source = image::DynamicImage::new_rgb8(4, 2);
        let mut encoded = Cursor::new(Vec::new());
        source
            .write_to(&mut encoded, image::ImageFormat::Png)
            .unwrap();

        let resized = resize_picture(encoded.get_ref(), 12, 12).unwrap();
        let decoded = image::load_from_memory(&resized).unwrap();
        assert_eq!((decoded.width(), decoded.height()), (12, 6));
    }

    #[test]
    fn damaged_index_recovers_from_atomic_backup() {
        let unique = format!(
            "dan_player_index_test_{}_{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        );
        let directory = std::env::temp_dir().join(unique);
        fs::create_dir_all(&directory).unwrap();
        let index_path = directory.join("index.json");
        let first = serde_json::json!({"version": 1, "folders": ["first"]});
        let second = serde_json::json!({"version": 2, "folders": ["second"]});

        write_index_json(&index_path, &first, false).unwrap();
        write_index_json(&index_path, &second, false).unwrap();
        fs::write(&index_path, b"{damaged").unwrap();

        let (recovered, used_backup) = read_index_json(&index_path).unwrap();
        assert!(used_backup);
        assert_eq!(recovered, first);

        fs::remove_dir_all(directory).unwrap();
    }
}
