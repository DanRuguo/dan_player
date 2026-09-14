use super::super::tag_reader::{
    normalize_decoded_id3_flags, preserve_legacy_language_frames, probe_tagged_audio,
};
use anyhow::{bail, ensure};
use lofty::{
    config::{ParseOptions, ParsingMode, WriteOptions},
    file::{AudioFile, FileType},
    id3::v2::{Frame, FrameId, Id3v2Tag, TextInformationFrame},
    ogg::{OggPictureStorage, VorbisComments},
    prelude::{Accessor, TagExt, TaggedFileExt},
    tag::TagType,
};
use std::{
    fs::{File, OpenOptions},
    io::{BufReader, Read, Seek, SeekFrom, Write},
    path::Path,
    time::Duration,
};

#[derive(Clone, Debug, PartialEq)]
enum NativeTag {
    Id3(Id3v2Tag),
    Ape(lofty::ape::ApeTag),
    Vorbis(VorbisComments),
    Mp4(lofty::mp4::Ilst),
    Riff(lofty::iff::wav::RiffInfoList),
    Aiff(lofty::iff::aiff::AiffTextChunks),
}
impl NativeTag {
    fn empty_after_edit(&self) -> bool {
        match self {
            Self::Id3(tag) => tag.is_empty(),
            Self::Ape(tag) => tag.is_empty(),
            Self::Mp4(tag) => tag.is_empty(),
            Self::Riff(tag) => tag.is_empty(),
            Self::Aiff(tag) => tag.is_empty(),
            // The native vendor belongs to the comment packet even when no
            // timed lyrics remain. Ogg requires that packet to exist.
            Self::Vorbis(_) => false,
        }
    }
    fn kind(&self) -> TagType {
        match self {
            Self::Id3(_) => TagType::Id3v2,
            Self::Ape(_) => TagType::Ape,
            Self::Vorbis(_) => TagType::VorbisComments,
            Self::Mp4(_) => TagType::Mp4Ilst,
            Self::Riff(_) => TagType::RiffInfo,
            Self::Aiff(_) => TagType::AiffText,
        }
    }
    fn same_metadata(&self, other: &Self) -> bool {
        match (self, other) {
            // Writing can normalize the ID3 container version and frame order;
            // every native frame, including language/descriptor/opaque payload,
            // is still compared. No conversion through generic TagItem occurs.
            (Self::Id3(tag), Self::Id3(actual)) => {
                if tag.flags() != actual.flags() {
                    return false;
                }
                let mut frames = std::collections::HashMap::new();
                for frame in tag {
                    *frames.entry(frame).or_insert(0usize) += 1;
                }
                for frame in actual {
                    match frames.get_mut(frame) {
                        Some(count) if *count > 0 => *count -= 1,
                        _ => return false,
                    }
                }
                frames.values().all(|count| *count == 0)
            }
            _ => self == other,
        }
    }
    fn write(&self, destination: &Path) -> anyhow::Result<()> {
        let options = WriteOptions::default();
        match self {
            Self::Id3(tag) => {
                let mut tag = tag.clone();
                preserve_legacy_language_frames(&mut tag);
                tag.save_to_path(destination, options)?;
            }
            Self::Ape(tag) => tag.save_to_path(destination, options)?,
            Self::Vorbis(tag) => tag.save_to_path(destination, options)?,
            Self::Mp4(tag) => tag.save_to_path(destination, options)?,
            Self::Riff(tag) => tag.save_to_path(destination, options)?,
            Self::Aiff(tag) => tag.save_to_path(destination, options)?,
        }
        Ok(())
    }
    fn edit(&mut self, title: &Option<String>, artist: &Option<String>, album: &Option<String>) {
        macro_rules! edit {
            ($tag:expr) => {{
                if let Some(value) = title {
                    $tag.set_title(value.clone());
                }
                if let Some(value) = artist {
                    $tag.set_artist(value.clone());
                }
                if let Some(value) = album {
                    $tag.set_album(value.clone());
                }
            }};
        }
        match self {
            Self::Id3(tag) => edit!(tag),
            Self::Ape(tag) => edit!(tag),
            Self::Vorbis(tag) => edit!(tag),
            Self::Mp4(tag) => edit!(tag),
            Self::Riff(tag) => edit!(tag),
            Self::Aiff(tag) => edit!(tag),
        }
    }
    fn update_duration(&mut self, duration: Duration) {
        match self {
            Self::Id3(tag) => {
                let id = FrameId::Valid(std::borrow::Cow::Borrowed("TLEN"));
                if tag.get(&id).is_some() {
                    tag.insert(Frame::Text(TextInformationFrame::new(
                        id,
                        lofty::TextEncoding::UTF8,
                        duration.as_millis().to_string(),
                    )));
                }
            }
            Self::Vorbis(tag) => {
                if tag.get("LENGTH").is_some() {
                    tag.insert("LENGTH".into(), duration.as_millis().to_string());
                }
                if tag.get("DURATION").is_some() {
                    tag.insert(
                        "DURATION".into(),
                        format!(
                            "{:02}:{:02}:{:06.3}",
                            duration.as_secs() / 3600,
                            duration.as_secs() / 60 % 60,
                            duration.as_secs_f64() % 60.0
                        ),
                    );
                }
            }
            _ => {}
        }
    }

    fn trim_lyrics(
        &mut self,
        start: i64,
        end: i64,
        warnings: &mut Vec<String>,
    ) -> anyhow::Result<()> {
        let transform = |text: &str, warnings: &mut Vec<String>| {
            let result = super::lyrics::transform(text, start, end);
            if let Some(warning) = result.warning {
                if !warnings.iter().any(|item| item == warning) {
                    warnings.push(warning.to_string());
                }
            }
            result
        };
        match self {
            Self::Id3(tag) => {
                let frames: Vec<_> = (&*tag)
                    .into_iter()
                    .filter(|frame| frame.id_str() == "USLT")
                    .cloned()
                    .collect();
                for frame in frames {
                    if let Frame::UnsynchronizedText(mut changed) = frame.clone() {
                        let result = transform(&changed.content, warnings);
                        if !result.adjusted {
                            continue;
                        }
                        changed.content = result.text;
                        tag.retain(|item| item != &frame);
                        if !changed.content.is_empty() {
                            ensure!(
                                tag.insert(Frame::UnsynchronizedText(changed)).is_none(),
                                "TRIM_TAGS_UNSUPPORTED|歌词帧存在重复标识，无法安全移植"
                            );
                        }
                    } else if !warnings.iter().any(|item| item == super::lyrics::WARNING) {
                        warnings.push(super::lyrics::WARNING.into());
                    }
                }
                if (&*tag).into_iter().any(|frame| frame.id_str() == "SYLT")
                    && !warnings.iter().any(|item| item == super::lyrics::WARNING)
                {
                    warnings.push(super::lyrics::WARNING.into());
                }
            }
            Self::Vorbis(tag) => {
                for key in ["LYRICS", "UNSYNCEDLYRICS", "SYNCEDLYRICS"] {
                    let values: Vec<_> = tag.get_all(key).map(str::to_string).collect();
                    if values.is_empty() {
                        continue;
                    }
                    let changed: Vec<_> = values
                        .iter()
                        .map(|value| transform(value, warnings))
                        .collect();
                    if changed.iter().all(|value| !value.adjusted) {
                        continue;
                    }
                    tag.remove(key).for_each(drop);
                    for value in changed {
                        if !value.adjusted || !value.text.is_empty() {
                            tag.push(key.into(), value.text);
                        }
                    }
                }
            }
            Self::Mp4(tag) => {
                use lofty::mp4::{Atom, AtomData, AtomIdent};
                let id = AtomIdent::Fourcc(*b"\xa9lyr");
                if let Some(atom) = tag.get(&id).cloned() {
                    let mut any_changed = false;
                    let mut data = Vec::new();
                    for value in atom.into_data() {
                        let updated = match &value {
                            AtomData::UTF8(text) | AtomData::UTF16(text) => {
                                let result = transform(text, warnings);
                                any_changed |= result.adjusted;
                                if result.adjusted && result.text.is_empty() {
                                    continue;
                                }
                                if matches!(value, AtomData::UTF8(_)) {
                                    AtomData::UTF8(result.text)
                                } else {
                                    AtomData::UTF16(result.text)
                                }
                            }
                            _ => {
                                if !warnings.iter().any(|item| item == super::lyrics::WARNING) {
                                    warnings.push(super::lyrics::WARNING.into());
                                }
                                value
                            }
                        };
                        data.push(updated);
                    }
                    if any_changed {
                        tag.remove(&id).for_each(drop);
                        if let Some(atom) = Atom::from_collection(id, data) {
                            tag.insert(atom);
                        }
                    }
                }
            }
            Self::Ape(tag) => {
                if tag.get("Lyrics").is_some()
                    && !warnings.iter().any(|item| item == super::lyrics::WARNING)
                {
                    warnings.push(super::lyrics::WARNING.into());
                }
            }
            _ => {}
        }
        Ok(())
    }
}

fn primary(file_type: FileType) -> NativeTag {
    match file_type {
        FileType::Mpeg | FileType::Aiff => NativeTag::Id3(Default::default()),
        FileType::Wav => NativeTag::Riff(Default::default()),
        FileType::Mp4 => NativeTag::Mp4(Default::default()),
        _ => NativeTag::Vorbis(Default::default()),
    }
}

fn read_tags(source: &Path, kind: FileType) -> anyhow::Result<Vec<NativeTag>> {
    let mut reader = BufReader::new(File::open(source)?);
    let options = ParseOptions::new()
        .read_properties(false)
        .parsing_mode(ParsingMode::Strict);
    let mut tags = Vec::new();
    macro_rules! append {
        ($tag:expr, $variant:ident) => {
            if let Some(tag) = $tag {
                tags.push(NativeTag::$variant(tag.clone()));
            }
        };
    }
    match kind {
        FileType::Mpeg => {
            let file = lofty::mpeg::MpegFile::read_from(&mut reader, options)?;
            append!(file.id3v2(), Id3);
            append!(file.ape(), Ape);
        }
        FileType::Flac => {
            let file = lofty::flac::FlacFile::read_from(&mut reader, options)?;
            ensure!(
                file.id3v2().is_none(),
                "TRIM_TAGS_UNSUPPORTED|FLAC 前置 ID3 标签无法安全移植"
            );
            if file.vorbis_comments().is_some() || !file.pictures().is_empty() {
                let mut comments = file.vorbis_comments().cloned().unwrap_or_default();
                for (picture, info) in file.pictures() {
                    ensure!(
                        comments
                            .insert_picture(picture.clone(), Some(*info))?
                            .is_none(),
                        "TRIM_TAGS_UNSUPPORTED|重复图标封面无法完整移植"
                    );
                }
                tags.push(NativeTag::Vorbis(comments));
            }
        }
        FileType::Vorbis => {
            let file = lofty::ogg::VorbisFile::read_from(&mut reader, options)?;
            tags.push(NativeTag::Vorbis(file.vorbis_comments().clone()));
        }
        FileType::Opus => {
            let file = lofty::ogg::OpusFile::read_from(&mut reader, options)?;
            tags.push(NativeTag::Vorbis(file.vorbis_comments().clone()));
        }
        FileType::Mp4 => {
            let file = lofty::mp4::Mp4File::read_from(&mut reader, options)?;
            append!(file.ilst(), Mp4);
        }
        FileType::Wav => {
            let file = lofty::iff::wav::WavFile::read_from(&mut reader, options)?;
            append!(file.riff_info(), Riff);
            append!(file.id3v2(), Id3);
        }
        FileType::Aiff => {
            let file = lofty::iff::aiff::AiffFile::read_from(&mut reader, options)?;
            append!(file.text_chunks(), Aiff);
            append!(file.id3v2(), Id3);
        }
        _ => bail!("TRIM_FORMAT_UNSUPPORTED|不支持此容器的标签移植"),
    }
    for tag in &mut tags {
        if let NativeTag::Id3(tag) = tag {
            normalize_decoded_id3_flags(tag)?;
        }
    }
    Ok(tags)
}

fn id3v1_bytes(path: &Path) -> anyhow::Result<Option<[u8; 128]>> {
    let mut file = File::open(path)?;
    if file.metadata()?.len() < 128 {
        return Ok(None);
    }
    file.seek(SeekFrom::End(-128))?;
    let mut bytes = [0; 128];
    file.read_exact(&mut bytes)?;
    Ok((&bytes[..3] == b"TAG").then_some(bytes))
}

pub(super) fn transfer(
    source: &Path,
    destination: &Path,
    kind: FileType,
    preserve: bool,
    title: Option<String>,
    artist: Option<String>,
    album: Option<String>,
    duration: Duration,
    lyric_start: i64,
    lyric_end: i64,
) -> anyhow::Result<Vec<String>> {
    if preserve {
        check_extra_metadata(source, kind)?;
    }
    if preserve
        && kind == FileType::Mpeg
        && (super::super::tag_reader::id3_compat::trim_probe(source).is_some()
            || read_tags(source, kind).is_err())
    {
        return super::super::tag_reader::id3_compat::transfer_trim(
            source,
            destination,
            [&title, &artist, &album],
            duration.as_millis(),
            id3v1_bytes(source)?,
            |text| {
                let result = super::lyrics::transform(text, lyric_start, lyric_end);
                (result.text, result.warning.is_some())
            },
        );
    }
    let mut tags = if preserve {
        read_tags(source, kind)?
    } else {
        Vec::new()
    };
    let legacy = if preserve && kind == FileType::Mpeg {
        id3v1_bytes(source)?
    } else {
        None
    };
    if title.is_some() || artist.is_some() || album.is_some() {
        let preferred = primary(kind);
        let tag = if let Some(index) = tags.iter().position(|tag| tag.kind() == preferred.kind()) {
            &mut tags[index]
        } else {
            tags.push(preferred);
            tags.last_mut().unwrap()
        };
        tag.edit(&title, &artist, &album);
    }
    let mut lyric_warnings = Vec::new();
    for tag in &mut tags {
        tag.update_duration(duration);
        tag.trim_lyrics(lyric_start, lyric_end, &mut lyric_warnings)?;
    }
    tags.retain(|tag| !tag.empty_after_edit());
    // FFmpeg may add an encoder tag even with -map_metadata -1. Clear target
    // tags before installing the explicit source set, including every picture.
    let output = probe_tagged_audio(destination, "TRIM_VERIFY_FAILED")?;
    for tag in output.tags() {
        tag.tag_type().remove_from_path(destination)?;
    }
    for tag in &tags {
        tag.write(destination)?;
    }
    if preserve && kind == FileType::Flac {
        copy_flac_applications(source, destination)?;
    }
    if let Some(bytes) = legacy {
        OpenOptions::new()
            .append(true)
            .open(destination)?
            .write_all(&bytes)?;
    }
    let actual = read_tags(destination, kind)?;
    // Ogg always has a comment packet; an intentionally empty output still has
    // the encoder's mandatory vendor string, which is not a user tag.
    let empty_ogg = tags.is_empty() && matches!(kind, FileType::Vorbis | FileType::Opus);
    if empty_ogg {
        ensure!(actual.iter().all(|tag| matches!(tag, NativeTag::Vorbis(comments) if comments.items().len()==0 && comments.pictures().is_empty())), "TRIM_TAGS_UNSUPPORTED|无法清理裁剪输出标签");
    }
    ensure!(empty_ogg || (tags.len() == actual.len() && tags.iter().all(|expected| actual.iter().any(|actual| expected.same_metadata(actual)))), "TRIM_TAGS_UNSUPPORTED|无法完整保留全部原生标签或封面；原歌曲未改动，可关闭保留元数据并另存副本");
    if kind == FileType::Mpeg {
        ensure!(
            legacy == id3v1_bytes(destination)?,
            "TRIM_TAGS_UNSUPPORTED|旧 ID3v1 标签校验失败"
        );
    }
    Ok(lyric_warnings)
}

// Reject metadata outside the native parsers' scope. Technical stream headers,
// padding and old seek tables describe the old audio and must be regenerated.
pub(super) fn check_extra_metadata(path: &Path, kind: FileType) -> anyhow::Result<()> {
    let mut file = File::open(path)?;
    let length = file.metadata()?.len();
    if kind == FileType::Flac {
        let mut header = [0; 4];
        file.read_exact(&mut header)?;
        ensure!(
            &header == b"fLaC",
            "TRIM_TAGS_UNSUPPORTED|无法完整保留混合 FLAC 标签"
        );
        loop {
            file.read_exact(&mut header)?;
            let block = header[0] & 0x7f;
            ensure!(
                matches!(block, 0 | 1 | 2 | 3 | 4 | 6),
                "TRIM_TAGS_UNSUPPORTED|FLAC 含应用或提示表元数据，暂不能安全移植"
            );
            let size = u32::from_be_bytes([0, header[1], header[2], header[3]]) as u64;
            ensure!(
                file.stream_position()?
                    .checked_add(size)
                    .is_some_and(|end| end <= length),
                "TRIM_TAGS_UNSUPPORTED|FLAC 元数据块越界"
            );
            file.seek(SeekFrom::Current(size as i64))?;
            if header[0] & 0x80 != 0 {
                break;
            }
        }
    } else if matches!(kind, FileType::Wav | FileType::Aiff) {
        file.seek(SeekFrom::Start(12))?;
        while file.stream_position()? + 8 <= length {
            let mut header = [0; 8];
            file.read_exact(&mut header)?;
            let id = &header[..4];
            let bytes = header[4..8].try_into().unwrap();
            let size = if kind == FileType::Wav {
                u32::from_le_bytes(bytes)
            } else {
                u32::from_be_bytes(bytes)
            } as u64;
            let end = file
                .stream_position()?
                .checked_add(size)
                .filter(|end| *end <= length)
                .ok_or_else(|| anyhow::anyhow!("TRIM_TAGS_UNSUPPORTED|音频块越界"))?;
            let known = if kind == FileType::Wav {
                matches!(
                    id,
                    b"fmt " | b"data" | b"fact" | b"JUNK" | b"PAD " | b"id3 " | b"ID3 "
                )
            } else {
                matches!(
                    id,
                    b"COMM"
                        | b"SSND"
                        | b"FVER"
                        | b"NAME"
                        | b"AUTH"
                        | b"(c) "
                        | b"ANNO"
                        | b"COMT"
                        | b"ID3 "
                        | b"id3 "
                )
            };
            if kind == FileType::Wav && id == b"LIST" {
                let mut list = [0; 4];
                ensure!(size >= 4, "TRIM_TAGS_UNSUPPORTED|LIST 块不完整");
                file.read_exact(&mut list)?;
                ensure!(
                    &list == b"INFO",
                    "TRIM_TAGS_UNSUPPORTED|WAV 含额外列表元数据"
                );
            } else {
                ensure!(
                    known,
                    "TRIM_TAGS_UNSUPPORTED|音频含不能完整移植的扩展元数据块"
                );
            }
            file.seek(SeekFrom::Start(end + (size & 1)))?;
        }
    } else if kind == FileType::Mp4 {
        check_mp4(&mut file, 0, length, 0, 0, false)?;
    } else if matches!(kind, FileType::Vorbis | FileType::Opus) {
        let mut streams = 0;
        while file.stream_position()? < length {
            let mut header = [0; 27];
            file.read_exact(&mut header)?;
            ensure!(
                &header[..4] == b"OggS" && header[4] == 0,
                "TRIM_TAGS_UNSUPPORTED|Ogg 页头不完整"
            );
            if header[5] & 2 != 0 {
                streams += 1;
            }
            ensure!(
                streams <= 1,
                "TRIM_TAGS_UNSUPPORTED|多逻辑流或串联 Ogg 的全部元数据暂不能完整移植"
            );
            let mut segments = vec![0u8; header[26] as usize];
            file.read_exact(&mut segments)?;
            let size: u64 = segments.iter().map(|length| *length as u64).sum();
            ensure!(
                file.stream_position()?
                    .checked_add(size)
                    .is_some_and(|end| end <= length),
                "TRIM_TAGS_UNSUPPORTED|Ogg 数据页越界"
            );
            file.seek(SeekFrom::Current(size as i64))?;
        }
    } else if kind == FileType::Mpeg {
        let read = length.min(65536);
        file.seek(SeekFrom::Start(length - read))?;
        let mut tail = vec![0; read as usize];
        file.read_exact(&mut tail)?;
        ensure!(
            !tail.windows(9).any(|part| part == b"LYRICSEND"),
            "TRIM_TAGS_UNSUPPORTED|旧 Lyrics3 歌词标签暂不能完整移植"
        );
    }
    Ok(())
}

// Application blocks can contain publisher notices or opaque application data.
// Retain them byte-for-byte; never copy old stream/seek headers into a clip.
fn flac_applications(path: &Path) -> anyhow::Result<(Vec<Vec<u8>>, u64, u64)> {
    let mut file = File::open(path)?;
    let mut header = [0u8; 4];
    file.read_exact(&mut header)?;
    ensure!(&header == b"fLaC", "TRIM_TAGS_UNSUPPORTED|FLAC 标识无效");
    let mut blocks = Vec::new();
    let mut total = 0usize;
    loop {
        let header_offset = file.stream_position()?;
        file.read_exact(&mut header)?;
        let size = u32::from_be_bytes([0, header[1], header[2], header[3]]) as usize;
        ensure!(
            file.stream_position()? + size as u64 <= file.metadata()?.len(),
            "TRIM_TAGS_UNSUPPORTED|FLAC 元数据块越界"
        );
        if header[0] & 127 == 2 {
            total += size;
            ensure!(
                size >= 4 && total <= 64 * 1024 * 1024,
                "TRIM_TAGS_UNSUPPORTED|FLAC 应用数据超限"
            );
            let mut bytes = vec![0; size];
            file.read_exact(&mut bytes)?;
            blocks.push(bytes);
        } else {
            file.seek(SeekFrom::Current(size as i64))?;
        }
        if header[0] & 128 != 0 {
            return Ok((blocks, file.stream_position()?, header_offset));
        }
    }
}

fn copy_flac_applications(source: &Path, destination: &Path) -> anyhow::Result<()> {
    let (blocks, _, _) = flac_applications(source)?;
    if blocks.is_empty() {
        return Ok(());
    }
    let (existing, audio_start, last_header) = flac_applications(destination)?;
    ensure!(
        existing.is_empty(),
        "TRIM_TAGS_UNSUPPORTED|裁剪输出包含意外应用数据"
    );
    let staged = destination.with_extension("flac-app-stage");
    let mut output = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&staged)?;
    let result = (|| -> anyhow::Result<()> {
        let mut input = File::open(destination)?;
        std::io::copy(&mut (&mut input).take(audio_start), &mut output)?;
        output.seek(SeekFrom::Start(last_header))?;
        input.seek(SeekFrom::Start(last_header))?;
        let mut flag = [0u8];
        input.read_exact(&mut flag)?;
        output.write_all(&[flag[0] & 127])?;
        output.seek(SeekFrom::Start(audio_start))?;
        for (index, block) in blocks.iter().enumerate() {
            let size = (block.len() as u32).to_be_bytes();
            output.write_all(&[
                2 | if index + 1 == blocks.len() { 128 } else { 0 },
                size[1],
                size[2],
                size[3],
            ])?;
            output.write_all(block)?;
        }
        input.seek(SeekFrom::Start(audio_start))?;
        std::io::copy(&mut input, &mut output)?;
        output.sync_all()?;
        ensure!(
            flac_applications(&staged)?.0 == blocks,
            "TRIM_VERIFY_FAILED|FLAC 应用数据回读不一致"
        );
        Ok(())
    })();
    drop(output);
    if let Err(error) = result {
        let _ = std::fs::remove_file(&staged);
        return Err(error);
    }
    if let Err(error) = std::fs::rename(&staged, destination) {
        let _ = std::fs::remove_file(&staged);
        return Err(error.into());
    }
    Ok(())
}

#[cfg(test)]
mod application_tests {
    use super::*;
    #[test]
    fn audio_trim_keeps_application_bytes_and_new_audio_only() {
        let root = std::env::temp_dir().join(format!(
            "dan-flac-app-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir(&root).unwrap();
        let source = root.join("source.flac");
        let output = root.join("output.flac");
        let original = b"fLaC\x00\x00\x00\x01S\x82\x00\x00\x08TESTnoteOLD_AUDIO";
        std::fs::write(&source, original).unwrap();
        std::fs::write(&output, b"fLaC\x80\x00\x00\x01NNEW_AUDIO").unwrap();
        copy_flac_applications(&source, &output).unwrap();
        let (apps, offset, _) = flac_applications(&output).unwrap();
        assert_eq!(apps, vec![b"TESTnote".to_vec()]);
        assert_eq!(
            &std::fs::read(&output).unwrap()[offset as usize..],
            b"NEW_AUDIO"
        );
        assert_eq!(std::fs::read(&source).unwrap(), original);
        std::fs::remove_dir_all(root).unwrap();
    }
}

fn check_mp4(
    file: &mut File,
    start: u64,
    end: u64,
    level: u8,
    depth: u8,
    in_track: bool,
) -> anyhow::Result<()> {
    ensure!(depth < 12, "TRIM_TAGS_UNSUPPORTED|MP4 元数据层级异常");
    let mut position = start;
    while position + 8 <= end {
        file.seek(SeekFrom::Start(position))?;
        let mut header = [0; 8];
        file.read_exact(&mut header)?;
        let mut size = u32::from_be_bytes(header[..4].try_into().unwrap()) as u64;
        let mut head = 8;
        if size == 1 {
            let mut wide = [0; 8];
            file.read_exact(&mut wide)?;
            size = u64::from_be_bytes(wide);
            head = 16;
        }
        if size == 0 {
            size = end - position;
        }
        ensure!(
            size >= head && position.checked_add(size).is_some_and(|next| next <= end),
            "TRIM_TAGS_UNSUPPORTED|MP4 元数据块越界"
        );
        let id = &header[4..];
        // Windows can leave a header-only Xtra atom containing no user data.
        if level == 2 && id == b"Xtra" && size == head {
            position += size;
            continue;
        }
        if level == 2 {
            ensure!(
                matches!(id, b"meta" | b"free" | b"skip"),
                "TRIM_TAGS_UNSUPPORTED|MP4 含额外用户元数据或章节"
            );
        }
        if level == 3 {
            ensure!(
                matches!(id, b"hdlr" | b"ilst" | b"free" | b"skip"),
                "TRIM_TAGS_UNSUPPORTED|MP4 含非 ilst 元数据"
            );
        }
        if matches!(
            id,
            b"moov" | b"trak" | b"mdia" | b"minf" | b"stbl" | b"edts" | b"udta"
        ) {
            check_mp4(
                file,
                position + head,
                position + size,
                if id == b"udta" { 2 } else { 1 },
                depth + 1,
                in_track || id == b"trak",
            )?;
        } else if id == b"meta" {
            ensure!(
                !in_track,
                "TRIM_TAGS_UNSUPPORTED|MP4 轨道独立元数据暂不能完整移植"
            );
            ensure!(size >= head + 4, "TRIM_TAGS_UNSUPPORTED|MP4 meta 不完整");
            check_mp4(
                file,
                position + head + 4,
                position + size,
                3,
                depth + 1,
                in_track,
            )?;
        } else if level == 2 {
            ensure!(
                matches!(id, b"free" | b"skip"),
                "TRIM_TAGS_UNSUPPORTED|MP4 含额外用户元数据或章节"
            );
        } else if level == 3 {
            ensure!(
                matches!(id, b"hdlr" | b"ilst" | b"free" | b"skip"),
                "TRIM_TAGS_UNSUPPORTED|MP4 含非 ilst 元数据，暂不能完整移植"
            );
        } else {
            ensure!(
                !matches!(id, b"uuid" | b"ID32"),
                "TRIM_TAGS_UNSUPPORTED|MP4 含私有扩展元数据"
            );
        }
        position += size;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn verification_compares_picture_bytes_not_only_size_or_description() {
        fn variants(byte: u8) -> Vec<NativeTag> {
            let picture = lofty::picture::Picture::new_unchecked(
                lofty::picture::PictureType::CoverFront,
                Some(lofty::picture::MimeType::Png),
                Some("same description".into()),
                vec![byte; 16],
            );
            let mut id3 = Id3v2Tag::default();
            id3.insert_picture(picture.clone());
            let mut vorbis = VorbisComments::default();
            vorbis
                .insert_picture(picture.clone(), Some(Default::default()))
                .unwrap();
            let mut mp4 = lofty::mp4::Ilst::default();
            mp4.insert_picture(picture);
            vec![
                NativeTag::Id3(id3),
                NativeTag::Vorbis(vorbis),
                NativeTag::Mp4(mp4),
            ]
        }
        for (expected, different) in variants(1).iter().zip(variants(2)) {
            assert!(expected.same_metadata(expected));
            assert!(!expected.same_metadata(&different));
        }
    }
}
