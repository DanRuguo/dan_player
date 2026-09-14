use super::*;
use lofty::{
    prelude::{ItemKey, TagExt},
    tag::{Tag, TagType},
};
use std::{
    io::{BufReader, Seek, SeekFrom, Write},
    process::Command,
    time::{SystemTime, UNIX_EPOCH},
};

struct Fixture(PathBuf);
impl Fixture {
    fn new() -> Self {
        let base = Path::new(env!("CARGO_MANIFEST_DIR")).join("target/qa-audio-trim");
        fs::create_dir_all(&base).unwrap();
        let id = TRANSACTION.fetch_add(1, Ordering::Relaxed);
        let path = base.join(format!(
            "{}-{}-{id}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir(&path).unwrap();
        Self(path)
    }
    fn file(&self, name: &str) -> PathBuf {
        self.0.join(name)
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        if let Ok(mut prepared) = prepared().lock() {
            prepared.retain(|key, _| {
                !key.starts_with(&self.0)
                    && !key
                        .to_string_lossy()
                        .contains(&*self.0.file_name().unwrap().to_string_lossy())
            });
        }
        let parent =
            fs::canonicalize(Path::new(env!("CARGO_MANIFEST_DIR")).join("target/qa-audio-trim"))
                .unwrap();
        let path = fs::canonicalize(&self.0).unwrap();
        assert!(path.starts_with(parent));
        fs::remove_dir_all(path).unwrap();
    }
}
fn string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}
fn wave(path: &Path, seconds: u32) {
    let length = 8000 * 2 * seconds;
    let mut bytes = Vec::new();
    bytes.extend(b"RIFF");
    bytes.extend((length + 36).to_le_bytes());
    bytes.extend(b"WAVEfmt ");
    bytes.extend(16u32.to_le_bytes());
    bytes.extend(1u16.to_le_bytes());
    bytes.extend(1u16.to_le_bytes());
    bytes.extend(8000u32.to_le_bytes());
    bytes.extend(16000u32.to_le_bytes());
    bytes.extend(2u16.to_le_bytes());
    bytes.extend(16u16.to_le_bytes());
    bytes.extend(b"data");
    bytes.extend(length.to_le_bytes());
    bytes.resize(44 + length as usize, 0);
    fs::write(path, bytes).unwrap();
}
fn preview(source: &Path) -> String {
    serde_json::from_str::<serde_json::Value>(&prepare_audio_trim(string(source)).unwrap()).unwrap()
        ["fingerprint"]
        .as_str()
        .unwrap()
        .into()
}
fn finish(source: &Path, temporary: &Path, preserve: bool) -> anyhow::Result<String> {
    finish_audio_trim_metadata(
        string(source),
        string(temporary),
        preserve,
        Some("裁剪标题".into()),
        Some("Artist".into()),
        Some("Album".into()),
        0.5,
        1.5,
    )
}

#[test]
fn wave_copy_and_atomic_overwrite_keep_audio_and_recovery_copy() {
    for overwrite in [false, true] {
        let fixture = Fixture::new();
        let source = fixture.file("source.wav");
        let temporary = fixture.file("temp.wav");
        wave(&source, 3);
        wave(&temporary, 1);
        let original = fs::read(&source).unwrap();
        let fingerprint = preview(&source);
        let output: serde_json::Value =
            serde_json::from_str(&finish(&source, &temporary, true).unwrap()).unwrap();
        assert_eq!(output["duration"], 1);
        let destination = if overwrite {
            source.clone()
        } else {
            fixture.file("copy.wav")
        };
        let result: serde_json::Value = serde_json::from_str(
            &commit_audio_trim(
                string(&source),
                string(&temporary),
                string(&destination),
                overwrite,
                fingerprint,
            )
            .unwrap(),
        )
        .unwrap();
        assert_eq!(result["audio"]["duration"], 1);
        assert_eq!(result["audio"]["title"], "裁剪标题");
        assert_eq!(result["audio"]["path"], result["path"]);
        if overwrite {
            assert_eq!(
                fs::read(result["backupPath"].as_str().unwrap()).unwrap(),
                original
            );
        } else {
            assert!(result["backupPath"].is_null());
            assert_eq!(fs::read(source).unwrap(), original);
        }
    }
}

#[test]
fn cloud_reparse_tags_are_not_path_redirects() {
    assert!(!redirects_path(0x9000001a)); // IO_REPARSE_TAG_CLOUD
    assert!(!redirects_path(0x9000f01a)); // IO_REPARSE_TAG_CLOUD_F
    assert!(redirects_path(0xa000000c)); // symbolic link
    assert!(redirects_path(0xa0000003)); // mount point / junction
}

#[test]
fn untagged_output_uses_the_destination_filename_only_without_a_title_tag() {
    let fixture = Fixture::new();
    let source = fixture.file("source.wav");
    let temporary = fixture.file("temporary.wav");
    let destination = fixture.file("用户选择的文件名.wav");
    wave(&source, 3);
    wave(&temporary, 1);
    let expected = preview(&source);
    finish_audio_trim_metadata(
        string(&source),
        string(&temporary),
        true,
        None,
        None,
        None,
        0.0,
        1.0,
    )
    .unwrap();
    let value: serde_json::Value = serde_json::from_str(
        &commit_audio_trim(
            string(&source),
            string(&temporary),
            string(&destination),
            false,
            expected,
        )
        .unwrap(),
    )
    .unwrap();
    assert_eq!(value["audio"]["title"], "用户选择的文件名.wav");
    assert!(!super::super::tag_reader::has_indexed_title(
        &probe_tagged_audio(&destination, "TEST").unwrap()
    ));
    let title = ".dan-player-trim-real-user-title.wav";
    let mut tag = Tag::new(TagType::RiffInfo);
    tag.set_title(title.into());
    tag.save_to_path(&source, lofty::config::WriteOptions::default())
        .unwrap();
    wave(&temporary, 1);
    let expected = preview(&source);
    finish_audio_trim_metadata(
        string(&source),
        string(&temporary),
        true,
        None,
        None,
        None,
        0.0,
        1.0,
    )
    .unwrap();
    let titled = fixture.file("different-name.wav");
    let value: serde_json::Value = serde_json::from_str(
        &commit_audio_trim(
            string(&source),
            string(&temporary),
            string(&titled),
            false,
            expected,
        )
        .unwrap(),
    )
    .unwrap();
    assert_eq!(value["audio"]["title"], title);
}

#[test]
fn unsupported_track_metadata_and_chained_streams_are_detected() {
    fn atom(id: &[u8; 4], payload: Vec<u8>) -> Vec<u8> {
        let mut atom = ((payload.len() + 8) as u32).to_be_bytes().to_vec();
        atom.extend(id);
        atom.extend(payload);
        atom
    }
    let fixture = Fixture::new();
    let mp4 = fixture.file("track-tags.m4a");
    let track_metadata = atom(b"udta", atom(b"meta", vec![0; 4]));
    fs::write(&mp4, atom(b"moov", atom(b"trak", track_metadata))).unwrap();
    assert!(tags::check_extra_metadata(&mp4, FileType::Mp4)
        .unwrap_err()
        .to_string()
        .starts_with("TRIM_TAGS_UNSUPPORTED|"));
    let ogg = fixture.file("chained.ogg");
    let mut page = vec![0; 27];
    page[..4].copy_from_slice(b"OggS");
    page[5] = 2;
    let mut pages = page.clone();
    pages.extend(page);
    fs::write(&ogg, pages).unwrap();
    assert!(tags::check_extra_metadata(&ogg, FileType::Vorbis)
        .unwrap_err()
        .to_string()
        .starts_with("TRIM_TAGS_UNSUPPORTED|"));
}

#[test]
fn embedded_unknown_lyrics_warn_without_changing_comments_or_original_text() {
    let fixture = Fixture::new();
    let source = fixture.file("source.wav");
    let temporary = fixture.file("temporary.wav");
    wave(&source, 3);
    wave(&temporary, 1);
    let text = "[00:01]<00:01.200>enhanced";
    let mut tag = Tag::new(TagType::Id3v2);
    tag.insert_text(ItemKey::Lyrics, text.into());
    tag.insert_text(ItemKey::Comment, "[00:01.00]ordinary comment".into());
    tag.save_to_path(&source, lofty::config::WriteOptions::default())
        .unwrap();
    let fingerprint = preview(&source);
    let value: serde_json::Value =
        serde_json::from_str(&finish(&source, &temporary, true).unwrap()).unwrap();
    assert_eq!(value["lyricWarnings"], json!([lyrics::WARNING]));
    let actual = probe_tagged_audio(&temporary, "TEST").unwrap();
    assert_eq!(
        actual
            .tag(TagType::Id3v2)
            .unwrap()
            .get_string(&ItemKey::Lyrics),
        Some(text)
    );
    assert_eq!(
        actual
            .tag(TagType::Id3v2)
            .unwrap()
            .get_string(&ItemKey::Comment),
        Some("[00:01.00]ordinary comment")
    );
    let destination = fixture.file("copy.wav");
    let result: serde_json::Value = serde_json::from_str(
        &commit_audio_trim(
            string(&source),
            string(&temporary),
            string(&destination),
            false,
            fingerprint,
        )
        .unwrap(),
    )
    .unwrap();
    assert_eq!(result["warnings"], json!([lyrics::WARNING]));
}

#[test]
fn cropping_before_the_first_lyric_can_remove_the_only_lyric_tag() {
    let fixture = Fixture::new();
    let source = fixture.file("source.wav");
    let temporary = fixture.file("temporary.wav");
    wave(&source, 3);
    wave(&temporary, 1);
    let mut tag = Tag::new(TagType::Id3v2);
    tag.insert_text(ItemKey::Lyrics, "[00:02]after clip".into());
    tag.save_to_path(&source, lofty::config::WriteOptions::default())
        .unwrap();
    finish_audio_trim_metadata(
        string(&source),
        string(&temporary),
        true,
        None,
        None,
        None,
        0.0,
        1.0,
    )
    .unwrap();
    assert!(probe_tagged_audio(&temporary, "TEST")
        .unwrap()
        .tags()
        .iter()
        .all(|tag| tag.get_string(&ItemKey::Lyrics).is_none()));
}

#[test]
fn fingerprint_rejects_same_size_same_time_content_change() {
    let fixture = Fixture::new();
    let source = fixture.file("source.wav");
    let temporary = fixture.file("temp.wav");
    wave(&source, 3);
    wave(&temporary, 1);
    let fingerprint = preview(&source);
    finish(&source, &temporary, true).unwrap();
    let before = fs::metadata(&source).unwrap().modified().unwrap();
    let mut file = OpenOptions::new().write(true).open(&source).unwrap();
    file.seek(SeekFrom::End(-1)).unwrap();
    file.write_all(&[1]).unwrap();
    file.set_times(fs::FileTimes::new().set_modified(before))
        .unwrap();
    drop(file);
    let modified = fs::read(&source).unwrap();
    let error = commit_audio_trim(
        string(&source),
        string(&temporary),
        string(&source),
        true,
        fingerprint,
    )
    .unwrap_err();
    assert!(error.to_string().starts_with("TRIM_SOURCE_CHANGED|"));
    assert_eq!(fs::read(&source).unwrap(), modified);
}

#[test]
fn existing_destination_and_aliases_are_never_overwritten() {
    let fixture = Fixture::new();
    let source = fixture.file("source.wav");
    let temporary = fixture.file("temp.wav");
    let alias = fixture.file("alias.wav");
    wave(&source, 3);
    wave(&temporary, 1);
    fs::hard_link(&source, &alias).unwrap();
    let original = fs::read(&source).unwrap();
    assert!(finish(&source, &alias, true)
        .unwrap_err()
        .to_string()
        .starts_with("TRIM_PATH_ALIAS|"));
    let fingerprint = preview(&source);
    finish(&source, &temporary, true).unwrap();
    assert!(commit_audio_trim(
        string(&source),
        string(&temporary),
        string(&alias),
        true,
        fingerprint.clone()
    )
    .unwrap_err()
    .to_string()
    .starts_with("TRIM_PATH_ALIAS|"));
    assert!(commit_audio_trim(
        string(&source),
        string(&temporary),
        string(&alias),
        false,
        fingerprint
    )
    .unwrap_err()
    .to_string()
    .starts_with("TRIM_DESTINATION_EXISTS|"));
    assert_eq!(fs::read(source).unwrap(), original);
    assert_eq!(fs::read(alias).unwrap(), original);
}

#[test]
fn modified_output_and_unverified_temporary_are_refused() {
    let fixture = Fixture::new();
    let source = fixture.file("source.wav");
    let temporary = fixture.file("temp.wav");
    wave(&source, 3);
    wave(&temporary, 1);
    let fingerprint = preview(&source);
    let original = fs::read(&source).unwrap();
    assert!(commit_audio_trim(
        string(&source),
        string(&temporary),
        string(&source),
        true,
        fingerprint.clone()
    )
    .unwrap_err()
    .to_string()
    .starts_with("TRIM_NOT_VERIFIED|"));
    finish(&source, &temporary, true).unwrap();
    OpenOptions::new()
        .append(true)
        .open(&temporary)
        .unwrap()
        .write_all(b"changed")
        .unwrap();
    assert!(commit_audio_trim(
        string(&source),
        string(&temporary),
        string(&source),
        true,
        fingerprint
    )
    .unwrap_err()
    .to_string()
    .starts_with("TRIM_OUTPUT_CHANGED|"));
    assert_eq!(fs::read(source).unwrap(), original);
}

#[test]
fn canceled_jobs_release_slots_even_after_temporary_deletion() {
    let fixture = Fixture::new();
    let source = fixture.file("source.wav");
    wave(&source, 3);
    for index in 0..70 {
        let temporary = fixture.file(&format!("temp-{index}.wav"));
        wave(&temporary, 1);
        finish(&source, &temporary, true).unwrap();
        fs::remove_file(&temporary).unwrap();
        release_audio_trim(string(&temporary));
        release_audio_trim(string(&temporary));
    }
    assert!(!prepared().lock().unwrap().keys().any(|key| key
        .to_string_lossy()
        .contains(&*fixture.0.file_name().unwrap().to_string_lossy())));
}

#[test]
fn unknown_wave_metadata_is_refused_instead_of_silently_discarded() {
    let fixture = Fixture::new();
    let source = fixture.file("source.wav");
    let temporary = fixture.file("temp.wav");
    wave(&source, 3);
    wave(&temporary, 1);
    let mut bytes = fs::read(&source).unwrap();
    bytes.extend(b"bext");
    bytes.extend(4u32.to_le_bytes());
    bytes.extend(b"test");
    let size = bytes.len() as u32 - 8;
    bytes[4..8].copy_from_slice(&size.to_le_bytes());
    fs::write(&source, &bytes).unwrap();
    assert!(finish(&source, &temporary, true)
        .unwrap_err()
        .to_string()
        .starts_with("TRIM_TAGS_UNSUPPORTED|"));
    assert_eq!(fs::read(&source).unwrap(), bytes);
    finish(&source, &temporary, false).unwrap();
}

fn picture(kind: lofty::picture::PictureType, color: u8) -> lofty::picture::Picture {
    let image = image::RgbImage::from_pixel(4, 4, image::Rgb([color, 35, 90]));
    let mut bytes = std::io::Cursor::new(Vec::new());
    image.write_to(&mut bytes, image::ImageFormat::Png).unwrap();
    lofty::picture::Picture::new_unchecked(
        kind,
        Some(lofty::picture::MimeType::Png),
        Some(format!("封面 {color}")),
        bytes.into_inner(),
    )
}

#[test]
#[ignore = "requires DAN_TRIM_TEST_FFMPEG; generates local synthetic files for seven containers"]
fn seven_real_containers_keep_native_tags_and_multiple_pictures() {
    let ffmpeg = std::env::var("DAN_TRIM_TEST_FFMPEG").expect("DAN_TRIM_TEST_FFMPEG");
    for (extension, codec) in [
        ("mp3", "libmp3lame"),
        ("flac", "flac"),
        ("m4a", "aac"),
        ("ogg", "libvorbis"),
        ("opus", "libopus"),
        ("wav", "pcm_s16le"),
        ("aiff", "pcm_s16be"),
    ] {
        let fixture = Fixture::new();
        let source = fixture.file(&format!("source.{extension}"));
        let temporary = fixture.file(&format!("temp.{extension}"));
        let output = Command::new(&ffmpeg)
            .args([
                "-hide_banner",
                "-loglevel",
                "error",
                "-f",
                "lavfi",
                "-i",
                "sine=frequency=440:duration=3",
                "-map_metadata",
                "-1",
                "-c:a",
                codec,
            ])
            .arg(&source)
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{extension}: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        let parsed = probe_tagged_audio(&source, "TEST").unwrap();
        let tag_type = if matches!(parsed.file_type(), FileType::Wav | FileType::Aiff) {
            TagType::Id3v2
        } else {
            parsed.primary_tag_type()
        };
        let mut tag = Tag::new(tag_type);
        tag.set_title("源标题".into());
        tag.set_artist("源歌手".into());
        tag.set_album("原专辑".into());
        tag.set_track(7);
        tag.insert_text(ItemKey::Composer, "作曲者".into());
        tag.insert_text(ItemKey::Language, "jpn".into());
        tag.insert_text(ItemKey::Lyrics, "[00:01.00] preserved lyric".into());
        tag.push_picture(picture(lofty::picture::PictureType::CoverFront, 70));
        tag.push_picture(picture(lofty::picture::PictureType::CoverBack, 190));
        tag.save_to_path(&source, lofty::config::WriteOptions::default())
            .unwrap();
        if tag_type == TagType::Id3v2 {
            let mut file = BufReader::new(File::open(&source).unwrap());
            let options = lofty::config::ParseOptions::default();
            let mut native = match parsed.file_type() {
                FileType::Mpeg => lofty::mpeg::MpegFile::read_from(&mut file, options)
                    .unwrap()
                    .id3v2()
                    .cloned()
                    .unwrap(),
                FileType::Wav => lofty::iff::wav::WavFile::read_from(&mut file, options)
                    .unwrap()
                    .id3v2()
                    .cloned()
                    .unwrap(),
                _ => lofty::iff::aiff::AiffFile::read_from(&mut file, options)
                    .unwrap()
                    .id3v2()
                    .cloned()
                    .unwrap(),
            };
            native.insert(lofty::id3::v2::Frame::Comment(
                lofty::id3::v2::CommentFrame::new(
                    lofty::TextEncoding::UTF8,
                    *b"jpn",
                    "descriptor 日本".into(),
                    "コメント".into(),
                ),
            ));
            native
                .save_to_path(&source, lofty::config::WriteOptions::default())
                .unwrap();
        }
        let original = fs::read(&source).unwrap();
        let before = probe_tagged_audio(&source, "TEST").unwrap();
        let pictures = before
            .tags()
            .iter()
            .map(|tag| tag.pictures().len())
            .sum::<usize>();
        assert_eq!(pictures, 2, "{extension}");
        let output = Command::new(&ffmpeg)
            .args(["-hide_banner", "-loglevel", "error", "-i"])
            .arg(&source)
            .args([
                "-ss",
                "0.5",
                "-t",
                "1",
                "-map",
                "0:a:0",
                "-map_metadata",
                "-1",
                "-vn",
                "-c:a",
                codec,
            ])
            .arg(&temporary)
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{extension}: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        let fingerprint = preview(&source);
        finish(&source, &temporary, true).unwrap_or_else(|error| panic!("{extension}: {error:#}"));
        let actual = probe_tagged_audio(&temporary, "TEST").unwrap();
        assert_eq!(
            actual
                .tags()
                .iter()
                .map(|tag| tag.pictures().len())
                .sum::<usize>(),
            2,
            "{extension}"
        );
        assert_eq!(
            actual
                .tags()
                .iter()
                .find_map(|tag| tag.get_string(&ItemKey::Composer)),
            Some("作曲者"),
            "{extension}"
        );
        assert_eq!(
            actual
                .tags()
                .iter()
                .find_map(|tag| tag.get_string(&ItemKey::Lyrics)),
            Some("[00:00.500]preserved lyric"),
            "{extension}"
        );
        let destination = fixture.file(&format!("result.{extension}"));
        commit_audio_trim(
            string(&source),
            string(&temporary),
            string(&destination),
            false,
            fingerprint,
        )
        .unwrap();
        assert_eq!(fs::read(source).unwrap(), original);
        eprintln!("PASS native trim metadata {extension}: pictures=2, tags, audio, copy verified");
    }
}
