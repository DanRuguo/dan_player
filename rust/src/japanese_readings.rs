//! Lazy optional IPADIC reader. No dictionary bytes are linked into the DLL.
use std::{borrow::Cow, fs::File, io::Read, path::Path, sync::{Arc, OnceLock}};
use flate2::read::GzDecoder;
use lindera::{mode::Mode, segmenter::Segmenter};
use lindera_dictionary::dictionary::{
    character_definition::CharacterDefinition, connection_cost_matrix::ConnectionCostMatrix,
    metadata::Metadata, prefix_dictionary::PrefixDictionary, unknown_dictionary::UnknownDictionary,
    Dictionary,
};
use sha2::{Digest, Sha256};
use crate::japanese_reading_lexicon::{enrich, hiragana, is_han};

const MAX_PACK: usize = 32 * 1024 * 1024;
const MAX_GZIP: usize = 8 * 1024 * 1024;
const HASH_V3: &str = "bc2e100b3d11e41038dd3fbaacfbd843c081a3d18c6105320220b36a667b7ee9";
const HASH_V2_LEGACY: &str = "a8acd8b6352774fe3f6ac3fdbec59313ce04b548dad84340c17f0ee4bfab6e43";
static SEGMENTER: OnceLock<Segmenter> = OnceLock::new();

fn merge_u16_planes(planes: &[u8], count: usize) -> Result<Vec<u16>, String> {
    if planes.len() != count.checked_mul(2).ok_or("Plane overflow")? {
        return Err("Invalid u16 plane slice".into());
    }
    let (p0, p1) = planes.split_at(count);
    let mut out = Vec::with_capacity(count);
    for i in 0..count {
        out.push(u16::from_le_bytes([p0[i], p1[i]]));
    }
    Ok(out)
}

fn merge_u32_planes(planes: &[u8], count: usize) -> Result<Vec<u32>, String> {
    if planes.len() != count.checked_mul(4).ok_or("Plane overflow")? {
        return Err("Invalid u32 plane slice".into());
    }
    let p0 = &planes[0..count];
    let p1 = &planes[count..count * 2];
    let p2 = &planes[count * 2..count * 3];
    let p3 = &planes[count * 3..count * 4];
    let mut out = Vec::with_capacity(count);
    for i in 0..count {
        out.push(u32::from_le_bytes([p0[i], p1[i], p2[i], p3[i]]));
    }
    Ok(out)
}

fn decode_vals_v3(packed: &[u8]) -> Result<Vec<u8>, String> {
    let header = packed.get(0..4).ok_or("Missing vals count")?;
    let count = u32::from_le_bytes(header.try_into().unwrap()) as usize;
    let expected = 4usize
        .checked_add(count.checked_mul(10).ok_or("Vals size overflow")?)
        .ok_or("Vals size overflow")?;
    if packed.len() != expected {
        return Err("Invalid vals payload size".into());
    }
    let mut pos = 4usize;
    let dwids = merge_u32_planes(&packed[pos..pos + count * 4], count)?;
    pos += count * 4;
    let dlids = merge_u16_planes(&packed[pos..pos + count * 2], count)?;
    pos += count * 2;
    let drids = merge_u16_planes(&packed[pos..pos + count * 2], count)?;
    pos += count * 2;
    let dcosts = merge_u16_planes(&packed[pos..pos + count * 2], count)?;

    let mut out = Vec::with_capacity(count * 10);
    let mut cw = 0u32;
    let mut cl = 0u16;
    let mut cc = 0u16;
    for i in 0..count {
        cw = cw.wrapping_add(dwids[i]);
        cl = cl.wrapping_add(dlids[i]);
        let cr = cl.wrapping_add(drids[i]);
        cc = cc.wrapping_add(dcosts[i]);
        out.extend_from_slice(&cw.to_le_bytes());
        out.extend_from_slice(&cl.to_le_bytes());
        out.extend_from_slice(&cr.to_le_bytes());
        out.extend_from_slice(&(cc as i16).to_le_bytes());
    }
    Ok(out)
}

fn decode_valsidx_v3(packed: &[u8]) -> Result<Vec<u8>, String> {
    let header = packed.get(0..4).ok_or("Missing valsidx count")?;
    let count = u32::from_le_bytes(header.try_into().unwrap()) as usize;
    let expected = 4usize
        .checked_add(count.checked_mul(8).ok_or("Valsidx overflow")?)
        .ok_or("Valsidx overflow")?;
    if packed.len() != expected {
        return Err("Invalid valsidx payload size".into());
    }
    let da0 = merge_u32_planes(&packed[4..4 + count * 4], count)?;
    let da1 = merge_u32_planes(&packed[4 + count * 4..expected], count)?;
    let mut out = Vec::with_capacity(count * 8);
    let mut c0 = 0u32;
    let mut c1 = 0u32;
    for i in 0..count {
        c0 = c0.wrapping_add(da0[i]);
        c1 = c1.wrapping_add(da1[i]);
        out.extend_from_slice(&c0.to_le_bytes());
        out.extend_from_slice(&c1.to_le_bytes());
    }
    Ok(out)
}

fn decode_words_v3(packed: &[u8]) -> Result<(Vec<u8>, Vec<u8>), String> {
    if packed.len() < 12 {
        return Err("Missing words header".into());
    }
    let n_yomis = u32::from_le_bytes(packed[0..4].try_into().unwrap()) as usize;
    let n_words = u32::from_le_bytes(packed[4..8].try_into().unwrap()) as usize;
    let stream_len = u32::from_le_bytes(packed[8..12].try_into().unwrap()) as usize;
    let lens_end = 12usize.checked_add(n_yomis).ok_or("Words header overflow")?;
    let stream_end = lens_end.checked_add(stream_len).ok_or("Words stream overflow")?;
    let dyids_bytes = n_words.checked_mul(4).ok_or("Words index overflow")?;
    if packed.len() != stream_end.checked_add(dyids_bytes).ok_or("Words total overflow")? {
        return Err("Invalid words payload size".into());
    }

    let ylens = &packed[12..lens_end];
    let ystream = &packed[lens_end..stream_end];
    let dyids = merge_u32_planes(&packed[stream_end..], n_words)?;

    const PREFIX: &[u8] = b"*\0*\0*\0*\0*\0*\0*\0";
    const SUFFIX: &[u8] = b"\0*";

    let mut words = Vec::with_capacity(n_yomis * 32);
    let mut yid_to_off = Vec::with_capacity(n_yomis);
    let mut spos = 0usize;
    let mut yutf8 = Vec::with_capacity(64);
    for &ln_u8 in ylens {
        let ln = ln_u8 as usize;
        let end = spos.checked_add(ln).ok_or("Yomi stream overflow")?;
        if end > ystream.len() {
            return Err("Truncated yomi stream".into());
        }
        yid_to_off.push(words.len() as u32);
        yutf8.clear();
        while spos < end {
            let b = ystream[spos];
            spos += 1;
            if (0x80..=0xDB).contains(&b) {
                let ch = char::from_u32(0x30A1 + u32::from(b - 0x80))
                    .ok_or("Invalid katakana code")?;
                let mut buf = [0u8; 4];
                yutf8.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
            } else if b == 0xFF {
                if spos >= end {
                    return Err("Truncated escaped yomi byte".into());
                }
                let ulen = ystream[spos] as usize;
                spos += 1;
                if spos + ulen > end {
                    return Err("Invalid escaped yomi length".into());
                }
                yutf8.extend_from_slice(&ystream[spos..spos + ulen]);
                spos += ulen;
            } else if b != 0 && b < 0x80 {
                yutf8.push(b);
            } else {
                return Err("Unexpected yomi code".into());
            }
        }
        std::str::from_utf8(&yutf8).map_err(|_| "Malformed UTF-8 yomi")?;
        let rec_len = (PREFIX.len() + yutf8.len() + SUFFIX.len()) as u32;
        words.extend_from_slice(&rec_len.to_le_bytes());
        words.extend_from_slice(PREFIX);
        words.extend_from_slice(&yutf8);
        words.extend_from_slice(SUFFIX);
    }
    if spos != ystream.len() {
        return Err("Unconsumed yomi bytes".into());
    }

    let mut wordsidx = Vec::with_capacity(n_words * 4);
    let mut cyid = 0u32;
    for d in dyids {
        cyid = cyid.wrapping_add(d);
        let off = *yid_to_off
            .get(cyid as usize)
            .ok_or("Out-of-bounds yomi index")?;
        wordsidx.extend_from_slice(&off.to_le_bytes());
    }
    Ok((words, wordsidx))
}

fn decode_matrix_v3(packed: &[u8]) -> Result<Vec<u8>, String> {
    if packed.len() < 6 {
        return Err("Missing matrix header".into());
    }
    let magic = u16::from_le_bytes(packed[0..2].try_into().unwrap());
    let rows = u16::from_le_bytes(packed[2..4].try_into().unwrap()) as usize;
    let cols = u16::from_le_bytes(packed[4..6].try_into().unwrap()) as usize;
    let count = rows.checked_mul(cols).ok_or("Matrix count overflow")?;
    let expected = 6usize
        .checked_add(count.checked_mul(2).ok_or("Matrix byte overflow")?)
        .ok_or("Matrix byte overflow")?;
    if magic != 0xFFFF || cols == 0 || packed.len() != expected {
        return Err("Invalid matrix payload".into());
    }
    let d2 = merge_u16_planes(&packed[6..], count)?;
    let mut grid = vec![0i16; count];
    let mut out = Vec::with_capacity(expected);
    out.extend_from_slice(&packed[0..6]);
    for i in 0..count {
        let r = i / cols;
        let c = i % cols;
        let pred: i32 = if r == 0 && c == 0 {
            0
        } else if r == 0 {
            i32::from(grid[i - 1])
        } else if c == 0 {
            i32::from(grid[i - cols])
        } else {
            i32::from(grid[i - 1]) + i32::from(grid[i - cols]) - i32::from(grid[i - cols - 1])
        };
        let val = ((pred as u32).wrapping_add(u32::from(d2[i])) & 0xFFFF) as u16 as i16;
        grid[i] = val;
        out.extend_from_slice(&val.to_le_bytes());
    }
    Ok(out)
}

fn load(path: &Path) -> Result<Segmenter, String> {
    let mut gzip = Vec::new();
    File::open(path).map_err(|e| e.to_string())?.take((MAX_GZIP + 1) as u64)
        .read_to_end(&mut gzip).map_err(|e| e.to_string())?;
    if gzip.len() > MAX_GZIP {
        return Err("Invalid Japanese dictionary checksum".into());
    }
    let digest = format!("{:x}", Sha256::digest(&gzip));
    let is_v3 = if digest == HASH_V3 {
        true
    } else if digest == HASH_V2_LEGACY {
        false
    } else {
        return Err("Invalid Japanese dictionary checksum".into());
    };
    let mut pack = Vec::new();
    GzDecoder::new(gzip.as_slice()).take((MAX_PACK + 1) as u64).read_to_end(&mut pack)
        .map_err(|error| error.to_string())?;
    let expected_magic: &[u8] = if is_v3 { b"DANIPAD3" } else { b"DANIPAD2" };
    if pack.len() > MAX_PACK || !pack.starts_with(expected_magic) {
        return Err("Invalid Japanese dictionary format".into());
    }
    let mut offset = 8usize;
    let mut part_slice = || -> Result<&[u8], String> {
        let header = pack.get(offset..offset + 4).ok_or("Missing dictionary part")?;
        let size = u32::from_le_bytes(header.try_into().unwrap()) as usize;
        offset += 4;
        let end = offset.checked_add(size).ok_or("Invalid dictionary length")?;
        let data = pack.get(offset..end).ok_or("Incomplete dictionary part")?;
        offset = end;
        Ok(data)
    };
    let metadata = Metadata::load(part_slice()?).map_err(|error| error.to_string())?;
    metadata.validate_format_version().map_err(|error| error.to_string())?;
    let character_definition = CharacterDefinition::load(part_slice()?).map_err(|error| error.to_string())?;
    let trie = part_slice()?.to_vec();
    let (vals, valsidx, words, wordsidx, matrix_bytes) = if is_v3 {
        let vals = decode_vals_v3(part_slice()?)?;
        let valsidx = decode_valsidx_v3(part_slice()?)?;
        let (words, wordsidx) = decode_words_v3(part_slice()?)?;
        let mtx = decode_matrix_v3(part_slice()?)?;
        (vals, valsidx, words, wordsidx, mtx)
    } else {
        let vals = part_slice()?.to_vec();
        let valsidx = part_slice()?.to_vec();
        let words = part_slice()?.to_vec();
        let wordsidx = part_slice()?.to_vec();
        let mtx = part_slice()?.to_vec();
        (vals, valsidx, words, wordsidx, mtx)
    };
    let matrix = ConnectionCostMatrix::load(matrix_bytes).map_err(|error| error.to_string())?;
    let unknown = UnknownDictionary::load(part_slice()?).map_err(|error| error.to_string())?;
    if offset != pack.len() { return Err("Unexpected dictionary tail".into()); }
    let prefix = PrefixDictionary::load(trie, valsidx, vals, wordsidx, words)
        .map_err(|error| error.to_string())?;
    let dictionary = Dictionary {
        prefix_dictionary: Arc::new(prefix), connection_cost_matrix: Arc::new(matrix),
        character_definition: Arc::new(character_definition), unknown_dictionary: Arc::new(unknown),
        metadata: Arc::new(metadata),
    };
    Ok(Segmenter::new(Mode::Normal, dictionary, None).keep_whitespace(true))
}

fn has_han(text: &str) -> bool {
    text.chars().any(is_han)
}

pub(crate) fn words(path: &Path, input: &str) -> Result<Vec<(String, String)>, String> {
    if input.is_empty() || input.len() > 400 || input.encode_utf16().count() > 100 {
        return Err("Invalid Japanese input bound".into());
    }
    if SEGMENTER.get().is_none() {
        // Missing/invalid components are retryable after an explicit install.
        let segmenter = load(path)?;
        let _ = SEGMENTER.set(segmenter);
    }
    let segmenter = SEGMENTER.get().ok_or("Japanese dictionary unavailable")?;
    let tokens = segmenter.segment(Cow::Borrowed(input)).map_err(|error| error.to_string())?;
    let mut offset = 0;
    let mut units = 0;
    let mut result = Vec::new();
    for mut token in tokens {
        if token.byte_start != offset || input.get(offset..token.byte_end) != Some(token.surface.as_ref()) {
            return Err("Incomplete Japanese word alignment".into());
        }
        offset = token.byte_end;
        let surface = token.surface.to_string();
        let yomi = if has_han(&surface) { token.get_detail(7) } else { None };
        let reading: String = if let Some(yomi) = yomi.filter(|v| !v.is_empty() && *v != "*" && *v != "UNK") {
            hiragana(yomi)
        } else { surface.clone() };
        units += reading.encode_utf16().count();
        if units > 2000 { return Err("Oversized Japanese result".into()); }
        result.push((surface, reading));
    }
    if offset != input.len() || result.is_empty() { return Err("Incomplete Japanese result".into()); }
    result = enrich(path, input, result);
    if result.iter().map(|(_, reading)| reading.encode_utf16().count()).sum::<usize>() > 2000 {
        return Err("Oversized Japanese result".into());
    }
    Ok(result)
}

/// Caller owns bounded UTF-8 buffers. Output is little-endian count followed by
/// length/text and length/reading pairs, preserving every original token.
#[no_mangle]
pub unsafe extern "C" fn dan_japanese_reading_words(
    path: *const u8, path_len: usize, input: *const u8, input_len: usize,
    output: *mut u8, output_cap: usize,
) -> i32 {
    if input.is_null() || output.is_null() || input_len == 0 || input_len > 400 || output_cap > 16384 { return -1; }
    if path.is_null() || path_len == 0 || path_len > 32768 { return -4; }
    std::panic::catch_unwind(|| {
        let path = match std::str::from_utf8(std::slice::from_raw_parts(path, path_len)) { Ok(v) => Path::new(v), Err(_) => return -4 };
        let input = match std::str::from_utf8(std::slice::from_raw_parts(input, input_len)) { Ok(v) => v, Err(_) => return -1 };
        let words = match words(path, input) { Ok(v) => v, Err(_) => return -4 };
        let mut result = Vec::new();
        result.extend_from_slice(&(words.len() as u32).to_le_bytes());
        for (text, reading) in words {
            for part in [text, reading] {
                result.extend_from_slice(&(part.len() as u32).to_le_bytes());
                result.extend_from_slice(part.as_bytes());
            }
        }
        if result.len() > output_cap { return -3; }
        std::ptr::copy_nonoverlapping(result.as_ptr(), output, result.len());
        result.len() as i32
    }).unwrap_or(-2)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn dictionary() -> std::path::PathBuf {
        Path::new(file!()).canonicalize().unwrap().parent().unwrap().parent().unwrap()
            .join("assets/ipadic-reading.bin.gz")
    }
    fn reading(input: &str) -> String { words(&dictionary(), input).unwrap().into_iter().map(|v| v.1).collect() }
    #[test]
    fn actual_dictionary_reads_compounds_and_inflections() {
        for (input, expected) in [
            ("今日はいい天気です。", "きょうはいいてんきです。"),
            ("明日また会えるかな", "あしたまたあえるかな"),
            ("大人が一昨日東京へ行った。", "おとながおとといとうきょうへいった。"),
            ("生きる希望と歌詞を読む", "いきるきぼうとかしをよむ"),
        ] { assert_eq!(reading(input), expected); }
        let tokens = words(&dictionary(), "明日また会えるかな").unwrap();
        assert_eq!(tokens.iter().map(|v| v.0.as_str()).collect::<String>(), "明日また会えるかな");
        assert!(tokens.iter().any(|v| v.0 == "会" && v.1 == "あ"));
    }
    #[test]
    fn mixed_unknowns_and_whitespace_are_preserved() {
        let input = "\t日本語 ＡＢＣ ① 👩‍👩‍👧‍👦 𱍐 尾\n";
        assert_eq!(reading(input), "\tにほんご ＡＢＣ ① 👩‍👩‍👧‍👦 𱍐 お\n");
        assert_eq!(reading("カタカナと日本語、ひらがな"), "カタカナとにほんご、ひらがな");
    }
    #[test]
    fn full_pipeline_recovers_unknown_words_and_preserves_known_context_yomi() {
        for (input, expected) in [
            ("もう大丈夫涙は勇気に変えたよ", "もうだいじょうぶなみだはゆうきにかえたよ"),
            ("奔る光の螺旋", "はしるひかりのらせん"),
            ("奔って奔らない奔れば奔ろう", "はしってはしらないはしればはしろう"),
            ("乞うた乞うて", "こうたこうて"),
            ("吹き上がる音と言葉の即興劇", "ふきあがるおととことばのそっきょうげき"),
            ("標本の蝶々", "ひょうほんのちょうちょう"),
            ("出会い別れ 繰り返す", "であいわかれ くりかえす"),
        ] {
            let result = words(&dictionary(), input).unwrap();
            assert_eq!(result.iter().map(|v| v.0.as_str()).collect::<String>(), input);
            assert_eq!(result.iter().map(|v| v.1.as_str()).collect::<String>(), expected);
        }
        assert_eq!(reading("明日"), "あした");
        assert_eq!(reading("今日"), "きょう");
        assert!(words(&dictionary(), "勇気と言葉").unwrap().iter().any(|v| v.0 == "気" && v.1 == "き"));
        assert!(words(&dictionary(), "蝶々").unwrap().iter().any(|v| v.0 == "々" && v.1 == "ちょう"));
    }
    #[test]
    fn ffi_rejects_invalid_input_missing_dictionary_and_small_output() {
        let path = dictionary().to_string_lossy().into_owned();
        let mut output = [0xabu8; 80];
        unsafe {
            assert_eq!(dan_japanese_reading_words(path.as_ptr(), path.len(), std::ptr::null(), 1, output.as_mut_ptr(), output.len()), -1);
            assert_eq!(dan_japanese_reading_words(std::ptr::null(), 0, b"a".as_ptr(), 1, output.as_mut_ptr(), output.len()), -4);
            assert_eq!(dan_japanese_reading_words(path.as_ptr(), path.len(), b"\xff".as_ptr(), 1, output.as_mut_ptr(), output.len()), -1);
            assert_eq!(dan_japanese_reading_words(path.as_ptr(), path.len(), "日本語".as_ptr(), 9, output.as_mut_ptr(), 1), -3);
        }
        assert!(output.iter().all(|value| *value == 0xab));
        assert!(words(&dictionary(), &"あ".repeat(101)).is_err());
        assert!(load(Path::new("missing-dictionary")).is_err());
    }
}
