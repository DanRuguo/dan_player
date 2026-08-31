//! Narrow fallback for readable MPEG streams with opaque, incompatible ID3
//! frame contents. It never repairs/discards an unedited frame. Only plain
//! ID3v2.3/2.4, bounded frames, zero global/frame flags and unique text targets
//! are accepted; all other layouts stay explicitly unsupported.

use super::*;
use std::ops::Range;

const MAX_TAG_BYTES: usize = 64 * 1024 * 1024;
const TEXT_IDS: [&[u8; 4]; 3] = [b"TIT2", b"TPE1", b"TALB"];

pub(super) fn has_empty_text_frame(source: &Path) -> bool {
    // Lofty 0.21 consumes a text frame's encoding byte before returning Skip,
    // then skips its declared size again. Depending on following bytes, this
    // can either error or silently omit later frames. Select the opaque path
    // before parsing when the bounded plain-layout scan proves this case.
    let Ok(file) = fs::File::open(source) else {
        return false;
    };
    let Ok(raw) = RawTag::read(&mut BufReader::new(file)) else {
        return false;
    };
    raw.frames.iter().any(|frame| {
        raw.body[frame.start] == b'T' && frame.len() == 11 && raw.body[frame.start + 10] <= 3
    })
}

fn unsupported() -> anyhow::Error {
    metadata_message(
        "TAG_LAYOUT_UNSUPPORTED",
        "此 ID3 标签布局暂不支持安全兼容编辑，已保留原文件及全部原始标签",
    )
}

struct RawTag {
    version: u8,
    body: Vec<u8>,
    frames: Vec<Range<usize>>,
}

impl RawTag {
    fn read(reader: &mut impl Read) -> anyhow::Result<Self> {
        let mut header = [0; 10];
        reader.read_exact(&mut header)?;
        if &header[..3] != b"ID3" || !matches!(header[3], 3 | 4) || header[4] != 0 || header[5] != 0
        {
            // Reject unsynchronisation, extended headers/CRCs, footer,
            // restrictions and unknown global flags, not merely ignore them.
            return Err(unsupported());
        }
        let size = syncsafe(&header[6..10]).ok_or_else(unsupported)?;
        if size > MAX_TAG_BYTES {
            return Err(unsupported());
        }
        let mut body = vec![0; size];
        reader.read_exact(&mut body)?;
        Self::parse(header[3], body)
    }

    fn parse(version: u8, body: Vec<u8>) -> anyhow::Result<Self> {
        let mut frames = Vec::new();
        let mut seen = HashSet::new();
        let mut offset = 0usize;
        while offset < body.len() {
            if body[offset] == 0 {
                if !body[offset..].iter().all(|byte| *byte == 0) {
                    return Err(unsupported());
                }
                break;
            }
            let header_end = offset.checked_add(10).ok_or_else(unsupported)?;
            let header = body.get(offset..header_end).ok_or_else(unsupported)?;
            if !header[..4]
                .iter()
                .all(|byte| byte.is_ascii_uppercase() || byte.is_ascii_digit())
                || header[8..10] != [0, 0]
            {
                // Includes frame compression/encryption/grouping/unsync,
                // read-only/alter-preservation flags and reserved bits.
                return Err(unsupported());
            }
            let length = if version == 4 {
                syncsafe(&header[4..8]).ok_or_else(unsupported)?
            } else {
                u32::from_be_bytes(header[4..8].try_into().unwrap()) as usize
            };
            let end = header_end.checked_add(length).ok_or_else(unsupported)?;
            if length == 0 || end > body.len() {
                return Err(unsupported());
            }
            if TEXT_IDS.contains(&header[..4].try_into().unwrap()) {
                if !seen.insert(header[..4].to_vec()) {
                    return Err(unsupported());
                }
                validate_text_encoding(version, &body[header_end..end])?;
            }
            frames.push(offset..end);
            offset = end;
        }
        Ok(Self {
            version,
            body,
            frames,
        })
    }

    fn is_edited(&self, frame: &Range<usize>, replaces_front: bool) -> anyhow::Result<bool> {
        let id = &self.body[frame.start..frame.start + 4];
        if TEXT_IDS.contains(&id.try_into().unwrap()) {
            return Ok(true);
        }
        if !replaces_front || id != b"APIC" {
            return Ok(false);
        }
        let version = if self.version == 3 {
            lofty::id3::v2::Id3v2Version::V3
        } else {
            lofty::id3::v2::Id3v2Version::V4
        };
        let mut payload = &self.body[frame.start + 10..frame.end];
        let picture = lofty::id3::v2::AttachedPictureFrame::parse(
            &mut payload,
            lofty::id3::v2::FrameFlags::default(),
            version,
        )
        .map_err(|_| unsupported())?;
        Ok(picture.picture.pic_type() == PictureType::CoverFront)
    }

    fn kept_frames(&self, replaces_front: bool) -> anyhow::Result<Vec<&[u8]>> {
        let mut kept = Vec::new();
        for frame in &self.frames {
            if !self.is_edited(frame, replaces_front)? {
                kept.push(&self.body[frame.clone()]);
            }
        }
        Ok(kept)
    }
}

fn syncsafe(bytes: &[u8]) -> Option<usize> {
    if bytes.len() != 4 || bytes.iter().any(|byte| byte & 0x80 != 0) {
        return None;
    }
    Some(
        bytes
            .iter()
            .fold(0usize, |value, byte| (value << 7) | *byte as usize),
    )
}

fn validate_text_encoding(version: u8, payload: &[u8]) -> anyhow::Result<()> {
    let Some((&encoding, text)) = payload.split_first() else {
        return Err(unsupported());
    };
    let valid = match encoding {
        0 => true,
        1 => {
            text.len() >= 2
                && text.len() % 2 == 0
                && ((text.starts_with(&[0xff, 0xfe]) && valid_utf16(&text[2..], true))
                    || (text.starts_with(&[0xfe, 0xff]) && valid_utf16(&text[2..], false)))
        }
        2 if version == 4 => valid_utf16(text, false),
        3 if version == 4 => std::str::from_utf8(text).is_ok(),
        _ => false,
    };
    if valid {
        Ok(())
    } else {
        Err(unsupported())
    }
}

fn valid_utf16(bytes: &[u8], little_endian: bool) -> bool {
    bytes.len() % 2 == 0
        && char::decode_utf16(bytes.chunks_exact(2).map(|chunk| {
            if little_endian {
                u16::from_le_bytes([chunk[0], chunk[1]])
            } else {
                u16::from_be_bytes([chunk[0], chunk[1]])
            }
        }))
        .all(|value| value.is_ok())
}

fn stream_properties(path: &Path) -> anyhow::Result<Option<AudioPropertiesSnapshot>> {
    let file = fs::File::open(path)?;
    let probe = Probe::new(BufReader::new(file))
        .options(lofty::config::ParseOptions::default().read_tags(false))
        .guess_file_type()?;
    if probe.file_type() != Some(FileType::Mpeg) {
        return Ok(None);
    }
    let audio = probe.read()?;
    let properties = AudioPropertiesSnapshot::from(&audio);
    if properties.sample_rate.unwrap_or(0) == 0
        || properties.channels.unwrap_or(0) == 0
        || properties.duration.is_zero()
    {
        return Ok(None);
    }
    Ok(Some(properties))
}

fn equal_remainder(left: &mut impl Read, right: &mut impl Read, size: u64) -> io::Result<bool> {
    let mut a = [0; 65536];
    let mut b = [0; 65536];
    let mut remaining = size;
    while remaining > 0 {
        let count = remaining.min(a.len() as u64) as usize;
        left.read_exact(&mut a[..count])?;
        right.read_exact(&mut b[..count])?;
        if a[..count] != b[..count] {
            return Ok(false);
        }
        remaining -= count as u64;
    }
    Ok(left.read(&mut a[..1])? == 0 && right.read(&mut b[..1])? == 0)
}

pub(super) fn try_write(
    source: &Path,
    target: &Path,
    title: &str,
    artist: &str,
    album: &str,
    picture_path: Option<&str>,
) -> anyhow::Result<bool> {
    let properties = match stream_properties(source) {
        Ok(Some(properties)) => properties,
        _ => return Ok(false),
    };
    if [title, artist, album]
        .iter()
        .any(|value| value.contains('\0'))
    {
        return Err(metadata_message(
            "TAG_INVALID_METADATA",
            "歌曲信息不能包含空字符，原文件未被修改",
        ));
    }
    let mut original = BufReader::new(fs::File::open(source)?);
    let original_metadata = original.get_ref().metadata()?;
    let raw = RawTag::read(&mut original)?;
    let original_payload_offset = original.stream_position()?;
    let replaces_front = picture_path.is_some();
    let kept = raw.kept_frames(replaces_front)?;
    let mut replacement = Tag::new(TagType::Id3v2);
    apply_tag_values(&mut replacement, title, artist, album, picture_path)?;
    let mut encoded = Vec::new();
    replacement.dump_to(
        &mut encoded,
        WriteOptions::default().use_id3v23(raw.version == 3),
    )?;
    let encoded = RawTag::read(&mut encoded.as_slice())?;
    let kept_size = kept
        .iter()
        .try_fold(0usize, |size, frame| size.checked_add(frame.len()))
        .ok_or_else(unsupported)?;
    let new_size = encoded
        .frames
        .iter()
        .try_fold(kept_size, |size, frame| size.checked_add(frame.len()))
        .ok_or_else(unsupported)?;
    if new_size > MAX_TAG_BYTES {
        return Err(unsupported());
    }
    let mut body = Vec::with_capacity(new_size.max(raw.body.len()));
    for frame in &kept {
        body.extend_from_slice(frame);
    }
    for frame in &encoded.frames {
        body.extend_from_slice(&encoded.body[frame.clone()]);
    }
    if body.len() > MAX_TAG_BYTES {
        return Err(unsupported());
    }
    body.resize(body.len().max(raw.body.len()), 0);
    let size = body.len();
    let mut prefix = vec![
        b'I',
        b'D',
        b'3',
        raw.version,
        0,
        0,
        ((size >> 21) & 127) as u8,
        ((size >> 14) & 127) as u8,
        ((size >> 7) & 127) as u8,
        (size & 127) as u8,
    ];
    prefix.extend_from_slice(&body);

    let mut temporary = TransactionPath::copy_of(source, "edit")?;
    {
        let mut output = OpenOptions::new()
            .write(true)
            .truncate(true)
            .open(temporary.path())?;
        output.write_all(&prefix)?;
        io::copy(&mut original, &mut output)?;
        output.sync_all()?;
    }
    let mut verified = BufReader::new(fs::File::open(temporary.path())?);
    let after = RawTag::read(&mut verified)?;
    if after.version != raw.version || after.kept_frames(replaces_front)? != kept {
        return Err(metadata_message(
            "TAG_VERIFY_PRESERVATION",
            "兼容写入未能完整保留原始标签，已取消替换",
        ));
    }
    let expected: Vec<_> = encoded
        .frames
        .iter()
        .map(|frame| &encoded.body[frame.clone()])
        .collect();
    let mut actual = Vec::new();
    for frame in &after.frames {
        if after.is_edited(frame, replaces_front)? {
            actual.push(&after.body[frame.clone()]);
        }
    }
    if actual != expected {
        return Err(metadata_message(
            "TAG_VERIFY_FIELDS",
            "兼容写入字段回读不一致，已保留原文件",
        ));
    }
    original.seek(SeekFrom::Start(original_payload_offset))?;
    let payload_size = original_metadata
        .len()
        .checked_sub(original_payload_offset)
        .ok_or_else(unsupported)?;
    if !equal_remainder(&mut original, &mut verified, payload_size)?
        || stream_properties(temporary.path())?.as_ref() != Some(&properties)
    {
        return Err(metadata_message(
            "TAG_VERIFY_AUDIO",
            "兼容写入的音频字节校验失败，已保留原文件",
        ));
    }
    let current = fs::metadata(source)?;
    if current.len() != original_metadata.len()
        || current.modified()? != original_metadata.modified()?
    {
        return Err(metadata_message(
            "TAG_SOURCE_CHANGED",
            "音频文件在编辑过程中被其他程序更改，已取消替换",
        ));
    }
    // Close our readers before the Windows rename transaction.
    drop(original);
    drop(verified);
    replace_with_rollback(source, target, &mut temporary)?;
    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn directory() -> PathBuf {
        let root = std::env::temp_dir().join(format!(
            "dan-id3-compat-{}-{}",
            std::process::id(),
            METADATA_TRANSACTION_ID.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&root).unwrap();
        root
    }

    fn frame(version: u8, id: &[u8; 4], payload: &[u8]) -> Vec<u8> {
        let size = payload.len();
        let mut bytes = id.to_vec();
        if version == 3 {
            bytes.extend_from_slice(&(size as u32).to_be_bytes());
        } else {
            bytes.extend_from_slice(&[
                ((size >> 21) & 127) as u8,
                ((size >> 14) & 127) as u8,
                ((size >> 7) & 127) as u8,
                (size & 127) as u8,
            ]);
        }
        bytes.extend_from_slice(&[0, 0]);
        bytes.extend_from_slice(payload);
        bytes
    }

    fn fixture(version: u8) -> Vec<u8> {
        let mut body = frame(version, b"TIT2", b"\0Old fixture");
        // The empty TYER triggers Lofty 0.21's consumed-frame double skip;
        // the non-standard timestamp makes its complete tag parse fail.
        body.extend(frame(
            version,
            if version == 3 { b"TYER" } else { b"TDRC" },
            if version == 3 {
                b"\0"
            } else {
                b"\x03not-a-date"
            },
        ));
        body.extend(frame(
            version,
            b"USLT",
            b"\0zhooriginal\0Synthetic lyric only",
        ));
        body.extend(frame(version, b"PRIV", b"synthetic.owner\0\x01\x02\x03"));
        body.extend([0; 32]);
        let size = body.len();
        let mut bytes = vec![
            b'I',
            b'D',
            b'3',
            version,
            0,
            0,
            ((size >> 21) & 127) as u8,
            ((size >> 14) & 127) as u8,
            ((size >> 7) & 127) as u8,
            (size & 127) as u8,
        ];
        bytes.extend(body);
        for _ in 0..3 {
            bytes.extend_from_slice(&[0xff, 0xfb, 0x90, 0x64]);
            bytes.extend([0x55; 413]);
        }
        bytes
    }

    #[test]
    fn metadata_raw_compat_preserves_opaque_frames_and_every_audio_byte() {
        for version in [3, 4] {
            let root = directory();
            let source = root.join("source.mp3");
            let target = root.join("renamed.mp3");
            let bytes = fixture(version);
            fs::write(&source, &bytes).unwrap();
            if version == 4 {
                assert!(probe_tagged_audio(&source, "test").is_err());
            }
            if version == 3 {
                assert!(has_empty_text_frame(&source));
            }
            let before = RawTag::read(&mut bytes.as_slice()).unwrap();
            write_metadata_safely(&source, &target, "新しい 제목", "Artists", "Album", None)
                .unwrap();
            let written = fs::read(&target).unwrap();
            let after = RawTag::read(&mut written.as_slice()).unwrap();
            assert_eq!(after.version, version);
            assert_eq!(
                before.kept_frames(false).unwrap(),
                after.kept_frames(false).unwrap()
            );
            assert_eq!(
                bytes[10 + before.body.len()..],
                written[10 + after.body.len()..]
            );
            assert!(!source.exists());
            assert_eq!(fs::read_dir(&root).unwrap().count(), 1);
            fs::remove_dir_all(root).unwrap();
        }
    }

    #[test]
    fn metadata_raw_compat_rejects_global_and_frame_flags_without_writing() {
        for global_flag in [0x80, 0x40, 0x20, 0x10, 1] {
            let mut bytes = fixture(4);
            bytes[5] = global_flag;
            assert!(RawTag::read(&mut bytes.as_slice()).is_err());
        }
        for index in [8, 9] {
            for flag in [1, 2, 4, 8, 16, 32, 64, 128] {
                let mut bytes = frame(4, b"TIT2", b"\x03Title");
                bytes[index] = flag;
                assert!(RawTag::parse(4, bytes).is_err());
            }
        }
    }

    #[test]
    fn metadata_raw_compat_rejects_ambiguous_lengths_ids_and_duplicates() {
        let valid = frame(4, b"TIT2", b"\x03Title");
        let mut duplicate = valid.clone();
        duplicate.extend(&valid);
        assert!(RawTag::parse(4, duplicate).is_err());
        let mut oversized = valid.clone();
        oversized[4..8].fill(0x7f);
        assert!(RawTag::parse(4, oversized).is_err());
        let mut invalid_sync = valid.clone();
        invalid_sync[4] = 0x80;
        assert!(RawTag::parse(4, invalid_sync).is_err());
        let mut invalid_id = valid.clone();
        invalid_id[0] = 0xff;
        assert!(RawTag::parse(4, invalid_id).is_err());
        assert!(RawTag::parse(4, valid[..valid.len() - 1].to_vec()).is_err());
        let mut dirty_padding = valid;
        dirty_padding.extend([0, 0, 1]);
        assert!(RawTag::parse(4, dirty_padding).is_err());
        let mut header = fixture(4);
        header[6] = 0x80;
        assert!(RawTag::read(&mut header.as_slice()).is_err());
        header[6] = 0x7f;
        assert!(RawTag::read(&mut header.as_slice()).is_err());
    }

    #[test]
    fn metadata_raw_compat_checks_each_text_encoding() {
        for payload in [
            b"\0Latin".as_slice(),
            b"\x01\xff\xfeA\0",
            b"\x01\xfe\xff\0A",
        ] {
            assert!(RawTag::parse(3, frame(3, b"TIT2", payload)).is_ok());
        }
        for payload in [b"\x02\0A".as_slice(), "\u{3}日本語 한국어".as_bytes()] {
            assert!(RawTag::parse(4, frame(4, b"TIT2", payload)).is_ok());
            assert!(RawTag::parse(3, frame(3, b"TIT2", payload)).is_err());
        }
        for payload in [
            b"\x04text".as_slice(),
            b"\x01A\0",
            b"\x01\xff\xfeA",
            b"\x01\xff\xfe\0\xd8",
            b"\x02A",
            b"\x03\xff",
        ] {
            assert!(RawTag::parse(4, frame(4, b"TIT2", payload)).is_err());
        }
    }

    #[test]
    fn metadata_raw_compat_collision_rolls_back_without_overwriting_target() {
        let root = directory();
        let source = root.join("source.mp3");
        let target = root.join("appeared.mp3");
        let original = fixture(3);
        fs::write(&source, &original).unwrap();
        fs::write(&target, b"independent data created by another program").unwrap();
        assert!(try_write(&source, &target, "New", "Artist", "Album", None).is_err());
        assert_eq!(fs::read(&source).unwrap(), original);
        assert_eq!(
            fs::read(&target).unwrap(),
            b"independent data created by another program"
        );
        assert_eq!(fs::read_dir(&root).unwrap().count(), 2);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn metadata_raw_compat_replaces_only_front_cover() {
        let root = directory();
        let source = root.join("source.mp3");
        let cover = root.join("cover.png");
        let initial = fixture(4);
        let raw = RawTag::read(&mut initial.as_slice()).unwrap();
        let mut pictures = Tag::new(TagType::Id3v2);
        let front = super::super::tests::test_picture(PictureType::CoverFront, 20);
        let back = super::super::tests::test_picture(PictureType::CoverBack, 80);
        let replacement = super::super::tests::test_picture(PictureType::CoverFront, 160);
        pictures.push_picture(front);
        pictures.push_picture(back);
        let mut encoded = Vec::new();
        pictures
            .dump_to(&mut encoded, WriteOptions::default())
            .unwrap();
        let picture_tag = RawTag::read(&mut encoded.as_slice()).unwrap();
        let mut body = Vec::new();
        for item in &raw.frames {
            body.extend_from_slice(&raw.body[item.clone()]);
        }
        for item in &picture_tag.frames {
            body.extend_from_slice(&picture_tag.body[item.clone()]);
        }
        let size = body.len();
        let mut bytes = vec![
            b'I',
            b'D',
            b'3',
            4,
            0,
            0,
            ((size >> 21) & 127) as u8,
            ((size >> 14) & 127) as u8,
            ((size >> 7) & 127) as u8,
            (size & 127) as u8,
        ];
        bytes.extend(body);
        bytes.extend_from_slice(&initial[10 + raw.body.len()..]);
        fs::write(&source, &bytes).unwrap();
        fs::write(&cover, replacement.data()).unwrap();
        assert!(try_write(&source, &source, "New", "Artist", "Album", cover.to_str()).unwrap());
        let written = fs::read(&source).unwrap();
        let before = RawTag::read(&mut bytes.as_slice()).unwrap();
        let after = RawTag::read(&mut written.as_slice()).unwrap();
        assert_eq!(
            before.kept_frames(true).unwrap(),
            after.kept_frames(true).unwrap()
        );
        let frames: Vec<_> = after
            .frames
            .iter()
            .filter(|frame| &after.body[frame.start..frame.start + 4] == b"APIC")
            .collect();
        assert_eq!(frames.len(), 2);
        let mut front_count = 0;
        for frame in frames {
            let mut payload = &after.body[frame.start + 10..frame.end];
            let parsed = lofty::id3::v2::AttachedPictureFrame::parse(
                &mut payload,
                lofty::id3::v2::FrameFlags::default(),
                lofty::id3::v2::Id3v2Version::V4,
            )
            .unwrap();
            if parsed.picture.pic_type() == PictureType::CoverFront {
                assert_eq!(parsed.picture.data(), replacement.data());
                front_count += 1;
            }
        }
        assert_eq!(front_count, 1);
        fs::remove_dir_all(root).unwrap();
    }
}
