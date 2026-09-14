//! Narrow fallback for readable MPEG streams with opaque, incompatible ID3
//! frame contents. It never repairs/discards an unedited frame. Only plain
//! ID3v2.3/2.4, bounded frames, zero global/frame flags and unique text targets
//! are accepted; all other layouts stay explicitly unsupported.

use super::*;
use std::ops::Range;

const MAX_TAG_BYTES: usize = 64 * 1024 * 1024;
const TEXT_IDS: [&[u8; 4]; 3] = [b"TIT2", b"TPE1", b"TALB"];

pub(crate) fn has_empty_text_frame(source: &Path) -> bool {
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

/// Read each bounded APIC frame independently. An unrelated date/text frame
/// that Lofty cannot parse must not make a valid embedded image disappear.
/// This uses the same conservative framing checks as the metadata fallback
/// and never rewrites tags or reads the MPEG payload.
pub(super) fn read_picture(source: &Path, width: u32, height: u32) -> Option<Vec<u8>> {
    let file = fs::File::open(source).ok()?;
    let raw = match RawTag::read(&mut BufReader::new(file)) {
        Ok(raw) => raw,
        Err(_) => return read_unsynced_picture(source, width, height),
    };
    let version = if raw.version == 3 {
        lofty::id3::v2::Id3v2Version::V3
    } else {
        lofty::id3::v2::Id3v2Version::V4
    };
    for front_only in [true, false] {
        for frame in &raw.frames {
            if &raw.body[frame.start..frame.start + 4] != b"APIC" {
                continue;
            }
            let mut payload = &raw.body[frame.start + 10..frame.end];
            let Ok(picture) = lofty::id3::v2::AttachedPictureFrame::parse(
                &mut payload,
                lofty::id3::v2::FrameFlags::default(),
                version,
            ) else {
                continue;
            };
            if (picture.picture.pic_type() == PictureType::CoverFront) != front_only {
                continue;
            }
            if let Some(bytes) = resize_picture(picture.picture.data(), width, height) {
                return Some(bytes);
            }
        }
    }
    None
}

fn read_unsynced_picture(source: &Path, width: u32, height: u32) -> Option<Vec<u8>> {
    let mut file = fs::File::open(source).ok()?;
    let mut header = [0; 10];
    file.read_exact(&mut header).ok()?;
    if &header[..3] != b"ID3" || header[3] != 4 || header[4] != 0 || header[5] & !0x80 != 0 {
        return None;
    }
    let size = syncsafe(&header[6..])?;
    if size > MAX_TAG_BYTES {
        return None;
    }
    let mut body = vec![0; size];
    file.read_exact(&mut body).ok()?;
    let mut offset = 0;
    let mut pictures = Vec::new();
    while offset + 10 <= body.len() && body[offset] != 0 {
        let frame = &body[offset..offset + 10];
        let length = syncsafe(&frame[4..8])?;
        let end = (offset + 10usize).checked_add(length)?;
        let encoded = body.get(offset + 10..end)?;
        if &frame[..4] == b"APIC" && frame[9] & !3 == 0 {
            let mut payload = Vec::with_capacity(encoded.len());
            let mut i = 0;
            while i < encoded.len() {
                let byte = encoded[i];
                payload.push(byte);
                i += 1;
                if (header[5] & 0x80 != 0 || frame[9] & 2 != 0)
                    && byte == 255
                    && encoded.get(i) == Some(&0)
                {
                    i += 1;
                }
            }
            let data = if frame[9] & 1 != 0 {
                payload.get(4..)?
            } else {
                &payload
            };
            if let Ok(picture) = lofty::id3::v2::AttachedPictureFrame::parse(
                &mut &data[..],
                lofty::id3::v2::FrameFlags::default(),
                lofty::id3::v2::Id3v2Version::V4,
            ) {
                pictures.push(picture.picture);
            }
        }
        offset = end;
    }
    pictures.sort_by_key(|p| p.pic_type() != PictureType::CoverFront);
    pictures
        .iter()
        .find_map(|p| resize_picture(p.data(), width, height))
}

fn unsupported() -> anyhow::Error {
    metadata_message(
        "TAG_LAYOUT_UNSUPPORTED",
        "此 ID3 标签布局暂不支持安全兼容编辑，已保留原文件及全部原始标签",
    )
}

struct RawTag {
    version: u8,
    flags: u8,
    body: Vec<u8>,
    frames: Vec<Range<usize>>,
}

/// Strict framing is retained even when a legacy frame's contents cannot be
/// decoded by Lofty. Only the audio-property probe skips those opaque values.
pub(crate) fn trim_probe(path: &Path) -> Option<TaggedFile> {
    RawTag::read_trim(&mut BufReader::new(fs::File::open(path).ok()?)).ok()?;
    let probe = Probe::new(BufReader::new(fs::File::open(path).ok()?))
        .options(lofty::config::ParseOptions::default().read_tags(false))
        .guess_file_type()
        .ok()?;
    if probe.file_type() != Some(FileType::Mpeg) {
        return None;
    }
    probe.read().ok()
}

fn raw_text(encoding: u8, bytes: &[u8]) -> anyhow::Result<String> {
    Ok(match encoding {
        0 => bytes.iter().map(|b| char::from(*b)).collect(),
        3 => std::str::from_utf8(bytes)?.to_string(),
        1 | 2 => {
            let (little, bytes) = if bytes.starts_with(&[0xff, 0xfe]) {
                (true, &bytes[2..])
            } else if bytes.starts_with(&[0xfe, 0xff]) {
                (false, &bytes[2..])
            } else if encoding == 2 {
                (false, bytes)
            } else {
                return Err(unsupported());
            };
            if bytes.len() % 2 != 0 {
                return Err(unsupported());
            }
            String::from_utf16(
                &bytes
                    .chunks_exact(2)
                    .map(|b| {
                        if little {
                            u16::from_le_bytes([b[0], b[1]])
                        } else {
                            u16::from_be_bytes([b[0], b[1]])
                        }
                    })
                    .collect::<Vec<_>>(),
            )?
        }
        _ => return Err(unsupported()),
    }
    .trim_end_matches('\0')
    .to_string())
}

fn encoded_text(version: u8, value: &str) -> Vec<u8> {
    if version == 4 {
        return value.as_bytes().to_vec();
    }
    let mut bytes = vec![0xff, 0xfe];
    for unit in value.encode_utf16() {
        bytes.extend_from_slice(&unit.to_le_bytes());
    }
    bytes
}
fn raw_frame(version: u8, id: &[u8], payload: &[u8]) -> Vec<u8> {
    let size = payload.len() as u32;
    let mut frame = id.to_vec();
    frame.extend_from_slice(&if version == 3 {
        size.to_be_bytes()
    } else {
        [
            ((size >> 21) & 127) as u8,
            ((size >> 14) & 127) as u8,
            ((size >> 7) & 127) as u8,
            (size & 127) as u8,
        ]
    });
    frame.extend_from_slice(&[0, 0]);
    frame.extend_from_slice(payload);
    frame
}

pub(crate) fn trim_text_fields(path: &Path) -> Option<[Option<String>; 3]> {
    let raw = RawTag::read_trim(&mut BufReader::new(fs::File::open(path).ok()?)).ok()?;
    Some(TEXT_IDS.map(|id| {
        raw.frames
            .iter()
            .find(|f| &raw.body[f.start..f.start + 4] == id)
            .and_then(|f| raw_text(raw.body[f.start + 10], &raw.body[f.start + 11..f.end]).ok())
    }))
}

/// Copy bounded original frames verbatim, replacing only requested text and
/// timestamps. This never opens the source for writing. The caller supplies a
/// private, already encoded MPEG output, and verifies its stream properties.
pub(crate) fn transfer_trim(
    source: &Path,
    destination: &Path,
    edits: [&Option<String>; 3],
    duration_ms: u128,
    legacy: Option<[u8; 128]>,
    transform: impl Fn(&str) -> (String, bool),
) -> anyhow::Result<Vec<String>> {
    let raw = RawTag::read_trim(&mut BufReader::new(fs::File::open(source)?))?;
    let mut tail = fs::File::open(source)?;
    let length = tail.metadata()?.len();
    let tail_end = length - if legacy.is_some() { 128 } else { 0 };
    let mut extras = Vec::new();
    let mut legacy_warning = false;
    if tail_end >= 32 {
        tail.seek(SeekFrom::Start(tail_end - 32))?;
        let mut footer = [0; 32];
        tail.read_exact(&mut footer)?;
        if &footer[..8] == b"APETAGEX" {
            let size = u32::from_le_bytes(footer[12..16].try_into()?) as u64;
            if size < 32 || size > MAX_TAG_BYTES as u64 || size > tail_end {
                return Err(unsupported());
            }
            let mut start = tail_end - size;
            if start >= 32 {
                tail.seek(SeekFrom::Start(start - 32))?;
                let mut signature = [0; 8];
                tail.read_exact(&mut signature)?;
                if &signature == b"APETAGEX" {
                    start -= 32;
                }
            }
            tail.seek(SeekFrom::Start(start))?;
            (&mut tail)
                .take(tail_end - start)
                .read_to_end(&mut extras)?;
        } else if &footer[23..] == b"LYRICS200" {
            let size: usize = std::str::from_utf8(&footer[17..23])?.parse()?;
            if size < 11 || size > MAX_TAG_BYTES || (size + 15) as u64 > tail_end {
                return Err(unsupported());
            }
            tail.seek(SeekFrom::Start(tail_end - (size + 15) as u64))?;
            let mut lyrics = vec![0; size];
            tail.read_exact(&mut lyrics)?;
            if !lyrics.starts_with(b"LYRICSBEGIN") {
                return Err(unsupported());
            }
            extras.extend_from_slice(b"LYRICSBEGIN");
            let mut offset = 11;
            while offset < lyrics.len() {
                let header = lyrics.get(offset..offset + 8).ok_or_else(unsupported)?;
                let count: usize = std::str::from_utf8(&header[3..])?.parse()?;
                let payload = lyrics
                    .get(offset + 8..offset + 8 + count)
                    .ok_or_else(unsupported)?;
                let updated = if &header[..3] == b"LYR" {
                    let text: String = payload.iter().map(|b| char::from(*b)).collect();
                    let (updated, warning) = transform(&text);
                    legacy_warning |= warning;
                    updated
                        .chars()
                        .map(|c| u8::try_from(c as u32))
                        .collect::<Result<Vec<_>, _>>()?
                } else {
                    payload.to_vec()
                };
                if updated.len() > 99999 {
                    return Err(unsupported());
                }
                extras.extend_from_slice(&header[..3]);
                extras.extend_from_slice(format!("{:05}", updated.len()).as_bytes());
                extras.extend(updated);
                offset += 8 + count;
            }
            if extras.len() > 999999 {
                return Err(unsupported());
            }
            extras.extend_from_slice(format!("{:06}LYRICS200", extras.len()).as_bytes());
        }
    }
    let mut body = Vec::new();
    let mut warnings = Vec::new();
    if legacy_warning {
        warnings.push("TRIM_LYRICS_UNSUPPORTED".into());
    }
    let warn = |warnings: &mut Vec<String>| {
        if warnings.is_empty() {
            warnings.push("TRIM_LYRICS_UNSUPPORTED".into());
        }
    };
    for frame in &raw.frames {
        let id = &raw.body[frame.start..frame.start + 4];
        if TEXT_IDS
            .iter()
            .enumerate()
            .any(|(i, key)| id == *key && edits[i].is_some())
        {
            continue;
        }
        if id == b"TLEN" {
            let mut value = vec![if raw.version == 3 { 1 } else { 3 }];
            value.extend(encoded_text(raw.version, &duration_ms.to_string()));
            body.extend(raw_frame(raw.version, id, &value));
            continue;
        }
        if id == b"USLT" {
            let payload = &raw.body[frame.start + 10..frame.end];
            let updated = (|| -> anyhow::Result<Vec<u8>> {
                if payload.len() < 5 {
                    return Err(unsupported());
                }
                let encoding = payload[0];
                let width = if encoding == 1 || encoding == 2 { 2 } else { 1 };
                let rest = &payload[4..];
                let separator = rest
                    .chunks_exact(width)
                    .position(|part| part.iter().all(|b| *b == 0))
                    .ok_or_else(unsupported)?
                    * width;
                let description = raw_text(encoding, &rest[..separator])?;
                let text = raw_text(encoding, &rest[separator + width..])?;
                let (text, unsupported_lyrics) = transform(&text);
                if unsupported_lyrics {
                    return Err(unsupported());
                }
                let mut result = vec![if raw.version == 3 { 1 } else { 3 }];
                result.extend_from_slice(&payload[1..4]);
                result.extend(encoded_text(raw.version, &description));
                result.extend(vec![0; if raw.version == 3 { 2 } else { 1 }]);
                result.extend(encoded_text(raw.version, &text));
                Ok(raw_frame(raw.version, id, &result))
            })();
            if let Ok(updated) = updated {
                body.extend(updated);
                continue;
            }
            warn(&mut warnings);
        } else if id == b"SYLT" {
            warn(&mut warnings);
        }
        body.extend_from_slice(&raw.body[frame.clone()]);
    }
    for (i, value) in edits.iter().enumerate() {
        if let Some(value) = value {
            if value.contains('\0') {
                return Err(unsupported());
            }
            let mut payload = vec![if raw.version == 3 { 1 } else { 3 }];
            payload.extend(encoded_text(raw.version, value));
            body.extend(raw_frame(raw.version, TEXT_IDS[i], &payload));
        }
    }
    if body.len() > MAX_TAG_BYTES {
        return Err(unsupported());
    }
    RawTag::parse_internal(raw.version, body.clone(), true)?;
    let mut input = BufReader::new(fs::File::open(destination)?);
    let existing = RawTag::read(&mut input)?;
    let payload_offset = 10 + existing.body.len() as u64;
    let staged = destination.with_extension("raw-trim-stage");
    let result = (|| -> anyhow::Result<()> {
        let mut output = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&staged)?;
        let size = body.len();
        output.write_all(&[
            b'I',
            b'D',
            b'3',
            raw.version,
            0,
            raw.flags,
            ((size >> 21) & 127) as u8,
            ((size >> 14) & 127) as u8,
            ((size >> 7) & 127) as u8,
            (size & 127) as u8,
        ])?;
        output.write_all(&body)?;
        io::copy(&mut input, &mut output)?;
        output.write_all(&extras)?;
        if let Some(bytes) = legacy {
            output.write_all(&bytes)?;
        }
        output.sync_all()?;
        drop(output);
        let check = RawTag::read_trim(&mut BufReader::new(fs::File::open(&staged)?))?;
        if check.body != body {
            return Err(unsupported());
        }
        // The only tail appended above is the exact original ID3v1 block.
        let mut copied = BufReader::new(fs::File::open(&staged)?);
        copied.seek(SeekFrom::Start(10 + body.len() as u64))?;
        input.seek(SeekFrom::Start(payload_offset))?;
        let count = input.get_ref().metadata()?.len() - payload_offset;
        let mut copied_audio = copied.take(count);
        if !equal_remainder(&mut input, &mut copied_audio, count)? {
            return Err(unsupported());
        }
        let mut expected_tail = extras.clone();
        if let Some(bytes) = legacy {
            expected_tail.extend_from_slice(&bytes);
        }
        let mut check_tail = fs::File::open(&staged)?;
        check_tail.seek(SeekFrom::End(-(expected_tail.len() as i64)))?;
        let mut actual_tail = Vec::new();
        check_tail.read_to_end(&mut actual_tail)?;
        if actual_tail != expected_tail {
            return Err(unsupported());
        }
        drop(check_tail);
        drop(input);
        fs::rename(&staged, destination)?;
        Ok(())
    })();
    if staged.exists() {
        let _ = fs::remove_file(&staged);
    }
    result?;
    Ok(warnings)
}

impl RawTag {
    fn read(reader: &mut impl Read) -> anyhow::Result<Self> {
        Self::read_internal(reader, false)
    }
    fn read_trim(reader: &mut impl Read) -> anyhow::Result<Self> {
        Self::read_internal(reader, true)
    }
    fn read_internal(reader: &mut impl Read, opaque: bool) -> anyhow::Result<Self> {
        let mut header = [0; 10];
        reader.read_exact(&mut header)?;
        if &header[..3] != b"ID3"
            || !matches!(header[3], 3 | 4)
            || header[4] != 0
            || (header[5] != 0 && !(opaque && header[3] == 4 && header[5] == 0x80))
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
        let mut raw = Self::parse_internal(header[3], body, opaque)?;
        raw.flags = header[5];
        Ok(raw)
    }

    fn parse(version: u8, body: Vec<u8>) -> anyhow::Result<Self> {
        Self::parse_internal(version, body, false)
    }
    fn parse_internal(version: u8, body: Vec<u8>, opaque: bool) -> anyhow::Result<Self> {
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
                || (header[8..10] != [0, 0]
                    && !(opaque && version == 4 && header[8] == 0 && header[9] & !3 == 0))
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
            flags: 0,
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
        // Identifying a front cover needs only the bounded APIC header. Do not
        // decode the old image or description: either may be damaged, and the
        // user explicitly asked to replace this frame. Other frames stay raw.
        let payload = &self.body[frame.start + 10..frame.end];
        if payload.first().is_none_or(|encoding| *encoding > 3) {
            return Err(unsupported());
        }
        let mime_end = payload[1..]
            .iter()
            .position(|byte| *byte == 0)
            .map(|position| position + 1)
            .ok_or_else(unsupported)?;
        let kind = *payload.get(mime_end + 1).ok_or_else(unsupported)?;
        Ok(kind == 3)
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

#[cfg(test)]
pub(super) fn try_write(
    source: &Path,
    target: &Path,
    title: &str,
    artist: &str,
    album: &str,
    picture_path: Option<&str>,
) -> anyhow::Result<bool> {
    try_write_expected(source, target, title, artist, album, picture_path, None)
}

pub(super) fn try_write_expected(
    source: &Path,
    target: &Path,
    title: &str,
    artist: &str,
    album: &str,
    picture_path: Option<&str>,
    expected_fingerprint: Option<&str>,
) -> anyhow::Result<bool> {
    check_metadata_fingerprint(source, expected_fingerprint)?;
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
    let front = replacement
        .get_picture_type(PictureType::CoverFront)
        .cloned();
    replacement.remove_picture_type(PictureType::CoverFront);
    let mut encoded = Vec::new();
    replacement.dump_to(
        &mut encoded,
        WriteOptions::default().use_id3v23(raw.version == 3),
    )?;
    let mut encoded = RawTag::read(&mut encoded.as_slice())?;
    if let Some(picture) = front {
        // The generic v2.3 writer emits an empty UTF-16 description without a
        // BOM. Use a Latin-1 empty description, independent of image bytes.
        let mut payload = b"\0".to_vec();
        payload.extend_from_slice(
            picture
                .mime_type()
                .ok_or_else(unsupported)?
                .as_str()
                .as_bytes(),
        );
        payload.extend_from_slice(&[0, 3, 0]);
        payload.extend_from_slice(picture.data());
        let length = payload.len() as u32;
        let mut frame = b"APIC".to_vec();
        frame.extend_from_slice(&if raw.version == 3 {
            length.to_be_bytes()
        } else {
            [
                ((length >> 21) & 127) as u8,
                ((length >> 14) & 127) as u8,
                ((length >> 7) & 127) as u8,
                (length & 127) as u8,
            ]
        });
        frame.extend_from_slice(&[0, 0]);
        frame.extend(payload);
        let end = encoded.frames.last().map_or(0, |frame| frame.end);
        encoded.body.truncate(end);
        encoded.body.extend(frame);
        encoded = RawTag::parse(raw.version, encoded.body)?;
    }
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
    check_metadata_fingerprint(source, expected_fingerprint)?;
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
    fn cover_read_ignores_unrelated_empty_and_invalid_date_frames() {
        for version in [3, 4] {
            let root = directory();
            let source = root.join("cover-fixture.mp3");
            let original = fixture(version);
            let old_size = syncsafe(&original[6..10]).unwrap();
            let image = image::RgbaImage::from_pixel(64, 48, image::Rgba([12, 91, 173, 255]));
            let mut png = Cursor::new(Vec::new());
            image.write_to(&mut png, image::ImageFormat::Png).unwrap();
            let mut picture = b"\0image/png\0\x03\0".to_vec();
            picture.extend_from_slice(png.get_ref());
            let mut body = original[10..10 + old_size - 32].to_vec();
            body.extend(frame(version, b"APIC", &picture));
            let size = body.len();
            let mut tagged = original[..10].to_vec();
            tagged[6..10].copy_from_slice(&[
                ((size >> 21) & 127) as u8,
                ((size >> 14) & 127) as u8,
                ((size >> 7) & 127) as u8,
                (size & 127) as u8,
            ]);
            tagged.extend(body);
            tagged.extend_from_slice(&original[10 + old_size..]);
            fs::write(&source, &tagged).unwrap();
            let bytes = _get_picture_by_lofty(&source.to_string_lossy().into_owned(), 96, 96)
                .expect("an incompatible text frame must not hide a valid embedded cover");
            let cover = image::load_from_memory(&bytes).unwrap().to_rgba8();
            assert_eq!(cover.dimensions(), (64, 48));
            assert_eq!(*cover.get_pixel(0, 0), image::Rgba([12, 91, 173, 255]));
            assert_eq!(
                fs::read(&source).unwrap(),
                tagged,
                "cover reads never rewrite tags"
            );
            let selected = root.join("selected.png");
            fs::write(&selected, png.get_ref()).unwrap();
            assert!(try_write(
                &source,
                &source,
                "New",
                "Artist",
                "Album",
                Some(selected.to_str().unwrap())
            )
            .unwrap());
            let saved = read_picture(&source, 96, 96).expect("written APIC must decode");
            assert_eq!(image::load_from_memory(&saved).unwrap().to_rgba8(), image);
            fs::remove_dir_all(root).unwrap();
        }
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
    fn audio_trim_raw_tags_keep_opaque_frames_and_audio_payload() {
        for version in [3, 4] {
            let root = directory();
            let source = root.join("source.mp3");
            let target = root.join("clip.mp3");
            let original = fixture(version);
            fs::write(&source, &original).unwrap();
            fs::write(&target, &original).unwrap();
            let before = RawTag::read(&mut original.as_slice()).unwrap();
            transfer_trim(
                &source,
                &target,
                [&None, &None, &None],
                7000,
                None,
                |text| (text.to_owned(), false),
            )
            .unwrap();
            let saved = fs::read(&target).unwrap();
            let after = RawTag::read(&mut saved.as_slice()).unwrap();
            for frame in &before.frames {
                let bytes = &before.body[frame.clone()];
                if &bytes[..4] != b"TLEN" && &bytes[..4] != b"USLT" {
                    assert!(after
                        .frames
                        .iter()
                        .any(|range| &after.body[range.clone()] == bytes));
                }
            }
            assert_eq!(
                &saved[10 + after.body.len()..],
                &original[10 + before.body.len()..]
            );
            assert_eq!(fs::read(&source).unwrap(), original);
            fs::remove_dir_all(root).unwrap();
        }
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
