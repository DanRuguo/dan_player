use std::{
    any::Any,
    collections::HashSet,
    fs::{self, OpenOptions},
    io::{self, BufReader, Cursor, Read, Seek, SeekFrom, Write},
    panic::{catch_unwind, AssertUnwindSafe},
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicU64, Ordering},
        Mutex,
    },
    time::{Duration, UNIX_EPOCH},
};

use image::imageops;
use lofty::config::WriteOptions;
use lofty::file::{FileType, TaggedFile};
use lofty::id3::v2::{BinaryFrame, Frame, FrameId, Id3v2Tag};
use lofty::picture::{Picture, PictureType};
use lofty::prelude::{Accessor, AudioFile, ItemKey, TagExt, TaggedFileExt};
use lofty::probe::Probe;
use lofty::tag::{Tag, TagItem, TagType};
use rayon::prelude::*;
use windows::{
    core::Interface,
    core::HSTRING,
    Storage::{
        FileProperties::{ThumbnailMode, ThumbnailType},
        StorageFile,
        Streams::{DataReader, IInputStream},
    },
    Win32::System::Com::{CoInitializeEx, CoUninitialize, COINIT_MULTITHREADED},
};

use crate::frb_generated::StreamSink;
use crate::index_scan::ScanLease;

use super::logger::log_to_dart;

#[path = "metadata_id3_compat.rs"]
mod id3_compat;
#[path = "incremental_index.rs"]
mod incremental_index;

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

const INDEX_VERSION: u64 = 113;
const CLASSIFICATION_VERSION: u64 = 1;
const DURATION_VERSION: u64 = 1;
static METADATA_TRANSACTION_ID: AtomicU64 = AtomicU64::new(0);
static METADATA_EDIT_LOCK: Mutex<()> = Mutex::new(());
static INDEX_REFRESH_LOCK: Mutex<()> = Mutex::new(());

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

/// Prepare a unique cancellation identity before dispatching a native scan.
#[flutter_rust_bridge::frb(sync)]
pub fn create_index_scan_task() -> anyhow::Result<String> {
    crate::index_scan::create()
}

/// Returns cancelling, committing, or finished; never interrupts a commit.
#[flutter_rust_bridge::frb(sync)]
pub fn cancel_index_scan_task(task_id: String) -> String {
    crate::index_scan::cancel(&task_id)
}

#[flutter_rust_bridge::frb(sync)]
pub fn release_index_scan_task(task_id: String) {
    crate::index_scan::release(&task_id);
}

pub fn update_audio_metadata(
    path: String,
    file_name: String,
    title: String,
    artist: String,
    album: String,
    picture_path: Option<String>,
    expected_fingerprint: Option<String>,
) -> anyhow::Result<String> {
    let _edit_guard = METADATA_EDIT_LOCK.lock().map_err(|_| {
        metadata_message(
            "TAG_EDIT_UNAVAILABLE",
            "歌曲信息编辑器尚未恢复，请重新启动播放器后重试",
        )
    })?;
    let old_path = PathBuf::from(&path);
    check_metadata_fingerprint(&old_path, expected_fingerprint.as_deref())?;
    let source_metadata = fs::metadata(&old_path).map_err(|error| {
        if error.kind() == io::ErrorKind::NotFound {
            metadata_io_error("TAG_SOURCE_MISSING", "音频文件不存在", error)
        } else {
            metadata_io_error("TAG_SOURCE_UNREADABLE", "无法访问音频文件", error)
        }
    })?;
    if !source_metadata.is_file() {
        return Err(metadata_message(
            "TAG_SOURCE_INVALID",
            "所选路径不是可编辑的音频文件",
        ));
    }
    if source_metadata.permissions().readonly() {
        return Err(metadata_message(
            "TAG_SOURCE_READ_ONLY",
            "音频文件为只读；播放器不会自动移除只读属性",
        ));
    }

    // A batch edit keeps the exact existing basename, including legal leading
    // spaces. Validate only a name the user actually wants to change.
    let sanitized_name = if old_path.file_name() == Some(std::ffi::OsStr::new(&file_name)) {
        file_name.clone()
    } else {
        sanitize_file_name(&file_name)
            .map_err(|error| metadata_error("TAG_INVALID_FILENAME", "文件名无效", error))?
    };
    let extension = old_path
        .extension()
        .map(|value| value.to_string_lossy().to_string())
        .unwrap_or_default();
    let mut target_name = sanitized_name;
    match Path::new(&target_name).extension() {
        Some(requested) if !extension.is_empty() => {
            if !requested.to_string_lossy().eq_ignore_ascii_case(&extension) {
                return Err(metadata_message(
                    "TAG_RENAME_EXTENSION",
                    "重命名不能改变音频文件扩展名",
                ));
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
        .ok_or_else(|| metadata_message("TAG_SOURCE_INVALID", "音频文件没有父文件夹"))?;
    let new_path = parent.join(target_name);

    if new_path != old_path && new_path.exists() && !same_existing_file(&old_path, &new_path) {
        return Err(metadata_message(
            "TAG_TARGET_EXISTS",
            "目标文件名已存在，请换一个名称",
        ));
    }

    write_metadata_with_expectation(
        &old_path,
        &new_path,
        &title,
        &artist,
        &album,
        picture_path.as_deref(),
        expected_fingerprint.as_deref(),
    )?;

    Ok(new_path.to_string_lossy().to_string())
}

fn metadata_message(code: &str, message: impl AsRef<str>) -> anyhow::Error {
    anyhow::anyhow!("{}|{}", code, message.as_ref())
}

fn metadata_error(code: &str, message: &str, error: impl std::fmt::Display) -> anyhow::Error {
    metadata_message(code, format!("{}：{}", message, error))
}

fn metadata_io_error(code: &str, message: &str, error: io::Error) -> anyhow::Error {
    // Windows sharing violations differ from permissions and cloud-provider
    // availability. Never remove attributes or stop playback automatically.
    match error.raw_os_error() {
        Some(32 | 33) if cfg!(windows) => metadata_error(
            "TAG_FILE_BUSY",
            &format!("{message}；文件正在被占用，请先切换当前歌曲并关闭其他占用程序后重试"),
            error,
        ),
        Some(112) if cfg!(windows) => metadata_error(
            "TAG_NO_SPACE",
            &format!("{message}；磁盘空间不足，无法完成安全副本写入"),
            error,
        ),
        _ if error.kind() == io::ErrorKind::PermissionDenied => metadata_error(
            "TAG_ACCESS_DENIED",
            &format!("{message}；没有文件或所在文件夹的写入权限，播放器不会修改权限或只读属性"),
            error,
        ),
        _ => metadata_error(code, message, error),
    }
}

fn same_existing_file(source: &Path, target: &Path) -> bool {
    // Windows is normally case-insensitive; a case-only rename must not be
    // mistaken for a collision. Canonical paths avoid accepting merely similar
    // names in a case-sensitive directory or replacing a different file.
    if !source
        .file_name()
        .zip(target.file_name())
        .is_some_and(|(a, b)| {
            a.to_string_lossy()
                .eq_ignore_ascii_case(&b.to_string_lossy())
        })
    {
        return false;
    }
    match (source.canonicalize(), target.canonicalize()) {
        (Ok(source), Ok(target)) => source == target,
        _ => false,
    }
}

fn move_file_without_replacing(source: &Path, target: &Path) -> io::Result<()> {
    #[cfg(windows)]
    {
        use std::os::windows::ffi::OsStrExt;
        use windows::Win32::Storage::FileSystem::{MoveFileExW, MOVEFILE_WRITE_THROUGH};
        // canonicalize the existing parents, not the absent target. This keeps
        // Rust's extended-length Windows paths for long Unicode filenames.
        let absolute = |path: &Path| -> io::Result<PathBuf> {
            let parent = path
                .parent()
                .ok_or_else(|| io::Error::from(io::ErrorKind::InvalidInput))?;
            let name = path
                .file_name()
                .ok_or_else(|| io::Error::from(io::ErrorKind::InvalidInput))?;
            Ok(parent.canonicalize()?.join(name))
        };
        let source = absolute(source)?;
        let target = absolute(target)?;
        let from: Vec<_> = source.as_os_str().encode_wide().chain(Some(0)).collect();
        let to: Vec<_> = target.as_os_str().encode_wide().chain(Some(0)).collect();
        // Deliberately omit MOVEFILE_REPLACE_EXISTING. A target created by
        // another program while tags are being verified must never be erased.
        unsafe {
            MoveFileExW(
                windows::core::PCWSTR(from.as_ptr()),
                windows::core::PCWSTR(to.as_ptr()),
                MOVEFILE_WRITE_THROUGH,
            )
        }
        .map_err(|error| io::Error::from_raw_os_error((error.code().0 as u32 & 0xffff) as i32))
    }
    #[cfg(not(windows))]
    {
        // Transaction files are in the same directory/filesystem. Linking has
        // no-overwrite semantics, unlike rename on Unix.
        fs::hard_link(source, target)?;
        fs::remove_file(source)
    }
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

fn check_metadata_fingerprint(source: &Path, expected: Option<&str>) -> anyhow::Result<()> {
    if let Some(expected) = expected {
        let actual = super::metadata_preflight::metadata_fingerprint(source)?;
        anyhow::ensure!(
            actual == expected,
            "TAG_SOURCE_CHANGED|预览后文件发生变化，已跳过修改"
        );
    }
    Ok(())
}

#[cfg(test)]
fn write_metadata_safely(
    source_path: &Path,
    target_path: &Path,
    title: &str,
    artist: &str,
    album: &str,
    picture_path: Option<&str>,
) -> anyhow::Result<()> {
    write_metadata_with_expectation(
        source_path,
        target_path,
        title,
        artist,
        album,
        picture_path,
        None,
    )
}

fn write_metadata_with_expectation(
    source_path: &Path,
    target_path: &Path,
    title: &str,
    artist: &str,
    album: &str,
    picture_path: Option<&str>,
    expected_fingerprint: Option<&str>,
) -> anyhow::Result<()> {
    check_metadata_fingerprint(source_path, expected_fingerprint)?;
    // Probe from bytes rather than the extension. This prevents a transcoded or
    // misnamed file from being handed to a writer for an unrelated container.
    if id3_compat::has_empty_text_frame(source_path)
        && id3_compat::try_write_expected(
            source_path,
            target_path,
            title,
            artist,
            album,
            picture_path,
            expected_fingerprint,
        )?
    {
        return Ok(());
    }
    let mut tagged_file = match probe_tagged_audio(source_path, "TAG_FORMAT_UNKNOWN") {
        Ok(file) => file,
        Err(error) => {
            if error.to_string().starts_with("TAG_PARSE_UNSUPPORTED|")
                && id3_compat::try_write_expected(
                    source_path,
                    target_path,
                    title,
                    artist,
                    album,
                    picture_path,
                    expected_fingerprint,
                )
                .map_err(|failure| {
                    if failure.to_string().starts_with("TAG_") {
                        failure
                    } else {
                        metadata_error(
                            "TAG_COMPAT_FAILED",
                            "兼容编辑未能完成，已保留原文件",
                            failure,
                        )
                    }
                })?
            {
                return Ok(());
            }
            return Err(error);
        }
    };
    let original_file_type = tagged_file.file_type();
    let original_properties = AudioPropertiesSnapshot::from(&tagged_file);
    let tag_type = tagged_file.primary_tag_type();
    if !tagged_file.supports_tag_type(tag_type) {
        return Err(metadata_message(
            "TAG_FORMAT_UNSUPPORTED",
            format!("识别到的 {:?} 音频格式不支持可写标签", original_file_type),
        ));
    }
    let preserved = PreservedMetadata::capture(&tagged_file, tag_type, picture_path.is_some());
    ensure_tag(&mut tagged_file, tag_type).map_err(|error| {
        metadata_error(
            "TAG_FORMAT_UNSUPPORTED",
            "音频格式不支持创建可写标签",
            error,
        )
    })?;

    {
        let tag = tagged_file
            .primary_tag_mut()
            .ok_or_else(|| metadata_message("TAG_FORMAT_UNSUPPORTED", "无法创建可写的主标签"))?;
        apply_tag_values(tag, title, artist, album, picture_path)?;
    }
    let expected_front_picture = tagged_file
        .primary_tag()
        .and_then(|tag| tag.get_picture_type(PictureType::CoverFront))
        .cloned();

    let mut temporary = TransactionPath::copy_of(source_path, "edit")?;
    let write_result = catch_unwind(AssertUnwindSafe(|| {
        // Only persist the tag the editor actually changed. `TaggedFile::save`
        // rewrites every legacy/auxiliary tag in the container. Besides being
        // unnecessary and weakening our preservation guarantee, Lofty 0.21's
        // ID3v1 writer truncates a Rust String at byte 30 and panics when that
        // offset falls inside a Unicode scalar. The copied file already holds
        // all untouched tags byte-for-byte; writing only the primary tag keeps
        // them intact and removes that unsafe legacy rewrite path entirely.
        let tag = tagged_file
            .primary_tag()
            .ok_or_else(|| metadata_message("TAG_FORMAT_UNSUPPORTED", "无法创建可写的主标签"))?;
        save_edited_primary_tag(
            tag,
            source_path,
            temporary.path(),
            original_file_type,
            picture_path.is_some(),
        )
    }));
    match write_result {
        Ok(result) => result?,
        Err(payload) => {
            return Err(metadata_message(
                "TAG_WRITER_PANIC",
                format!(
                    "标签写入器异常退出，原文件未被修改：{}",
                    panic_payload_to_string(payload.as_ref())
                ),
            ));
        }
    }

    OpenOptions::new()
        .read(true)
        .write(true)
        .open(temporary.path())
        .and_then(|file| file.sync_all())
        .map_err(|error| metadata_io_error("TAG_WRITE_FAILED", "无法同步临时副本", error))?;

    let verified = match probe_tagged_audio(temporary.path(), "TAG_VERIFY_FORMAT") {
        Ok(file) => file,
        Err(error) if error.to_string().starts_with("TAG_PARSE_UNSUPPORTED|") => {
            // A readable source can expose a writer-only encoding limitation
            // (for example an empty UTF-16 APIC description). No commit has
            // occurred: discard the invalid temporary output before trying the
            // exact same bounded, plain-ID3 path used for parser limitations.
            drop(temporary);
            if id3_compat::try_write_expected(
                source_path,
                target_path,
                title,
                artist,
                album,
                picture_path,
                expected_fingerprint,
            )? {
                return Ok(());
            }
            return Err(error);
        }
        Err(error) => return Err(error),
    };
    verify_metadata_edit(
        &verified,
        original_file_type,
        &original_properties,
        &preserved,
        tag_type,
        title,
        artist,
        album,
        picture_path.is_some(),
        expected_front_picture.as_ref(),
    )?;

    check_metadata_fingerprint(source_path, expected_fingerprint)?;
    replace_with_rollback(source_path, target_path, &mut temporary)?;

    Ok(())
}

pub(crate) fn probe_tagged_audio(path: &Path, error_code: &str) -> anyhow::Result<TaggedFile> {
    let mut file = fs::File::open(path)
        .map_err(|error| metadata_io_error("TAG_SOURCE_UNREADABLE", "无法读取音频文件", error))?;
    // Lofty's MPEG sync search may misidentify an ASF header as MPEG even
    // though the filename is .mp3. Windows playback support is not evidence
    // that our transactional tag writer supports this actual container.
    let mut signature = [0; 16];
    if file.read_exact(&mut signature).is_ok()
        && signature
            == [
                0x30, 0x26, 0xb2, 0x75, 0x8e, 0x66, 0xcf, 0x11, 0xa6, 0xd9, 0x00, 0xaa, 0x00, 0x62,
                0xce, 0x6c,
            ]
    {
        return Err(metadata_message("TAG_FORMAT_UNSUPPORTED",
            "实际音频容器为 ASF/WMA；播放器支持播放，但暂不支持安全编辑该容器的标签。原文件未被修改"));
    }
    if &signature[..3] == b"ID3" && signature[6..10].iter().all(|byte| byte & 0x80 == 0) {
        let tag_size = signature[6..10]
            .iter()
            .fold(0u64, |size, byte| (size << 7) | *byte as u64);
        let footer = if signature[3] == 4 && signature[5] & 0x10 != 0 {
            10
        } else {
            0
        };
        let mut atom = [0; 8];
        if file.seek(SeekFrom::Start(10 + tag_size + footer)).is_ok()
            && file.read_exact(&mut atom).is_ok()
            && &atom[4..8] == b"ftyp"
        {
            return Err(metadata_message("TAG_LAYOUT_UNSUPPORTED",
                "实际内容为带前置 ID3 标签的 MP4 容器；此混合布局暂不支持安全编辑，原文件和扩展名均未修改"));
        }
    }
    file.seek(SeekFrom::Start(0))
        .map_err(|error| metadata_io_error("TAG_SOURCE_UNREADABLE", "无法读取音频文件", error))?;
    let probe = Probe::new(BufReader::new(file))
        .guess_file_type()
        .map_err(|error| metadata_error(error_code, "探测音频内容失败", error))?;
    if probe.file_type().is_none() {
        let declared_unsupported = path
            .extension()
            .map(|extension| extension.to_ascii_lowercase())
            .and_then(|extension| SUPPORT_FORMAT.get(&extension.to_string_lossy()))
            .is_some_and(|supported| !*supported);
        return Err(metadata_message(
            if declared_unsupported {
                "TAG_FORMAT_UNSUPPORTED"
            } else {
                error_code
            },
            if declared_unsupported {
                "该音频格式目前仅支持读取或播放，不支持安全写入标签"
            } else {
                "当前标签编辑器无法识别此音频容器或标签组合；这不代表文件无法播放。原文件未被修改"
            },
        ));
    }
    probe.read().map_err(|error| {
        metadata_error(
            "TAG_PARSE_UNSUPPORTED",
            "当前标签编辑器无法完整解析此容器或标签组合，已保留原文件",
            error,
        )
    })
}

fn save_edited_primary_tag(
    tag: &Tag,
    source: &Path,
    destination: &Path,
    file_type: FileType,
    replaces_front: bool,
) -> anyhow::Result<()> {
    let result = if tag.tag_type() == TagType::Id3v2 {
        // Lofty 0.21's generic Tag::save uses borrowed FrameRefs that replace
        // COMM/USLT language+description with defaults. Even its owned generic
        // conversion may normalize unrelated multi-value frames. Keep the
        // format-specific tag and edit only the explicitly requested fields.
        let mut file = BufReader::new(fs::File::open(source).map_err(|error| {
            metadata_io_error("TAG_SOURCE_UNREADABLE", "无法读取音频文件", error)
        })?);
        let options = lofty::config::ParseOptions::default().read_properties(false);
        let parsed = match file_type {
            FileType::Mpeg => lofty::mpeg::MpegFile::read_from(&mut file, options)
                .map(|file| file.id3v2().cloned()),
            FileType::Aac => {
                lofty::aac::AacFile::read_from(&mut file, options).map(|file| file.id3v2().cloned())
            }
            FileType::Aiff => lofty::iff::aiff::AiffFile::read_from(&mut file, options)
                .map(|file| file.id3v2().cloned()),
            FileType::Wav => lofty::iff::wav::WavFile::read_from(&mut file, options)
                .map(|file| file.id3v2().cloned()),
            _ => {
                return Err(metadata_message(
                    "TAG_FORMAT_UNSUPPORTED",
                    "该音频容器暂不支持安全编辑 ID3 标签",
                ))
            }
        };
        let mut native = parsed
            .map_err(|error| {
                metadata_error(
                    "TAG_PARSE_UNSUPPORTED",
                    "无法完整读取原生 ID3 标签，已保留原文件",
                    error,
                )
            })?
            .unwrap_or_default();
        native.set_title(tag.title().unwrap_or_default().into_owned());
        native.set_artist(tag.artist().unwrap_or_default().into_owned());
        native.set_album(tag.album().unwrap_or_default().into_owned());
        // The parser has already decoded whole-tag unsynchronisation. Lofty
        // 0.21 writes decoded frame payloads without escaping them again, but
        // otherwise copies this flag and creates an unreadable tag. Correct
        // only this known representation flag; retain every other tag flag.
        normalize_decoded_id3_flags(&mut native)?;
        if replaces_front {
            native.remove_picture_type(PictureType::CoverFront);
            if let Some(picture) = tag.get_picture_type(PictureType::CoverFront) {
                native.insert_picture(picture.clone());
            }
        }
        preserve_legacy_language_frames(&mut native);
        native.save_to_path(destination, WriteOptions::default())
    } else {
        tag.save_to_path(destination, WriteOptions::default())
    };
    result.map_err(|error| {
        metadata_error(
            "TAG_WRITE_FAILED",
            "写入临时副本失败，原文件未被修改",
            error,
        )
    })
}

fn normalize_decoded_id3_flags(tag: &mut Id3v2Tag) -> anyhow::Result<()> {
    // The writer also emits plain decoded frame bytes, without the original
    // frame-level escape bytes or consumed data-length indicator. Never apply
    // this normalization to compression/encryption, which need their own
    // encoding implementation and must remain a safe refusal here.
    if (&*tag).into_iter().any(|frame| {
        let flags = frame.flags();
        flags.compression || flags.encryption.is_some()
    }) {
        return Err(metadata_message(
            "TAG_LAYOUT_UNSUPPORTED",
            "当前写入器无法安全重编码压缩或加密 ID3 帧，已保留原文件及全部标签",
        ));
    }
    let mut flags = *tag.flags();
    flags.unsynchronisation = false;
    tag.set_flags(flags);
    let decoded: Vec<_> = (&*tag)
        .into_iter()
        .filter(|frame| {
            let flags = frame.flags();
            flags.unsynchronisation || flags.data_length_indicator.is_some()
        })
        .cloned()
        .collect();
    // Binary/opaque frame equality includes flags. Inserting a normalized
    // clone alone would append it beside the stale encoded-flags version.
    tag.retain(|frame| !decoded.contains(frame));
    for mut frame in decoded {
        let mut flags = frame.flags();
        flags.unsynchronisation = false;
        flags.data_length_indicator = None;
        frame.set_flags(flags);
        if tag.insert(frame).is_some() {
            return Err(metadata_message(
                "TAG_LAYOUT_UNSUPPORTED",
                "ID3 帧表示转换出现重复标识，已保留原文件及全部标签",
            ));
        }
    }
    Ok(())
}

fn preserve_legacy_language_frames(tag: &mut Id3v2Tag) {
    // Some readable legacy files use spaces/NUL in the three language bytes.
    // Preserve those bytes, descriptor and text, rather than invent a language
    // or discard the untouched lyric. Binary frames bypass only Lofty's
    // language validator; the normal post-write semantic check still applies.
    for id in ["COMM", "USLT"] {
        let frame_id = FrameId::Valid(std::borrow::Cow::Borrowed(id));
        let needs_preservation = (&*tag).into_iter().any(|frame| match frame {
            Frame::Comment(value) if id == "COMM" => {
                value.language.iter().any(|c| !c.is_ascii_alphabetic())
            }
            Frame::UnsynchronizedText(value) if id == "USLT" => {
                value.language.iter().any(|c| !c.is_ascii_alphabetic())
            }
            _ => false,
        });
        if !needs_preservation {
            continue;
        }
        let frames: Vec<_> = tag.remove(&frame_id).collect();
        for frame in frames {
            let legacy = match &frame {
                Frame::Comment(value)
                    if value.language.iter().any(|c| !c.is_ascii_alphabetic()) =>
                {
                    Some((
                        value.language,
                        value.description.as_str(),
                        value.content.as_str(),
                    ))
                }
                Frame::UnsynchronizedText(value)
                    if value.language.iter().any(|c| !c.is_ascii_alphabetic()) =>
                {
                    Some((
                        value.language,
                        value.description.as_str(),
                        value.content.as_str(),
                    ))
                }
                _ => None,
            };
            if let Some((language, description, content)) = legacy {
                // The writer above emits ID3v2.4, whose UTF-8 text encoding is 3.
                let mut bytes = vec![3];
                bytes.extend_from_slice(&language);
                bytes.extend_from_slice(description.as_bytes());
                bytes.push(0);
                bytes.extend_from_slice(content.as_bytes());
                tag.insert(Frame::Binary(BinaryFrame::new(frame_id.clone(), bytes)));
            } else {
                tag.insert(frame);
            }
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct AudioPropertiesSnapshot {
    duration: Duration,
    audio_bitrate: Option<u32>,
    sample_rate: Option<u32>,
    bit_depth: Option<u8>,
    channels: Option<u8>,
}

impl From<&TaggedFile> for AudioPropertiesSnapshot {
    fn from(file: &TaggedFile) -> Self {
        let properties = file.properties();
        Self {
            duration: properties.duration(),
            audio_bitrate: properties.audio_bitrate(),
            sample_rate: properties.sample_rate(),
            bit_depth: properties.bit_depth(),
            channels: properties.channels(),
        }
    }
}

#[derive(Clone)]
struct PreservedTag {
    tag_type: TagType,
    items: Vec<TagItem>,
    pictures: Vec<Picture>,
}

struct PreservedMetadata(Vec<PreservedTag>);

impl PreservedMetadata {
    fn capture(file: &TaggedFile, edited_tag_type: TagType, replaces_front: bool) -> Self {
        Self(
            file.tags()
                .iter()
                .map(|tag| PreservedTag {
                    tag_type: tag.tag_type(),
                    items: tag
                        .items()
                        .filter(|item| {
                            tag.tag_type() != edited_tag_type || !is_edited_metadata_key(item.key())
                        })
                        .cloned()
                        .collect(),
                    pictures: tag
                        .pictures()
                        .iter()
                        .filter(|picture| {
                            tag.tag_type() != edited_tag_type
                                || !replaces_front
                                || picture.pic_type() != PictureType::CoverFront
                        })
                        .cloned()
                        .collect(),
                })
                .collect(),
        )
    }

    fn verify(&self, file: &TaggedFile, edited_tag_type: TagType, replaces_front: bool) -> bool {
        self.0.iter().all(|expected| {
            let Some(actual) = file.tag(expected.tag_type) else {
                return false;
            };
            let actual_items: Vec<&TagItem> = actual
                .items()
                .filter(|item| {
                    expected.tag_type != edited_tag_type || !is_edited_metadata_key(item.key())
                })
                .collect();
            let actual_pictures: Vec<&Picture> = actual
                .pictures()
                .iter()
                .filter(|picture| {
                    expected.tag_type != edited_tag_type
                        || !replaces_front
                        || picture.pic_type() != PictureType::CoverFront
                })
                .collect();
            multiset_contains(&actual_items, &expected.items)
                && actual_items.len() == expected.items.len()
                && multiset_contains(&actual_pictures, &expected.pictures)
                && actual_pictures.len() == expected.pictures.len()
        })
    }
}

fn multiset_contains<T: PartialEq>(actual: &[&T], expected: &[T]) -> bool {
    let mut unmatched = actual.to_vec();
    for item in expected {
        let Some(index) = unmatched.iter().position(|candidate| *candidate == item) else {
            return false;
        };
        unmatched.remove(index);
    }
    true
}

fn is_edited_metadata_key(key: &ItemKey) -> bool {
    key == &ItemKey::TrackTitle || key == &ItemKey::TrackArtist || key == &ItemKey::AlbumTitle
}

#[allow(clippy::too_many_arguments)]
fn verify_metadata_edit(
    file: &TaggedFile,
    original_file_type: FileType,
    original_properties: &AudioPropertiesSnapshot,
    preserved: &PreservedMetadata,
    edited_tag_type: TagType,
    title: &str,
    artist: &str,
    album: &str,
    replaces_front: bool,
    expected_front: Option<&Picture>,
) -> anyhow::Result<()> {
    if file.file_type() != original_file_type {
        return Err(metadata_message(
            "TAG_VERIFY_FORMAT",
            "写入后的音频格式与原文件不一致，已保留原文件",
        ));
    }
    if AudioPropertiesSnapshot::from(file) != *original_properties {
        return Err(metadata_message(
            "TAG_VERIFY_AUDIO",
            "写入后音频流属性发生变化，已保留原文件",
        ));
    }
    let Some(tag) = file.tag(edited_tag_type) else {
        return Err(metadata_message(
            "TAG_VERIFY_FIELDS",
            "回读时找不到刚写入的主标签，已保留原文件",
        ));
    };
    if tag.title().as_deref() != Some(title)
        || tag.artist().as_deref() != Some(artist)
        || tag.album().as_deref() != Some(album)
    {
        return Err(metadata_message(
            "TAG_VERIFY_FIELDS",
            "回读的歌曲名、艺术家或专辑与请求不一致，已保留原文件",
        ));
    }
    if replaces_front {
        let written = tag.get_picture_type(PictureType::CoverFront);
        let picture_matches = written
            .zip(expected_front)
            .is_some_and(|(actual, expected)| {
                actual.pic_type() == expected.pic_type() && actual.data() == expected.data()
            });
        if !picture_matches {
            return Err(metadata_message(
                "TAG_VERIFY_COVER",
                "回读的专辑封面与所选图片不一致，已保留原文件",
            ));
        }
    }
    if !preserved.verify(file, edited_tag_type, replaces_front) {
        return Err(metadata_message(
            "TAG_VERIFY_PRESERVATION",
            "未编辑的标签、歌词或图片未能完整保留，已取消替换",
        ));
    }
    Ok(())
}

struct TransactionPath {
    path: PathBuf,
    remove_on_drop: bool,
}

impl TransactionPath {
    fn copy_of(source: &Path, purpose: &str) -> anyhow::Result<Self> {
        let path = reserve_transaction_path(source, purpose)?;
        let guard = Self {
            path,
            remove_on_drop: true,
        };
        fs::copy(source, guard.path()).map_err(|error| {
            metadata_io_error("TAG_COPY_FAILED", "无法创建同目录安全副本", error)
        })?;
        Ok(guard)
    }

    fn path(&self) -> &Path {
        &self.path
    }

    fn disarm(&mut self) {
        self.remove_on_drop = false;
    }
}

impl Drop for TransactionPath {
    fn drop(&mut self) {
        if self.remove_on_drop {
            let _ = fs::remove_file(&self.path);
        }
    }
}

fn reserve_transaction_path(source: &Path, purpose: &str) -> anyhow::Result<PathBuf> {
    let parent = source.parent().ok_or_else(|| {
        metadata_message("TAG_SOURCE_INVALID", "音频文件没有可用于事务写入的父目录")
    })?;
    let extension = source
        .extension()
        .and_then(|value| value.to_str())
        .unwrap_or("");
    for _ in 0..128 {
        let id = METADATA_TRANSACTION_ID.fetch_add(1, Ordering::Relaxed);
        let name = if extension.is_empty() {
            format!(".dan-player-{}-{}-{}", purpose, std::process::id(), id)
        } else {
            format!(
                ".dan-player-{}-{}-{}.{}",
                purpose,
                std::process::id(),
                id,
                extension
            )
        };
        let candidate = parent.join(name);
        match OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&candidate)
        {
            Ok(_) => return Ok(candidate),
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => {
                return Err(metadata_io_error(
                    "TAG_COPY_FAILED",
                    "无法在音频所在目录创建安全副本",
                    error,
                ));
            }
        }
    }
    Err(metadata_message(
        "TAG_COPY_FAILED",
        "无法分配唯一的临时文件名",
    ))
}

fn unused_transaction_path(source: &Path, purpose: &str) -> anyhow::Result<PathBuf> {
    let reserved = reserve_transaction_path(source, purpose)?;
    fs::remove_file(&reserved)
        .map_err(|error| metadata_io_error("TAG_REPLACE_FAILED", "无法准备回滚文件路径", error))?;
    Ok(reserved)
}

fn replace_with_rollback(
    source_path: &Path,
    target_path: &Path,
    temporary: &mut TransactionPath,
) -> anyhow::Result<()> {
    let backup_path = unused_transaction_path(source_path, "backup")?;
    move_file_without_replacing(source_path, &backup_path).map_err(|error| {
        metadata_io_error(
            "TAG_REPLACE_FAILED",
            "无法暂存原文件；原文件未被修改",
            error,
        )
    })?;

    match move_file_without_replacing(temporary.path(), target_path) {
        Ok(()) => {
            temporary.disarm();
            if let Err(error) = fs::remove_file(&backup_path) {
                log_to_dart(format!(
                    "metadata edit succeeded but recovery copy could not be removed: {:?}: {}",
                    backup_path, error
                ));
            }
            Ok(())
        }
        Err(replace_error) => {
            let rollback =
                move_file_without_replacing(&backup_path, source_path).or_else(|rename_error| {
                    if source_path.exists() {
                        return Err(rename_error);
                    }
                    fs::File::open(&backup_path)
                        .and_then(|mut backup| {
                            let mut restored = OpenOptions::new()
                                .write(true)
                                .create_new(true)
                                .open(source_path)?;
                            io::copy(&mut backup, &mut restored)?;
                            restored.sync_all()
                        })
                        .map_err(|_| rename_error)
                });
            match rollback {
                Ok(()) => Err(metadata_io_error(
                    "TAG_REPLACE_FAILED",
                    "替换文件失败，已恢复原文件",
                    replace_error,
                )),
                Err(rollback_error) => Err(metadata_message(
                    "TAG_ROLLBACK_FAILED",
                    format!(
                        "替换失败且自动回滚未完成；原始副本保留在 {:?}。替换错误：{}；回滚错误：{}",
                        backup_path, replace_error, rollback_error
                    ),
                )),
            }
        }
    }
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
            .map_err(|error| metadata_error("TAG_COVER_READ", "无法打开所选封面", error))?;
        let mut picture = Picture::from_reader(&mut pic_file)
            .map_err(|error| metadata_error("TAG_COVER_INVALID", "无法解析所选封面", error))?;
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

/// Extensions are only a discovery allow-list. Playback also accepts files
/// whose container does not match that extension, so metadata reads must
/// verify the bytes before selecting a parser instead of trusting the suffix.
fn read_tagged_file_by_content(path: impl AsRef<Path>) -> anyhow::Result<TaggedFile> {
    Ok(Probe::open(path)?.guess_file_type()?.read()?)
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
    composer: Option<String>,
    album_artist: Option<String>,
    classification_version: u64,
    track: Option<u32>,
    /// in secs
    duration: u64,
    /// Successful duration-reader algorithm version. Missing old values are
    /// re-read once by the next incremental refresh.
    duration_version: u64,
    /// kbps
    bitrate: Option<u32>,
    sample_rate: Option<u32>,
    /// Language tag, not a guess based on the title or artist.
    language: Option<String>,
    /// Source file length when indexed; the statistics page rechecks it.
    file_size: Option<u64>,
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
            composer: None,
            album_artist: None,
            // Filename-only recovery has not successfully read these tags.
            classification_version: 0,
            track: None,
            duration: 0,
            duration_version: 0,
            bitrate: None,
            sample_rate: None,
            language: None,
            file_size: None,
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
            "composer": self.composer,
            "album_artist": self.album_artist,
            "classification_version": self.classification_version,
            "track": self.track,
            "duration": self.duration,
            "duration_version": self.duration_version,
            "bitrate": self.bitrate,
            "sample_rate": self.sample_rate,
            "language": self.language,
            "file_size": self.file_size,
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
        if is_metadata_transaction_path(path) {
            return None;
        }
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

        let with_file_size = |mut audio: Audio| {
            audio.file_size = Some(file_metadata.len());
            audio
        };

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
                        // Use only the already-needed Windows fallback. A
                        // missing composer must not cause an extra WinRT read.
                        if value.composer.is_none() && windows_value.composer.is_some() {
                            value.composer = windows_value.composer;
                            used_windows = true;
                        }
                        if value.album_artist.is_none() && windows_value.album_artist.is_some() {
                            value.album_artist = windows_value.album_artist;
                            used_windows = true;
                        }
                        if used_windows {
                            value.by = Some("Lofty+Windows".to_string());
                        }
                    }
                }
                return Some(with_file_size(value));
            }

            match Self::read_by_win_music_properties(path, modified, created) {
                Ok(value) => Some(with_file_size(value)),
                Err(err) => {
                    log_to_dart(format!("{:?}: {}", path, err));
                    Self::new_with_path(path, None).map(with_file_size)
                }
            }
        } else {
            match Self::read_by_win_music_properties(path, modified, created) {
                Ok(value) => Some(with_file_size(value)),
                Err(err) => {
                    log_to_dart(format!("{:?}: {}", path, err));
                    Self::new_with_path(path, None).map(with_file_size)
                }
            }
        }
    }

    /// 使用 lofty 获取音乐标签。只在文件名不正确、没有标签或包含不支持的编码时返回 None
    fn read_by_lofty(path: impl AsRef<Path>, modified: u64, created: u64) -> Option<Self> {
        let path = path.as_ref();
        let tagged_file = match read_tagged_file_by_content(path) {
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
            composer: first_tag_text_with_source(&tags, &ItemKey::Composer).map(|(value, _)| value),
            album_artist: first_tag_text_with_source(&tags, &ItemKey::AlbumArtist)
                .map(|(value, _)| value),
            classification_version: CLASSIFICATION_VERSION,
            track,
            duration: properties.duration().as_secs(),
            duration_version: DURATION_VERSION,
            bitrate: properties.audio_bitrate(),
            sample_rate: properties.sample_rate(),
            language: first_tag_text_with_source(&tags, &ItemKey::Language).map(|(value, _)| value),
            file_size: None,
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

        let composers = music_properties.Composers().and_then(|values| {
            let mut names = Vec::new();
            for index in 0..values.Size()? {
                let name = values.GetAt(index)?.to_string();
                if !metadata_is_missing(&name) {
                    names.push(name.trim().to_string());
                }
            }
            Ok((!names.is_empty()).then(|| names.join("/")))
        });
        let album_artist = music_properties.AlbumArtist().map(|value| {
            let value = value.to_string();
            (!metadata_is_missing(&value)).then(|| value.trim().to_string())
        });
        let classification_version = if composers.is_ok() && album_artist.is_ok() {
            CLASSIFICATION_VERSION
        } else {
            0
        };

        Ok(Audio {
            title,
            artist,
            album,
            composer: composers.ok().flatten(),
            album_artist: album_artist.ok().flatten(),
            classification_version,
            track: Some(music_properties.TrackNumber()?),
            duration: duration.as_secs(),
            duration_version: DURATION_VERSION,
            bitrate: Some(music_properties.Bitrate()? / 1000),
            sample_rate: None,
            language: None,
            file_size: None,
            path: path.to_string_lossy().to_string(),
            modified,
            created,
            by: Some("Windows".to_string()),
            needs_windows_text_fallback: false,
        })
    }
}

fn is_supported_audio_path(path: &Path) -> bool {
    if is_metadata_transaction_path(path) {
        return false;
    }
    path.extension()
        .map(|extension| extension.to_ascii_lowercase())
        .and_then(|extension| SUPPORT_FORMAT.get(&extension.to_string_lossy()))
        .is_some()
}

/// Recovery copies intentionally stay beside the source so replacement can be
/// atomic. If Windows or a sync client temporarily prevents deleting one, a
/// later scan must never import that implementation detail as a duplicate song.
fn is_metadata_transaction_path(path: &Path) -> bool {
    let Some(stem) = path.file_stem().and_then(|value| value.to_str()) else {
        return false;
    };
    if !stem.starts_with('.') {
        return false;
    }
    [".dan-player-edit-", ".dan-player-backup-"]
        .iter()
        .any(|marker| {
            let Some((_, identifiers)) = stem.rsplit_once(marker) else {
                return false;
            };
            let mut parts = identifiers.split('-');
            matches!(
                (parts.next(), parts.next(), parts.next()),
                (Some(process), Some(sequence), None)
                    if !process.is_empty()
                        && !sequence.is_empty()
                        && process.bytes().all(|value| value.is_ascii_digit())
                        && sequence.bytes().all(|value| value.is_ascii_digit())
            )
        })
}

fn _get_picture_by_windows(
    path: &String,
    requested_size: u32,
) -> Result<Option<Vec<u8>>, windows::core::Error> {
    let _apartment = ComApartment::multithreaded();
    let file = StorageFile::GetFileFromPathAsync(&HSTRING::from(path))?.get()?;
    let thumbnail = file
        // The default MusicView thumbnail is small. Pass physical pixels, not
        // logical pixels/UseCurrentScale (Dart already accounts for View DPR).
        .GetThumbnailAsyncOverloadDefaultOptions(
            ThumbnailMode::MusicView,
            requested_size.clamp(1, 2048),
        )?
        .get()?;

    // MusicView falls back to the registered player's document icon. That is
    // not album artwork and must never become a persistent cover thumbnail.
    if thumbnail.Type()? != ThumbnailType::Image || thumbnail.Size()? > 16 * 1024 * 1024 {
        thumbnail.Close()?;
        return Ok(None);
    }

    let size = thumbnail.Size()? as u32;
    let stream: IInputStream = thumbnail.cast()?;

    let mut buffer = vec![0u8; size as usize];
    let data_reader = DataReader::CreateDataReader(&stream)?;
    data_reader.LoadAsync(size)?.get()?;
    data_reader.ReadBytes(&mut buffer)?;

    data_reader.Close()?;
    stream.Close()?;

    Ok(Some(buffer))
}

// Keep in sync with Dart ArtworkSize: enough pixels on *both* axes for
// BoxFit.cover, never upscale a small original, at most 4M thumbnail output
// pixels (16MiB RGBA). Source decoding/resampling can use more working memory.
fn cover_decode_dimensions(
    source_width: u32,
    source_height: u32,
    width: u32,
    height: u32,
) -> (u32, u32) {
    let source_width = source_width.max(1);
    let source_height = source_height.max(1);
    let needed = ((width.clamp(1, 2048) as f64 / source_width as f64)
        .max(height.clamp(1, 2048) as f64 / source_height as f64))
    .min(1.0);
    let budget = (4096.0 / source_width as f64)
        .min(4096.0 / source_height as f64)
        .min((4194304.0 / (source_width as f64 * source_height as f64)).sqrt());
    let scale = needed.min(budget);
    let dimension = |source: u32| {
        let scaled = source as f64 * scale;
        let result = if budget < needed {
            scaled.floor()
        } else {
            scaled.ceil()
        };
        (result as u32).clamp(1, source)
    };
    (dimension(source_width), dimension(source_height))
}

fn resize_picture(pic: &[u8], width: u32, height: u32) -> Option<Vec<u8>> {
    let mut reader = image::ImageReader::new(Cursor::new(pic))
        .with_guessed_format()
        .ok()?;
    let mut limits = image::Limits::default();
    limits.max_image_width = Some(16384);
    limits.max_image_height = Some(16384);
    limits.max_alloc = Some(128 * 1024 * 1024);
    reader.limits(limits);
    let loaded_pic = reader.decode().ok()?;
    let (result_width, result_height) =
        cover_decode_dimensions(loaded_pic.width(), loaded_pic.height(), width, height);
    let resized_img = if result_width == loaded_pic.width() && result_height == loaded_pic.height()
    {
        loaded_pic.to_rgba8()
    } else {
        imageops::resize(
            &loaded_pic,
            result_width,
            result_height,
            imageops::FilterType::Lanczos3,
        )
    };
    let mut output = Cursor::new(Vec::new());
    resized_img
        .write_to(&mut output, image::ImageFormat::Png)
        .ok()?;
    Some(output.into_inner())
}

fn _get_picture_by_lofty(path: &String, width: u32, height: u32) -> Option<Vec<u8>> {
    if let Some(picture) = id3_compat::read_picture(Path::new(path), width, height) {
        return Some(picture);
    }
    if let Ok(tagged_file) = read_tagged_file_by_content(path) {
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

    match _get_picture_by_windows(&path, width.max(height)) {
        Ok(Some(pic)) => resize_picture(&pic, width, height),
        Ok(None) => None,
        Err(err) => {
            log_to_dart(format!("fail to get pic: {}", err));
            None
        }
    }
}

fn _get_lyric_from_lofty(path: &String) -> Option<String> {
    if let Ok(tagged_file) = read_tagged_file_by_content(path) {
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
    task_id: Option<String>,
    sink: StreamSink<IndexActionState>,
) -> Result<(), io::Error> {
    let task = ScanLease::begin(task_id).map_err(io::Error::other)?;
    task.control.check().map_err(io::Error::other)?;
    let _guard = INDEX_REFRESH_LOCK
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    let path = PathBuf::from(index_path).join("index.json");
    let previous = read_index_json(&path).ok();
    let index = incremental_index::refresh_cancellable(
        previous
            .as_ref()
            .map(|(index, _)| index)
            .filter(|index| index["folders"].is_array()),
        &folders,
        true,
        &|path| Audio::read_from_path(path).map(|audio| audio.to_json_value()),
        &task.control,
        |progress| {
            let _ = sink.add(IndexActionState {
                progress,
                message: String::new(),
            });
        },
    )
    .map_err(io::Error::other)?;
    task.control.begin_commit().map_err(io::Error::other)?;
    let _ = sink.add(IndexActionState {
        progress: 1.0,
        message: "INDEX_PHASE_COMMITTING".into(),
    });
    write_index_json(
        &path,
        &index,
        previous.is_some_and(|(_, recovered)| recovered),
    )
}

fn needs_classification_backfill(audio: &serde_json::Value) -> bool {
    audio["classification_version"].as_u64().unwrap_or(0) < CLASSIFICATION_VERSION
}

fn needs_duration_backfill(audio: &serde_json::Value) -> bool {
    audio["duration_version"].as_u64().unwrap_or(0) < DURATION_VERSION
}

/// Backfill only newly supported tags. Keep old paths, order, timestamps and
/// extension fields intact. A failed read remains pending for a later refresh.
#[cfg(test)]
fn apply_audio_index_update(
    previous: &mut serde_json::Value,
    audio: Option<Audio>,
    classification_only: bool,
) -> bool {
    let Some(audio) = audio else {
        return false;
    };
    if classification_only {
        if audio.classification_version < CLASSIFICATION_VERSION {
            return false;
        }
        let Some(fields) = previous.as_object_mut() else {
            return false;
        };
        fields.insert("composer".to_string(), serde_json::json!(audio.composer));
        fields.insert(
            "album_artist".to_string(),
            serde_json::json!(audio.album_artist),
        );
        fields.insert(
            "classification_version".to_string(),
            serde_json::json!(audio.classification_version),
        );
    } else {
        *previous = audio.to_json_value();
    }
    true
}

#[cfg(test)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
enum IndexedPathState {
    Present,
    Missing,
}

/// `Path::exists` collapses access failures into `false`, which can erase a
/// library on an offline drive. A path is considered missing only after its
/// parent directory was enumerated successfully and the entry was absent.
#[cfg(test)]
fn indexed_path_state(path: &Path) -> io::Result<IndexedPathState> {
    match fs::symlink_metadata(path) {
        Ok(_) => Ok(IndexedPathState::Present),
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            let parent = path.parent().ok_or_else(|| {
                io::Error::new(
                    io::ErrorKind::NotFound,
                    format!("cannot confirm whether {:?} is missing", path),
                )
            })?;
            let target_name = path.file_name().ok_or_else(|| {
                io::Error::new(
                    io::ErrorKind::InvalidInput,
                    format!("indexed path has no file name: {:?}", path),
                )
            })?;
            for item in fs::read_dir(parent)? {
                let entry = item?;
                if entry.file_name() == target_name {
                    return Err(io::Error::new(
                        io::ErrorKind::PermissionDenied,
                        format!("{:?} is listed by its parent but cannot be inspected", path),
                    ));
                }
            }
            Ok(IndexedPathState::Missing)
        }
        Err(error) => Err(error),
    }
}

#[cfg(test)]
fn retain_confirmed_index_paths(
    entries: &mut Vec<serde_json::Value>,
    description: &str,
) -> anyhow::Result<()> {
    let decisions = entries
        .iter()
        .map(|entry| {
            let path = entry["path"].as_str().ok_or_else(|| {
                anyhow::anyhow!("INDEX_SCHEMA_INVALID|{}记录缺少路径", description)
            })?;
            indexed_path_state(Path::new(path))
                .map(|state| state == IndexedPathState::Present)
                .map_err(|error| {
                    anyhow::anyhow!(
                        "INDEX_SCAN_INCOMPLETE|无法确认{} {:?} 是否存在；本轮索引未保存：{}",
                        description,
                        path,
                        error
                    )
                })
        })
        .collect::<anyhow::Result<Vec<_>>>()?;
    let mut decisions = decisions.into_iter();
    entries.retain(|_| decisions.next().unwrap_or(false));
    Ok(())
}

/// Read-only recursive discovery plus size/nanosecond-time change detection.
/// The complete result is committed atomically; failed enumeration leaves the
/// old index intact. Full rebuilding is available through the separate API.
pub fn update_index(
    index_path: String,
    task_id: Option<String>,
    sink: StreamSink<IndexActionState>,
) -> anyhow::Result<()> {
    let task = ScanLease::begin(task_id)?;
    task.control.check()?;
    let _guard = INDEX_REFRESH_LOCK
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    let path = PathBuf::from(index_path).join("index.json");
    let (previous, recovered) = read_index_json(&path)?;
    let legacy;
    let previous = if previous.is_array() {
        legacy = serde_json::json!({"folders": previous.as_array().unwrap().iter().map(|folder|
            serde_json::json!({"path": folder["path"], "audios": []})).collect::<Vec<_>>()});
        &legacy
    } else {
        &previous
    };
    let roots = incremental_index::roots(previous)?;
    let index = incremental_index::refresh_cancellable(
        Some(previous),
        &roots,
        previous["version"].as_u64() != Some(INDEX_VERSION),
        &|path| Audio::read_from_path(path).map(|audio| audio.to_json_value()),
        &task.control,
        |progress| {
            let _ = sink.add(IndexActionState {
                progress,
                message: String::new(),
            });
        },
    )?;
    task.control.begin_commit()?;
    let _ = sink.add(IndexActionState {
        progress: 1.0,
        message: "INDEX_PHASE_COMMITTING".into(),
    });
    write_index_json(&path, &index, recovered)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    #[test]
    fn metadata_unchanged_basename_keeps_legal_leading_space() {
        let directory = test_directory("metadata_unchanged_basename");
        let source = directory.join(" source.mp3");
        write_minimal_mpeg_with_legacy_id3v1(&source);
        let result = update_audio_metadata(
            source.to_string_lossy().into_owned(),
            " source.mp3".into(),
            "Changed title".into(),
            "Artist".into(),
            "Album".into(),
            None,
            None,
        )
        .unwrap();
        assert_eq!(PathBuf::from(result), source);
        assert!(source.is_file());
        assert!(!directory.join("source.mp3").exists());
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn metadata_preview_fingerprint_rejects_changed_source_before_writing() {
        let directory = test_directory("metadata_fingerprint");
        let source = directory.join("source.mp3");
        write_minimal_mpeg_with_legacy_id3v1(&source);
        let expected = super::super::metadata_preflight::metadata_fingerprint(&source).unwrap();
        let mut externally_changed = fs::read(&source).unwrap();
        externally_changed.extend_from_slice(b"external edit");
        fs::write(&source, &externally_changed).unwrap();
        let error = update_audio_metadata(
            source.to_string_lossy().into_owned(),
            "source.mp3".into(),
            "New".into(),
            "Artist".into(),
            "Album".into(),
            None,
            Some(expected),
        )
        .unwrap_err();
        assert!(error.to_string().starts_with("TAG_SOURCE_CHANGED|"));
        assert_eq!(fs::read(&source).unwrap(), externally_changed);
        assert_eq!(fs::read_dir(&directory).unwrap().count(), 1);
        fs::remove_dir_all(directory).unwrap();
    }
    // Explicitly opt-in: only a marker-bearing, workspace-local copy folder is
    // accepted. No production music path is ever passed to a writer here.
    #[test]
    #[ignore = "isolated copy-only metadata compatibility probe"]
    fn metadata_isolated_copies_probe() {
        use std::collections::BTreeMap;
        let allowed = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .unwrap()
            .parent()
            .unwrap()
            .join("tool")
            .canonicalize()
            .unwrap();
        let root = PathBuf::from(
            std::env::var_os("DAN_PLAYER_METADATA_COPY_DIR")
                .expect("Set the explicit anonymous-copy directory under workspace tool"),
        )
        .canonicalize()
        .unwrap();
        assert!(root.starts_with(&allowed) && root != allowed);
        assert_eq!(
            std::fs::read_to_string(root.join(".qa-metadata-copies"))
                .unwrap()
                .trim_start_matches('\u{feff}')
                .trim(),
            "isolated-metadata-copies-v1"
        );
        let mut totals = BTreeMap::<String, usize>::new();
        let mut payloads_verified = 0usize;
        let mut windows_fields_match = 0usize;
        let mut windows_fields_unavailable = 0usize;
        let mut container_totals = BTreeMap::<String, usize>::new();
        let mut windows_mismatches = BTreeMap::<String, usize>::new();
        let mut entries: Vec<_> = std::fs::read_dir(&root)
            .unwrap()
            .map(Result::unwrap)
            .collect();
        entries.sort_by_key(|entry| entry.file_name());
        for entry in entries {
            let source = entry.path();
            let name = entry.file_name().into_string().unwrap();
            if !matches!(
                source.extension().and_then(|ext| ext.to_str()),
                Some("mp3" | "flac")
            ) {
                continue;
            }
            assert!(source
                .file_stem()
                .unwrap()
                .to_str()
                .unwrap()
                .chars()
                .all(|ch| ch.is_ascii_digit()));
            assert!(!entry.file_type().unwrap().is_symlink());
            assert_eq!(
                source.canonicalize().unwrap().parent(),
                Some(root.as_path())
            );
            let before_bytes = std::fs::read(&source).unwrap();
            let container = if before_bytes.get(4..8) == Some(b"ftyp") {
                "MP4"
            } else if before_bytes.starts_with(b"fLaC") {
                "FLAC"
            } else {
                "other"
            };
            *container_totals.entry(container.into()).or_default() += 1;
            let result = super::update_audio_metadata(
                source.to_string_lossy().into_owned(),
                name.clone(),
                "QA 独立副本测试".into(),
                "QA Artist".into(),
                "QA Album".into(),
                None,
                None,
            );
            let code = result
                .as_ref()
                .err()
                .map(|e| {
                    e.to_string()
                        .split('|')
                        .next()
                        .unwrap_or("UNKNOWN")
                        .to_owned()
                })
                .unwrap_or_else(|| "OK".into());
            *totals.entry(code.clone()).or_default() += 1;
            if result.is_err() {
                assert!(
                    std::fs::read(&source).unwrap() == before_bytes,
                    "failed edit changed copy id={name}"
                );
                println!("FAILED id={name} code={code}");
            } else {
                let after_bytes = std::fs::read(&source).unwrap();
                assert!(
                    copy_probe_audio_payloads(&before_bytes).expect("known copy audio layout")
                        == copy_probe_audio_payloads(&after_bytes)
                            .expect("known output audio layout"),
                    "audio payload changed id={name}"
                );
                payloads_verified += 1;
                let dos_path = source.to_string_lossy();
                let dos_path = dos_path.strip_prefix(r"\\?\").unwrap_or(&dos_path);
                match Audio::read_by_win_music_properties(dos_path, 0, 0) {
                    Ok(properties)
                        if properties.title == "QA 独立副本测试"
                            && properties.artist == "QA Artist"
                            && properties.album == "QA Album" =>
                    {
                        windows_fields_match += 1
                    }
                    Ok(properties) => {
                        windows_fields_unavailable += 1;
                        println!("WINDOWS_FIELDS_MISMATCH id={name}");
                        let actual_type = probe_tagged_audio(&source, "test")
                            .map(|file| format!("{:?}", file.file_type()))
                            .unwrap_or_else(|_| "opaque-id3".into());
                        let key = format!(
                            "{actual_type}: title={} artist={} album={} artist_is_album_artist={}",
                            properties.title == "QA 独立副本测试",
                            properties.artist == "QA Artist",
                            properties.album == "QA Album",
                            properties.album_artist.as_deref() == Some(properties.artist.as_str())
                        );
                        *windows_mismatches.entry(key).or_default() += 1;
                    }
                    Err(error) => {
                        windows_fields_unavailable += 1;
                        if windows_fields_unavailable == 1 {
                            println!("WINDOWS_PROPERTIES_UNAVAILABLE hresult={}", error.code().0);
                        }
                    }
                }
            }
        }
        println!(
            "COPY_PROBE_SUMMARY {}",
            serde_json::to_string(&totals).unwrap()
        );
        println!("AUDIO_PAYLOAD_BYTES_UNCHANGED {payloads_verified}");
        println!("WINDOWS_FIELDS matched={windows_fields_match} unavailable_or_different={windows_fields_unavailable}");
        println!(
            "COPY_CONTAINERS {}",
            serde_json::to_string(&container_totals).unwrap()
        );
        println!(
            "WINDOWS_MISMATCH_DETAILS {}",
            serde_json::to_string(&windows_mismatches).unwrap()
        );
    }

    fn copy_probe_audio_payloads(bytes: &[u8]) -> Option<Vec<&[u8]>> {
        if bytes.get(4..8) == Some(b"ftyp") {
            let mut offset = 0usize;
            let mut payloads = Vec::new();
            while offset < bytes.len() {
                let header = bytes.get(offset..offset.checked_add(8)?)?;
                let length = u32::from_be_bytes(header[..4].try_into().ok()?);
                let (length, header_length) = match length {
                    0 => (bytes.len().checked_sub(offset)?, 8usize),
                    1 => {
                        let wide = bytes.get(offset.checked_add(8)?..offset.checked_add(16)?)?;
                        (
                            usize::try_from(u64::from_be_bytes(wide.try_into().ok()?)).ok()?,
                            16,
                        )
                    }
                    value => (value as usize, 8),
                };
                if length < header_length {
                    return None;
                }
                let end = offset.checked_add(length)?;
                if end > bytes.len() {
                    return None;
                }
                if &header[4..8] == b"mdat" {
                    payloads.push(bytes.get(offset.checked_add(header_length)?..end)?);
                }
                offset = end;
            }
            return (!payloads.is_empty()).then_some(payloads);
        }
        let offset = copy_probe_payload_offset(bytes)?;
        Some(vec![&bytes[offset..]])
    }

    fn copy_probe_payload_offset(bytes: &[u8]) -> Option<usize> {
        let mut offset = 0usize;
        if bytes.get(..3)? == b"ID3" {
            let size = bytes.get(6..10)?.iter().try_fold(0usize, |size, byte| {
                if byte & 0x80 != 0 {
                    None
                } else {
                    Some((size << 7) | *byte as usize)
                }
            })?;
            offset = 10usize.checked_add(size)?;
            if bytes[3] == 4 && bytes[5] & 0x10 != 0 {
                offset = offset.checked_add(10)?;
            }
        }
        if bytes.get(offset..offset.checked_add(4)?)? == b"fLaC" {
            offset += 4;
            loop {
                let header = bytes.get(offset..offset.checked_add(4)?)?;
                let size =
                    (header[1] as usize) << 16 | (header[2] as usize) << 8 | header[3] as usize;
                let last = header[0] & 0x80 != 0;
                offset = offset.checked_add(4)?.checked_add(size)?;
                if offset > bytes.len() {
                    return None;
                }
                if last {
                    return Some(offset);
                }
            }
        }
        // Preserve any tolerated bytes between ID3 and the first MPEG frame
        // as part of the payload too; they need not themselves be a sync word.
        (offset < bytes.len()).then_some(offset)
    }

    use super::*;

    fn test_directory(name: &str) -> PathBuf {
        let unique = format!(
            "dan_player_{}_{}_{}",
            name,
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        );
        let directory = std::env::temp_dir().join(unique);
        fs::create_dir_all(&directory).unwrap();
        directory
    }

    fn write_pcm_wav(path: &Path, sample_count: usize) {
        const SAMPLE_RATE: u32 = 8_000;
        let samples = vec![128u8; sample_count];
        let mut bytes = Vec::with_capacity(44 + samples.len());
        bytes.extend_from_slice(b"RIFF");
        bytes.extend_from_slice(&(36u32 + samples.len() as u32).to_le_bytes());
        bytes.extend_from_slice(b"WAVEfmt ");
        bytes.extend_from_slice(&16u32.to_le_bytes());
        bytes.extend_from_slice(&1u16.to_le_bytes());
        bytes.extend_from_slice(&1u16.to_le_bytes());
        bytes.extend_from_slice(&SAMPLE_RATE.to_le_bytes());
        bytes.extend_from_slice(&SAMPLE_RATE.to_le_bytes());
        bytes.extend_from_slice(&1u16.to_le_bytes());
        bytes.extend_from_slice(&8u16.to_le_bytes());
        bytes.extend_from_slice(b"data");
        bytes.extend_from_slice(&(samples.len() as u32).to_le_bytes());
        bytes.extend_from_slice(&samples);
        fs::write(path, bytes).unwrap();
    }

    fn write_minimal_wav(path: &Path) {
        write_pcm_wav(path, 800);
    }

    fn write_minimal_mpeg_with_legacy_id3v1(path: &Path) {
        // Three MPEG-1 Layer III frames (128 kbps / 44.1 kHz), followed by an
        // intentionally non-ASCII ID3v1 field. ID3v1 is byte-oriented; Lofty
        // 0.21 decodes the high bytes into multi-byte Rust chars and its legacy
        // writer then used to split that String at byte 30, inside a char.
        let mut bytes = Vec::new();
        for _ in 0..3 {
            let mut frame = vec![0u8; 417];
            frame[..4].copy_from_slice(&[0xff, 0xfb, 0x90, 0x64]);
            bytes.extend_from_slice(&frame);
        }
        let mut id3v1 = [0u8; 128];
        id3v1[..3].copy_from_slice(b"TAG");
        id3v1[3] = b'A';
        id3v1[4..33].fill(0xd8);
        id3v1[127] = 0xff;
        bytes.extend_from_slice(&id3v1);
        fs::write(path, bytes).unwrap();
    }

    pub(super) fn test_picture(picture_type: PictureType, red: u8) -> Picture {
        let source = image::ImageBuffer::from_pixel(2, 2, image::Rgb([red, 20u8, 30u8]));
        let mut encoded = Cursor::new(Vec::new());
        image::DynamicImage::ImageRgb8(source)
            .write_to(&mut encoded, image::ImageFormat::Png)
            .unwrap();
        let mut encoded = Cursor::new(encoded.into_inner());
        let mut picture = Picture::from_reader(&mut encoded).unwrap();
        picture.set_pic_type(picture_type);
        picture
    }

    #[test]
    fn metadata_writer_parse_failure_uses_bounded_raw_without_changing_picture() {
        let directory = test_directory("metadata_utf16_picture");
        let source = directory.join("source.mp3");
        write_minimal_mpeg_with_legacy_id3v1(&source);
        let audio = fs::read(&source).unwrap();
        let picture = test_picture(PictureType::CoverFront, 50);
        let mut payload = vec![1];
        payload.extend_from_slice(b"image/png\0\x03\xff\xfe\0\0");
        payload.extend_from_slice(picture.data());
        let syncsafe = |size: usize| {
            [
                ((size >> 21) & 127) as u8,
                ((size >> 14) & 127) as u8,
                ((size >> 7) & 127) as u8,
                (size & 127) as u8,
            ]
        };
        let mut original_frame = b"APIC".to_vec();
        original_frame.extend_from_slice(&syncsafe(payload.len()));
        original_frame.extend_from_slice(&[0, 0]);
        original_frame.extend_from_slice(&payload);
        let mut source_bytes = b"ID3\x04\0\0".to_vec();
        source_bytes.extend_from_slice(&syncsafe(original_frame.len()));
        source_bytes.extend_from_slice(&original_frame);
        source_bytes.extend_from_slice(&audio);
        fs::write(&source, &source_bytes).unwrap();
        let before = probe_tagged_audio(&source, "test").unwrap();
        let temporary = TransactionPath::copy_of(&source, "edit").unwrap();
        let mut edit = before.primary_tag().unwrap().clone();
        apply_tag_values(&mut edit, "Title", "Artist", "Album", None).unwrap();
        save_edited_primary_tag(&edit, &source, temporary.path(), FileType::Mpeg, false).unwrap();
        assert!(probe_tagged_audio(temporary.path(), "test")
            .err()
            .unwrap()
            .to_string()
            .starts_with("TAG_PARSE_UNSUPPORTED|"));
        drop(temporary);
        write_metadata_safely(&source, &source, "Title", "Artist", "Album", None).unwrap();
        let after = fs::read(&source).unwrap();
        assert_eq!(&after[10..10 + original_frame.len()], &original_frame);
        assert_eq!(&after[copy_probe_payload_offset(&after).unwrap()..], &audio);
        assert_eq!(
            probe_tagged_audio(&source, "test")
                .unwrap()
                .primary_tag()
                .unwrap()
                .title()
                .as_deref(),
            Some("Title")
        );
        assert_eq!(fs::read_dir(&directory).unwrap().count(), 1);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn metadata_native_id3_decoded_frame_flags_keep_payload_and_other_flags() {
        let directory = test_directory("metadata_frame_unsync");
        let source = directory.join("source.mp3");
        write_minimal_mpeg_with_legacy_id3v1(&source);
        let audio = fs::read(&source).unwrap();
        let original = vec![0x31, 0xff, 0xe0, 0x32, 0xff, 0x00, 0xff];
        let stored = vec![0x31, 0xff, 0x00, 0xe0, 0x32, 0xff, 0x00, 0x00, 0xff, 0x00];
        let frame_size = stored.len() + 4;
        let tag_size = frame_size + 10;
        let mut bytes = vec![b'I', b'D', b'3', 4, 0, 0, 0, 0, 0, tag_size as u8];
        bytes.extend_from_slice(b"XQA1");
        bytes.extend_from_slice(&[0, 0, 0, frame_size as u8, 0x10, 0x03]);
        bytes.extend_from_slice(&[0, 0, 0, original.len() as u8]);
        bytes.extend_from_slice(&stored);
        bytes.extend_from_slice(&audio);
        fs::write(&source, &bytes).unwrap();
        let before = probe_tagged_audio(&source, "test").unwrap();
        let preserved = PreservedMetadata::capture(&before, TagType::Id3v2, false);
        write_metadata_safely(&source, &source, "Title", "Artist", "Album", None).unwrap();
        let after = probe_tagged_audio(&source, "test").unwrap();
        assert!(preserved.verify(&after, TagType::Id3v2, false));
        let result = fs::read(&source).unwrap();
        let read = lofty::mpeg::MpegFile::read_from(&mut Cursor::new(&result), Default::default())
            .unwrap();
        let Frame::Binary(frame) = read
            .id3v2()
            .unwrap()
            .get(&FrameId::Valid(std::borrow::Cow::Borrowed("XQA1")))
            .unwrap()
        else {
            panic!("binary frame must remain binary")
        };
        assert_eq!(frame.data, original);
        assert!(frame.flags().read_only);
        assert!(!frame.flags().unsynchronisation);
        assert!(frame.flags().data_length_indicator.is_none());
        assert_eq!(
            &result[copy_probe_payload_offset(&result).unwrap()..],
            &audio
        );
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn metadata_native_id3_rejects_compression_encryption_without_dropping_flags() {
        for encrypted in [false, true] {
            let mut tag = Id3v2Tag::new();
            let mut frame = Frame::Binary(BinaryFrame::new(
                FrameId::Valid(std::borrow::Cow::Borrowed("XQA1")),
                vec![1, 2, 3],
            ));
            let mut flags = frame.flags();
            flags.compression = !encrypted;
            flags.encryption = encrypted.then_some(0x80);
            flags.unsynchronisation = true;
            flags.data_length_indicator = Some(3);
            frame.set_flags(flags);
            tag.insert(frame);
            let before = tag.clone();
            assert!(normalize_decoded_id3_flags(&mut tag)
                .unwrap_err()
                .to_string()
                .starts_with("TAG_LAYOUT_UNSUPPORTED|"));
            assert_eq!(tag, before);
        }
    }

    #[test]
    fn metadata_native_id3_decoded_global_unsync_keeps_binary_and_audio() {
        for version in [3, 4] {
            let directory = test_directory("metadata_global_unsync");
            let source = directory.join("source.mp3");
            write_minimal_mpeg_with_legacy_id3v1(&source);
            let audio = fs::read(&source).unwrap();
            let id = FrameId::Valid(std::borrow::Cow::Borrowed("XQA1"));
            let binary = Frame::Binary(BinaryFrame::new(
                id.clone(),
                vec![0x31, 0xff, 0xe0, 0x32, 0xff, 0x00, 0xff],
            ));
            let mut tag = Id3v2Tag::new();
            tag.set_title("Synthetic".into());
            tag.insert(binary.clone());
            let mut plain = Vec::new();
            tag.dump_to(&mut plain, WriteOptions::default().use_id3v23(version == 3))
                .unwrap();
            let mut escaped = Vec::new();
            for (index, byte) in plain[10..].iter().copied().enumerate() {
                escaped.push(byte);
                if byte == 0xff
                    && plain
                        .get(11 + index)
                        .is_none_or(|next| *next == 0 || *next >= 0xe0)
                {
                    escaped.push(0);
                }
            }
            let length = escaped.len();
            let mut bytes = vec![
                b'I',
                b'D',
                b'3',
                version,
                0,
                0xa0,
                ((length >> 21) & 127) as u8,
                ((length >> 14) & 127) as u8,
                ((length >> 7) & 127) as u8,
                (length & 127) as u8,
            ];
            bytes.extend_from_slice(&escaped);
            bytes.extend_from_slice(&audio);
            fs::write(&source, &bytes).unwrap();
            let before = probe_tagged_audio(&source, "test").unwrap();
            let preserved = PreservedMetadata::capture(&before, TagType::Id3v2, false);
            write_metadata_safely(&source, &source, "New title", "Artist", "Album", None).unwrap();
            let after = probe_tagged_audio(&source, "test").unwrap();
            assert!(preserved.verify(&after, TagType::Id3v2, false));
            let result_bytes = fs::read(&source).unwrap();
            let mut reader = Cursor::new(&result_bytes);
            let read = lofty::mpeg::MpegFile::read_from(&mut reader, Default::default()).unwrap();
            let read_tag = read.id3v2().unwrap();
            assert!(!read_tag.flags().unsynchronisation);
            assert!(read_tag.flags().experimental);
            assert_eq!(read_tag.get(&id), Some(&binary));
            assert_eq!(
                &result_bytes[copy_probe_payload_offset(&result_bytes).unwrap()..],
                &audio
            );
            fs::remove_dir_all(directory).unwrap();
        }
    }

    #[test]
    fn metadata_native_id3_keeps_language_descriptors_and_legacy_lyrics() {
        use lofty::id3::v2::{CommentFrame, UnsynchronizedTextFrame};
        use lofty::TextEncoding;
        for legacy_language in [false, true] {
            let directory = test_directory("metadata_id3_language");
            let source = directory.join("source.mp3");
            write_minimal_mpeg_with_legacy_id3v1(&source);
            let mut native = Id3v2Tag::new();
            native.set_title("Synthetic title".into());
            native.insert(Frame::Comment(CommentFrame::new(
                TextEncoding::UTF8,
                *b"zho",
                "description".into(),
                "First\0Second".into(),
            )));
            native.insert(Frame::UnsynchronizedText(UnsynchronizedTextFrame::new(
                TextEncoding::UTF8,
                *b"jpn",
                "original".into(),
                "Synthetic lyric".into(),
            )));
            native.insert_picture(test_picture(PictureType::CoverBack, 120));
            if legacy_language {
                native.insert(Frame::Binary(BinaryFrame::new(
                    FrameId::Valid(std::borrow::Cow::Borrowed("USLT")),
                    b"\x03   \0Legacy synthetic lyric".to_vec(),
                )));
            }
            native
                .save_to_path(&source, WriteOptions::default())
                .unwrap();
            let before = probe_tagged_audio(&source, "test").unwrap();
            let preserved = PreservedMetadata::capture(&before, TagType::Id3v2, false);
            write_metadata_safely(&source, &source, "New title", "Artist", "Album", None).unwrap();
            let after = probe_tagged_audio(&source, "test").unwrap();
            assert!(preserved.verify(&after, TagType::Id3v2, false));
            assert_eq!(
                after
                    .primary_tag()
                    .unwrap()
                    .get(&ItemKey::Comment)
                    .unwrap()
                    .lang(),
                b"zho"
            );
            assert_eq!(fs::read_dir(&directory).unwrap().count(), 1);
            fs::remove_dir_all(directory).unwrap();
        }
    }

    #[test]
    fn metadata_cover_edit_keeps_back_cover_and_untouched_lyrics() {
        let directory = test_directory("metadata_native_cover");
        let source = directory.join("source.mp3");
        let cover = directory.join("cover.png");
        write_minimal_mpeg_with_legacy_id3v1(&source);
        let mut tag = Id3v2Tag::new();
        tag.set_title("Fixture".into());
        let old_front = test_picture(PictureType::CoverFront, 40);
        let back = test_picture(PictureType::CoverBack, 80);
        tag.insert_picture(old_front);
        tag.insert_picture(back.clone());
        tag.insert(Frame::UnsynchronizedText(
            lofty::id3::v2::UnsynchronizedTextFrame::new(
                lofty::TextEncoding::UTF8,
                *b"kor",
                "original".into(),
                "Only synthetic lyric".into(),
            ),
        ));
        tag.save_to_path(&source, WriteOptions::default()).unwrap();
        let replacement = test_picture(PictureType::CoverFront, 180);
        fs::write(&cover, replacement.data()).unwrap();
        write_metadata_safely(&source, &source, "New", "Artist", "Album", cover.to_str()).unwrap();
        let after = probe_tagged_audio(&source, "test").unwrap();
        let primary = after.primary_tag().unwrap();
        assert_eq!(
            primary
                .get_picture_type(PictureType::CoverBack)
                .unwrap()
                .data(),
            back.data()
        );
        assert_eq!(
            primary
                .get_picture_type(PictureType::CoverFront)
                .unwrap()
                .data(),
            replacement.data()
        );
        assert_eq!(primary.get(&ItemKey::Lyrics).unwrap().lang(), b"kor");
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn metadata_actual_asf_container_is_not_reported_as_damaged_mp3() {
        let directory = test_directory("metadata_asf");
        let source = directory.join("mislabeled.mp3");
        let signature = [
            0x30, 0x26, 0xb2, 0x75, 0x8e, 0x66, 0xcf, 0x11, 0xa6, 0xd9, 0x00, 0xaa, 0x00, 0x62,
            0xce, 0x6c,
        ];
        fs::write(&source, signature).unwrap();
        let error =
            write_metadata_safely(&source, &source, "New", "Artist", "Album", None).unwrap_err();
        assert!(error.to_string().starts_with("TAG_FORMAT_UNSUPPORTED|"));
        assert!(!error.to_string().contains("损坏"));
        assert_eq!(fs::read(&source).unwrap(), signature);
        fs::remove_dir_all(directory).unwrap();
    }

    #[cfg(windows)]
    #[test]
    fn metadata_case_only_rename_is_not_an_existing_target_collision() {
        let directory = test_directory("metadata_case_rename");
        let source = directory.join("source.mp3");
        write_minimal_mpeg_with_legacy_id3v1(&source);
        let result = update_audio_metadata(
            source.to_string_lossy().into_owned(),
            "SOURCE.MP3".into(),
            "Title".into(),
            "Artist".into(),
            "Album".into(),
            None,
            None,
        )
        .unwrap();
        assert!(result.ends_with("SOURCE.MP3"));
        assert_eq!(
            fs::read_dir(&directory)
                .unwrap()
                .next()
                .unwrap()
                .unwrap()
                .file_name(),
            "SOURCE.MP3"
        );
        fs::remove_dir_all(directory).unwrap();
    }

    #[cfg(windows)]
    #[test]
    fn metadata_sharing_violation_keeps_source_and_reports_busy() {
        use std::os::windows::fs::OpenOptionsExt;
        let directory = test_directory("metadata_busy");
        let source = directory.join("source.mp3");
        write_minimal_mpeg_with_legacy_id3v1(&source);
        let before = fs::read(&source).unwrap();
        let held = OpenOptions::new()
            .read(true)
            .share_mode(1)
            .open(&source)
            .unwrap();
        let error =
            write_metadata_safely(&source, &source, "New", "Artist", "Album", None).unwrap_err();
        assert!(error.to_string().starts_with("TAG_FILE_BUSY|"));
        assert_eq!(fs::read(&source).unwrap(), before);
        assert_eq!(fs::read_dir(&directory).unwrap().count(), 1);
        drop(held);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn metadata_transaction_does_not_overwrite_a_late_target() {
        let directory = test_directory("metadata_late_target");
        let source = directory.join("source.mp3");
        let target = directory.join("late.mp3");
        write_minimal_mpeg_with_legacy_id3v1(&source);
        let before = fs::read(&source).unwrap();
        fs::write(&target, b"unrelated late target").unwrap();
        let error =
            write_metadata_safely(&source, &target, "New", "Artist", "Album", None).unwrap_err();
        assert!(error.to_string().contains("已恢复原文件"));
        assert_eq!(fs::read(&source).unwrap(), before);
        assert_eq!(fs::read(&target).unwrap(), b"unrelated late target");
        assert_eq!(fs::read_dir(&directory).unwrap().count(), 2);
        fs::remove_dir_all(directory).unwrap();
    }

    #[cfg(windows)]
    #[test]
    fn metadata_long_unicode_filename_does_not_overflow_transaction_basename() {
        let directory = test_directory("metadata_long_name");
        let source = directory.join(format!("{}.mp3", "字".repeat(220)));
        write_minimal_mpeg_with_legacy_id3v1(&source);
        write_metadata_safely(&source, &source, "New", "Artist", "Album", None).unwrap();
        assert_eq!(
            probe_tagged_audio(&source, "test")
                .unwrap()
                .primary_tag()
                .unwrap()
                .title()
                .as_deref(),
            Some("New")
        );
        assert_eq!(fs::read_dir(&directory).unwrap().count(), 1);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn metadata_edit_uses_verified_copy_and_preserves_unrequested_values() {
        let directory = test_directory("metadata_transaction");
        let source = directory.join("source.mp3");
        let target = directory.join("renamed.mp3");
        // The extension is intentionally wrong: content probing must still
        // identify the WAV container and use its actual writer.
        write_minimal_wav(&source);
        let mut tagged = probe_tagged_audio(&source, "test").unwrap();
        let tag_type = tagged.primary_tag_type();
        ensure_tag(&mut tagged, tag_type).unwrap();
        let tag = tagged.primary_tag_mut().unwrap();
        tag.set_title("Old title".to_string());
        tag.set_artist("Old artist".to_string());
        tag.set_album("Old album".to_string());
        // WAV's primary RIFF INFO tag cannot represent every field. Keep a
        // secondary ID3v2 tag so this fixture exercises cross-tag preservation,
        // including lyrics and more than one picture.
        let mut auxiliary = Tag::new(TagType::Id3v2);
        auxiliary.insert_text(ItemKey::Composer, "Keep composer".to_string());
        auxiliary.insert_text(ItemKey::Lyrics, "[00:01.00]Keep lyric".to_string());
        auxiliary.insert_text(ItemKey::Comment, "Keep comment".to_string());
        auxiliary.push_picture(test_picture(PictureType::CoverFront, 120));
        auxiliary.push_picture(test_picture(PictureType::CoverBack, 220));
        tagged.insert_tag(auxiliary);
        tagged
            .save_to_path(&source, WriteOptions::default())
            .unwrap();

        write_metadata_safely(
            &source,
            &target,
            "New title",
            "New artist",
            "New album",
            None,
        )
        .unwrap();

        assert!(!source.exists());
        let edited = probe_tagged_audio(&target, "test").unwrap();
        let tag = edited.primary_tag().unwrap();
        assert_eq!(tag.title().as_deref(), Some("New title"));
        assert_eq!(tag.artist().as_deref(), Some("New artist"));
        assert_eq!(tag.album().as_deref(), Some("New album"));
        let auxiliary = edited.tag(TagType::Id3v2).unwrap();
        assert_eq!(
            auxiliary.get_string(&ItemKey::Composer),
            Some("Keep composer")
        );
        assert_eq!(
            auxiliary.get_string(&ItemKey::Lyrics),
            Some("[00:01.00]Keep lyric")
        );
        assert_eq!(
            auxiliary.get_string(&ItemKey::Comment),
            Some("Keep comment")
        );
        assert!(auxiliary
            .get_picture_type(PictureType::CoverFront)
            .is_some());
        assert!(auxiliary.get_picture_type(PictureType::CoverBack).is_some());
        assert_eq!(
            fs::read_dir(&directory).unwrap().count(),
            1,
            "transaction files must be cleaned after success"
        );
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn unicode_filename_edit_does_not_rewrite_legacy_id3v1_or_touch_source_on_failure() {
        let directory = test_directory("unicode_metadata_transaction");
        let source = directory.join("今、歩き出す君へ。.mp3");
        write_minimal_mpeg_with_legacy_id3v1(&source);
        let original_legacy_title = probe_tagged_audio(&source, "test")
            .unwrap()
            .tag(TagType::Id3v1)
            .unwrap()
            .title()
            .unwrap()
            .into_owned();

        write_metadata_safely(
            &source,
            &source,
            "今、歩き出す君へ。",
            "永原真夏",
            "さくら、もゆ。",
            None,
        )
        .unwrap();

        let edited = probe_tagged_audio(&source, "test").unwrap();
        let primary = edited.primary_tag().unwrap();
        assert_eq!(primary.title().as_deref(), Some("今、歩き出す君へ。"));
        assert_eq!(primary.artist().as_deref(), Some("永原真夏"));
        assert_eq!(primary.album().as_deref(), Some("さくら、もゆ。"));
        assert_eq!(
            edited.tag(TagType::Id3v1).unwrap().title().as_deref(),
            Some(original_legacy_title.as_str()),
            "the unrelated legacy tag must remain byte-for-byte readable"
        );
        assert_eq!(fs::read_dir(&directory).unwrap().count(), 1);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn unknown_content_never_rewrites_the_original_or_leaves_a_temp_file() {
        let directory = test_directory("metadata_unknown");
        let source = directory.join("not-really.mp3");
        let original = b"not an audio container".to_vec();
        fs::write(&source, &original).unwrap();

        let error = write_metadata_safely(&source, &source, "Title", "Artist", "Album", None)
            .unwrap_err()
            .to_string();
        assert!(error.starts_with("TAG_FORMAT_UNKNOWN|"));
        assert_eq!(fs::read(&source).unwrap(), original);
        assert_eq!(fs::read_dir(&directory).unwrap().count(), 1);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn read_only_unicode_source_is_refused_without_changing_a_byte() {
        let directory = test_directory("metadata_read_only");
        let source = directory.join("今、歩き出す君へ。.mp3");
        write_minimal_wav(&source);
        let original = fs::read(&source).unwrap();
        let original_permissions = fs::metadata(&source).unwrap().permissions();
        let mut permissions = original_permissions.clone();
        permissions.set_readonly(true);
        fs::set_permissions(&source, permissions).unwrap();

        let error = update_audio_metadata(
            source.to_string_lossy().into_owned(),
            "今、歩き出す君へ。.mp3".to_string(),
            "New".to_string(),
            "Artist".to_string(),
            "Album".to_string(),
            None,
            None,
        )
        .unwrap_err()
        .to_string();
        assert!(error.starts_with("TAG_SOURCE_READ_ONLY|"));
        assert_eq!(fs::read(&source).unwrap(), original);
        assert_eq!(fs::read_dir(&directory).unwrap().count(), 1);

        fs::set_permissions(&source, original_permissions).unwrap();
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn transaction_recovery_files_are_never_scanned_as_songs() {
        let generated = Path::new(".song.dan-player-backup-1234-8.mp3");
        let editing = Path::new(".song.dan-player-edit-1234-9.flac");
        assert!(is_metadata_transaction_path(generated));
        assert!(is_metadata_transaction_path(editing));
        assert!(!is_supported_audio_path(generated));
        assert!(!is_supported_audio_path(editing));
        assert!(!is_metadata_transaction_path(Path::new(
            "my.dan-player-backup-remix.mp3"
        )));
        assert!(is_supported_audio_path(Path::new(
            "my.dan-player-backup-remix.mp3"
        )));
    }

    #[test]
    fn indexed_missing_path_requires_an_accessible_parent() {
        let directory = test_directory("index_path_state");
        let existing = directory.join("existing.mp3");
        fs::write(&existing, b"fixture").unwrap();
        assert_eq!(
            indexed_path_state(&existing).unwrap(),
            IndexedPathState::Present
        );
        assert_eq!(
            indexed_path_state(&directory.join("missing.mp3")).unwrap(),
            IndexedPathState::Missing
        );
        assert!(indexed_path_state(&directory.join("offline").join("song.mp3")).is_err());
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn an_unverifiable_index_path_never_mutates_the_snapshot() {
        let directory = test_directory("index_fail_closed");
        let path = directory.join("offline").join("song.mp3");
        let mut entries = vec![serde_json::json!({"path": path})];
        let original = entries.clone();

        let error = retain_confirmed_index_paths(&mut entries, "歌曲文件")
            .unwrap_err()
            .to_string();

        assert!(error.starts_with("INDEX_SCAN_INCOMPLETE|"));
        assert_eq!(entries, original);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn classification_fields_are_explicit_optional_tags() {
        let mut audio = Audio::new_with_path("track.mp3", None).unwrap();
        assert_eq!(audio.to_json_value()["classification_version"], 0);
        assert!(audio.to_json_value()["composer"].is_null());
        assert!(audio.to_json_value()["album_artist"].is_null());
        audio.composer = Some("坂本龍一".to_string());
        audio.album_artist = Some("Original Soundtrack".to_string());
        audio.classification_version = CLASSIFICATION_VERSION;
        let json = audio.to_json_value();
        assert_eq!(json["composer"], "坂本龍一");
        assert_eq!(json["album_artist"], "Original Soundtrack");
        assert_eq!(json["classification_version"], 1);
        assert_eq!(INDEX_VERSION, 113);
    }

    #[test]
    fn content_probe_reads_duration_when_supported_extension_is_misleading() {
        let directory = test_directory("duration_content_probe");
        let source = directory.join("wav-bytes-with-mp3-name.mp3");
        write_pcm_wav(&source, 16_000);

        let audio = Audio::read_by_lofty(&source, 0, 0).unwrap();

        assert_eq!(audio.duration, 2);
        assert_eq!(audio.duration_version, DURATION_VERSION);
        assert_eq!(
            read_tagged_file_by_content(&source).unwrap().file_type(),
            FileType::Wav
        );
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn duration_marker_distinguishes_old_index_from_verified_zero_duration() {
        for marker in [
            serde_json::Value::Null,
            serde_json::json!(false),
            serde_json::json!("1"),
            serde_json::json!(0),
        ] {
            assert!(needs_duration_backfill(
                &serde_json::json!({"duration_version": marker})
            ));
        }
        assert!(needs_duration_backfill(
            &serde_json::json!({"duration": 120})
        ));
        assert!(!needs_duration_backfill(
            &serde_json::json!({"duration": 0, "duration_version": 1})
        ));
    }

    #[test]
    fn composers_are_never_inferred_from_performers_or_album_artists() {
        let mut tag = Tag::new(TagType::Id3v2);
        tag.insert_text(ItemKey::TrackArtist, "Performer".to_string());
        tag.insert_text(ItemKey::AlbumArtist, "Album owner".to_string());
        assert!(first_tag_text_with_source(&[&tag], &ItemKey::Composer).is_none());
        tag.insert_text(ItemKey::Composer, "Sakamoto, R".to_string());
        assert_eq!(
            first_tag_text(&[&tag], &ItemKey::Composer).as_deref(),
            Some("Sakamoto, R")
        );
        assert_eq!(artist_from_tags_with_source(&[&tag]).0, "Performer");
        assert_eq!(
            first_tag_text(&[&tag], &ItemKey::AlbumArtist).as_deref(),
            Some("Album owner")
        );
    }

    #[test]
    fn classification_marker_distinguishes_missing_from_successfully_read_nulls() {
        for marker in [
            serde_json::Value::Null,
            serde_json::json!(false),
            serde_json::json!(true),
            serde_json::json!(-1),
            serde_json::json!("1"),
            serde_json::json!(1.5),
            serde_json::json!(0),
        ] {
            assert!(needs_classification_backfill(
                &serde_json::json!({"classification_version": marker})
            ));
        }
        assert!(needs_classification_backfill(
            &serde_json::json!({"composer": "Old"})
        ));
        for marker in [1, 2] {
            assert!(!needs_classification_backfill(
                &serde_json::json!({"classification_version": marker, "composer": null, "album_artist": null})
            ));
        }
    }

    #[test]
    fn classification_backfill_preserves_all_unrelated_old_index_fields() {
        let mut previous = serde_json::json!({"path": "original.mp3", "title": "Keep title", "artist": "Keep artist", "album": "Keep album", "modified": 120, "created": 100, "track": 3, "duration": 60, "extension": {"custom": [4, 3, 2]}});
        let mut expected = previous.clone();
        let mut read = Audio::new_with_path("different.mp3", Some("Lofty".to_string())).unwrap();
        read.title = "Scanner title".to_string();
        read.modified = 999;
        read.composer = Some("Composer".to_string());
        read.album_artist = Some("Album Artist".to_string());
        read.classification_version = CLASSIFICATION_VERSION;
        assert!(apply_audio_index_update(&mut previous, Some(read), true));
        expected["composer"] = serde_json::json!("Composer");
        expected["album_artist"] = serde_json::json!("Album Artist");
        expected["classification_version"] = serde_json::json!(1);
        assert_eq!(previous, expected);
    }

    #[test]
    fn a_successful_empty_tag_read_finishes_backfill_without_inventing_names() {
        let mut previous = serde_json::json!({"path": "a.mp3", "artist": "Singer"});
        let mut read = Audio::new_with_path("a.mp3", Some("Lofty".to_string())).unwrap();
        read.classification_version = CLASSIFICATION_VERSION;
        assert!(apply_audio_index_update(&mut previous, Some(read), true));
        assert!(previous["composer"].is_null());
        assert!(previous["album_artist"].is_null());
        assert!(!needs_classification_backfill(&previous));
        assert_eq!(previous["artist"], "Singer");
    }

    #[test]
    fn failed_backfill_keeps_the_original_record_pending() {
        let before =
            serde_json::json!({"path": "a.mp3", "title": "Keep", "classification_version": 0});
        let mut previous = before.clone();
        assert!(!apply_audio_index_update(&mut previous, None, true));
        assert_eq!(previous, before);
        let filename_only = Audio::new_with_path("a.mp3", None).unwrap();
        assert!(!apply_audio_index_update(
            &mut previous,
            Some(filename_only),
            true
        ));
        assert_eq!(previous, before);
        assert!(needs_classification_backfill(&previous));
    }

    #[test]
    fn actual_modified_files_keep_the_normal_full_metadata_refresh() {
        let mut previous = serde_json::json!({"path": "a.mp3", "title": "Old"});
        let mut read = Audio::new_with_path("a.mp3", Some("Lofty".to_string())).unwrap();
        read.title = "New".to_string();
        read.composer = Some("Composer".to_string());
        read.classification_version = CLASSIFICATION_VERSION;
        let expected = read.to_json_value();
        assert!(apply_audio_index_update(&mut previous, Some(read), false));
        assert_eq!(previous, expected);
    }

    #[test]
    fn language_and_file_size_are_optional_index_fields() {
        let mut audio = Audio::new_with_path("track.mp3", None).unwrap();
        assert!(audio.to_json_value()["language"].is_null());
        assert!(audio.to_json_value()["file_size"].is_null());

        audio.language = Some("ja".to_string());
        audio.file_size = Some(4096);
        let value = audio.to_json_value();
        assert_eq!(value["language"], "ja");
        assert_eq!(value["file_size"], 4096);
    }

    #[test]
    fn explicit_language_tag_is_read_without_using_the_title() {
        let empty = Tag::new(TagType::Id3v1);
        let mut tagged = Tag::new(TagType::Id3v2);
        tagged.insert_text(ItemKey::TrackTitle, "春夏秋冬".to_string());
        assert!(first_tag_text_with_source(&[&tagged], &ItemKey::Language).is_none());
        tagged.insert_text(ItemKey::Language, "jpn".to_string());
        assert_eq!(
            first_tag_text_with_source(&[&empty, &tagged], &ItemKey::Language)
                .map(|(value, _)| value),
            Some("jpn".to_string())
        );
    }

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
        assert_eq!((decoded.width(), decoded.height()), (4, 2));
    }

    #[test]
    fn cover_windows_file_icon_is_not_album_artwork() {
        let directory = test_directory("cover_windows_icon");
        let source = directory.join("no-artwork.wav");
        write_minimal_wav(&source);
        let before = fs::read(&source).unwrap();
        let source_path = source.to_string_lossy().into_owned();
        assert!(_get_picture_by_windows(&source_path, 96).unwrap().is_none());
        assert!(get_picture_from_path(source_path, 96, 96).is_none());
        assert_eq!(fs::read(&source).unwrap(), before);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn cover_decode_landscape_and_portrait_keep_both_target_axes() {
        assert_eq!(cover_decode_dimensions(1600, 900, 400, 400), (712, 400));
        assert_eq!(cover_decode_dimensions(900, 1600, 400, 400), (400, 712));
        assert_eq!(cover_decode_dimensions(1200, 1200, 192, 192), (192, 192));
    }

    #[test]
    fn cover_decode_never_invents_pixels_for_a_small_original() {
        assert_eq!(cover_decode_dimensions(32, 16, 512, 512), (32, 16));
        assert_eq!(cover_decode_dimensions(16, 32, 512, 512), (16, 32));
        assert_eq!(cover_decode_dimensions(24, 24, 48, 48), (24, 24));
    }

    #[test]
    fn cover_decode_has_finite_memory_for_extreme_images() {
        for (width, height) in [(16000, 100), (100, 16000), (16000, 16000)] {
            let (out_width, out_height) = cover_decode_dimensions(width, height, 2048, 2048);
            assert!(out_width <= 4096 && out_height <= 4096);
            assert!(out_width as u64 * out_height as u64 <= 4 * 1024 * 1024);
        }
    }

    #[test]
    fn cover_resize_keeps_native_sized_sharp_pixel_data() {
        let source = image::ImageBuffer::from_fn(32, 32, |x, y| {
            if (x + y) % 2 == 0 {
                image::Rgba([255u8, 255, 255, 255])
            } else {
                image::Rgba([0u8, 0, 0, 255])
            }
        });
        let mut encoded = Cursor::new(Vec::new());
        source
            .write_to(&mut encoded, image::ImageFormat::Png)
            .unwrap();
        let resized = resize_picture(encoded.get_ref(), 32, 32).unwrap();
        assert_eq!(
            image::load_from_memory(&resized).unwrap().to_rgba8(),
            source
        );
    }

    #[test]
    fn cover_resize_landscape_png_is_not_an_undersized_contain_thumbnail() {
        let source = image::DynamicImage::new_rgb8(160, 90);
        let mut encoded = Cursor::new(Vec::new());
        source
            .write_to(&mut encoded, image::ImageFormat::Png)
            .unwrap();
        let resized = resize_picture(encoded.get_ref(), 48, 48).unwrap();
        let decoded = image::load_from_memory(&resized).unwrap();
        assert_eq!((decoded.width(), decoded.height()), (86, 48));
    }

    #[test]
    fn cover_resize_invalid_image_is_a_safe_miss() {
        assert!(resize_picture(b"not an image", 48, 48).is_none());
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
