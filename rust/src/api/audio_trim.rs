//! Validated metadata transfer and commit for the app's FFmpeg trim output.
//! The source is read-only until the final same-directory atomic replacement.
use super::{
    metadata_preflight::{metadata_fingerprint, physical_source_key},
    tag_reader::{probe_tagged_audio, Audio},
};
use anyhow::{bail, ensure, Context};
use lofty::{
    file::{AudioFile, FileType},
    prelude::{Accessor, TaggedFileExt},
};
use serde_json::json;
use sha2::{Digest, Sha256};
use std::{
    collections::HashMap,
    fs::{self, File, OpenOptions},
    io::Read,
    panic::{catch_unwind, AssertUnwindSafe},
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicU64, Ordering},
        Mutex, OnceLock,
    },
};

#[path = "audio_trim_lyrics.rs"]
mod lyrics;
#[path = "audio_trim_tags.rs"]
mod tags;

static TRANSACTION: AtomicU64 = AtomicU64::new(0);
static COMMIT_LOCK: Mutex<()> = Mutex::new(());
static PREPARED: OnceLock<Mutex<HashMap<PathBuf, Prepared>>> = OnceLock::new();
struct Prepared {
    source: PathBuf,
    source_fingerprint: String,
    output_hash: String,
    lyric_warnings: Vec<String>,
}
fn prepared() -> &'static Mutex<HashMap<PathBuf, Prepared>> {
    PREPARED.get_or_init(Default::default)
}

fn plain_path(path: &Path) -> anyhow::Result<PathBuf> {
    ensure!(path.is_absolute(), "TRIM_PATH_INVALID|需要绝对文件路径");
    for component in path.ancestors() {
        match fs::symlink_metadata(component) {
            Ok(metadata) => {
                ensure!(
                    !metadata.file_type().is_symlink(),
                    "TRIM_PATH_ALIAS|不通过符号链接或目录联接写入歌曲"
                );
                #[cfg(windows)]
                {
                    use std::os::windows::{
                        fs::{MetadataExt, OpenOptionsExt},
                        io::AsRawHandle,
                    };
                    use windows::Win32::{
                        Foundation::HANDLE,
                        Storage::FileSystem::{
                            FileAttributeTagInfo, GetFileInformationByHandleEx,
                            FILE_ATTRIBUTE_TAG_INFO, FILE_FLAG_BACKUP_SEMANTICS,
                            FILE_FLAG_OPEN_REPARSE_POINT,
                        },
                    };
                    if metadata.file_attributes() & 0x400 != 0 {
                        let file = OpenOptions::new()
                            .read(true)
                            .custom_flags(
                                FILE_FLAG_BACKUP_SEMANTICS.0 | FILE_FLAG_OPEN_REPARSE_POINT.0,
                            )
                            .open(component)?;
                        let mut info = FILE_ATTRIBUTE_TAG_INFO::default();
                        unsafe {
                            GetFileInformationByHandleEx(
                                HANDLE(file.as_raw_handle() as isize),
                                FileAttributeTagInfo,
                                (&mut info as *mut FILE_ATTRIBUTE_TAG_INFO).cast(),
                                std::mem::size_of::<FILE_ATTRIBUTE_TAG_INFO>() as u32,
                            )?;
                        }
                        ensure!(
                            !redirects_path(info.ReparseTag),
                            "TRIM_PATH_ALIAS|不通过符号链接或目录联接写入歌曲"
                        );
                    }
                }
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => return Err(error.into()),
        }
    }
    Ok(fs::canonicalize(path)?)
}

fn redirects_path(reparse_tag: u32) -> bool {
    reparse_tag & 0x20000000 != 0
}

fn display_path(path: &Path) -> String {
    let text = path.to_string_lossy();
    #[cfg(windows)]
    {
        if let Some(unc) = text.strip_prefix(r"\\?\UNC\") {
            return format!(r"\\{unc}");
        }
        text.strip_prefix(r"\\?\").unwrap_or(&text).to_string()
    }
    #[cfg(not(windows))]
    {
        text.into_owned()
    }
}

fn digest(path: &Path) -> anyhow::Result<String> {
    let mut file = File::open(path)?;
    let mut digest = Sha256::new();
    let mut buffer = [0; 128 * 1024];
    loop {
        let read = file.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        digest.update(&buffer[..read]);
    }
    Ok(format!("{:x}", digest.finalize()))
}

fn fingerprint(path: &Path) -> anyhow::Result<String> {
    let before = metadata_fingerprint(path)?;
    let key = physical_source_key(path)?;
    let sha = digest(path)?;
    ensure!(
        before == metadata_fingerprint(path)? && key == physical_source_key(path)?,
        "TRIM_SOURCE_CHANGED|读取期间歌曲已改变，请重新预览"
    );
    Ok(format!("{key}|{before}|{sha}"))
}

fn container(file_type: FileType) -> anyhow::Result<&'static str> {
    Ok(match file_type {
        FileType::Mpeg => "mp3",
        FileType::Flac => "flac",
        FileType::Mp4 => "mp4",
        FileType::Vorbis => "ogg",
        FileType::Opus => "opus",
        FileType::Wav => "wav",
        FileType::Aiff => "aiff",
        _ => bail!("TRIM_FORMAT_UNSUPPORTED|此音频容器暂不支持安全裁剪"),
    })
}

fn trim_probe(path: &Path, code: &str) -> anyhow::Result<lofty::file::TaggedFile> {
    let opaque = super::tag_reader::id3_compat::trim_probe(path);
    if super::tag_reader::id3_compat::has_empty_text_frame(path) {
        if let Some(file) = opaque {
            return Ok(file);
        }
    }
    probe_tagged_audio(path, code)
        .or_else(|error| super::tag_reader::id3_compat::trim_probe(path).ok_or(error))
}

/// Read-only preview. The opaque fingerprint binds content, size, time and file ID.
pub fn prepare_audio_trim(source_path: String) -> anyhow::Result<String> {
    let path = plain_path(Path::new(&source_path))?;
    let fingerprint = fingerprint(&path)?;
    let audio = trim_probe(&path, "TRIM_FORMAT_UNSUPPORTED")?;
    let tag = audio.primary_tag().or_else(|| audio.first_tag());
    Ok(json!({"fingerprint":fingerprint, "sourceKey":physical_source_key(&path)?,
        "container":container(audio.file_type())?, "durationMs":audio.properties().duration().as_millis(),
        "title":tag.and_then(|t| t.title()), "artist":tag.and_then(|t| t.artist()),
        "album":tag.and_then(|t| t.album()), "readOnly":fs::metadata(&path)?.permissions().readonly()
    }).to_string())
}

/// Returns the same Audio JSON schema as indexing, also for the app's own temp file.
pub fn read_audio_trim_file(path: String) -> anyhow::Result<String> {
    let path = plain_path(Path::new(&path))?;
    trim_probe(&path, "TRIM_VERIFY_FAILED")?;
    let mut audio = Audio::read_explicit_path(&path)
        .context("TRIM_VERIFY_FAILED|无法读取裁剪后的歌曲")?
        .to_json_value();
    audio["path"] = json!(display_path(&path));
    if let Some(fields) = super::tag_reader::id3_compat::trim_text_fields(&path) {
        for (key, value) in ["title", "artist", "album"].into_iter().zip(fields) {
            if let Some(value) = value {
                audio[key] = json!(value);
            }
        }
    }
    Ok(audio.to_string())
}

/// Returns JSON {text, adjusted, warning}; unknown timed formats remain intact.
pub fn trim_audio_lyric_text(
    text: String,
    start_seconds: f64,
    end_seconds: f64,
) -> anyhow::Result<String> {
    let (start, end) = lyrics::bounds(start_seconds, end_seconds)?;
    let result = lyrics::transform(&text, start, end);
    Ok(json!({"text":result.text,"adjusted":result.adjusted,"warning":result.warning}).to_string())
}

/// Idempotent cleanup for canceled/failed jobs, including already removed temps.
pub fn release_audio_trim(temporary_path: String) {
    fn key(path: &Path) -> String {
        let path = fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
        let text = path.to_string_lossy();
        #[cfg(windows)]
        {
            text.trim_start_matches(r"\\?\")
                .replace('/', "\\")
                .to_lowercase()
        }
        #[cfg(not(windows))]
        {
            text.into_owned()
        }
    }
    let released = key(Path::new(&temporary_path));
    if let Ok(mut prepared) = prepared().lock() {
        prepared.retain(|path, _| key(path) != released);
    }
}

/// Transfers native tags to an already encoded temporary file. Nothing writes to
/// the source. A changed/missing native field or picture rejects preservation.
pub fn finish_audio_trim_metadata(
    source_path: String,
    temporary_path: String,
    preserve_metadata: bool,
    title: Option<String>,
    artist: Option<String>,
    album: Option<String>,
    start_seconds: f64,
    end_seconds: f64,
) -> anyhow::Result<String> {
    let (lyric_start, lyric_end) = lyrics::bounds(start_seconds, end_seconds)?;
    let source = plain_path(Path::new(&source_path))?;
    let temporary = plain_path(Path::new(&temporary_path))?;
    ensure!(
        source != temporary && physical_source_key(&source)? != physical_source_key(&temporary)?,
        "TRIM_PATH_ALIAS|裁剪临时文件不能指向原歌曲"
    );
    let source_fingerprint = fingerprint(&source)?;
    let original = trim_probe(&source, "TRIM_FORMAT_UNSUPPORTED")?;
    let before = trim_probe(&temporary, "TRIM_VERIFY_FAILED")?;
    container(original.file_type())?;
    ensure!(
        original.file_type() == before.file_type(),
        "TRIM_FORMAT_CHANGED|裁剪输出必须保持原音频容器"
    );
    ensure!(
        !before.properties().duration().is_zero(),
        "TRIM_EMPTY_OUTPUT|裁剪输出没有有效音频时长"
    );
    let result = catch_unwind(AssertUnwindSafe(|| {
        tags::transfer(
            &source,
            &temporary,
            original.file_type(),
            preserve_metadata,
            title,
            artist,
            album,
            before.properties().duration(),
            lyric_start,
            lyric_end,
        )
    }));
    let lyric_warnings = match result {
        Ok(value) => value?,
        Err(_) => bail!("TRIM_TAGS_UNSUPPORTED|标签写入器无法完整保留此歌曲元数据，原文件未改动"),
    };
    let after = trim_probe(&temporary, "TRIM_VERIFY_FAILED")?;
    ensure!(
        after.file_type() == before.file_type()
            && after.properties().duration() == before.properties().duration()
            && after.properties().sample_rate() == before.properties().sample_rate()
            && after.properties().channels() == before.properties().channels(),
        "TRIM_VERIFY_FAILED|标签写入改变了裁剪音频属性"
    );
    OpenOptions::new()
        .read(true)
        .write(true)
        .open(&temporary)?
        .sync_all()?;
    let mut audio: serde_json::Value = serde_json::from_str(&read_audio_trim_file(
        temporary.to_string_lossy().into_owned(),
    )?)?;
    audio["lyricWarnings"] = json!(lyric_warnings);
    let mut prepared = prepared()
        .lock()
        .map_err(|_| anyhow::anyhow!("TRIM_BUSY|裁剪状态不可用"))?;
    prepared.retain(|path, _| path.exists());
    ensure!(
        prepared.len() < 64 || prepared.contains_key(&temporary),
        "TRIM_BUSY|待提交裁剪过多，请重试"
    );
    prepared.insert(
        temporary.clone(),
        Prepared {
            source,
            source_fingerprint,
            output_hash: digest(&temporary)?,
            lyric_warnings,
        },
    );
    Ok(audio.to_string())
}

struct Staged(PathBuf);
impl Drop for Staged {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.0);
    }
}
fn reserve_near(destination: &Path) -> anyhow::Result<Staged> {
    let parent = destination
        .parent()
        .context("TRIM_PATH_INVALID|输出没有父目录")?;
    let extension = destination
        .extension()
        .unwrap_or_default()
        .to_string_lossy();
    for _ in 0..128 {
        let id = TRANSACTION.fetch_add(1, Ordering::Relaxed);
        let path = parent.join(format!(
            ".dan-player-trim-{}-{id}.{extension}",
            std::process::id()
        ));
        match OpenOptions::new().write(true).create_new(true).open(&path) {
            Ok(_) => return Ok(Staged(path)),
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(error.into()),
        }
    }
    bail!("TRIM_STAGE_FAILED|无法创建安全输出副本")
}

fn move_new(source: &Path, destination: &Path) -> anyhow::Result<()> {
    #[cfg(windows)]
    {
        use windows::{
            core::HSTRING,
            Win32::Storage::FileSystem::{MoveFileExW, MOVEFILE_WRITE_THROUGH},
        };
        unsafe {
            MoveFileExW(
                &HSTRING::from(source),
                &HSTRING::from(destination),
                MOVEFILE_WRITE_THROUGH,
            )?;
        }
    }
    #[cfg(not(windows))]
    {
        fs::hard_link(source, destination)?;
        fs::remove_file(source)?;
    }
    Ok(())
}

fn atomic_replace(source: &Path, temporary: &Path, backup: &Path) -> anyhow::Result<()> {
    #[cfg(windows)]
    {
        use windows::{
            core::HSTRING,
            Win32::Storage::FileSystem::{ReplaceFileW, REPLACE_FILE_FLAGS},
        };
        unsafe {
            ReplaceFileW(
                &HSTRING::from(source),
                &HSTRING::from(temporary),
                &HSTRING::from(backup),
                REPLACE_FILE_FLAGS(0),
                None,
                None,
            )?;
        }
    }
    #[cfg(not(windows))]
    {
        fs::hard_link(source, backup)?;
        fs::rename(temporary, source)?;
    }
    Ok(())
}

/// Copies never replace an existing file. Overwrite accepts only the original
/// source path, validates its strong preview fingerprint, and keeps a backup.
pub fn commit_audio_trim(
    source_path: String,
    temporary_path: String,
    destination_path: String,
    overwrite: bool,
    expected_fingerprint: String,
) -> anyhow::Result<String> {
    let _lock = COMMIT_LOCK
        .lock()
        .map_err(|_| anyhow::anyhow!("TRIM_BUSY|裁剪提交不可用"))?;
    let source = plain_path(Path::new(&source_path))?;
    let temporary = plain_path(Path::new(&temporary_path))?;
    let destination_argument = Path::new(&destination_path);
    let destination = if overwrite {
        let destination = plain_path(destination_argument)?;
        ensure!(
            destination == source,
            "TRIM_PATH_ALIAS|覆盖只允许原歌曲路径，不能覆盖其他文件或其别名"
        );
        ensure!(
            !fs::metadata(&source)?.permissions().readonly(),
            "TRIM_READ_ONLY|歌曲为只读文件"
        );
        destination
    } else {
        ensure!(
            fs::symlink_metadata(destination_argument)
                .is_err_and(|error| error.kind() == std::io::ErrorKind::NotFound),
            "TRIM_DESTINATION_EXISTS|目标文件已经存在，请选择新文件名"
        );
        let parent = plain_path(
            destination_argument
                .parent()
                .context("TRIM_PATH_INVALID|输出没有父目录")?,
        )?;
        parent.join(
            destination_argument
                .file_name()
                .context("TRIM_PATH_INVALID|输出缺少文件名")?,
        )
    };
    ensure!(
        source != temporary && physical_source_key(&source)? != physical_source_key(&temporary)?,
        "TRIM_PATH_ALIAS|裁剪临时文件不能指向原歌曲"
    );
    let prepared = prepared()
        .lock()
        .map_err(|_| anyhow::anyhow!("TRIM_BUSY|裁剪状态不可用"))?
        .remove(&temporary)
        .context("TRIM_NOT_VERIFIED|请先验证裁剪输出与标签")?;
    ensure!(
        prepared.source == source
            && prepared.source_fingerprint == expected_fingerprint
            && fingerprint(&source)? == expected_fingerprint,
        "TRIM_SOURCE_CHANGED|预览后歌曲已改变，已取消覆盖"
    );
    ensure!(
        digest(&temporary)? == prepared.output_hash,
        "TRIM_OUTPUT_CHANGED|验证后临时音频已改变"
    );
    let staged = reserve_near(&destination)?;
    fs::copy(&temporary, &staged.0)?;
    OpenOptions::new()
        .read(true)
        .write(true)
        .open(&staged.0)?
        .sync_all()?;
    ensure!(
        digest(&staged.0)? == prepared.output_hash,
        "TRIM_VERIFY_FAILED|输出副本校验失败"
    );
    // Read and validate before publishing. Once replacement succeeds this API
    // must report success even if a subsequent metadata reader becomes unavailable.
    let mut audio: serde_json::Value = serde_json::from_str(&read_audio_trim_file(
        staged.0.to_string_lossy().into_owned(),
    )?)?;
    audio["path"] = json!(display_path(&destination));
    let staged_tags = trim_probe(&staged.0, "TRIM_VERIFY_FAILED")?;
    let raw_title = super::tag_reader::id3_compat::trim_text_fields(&staged.0)
        .and_then(|fields| fields[0].clone())
        .is_some_and(|title| !title.trim().is_empty());
    if !super::tag_reader::has_indexed_title(&staged_tags) && !raw_title {
        audio["title"] = json!(destination
            .file_name()
            .unwrap_or_default()
            .to_string_lossy());
    }
    ensure!(
        fingerprint(&source)? == expected_fingerprint,
        "TRIM_SOURCE_CHANGED|提交前歌曲已改变"
    );
    let backup = if overwrite {
        let reserved = reserve_near(&source)?;
        let backup = reserved.0.with_extension(format!(
            "{}.trim-backup",
            source.extension().unwrap_or_default().to_string_lossy()
        ));
        ensure!(!backup.exists(), "TRIM_BACKUP_EXISTS|恢复副本路径已存在");
        if let Err(error) = atomic_replace(&source, &staged.0, &backup) {
            // Some documented ReplaceFileW failure modes move the old file to
            // its backup before the replacement fails. Restore that name when
            // possible, and always identify the recovery copy in the error.
            if !source.exists() && backup.exists() {
                let restored = move_new(&backup, &source);
                bail!(
                    "TRIM_COMMIT_FAILED|替换失败；恢复原路径：{}；原始副本路径：{}；{}",
                    restored.is_ok(),
                    backup.display(),
                    error
                );
            }
            if source.exists() && digest(&source).is_ok_and(|hash| hash == prepared.output_hash) {
                // The content is already published despite an OS error. Return
                // committed success; callers must not treat it as an untouched source.
                audio["commitWarning"] = json!(format!(
                    "TRIM_COMMIT_WARNING|系统报告替换异常，但输出内容已校验：{error}"
                ));
            } else {
                bail!(
                    "TRIM_COMMIT_FAILED|替换未完成；原始副本路径：{}；{}",
                    backup.display(),
                    error
                );
            }
        }
        Some(backup)
    } else {
        move_new(&staged.0, &destination)
            .context("TRIM_COMMIT_FAILED|无法创建输出文件，已有文件未被覆盖")?;
        None
    };
    // These reads are optional after publication; no later I/O failure can turn
    // a committed file into an apparent failed/canceled trim.
    if let Ok(metadata) = fs::metadata(&destination) {
        audio["file_size"] = json!(metadata.len());
        if let Ok(time) = metadata.modified().and_then(|time| {
            time.duration_since(std::time::UNIX_EPOCH)
                .map_err(std::io::Error::other)
        }) {
            audio["modified"] = json!(time.as_secs());
        }
        if let Ok(time) = metadata.created().and_then(|time| {
            time.duration_since(std::time::UNIX_EPOCH)
                .map_err(std::io::Error::other)
        }) {
            audio["created"] = json!(time.as_secs());
        }
    }
    Ok(json!({"path":display_path(&destination), "backupPath":backup.as_deref().map(display_path), "audio":audio, "warnings":prepared.lyric_warnings}).to_string())
}

#[cfg(test)]
#[path = "audio_trim_tests.rs"]
mod tests;
