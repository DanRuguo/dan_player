use lofty::prelude::{Accessor, TaggedFileExt};
use serde_json::json;
use std::{fs, path::Path, time::UNIX_EPOCH};

fn physical_source_key(path: &Path) -> anyhow::Result<String> {
    #[cfg(windows)]
    {
        use std::os::windows::io::AsRawHandle;
        use windows::Win32::{
            Foundation::HANDLE,
            Storage::FileSystem::{GetFileInformationByHandle, BY_HANDLE_FILE_INFORMATION},
        };
        let file = fs::File::open(path)?;
        let mut info = BY_HANDLE_FILE_INFORMATION::default();
        unsafe {
            GetFileInformationByHandle(HANDLE(file.as_raw_handle() as isize), &mut info)?;
        }
        Ok(format!(
            "{}:{}:{}",
            info.dwVolumeSerialNumber, info.nFileIndexHigh, info.nFileIndexLow
        ))
    }
    #[cfg(not(windows))]
    {
        Ok(fs::canonicalize(path)?.to_string_lossy().into_owned())
    }
}

pub(crate) fn metadata_fingerprint(path: &Path) -> anyhow::Result<String> {
    let metadata = fs::metadata(path)?;
    anyhow::ensure!(metadata.is_file(), "TAG_SOURCE_UNREADABLE|音频路径不是文件");
    Ok(format!(
        "{}_{}",
        metadata.len(),
        metadata.modified()?.duration_since(UNIX_EPOCH)?.as_nanos()
    ))
}

/// Read-only preview, using exactly the container probe used by safe edits.
/// Neither extension guesses nor the cached library are evidence of writability.
pub fn preflight_audio_metadata(path: String) -> anyhow::Result<String> {
    let path = Path::new(&path);
    let before = metadata_fingerprint(path)?;
    let source_key = physical_source_key(path)?;
    let metadata = fs::metadata(path)?;
    let tagged = match super::tag_reader::probe_tagged_audio(path, "TAG_FORMAT_UNKNOWN") {
        Ok(tagged) => tagged,
        Err(error) => {
            return Ok(json!({
                "supported": false, "readOnly": metadata.permissions().readonly(),
                "fingerprint": before, "sourceKey": source_key, "reason": error.to_string(),
            })
            .to_string())
        }
    };
    let supported = tagged.supports_tag_type(tagged.primary_tag_type());
    let tag = tagged.primary_tag().or_else(|| tagged.first_tag());
    let value = json!({
        "supported": supported, "readOnly": metadata.permissions().readonly(),
        "fingerprint": before,
        "sourceKey": source_key,
        "title": tag.and_then(|tag| tag.title()).map(|value| value.into_owned()).unwrap_or_default(),
        "artist": tag.and_then(|tag| tag.artist()).map(|value| value.into_owned()).unwrap_or_default(),
        "album": tag.and_then(|tag| tag.album()).map(|value| value.into_owned()).unwrap_or_default(),
        "reason": if supported { "" } else { "TAG_FORMAT_UNSUPPORTED|当前实际音频容器不支持安全写入标签" },
    });
    anyhow::ensure!(
        metadata_fingerprint(path)? == before,
        "TAG_SOURCE_CHANGED|读取期间文件已改变，请重新预览"
    );
    Ok(value.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    #[cfg(windows)]
    fn hard_links_share_native_physical_source_key() {
        let parent = std::env::current_dir()
            .unwrap()
            .join("target/qa-metadata-preflight");
        fs::create_dir_all(&parent).unwrap();
        let unique = std::time::SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let root = parent.join(format!("hard-links-{}-{unique}", std::process::id()));
        fs::create_dir(&root).unwrap();
        let source = root.join("source.mp3");
        let alias = root.join("alias.mp3");
        fs::write(&source, b"physical identity fixture").unwrap();
        fs::hard_link(&source, &alias).unwrap();
        let first: serde_json::Value = serde_json::from_str(
            &preflight_audio_metadata(source.to_string_lossy().into_owned()).unwrap(),
        )
        .unwrap();
        let second: serde_json::Value = serde_json::from_str(
            &preflight_audio_metadata(alias.to_string_lossy().into_owned()).unwrap(),
        )
        .unwrap();
        assert_eq!(first["sourceKey"], second["sourceKey"]);
        assert!(first["sourceKey"].as_str().unwrap().contains(':'));
        assert_eq!(fs::read(&source).unwrap(), b"physical identity fixture");
        fs::remove_file(alias).unwrap();
        fs::remove_file(source).unwrap();
        fs::remove_dir(root).unwrap();
    }
    #[test]
    fn preflight_rejects_unknown_without_touching_file() {
        let path = std::env::temp_dir().join(format!("dan-preflight-{}.mp3", std::process::id()));
        fs::write(&path, b"not an audio file").unwrap();
        let fingerprint = metadata_fingerprint(&path).unwrap();
        let result: serde_json::Value = serde_json::from_str(
            &preflight_audio_metadata(path.to_string_lossy().into_owned()).unwrap(),
        )
        .unwrap();
        assert_eq!(result["supported"], false);
        assert_eq!(result["fingerprint"], fingerprint);
        assert_eq!(fs::read(&path).unwrap(), b"not an audio file");
        fs::remove_file(path).unwrap();
    }
}
