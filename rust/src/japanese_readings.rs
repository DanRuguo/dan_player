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
const HASH: &str = "a8acd8b6352774fe3f6ac3fdbec59313ce04b548dad84340c17f0ee4bfab6e43";
static SEGMENTER: OnceLock<Segmenter> = OnceLock::new();

fn load(path: &Path) -> Result<Segmenter, String> {
    let mut gzip = Vec::new();
    File::open(path).map_err(|e| e.to_string())?.take((MAX_GZIP + 1) as u64)
        .read_to_end(&mut gzip).map_err(|e| e.to_string())?;
    if gzip.len() > MAX_GZIP || format!("{:x}", Sha256::digest(&gzip)) != HASH {
        return Err("Invalid Japanese dictionary checksum".into());
    }
    let mut pack = Vec::new();
    GzDecoder::new(gzip.as_slice()).take((MAX_PACK + 1) as u64).read_to_end(&mut pack)
        .map_err(|error| error.to_string())?;
    if pack.len() > MAX_PACK || !pack.starts_with(b"DANIPAD2") {
        return Err("Invalid Japanese dictionary format".into());
    }
    let mut offset = 8usize;
    let mut part = || -> Result<Vec<u8>, String> {
        let header = pack.get(offset..offset + 4).ok_or("Missing dictionary part")?;
        let size = u32::from_le_bytes(header.try_into().unwrap()) as usize;
        offset += 4;
        let end = offset.checked_add(size).ok_or("Invalid dictionary length")?;
        let data = pack.get(offset..end).ok_or("Incomplete dictionary part")?.to_vec();
        offset = end;
        Ok(data)
    };
    let metadata = Metadata::load(&part()?).map_err(|error| error.to_string())?;
    metadata.validate_format_version().map_err(|error| error.to_string())?;
    let character_definition = CharacterDefinition::load(&part()?).map_err(|error| error.to_string())?;
    let trie = part()?;
    let vals = part()?;
    let valsidx = part()?;
    let words = part()?;
    let wordsidx = part()?;
    let matrix = ConnectionCostMatrix::load(part()?).map_err(|error| error.to_string())?;
    let unknown = UnknownDictionary::load(&part()?).map_err(|error| error.to_string())?;
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
        assert!(load(Path::new("missing-dictionary" )).is_err());
    }
}
