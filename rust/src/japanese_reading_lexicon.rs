//! Supplemental whole-word readings and conservative alignment of known yomi.
//!
//! IPADIC remains the contextual analyzer. This lexicon may fill an unknown word,
//! or divide an already established reading; it never invents a character yomi.
use std::{
    collections::{BTreeMap, HashMap},
    fs::File,
    io::Read,
    path::Path,
    sync::OnceLock,
};

use flate2::read::GzDecoder;
use serde_json::Value;
use sha2::{Digest, Sha256};

const MAX_WORDS: usize = 2_000_000;
const MAX_ALIGNMENT_STEPS: usize = 8192;
static WORD_LEXICON: OnceLock<ReadingLexicon> = OnceLock::new();
static KANJI_LEXICON: OnceLock<ReadingLexicon> = OnceLock::new();
const WORD_HASH: &str = "f4bf033fb622280875be6199d20d44fe2307310ea41b403a37f30c6b3a23a772";
const KANJI_HASH: &str = "18c12298210019c8b620287b0c995ca30d8fad73542ef46d395736f4e29e49d3";

#[derive(Clone, Copy)]
enum ResourceKind {
    Words,
    Kanji,
}

impl ResourceKind {
    fn file_name(self) -> &'static str {
        match self {
            Self::Words => "supplemental-reading-v1.json.gz",
            Self::Kanji => "kanji-reading-v1.json.gz",
        }
    }

    fn hash(self) -> &'static str {
        match self {
            Self::Words => WORD_HASH,
            Self::Kanji => KANJI_HASH,
        }
    }

    fn limits(self) -> (usize, usize) {
        match self {
            Self::Words => (8 * 1024 * 1024, 32 * 1024 * 1024),
            Self::Kanji => (256 * 1024, 1024 * 1024),
        }
    }
}

pub(crate) fn is_han(c: char) -> bool {
    matches!(c, '々' | '〻')
        || matches!(c as u32,
        0x3400..=0x9fff | 0xf900..=0xfaff | 0x20000..=0x323af)
}

pub(crate) fn hiragana(text: &str) -> String {
    text.chars()
        .map(|c| match c as u32 {
            0x30a1..=0x30f6 => char::from_u32(c as u32 - 0x60).unwrap(),
            _ => c,
        })
        .collect()
}

fn is_kana_reading(text: &str) -> bool {
    !text.is_empty()
        && text.chars().all(|c| {
            matches!(c as u32,
        0x3041..=0x3096 | 0x3099..=0x309a | 0x30fc)
        })
}

pub(crate) struct ReadingLexicon {
    words: HashMap<String, String>,
    kanji: HashMap<char, Vec<String>>,
}

pub(crate) fn enrich(
    dictionary_path: &Path,
    input: &str,
    words: Vec<(String, String)>,
) -> Vec<(String, String)> {
    enrich_with_caches(dictionary_path, input, words, &WORD_LEXICON, &KANJI_LEXICON)
}

fn cached_resource<'a>(
    directory: &Path,
    kind: ResourceKind,
    cache: &'a OnceLock<ReadingLexicon>,
) -> Option<&'a ReadingLexicon> {
    if let Some(lexicon) = cache.get() {
        return Some(lexicon);
    }
    // Cache successes only. Missing/bad component files can be atomically
    // replaced by an explicit component install without restarting the worker.
    let lexicon = ReadingLexicon::load_path(&directory.join(kind.file_name()), kind).ok()?;
    let _ = cache.set(lexicon);
    cache.get()
}

fn enrich_with_caches(
    dictionary_path: &Path,
    input: &str,
    words: Vec<(String, String)>,
    word_cache: &OnceLock<ReadingLexicon>,
    kanji_cache: &OnceLock<ReadingLexicon>,
) -> Vec<(String, String)> {
    let directory = dictionary_path.parent().unwrap_or_else(|| Path::new("."));
    let kanji = cached_resource(directory, ResourceKind::Kanji, kanji_cache);
    let needs_words = words
        .iter()
        .any(|(text, reading)| text == reading && text.chars().any(is_han));
    let supplemental = if needs_words {
        cached_resource(directory, ResourceKind::Words, word_cache)
    } else {
        None
    };
    if let Some(kanji) = kanji {
        kanji.enrich(input, words, supplemental)
    } else if let Some(supplemental) = supplemental {
        supplemental.enrich(input, words, Some(supplemental))
    } else {
        words
    }
}

impl ReadingLexicon {
    fn load_path(path: &Path, kind: ResourceKind) -> Result<Self, String> {
        let mut gzip = Vec::new();
        let (max_compressed, _) = kind.limits();
        File::open(path)
            .map_err(|error| error.to_string())?
            .take((max_compressed + 1) as u64)
            .read_to_end(&mut gzip)
            .map_err(|error| error.to_string())?;
        if gzip.len() > max_compressed || format!("{:x}", Sha256::digest(&gzip)) != kind.hash() {
            return Err("Invalid supplemental reading checksum".into());
        }
        Self::load(&gzip, kind)
    }

    fn load(gzip: &[u8], kind: ResourceKind) -> Result<Self, String> {
        let (max_compressed, max_json) = kind.limits();
        if gzip.len() > max_compressed {
            return Err("Oversized supplemental reading dictionary".into());
        }
        let mut json = Vec::new();
        GzDecoder::new(gzip)
            .take((max_json + 1) as u64)
            .read_to_end(&mut json)
            .map_err(|error| error.to_string())?;
        if json.len() > max_json {
            return Err("Oversized supplemental reading data".into());
        }
        Self::from_json(&json, kind)
    }

    fn from_json(json: &[u8], kind: ResourceKind) -> Result<Self, String> {
        let mut document: Value =
            serde_json::from_slice(json).map_err(|error| error.to_string())?;
        if document.get("version").and_then(Value::as_u64) != Some(1) {
            return Err("Unsupported supplemental reading version".into());
        }
        let mut words = HashMap::new();
        if matches!(kind, ResourceKind::Words) {
            let values = document
                .get_mut("words")
                .and_then(Value::as_object_mut)
                .ok_or("Missing supplemental words")?;
            if values.len() > MAX_WORDS {
                return Err("Oversized supplemental word count".into());
            }
            words.reserve(values.len());
            for (surface, value) in std::mem::take(values) {
                let Value::String(reading) = value else {
                    return Err("Invalid supplemental word reading".into());
                };
                if !surface.chars().any(is_han) || !is_kana_reading(&reading) {
                    return Err("Invalid supplemental word spelling".into());
                }
                // Longer spellings cannot occur in this analyzer's bounded input.
                if surface.encode_utf16().count() <= 100 && reading.encode_utf16().count() <= 2000 {
                    words.insert(surface, reading);
                }
            }
        }
        let mut kanji = HashMap::new();
        if matches!(kind, ResourceKind::Kanji) {
            let values = document
                .get_mut("kanji")
                .and_then(Value::as_object_mut)
                .ok_or("Missing supplemental character readings")?;
            kanji.reserve(values.len());
            for (surface, value) in std::mem::take(values) {
                let mut characters = surface.chars();
                let character = characters.next().ok_or("Empty supplemental character")?;
                if characters.next().is_some() || !is_han(character) {
                    return Err("Invalid supplemental character".into());
                }
                let Value::Array(values) = value else {
                    return Err("Invalid supplemental character readings".into());
                };
                let mut readings = Vec::new();
                for value in values {
                    let Value::String(reading) = value else {
                        return Err("Invalid supplemental character reading".into());
                    };
                    if !is_kana_reading(&reading) {
                        return Err("Invalid supplemental character yomi".into());
                    }
                    readings.push(reading);
                }
                readings.sort();
                readings.dedup();
                kanji.insert(character, readings);
            }
        }
        Ok(Self { words, kanji })
    }

    fn enrich(
        &self,
        input: &str,
        words: Vec<(String, String)>,
        supplemental: Option<&Self>,
    ) -> Vec<(String, String)> {
        let mut boundaries = vec![0];
        let mut unknown = Vec::with_capacity(words.len());
        for (text, reading) in &words {
            boundaries.push(boundaries.last().unwrap() + text.len());
            unknown.push(text == reading && text.chars().any(is_han));
        }
        let mut result = Vec::new();
        let mut start = 0;
        while start < words.len() {
            let mut replacement = None;
            let mut contains_unknown = false;
            // Replacements span complete analyzer tokens and at least one
            // unknown Han. A fully known IPADIC span is never replaced.
            for end in start + 1..=words.len() {
                contains_unknown |= unknown[end - 1];
                if contains_unknown {
                    let surface = &input[boundaries[start]..boundaries[end]];
                    if let Some(reading) =
                        supplemental.and_then(|lexicon| lexicon.words.get(surface))
                    {
                        replacement = Some((end, surface, reading.as_str()));
                    }
                }
            }
            let (end, surface, reading) = if let Some(replacement) = replacement {
                replacement
            } else {
                (start + 1, words[start].0.as_str(), words[start].1.as_str())
            };
            if let Some(aligned) = self.align(surface, reading) {
                result.extend(aligned);
            } else {
                result.push((surface.to_owned(), reading.to_owned()));
            }
            start = end;
        }
        result
    }

    fn align(&self, surface: &str, reading: &str) -> Option<Vec<(String, String)>> {
        if !surface.chars().any(is_han) || !is_kana_reading(reading) {
            return None;
        }
        let characters: Vec<char> = surface.chars().collect();
        if characters.len() < 2 {
            return None;
        }
        let mut units = Vec::new();
        let mut previous_han = None;
        for character in characters {
            let candidates = if is_han(character) {
                let key = if matches!(character, '々' | '〻') {
                    previous_han?
                } else {
                    previous_han = Some(character);
                    character
                };
                variants(self.kanji.get(&key)?)
            } else {
                let kana = hiragana(&character.to_string());
                if !is_kana_reading(&kana) {
                    return None;
                }
                previous_han = None;
                vec![kana]
            };
            units.push((character.to_string(), candidates));
        }
        let mut states = BTreeMap::from([(
            0,
            Alignment {
                count: 1,
                parts: Vec::new(),
            },
        )]);
        let mut steps = 0;
        for (surface, candidates) in units {
            let mut next: BTreeMap<usize, Alignment> = BTreeMap::new();
            for (offset, state) in states {
                for candidate in &candidates {
                    steps += 1;
                    if steps > MAX_ALIGNMENT_STEPS {
                        return None;
                    }
                    if !reading[offset..].starts_with(candidate) {
                        continue;
                    }
                    let end = offset + candidate.len();
                    if let Some(existing) = next.get_mut(&end) {
                        existing.count = (existing.count + state.count).min(2);
                    } else {
                        let mut parts = state.parts.clone();
                        parts.push((surface.clone(), candidate.clone()));
                        next.insert(
                            end,
                            Alignment {
                                count: state.count,
                                parts,
                            },
                        );
                    }
                }
            }
            if next.is_empty() {
                return None;
            }
            states = next;
        }
        let complete = states.remove(&reading.len())?;
        (complete.count == 1).then_some(complete.parts)
    }
}

struct Alignment {
    // Capped at two: anything nonunique keeps the original whole-word reading.
    count: u8,
    parts: Vec<(String, String)>,
}

fn variants(readings: &[String]) -> Vec<String> {
    let mut result = Vec::new();
    for reading in readings {
        let mut initial = vec![reading.clone()];
        let mut characters = reading.chars();
        let Some(first) = characters.next() else {
            continue;
        };
        let voiced = match first {
            'か' => Some('が'),
            'き' => Some('ぎ'),
            'く' => Some('ぐ'),
            'け' => Some('げ'),
            'こ' => Some('ご'),
            'さ' => Some('ざ'),
            'し' => Some('じ'),
            'す' => Some('ず'),
            'せ' => Some('ぜ'),
            'そ' => Some('ぞ'),
            'た' => Some('だ'),
            'ち' => Some('ぢ'),
            'つ' => Some('づ'),
            'て' => Some('で'),
            'と' => Some('ど'),
            'は' => Some('ば'),
            'ひ' => Some('び'),
            'ふ' => Some('ぶ'),
            'へ' => Some('べ'),
            'ほ' => Some('ぼ'),
            _ => None,
        };
        if let Some(voiced) = voiced {
            initial.push(format!("{voiced}{}", characters.as_str()));
        }
        let half_voiced = match first {
            'は' => Some('ぱ'),
            'ひ' => Some('ぴ'),
            'ふ' => Some('ぷ'),
            'へ' => Some('ぺ'),
            'ほ' => Some('ぽ'),
            _ => None,
        };
        if let Some(half_voiced) = half_voiced {
            initial.push(format!("{half_voiced}{}", characters.as_str()));
        }
        for candidate in initial {
            if let Some((last_offset, last)) = candidate.char_indices().last() {
                if matches!(last, 'く' | 'き' | 'つ' | 'ち') && last_offset > 0 {
                    result.push(format!("{}っ", &candidate[..last_offset]));
                }
            }
            result.push(candidate);
        }
    }
    result.sort();
    result.dedup();
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture() -> ReadingLexicon {
        ReadingLexicon::from_json(br#"{"version":1,"kanji":{}}"#, ResourceKind::Kanji).unwrap()
    }

    fn pairs(values: &[(&str, &str)]) -> Vec<(String, String)> {
        values
            .iter()
            .map(|(text, reading)| (text.to_string(), reading.to_string()))
            .collect()
    }

    #[test]
    fn unknown_recovery_uses_longest_whole_word_and_preserves_context() {
        let mut lexicon = fixture();
        lexicon.words.insert("奔る".into(), "はしる".into());
        lexicon.words.insert("奔".into(), "ほん".into());
        lexicon.words.insert("明日".into(), "あす".into());
        let words = pairs(&[("奔", "奔"), ("る", "る"), (" ", " "), ("明日", "あした")]);
        assert_eq!(
            lexicon.enrich("奔る 明日", words, Some(&lexicon)),
            pairs(&[("奔る", "はしる"), (" ", " "), ("明日", "あした")])
        );
        assert_eq!(
            lexicon.enrich("未収録", pairs(&[("未収録", "未収録")]), Some(&lexicon)),
            pairs(&[("未収録", "未収録")])
        );
    }

    #[test]
    fn known_yomi_alignment_requires_unique_complete_match() {
        let mut lexicon = fixture();
        lexicon.kanji.insert('勇', vec!["ゆう".into()]);
        lexicon.kanji.insert('気', vec!["き".into()]);
        lexicon.kanji.insert('言', vec!["こと".into()]);
        lexicon.kanji.insert('葉', vec!["は".into()]);
        assert_eq!(
            lexicon.align("勇気", "ゆうき"),
            Some(pairs(&[("勇", "ゆう"), ("気", "き")]))
        );
        assert_eq!(
            lexicon.align("言葉", "ことば"),
            Some(pairs(&[("言", "こと"), ("葉", "ば")]))
        );
        assert!(lexicon.align("勇気", "ゆうげん").is_none());
        lexicon.kanji.insert('勇', vec!["ゆう".into(), "ゆ".into()]);
        lexicon.kanji.insert('気', vec!["き".into(), "うき".into()]);
        assert!(lexicon.align("勇気", "ゆうき").is_none());
    }

    #[test]
    fn iteration_and_kana_anchors_preserve_surface_and_fixed_yomi() {
        let mut lexicon = fixture();
        lexicon.kanji.insert('蝶', vec!["ちょう".into()]);
        lexicon.kanji.insert('時', vec!["とき".into()]);
        lexicon.kanji.insert('会', vec!["あ".into()]);
        assert_eq!(
            lexicon.align("蝶々", "ちょうちょう"),
            Some(pairs(&[("蝶", "ちょう"), ("々", "ちょう")]))
        );
        assert_eq!(
            lexicon.align("時〻", "ときどき"),
            Some(pairs(&[("時", "とき"), ("〻", "どき")]))
        );
        assert_eq!(
            lexicon.align("会える", "あえる"),
            Some(pairs(&[("会", "あ"), ("え", "え"), ("る", "る")]))
        );
        assert!(lexicon.align("々蝶", "ちょうちょう").is_none());
        assert!(lexicon.align("会X", "あえる").is_none());
    }

    #[test]
    fn malformed_resource_is_rejected_without_unsafe_guesses() {
        assert!(
            ReadingLexicon::from_json(br#"{"version":2,"words":{}}"#, ResourceKind::Words).is_err()
        );
        assert!(ReadingLexicon::from_json(
            br#"{"version":1,"words":{"x":"unknown"}}"#,
            ResourceKind::Words
        )
        .is_err());
        assert!(ReadingLexicon::load(b"invalid-gzip", ResourceKind::Words).is_err());
        assert!(is_han('々') && is_han('〻') && is_han('𠮷'));
        assert!(!is_han('あ'));
    }

    #[test]
    fn official_resources_load_and_keep_ambiguous_words_unselected() {
        let directory = Path::new(file!())
            .canonicalize()
            .unwrap()
            .parent()
            .unwrap()
            .parent()
            .unwrap()
            .join("assets");
        let words = ReadingLexicon::load_path(
            &directory.join(ResourceKind::Words.file_name()),
            ResourceKind::Words,
        )
        .unwrap();
        let kanji = ReadingLexicon::load_path(
            &directory.join(ResourceKind::Kanji.file_name()),
            ResourceKind::Kanji,
        )
        .unwrap();
        assert_eq!(words.words.len(), 505_327);
        assert_eq!(kanji.kanji.len(), 12_356);
        for (surface, expected) in [
            ("奔る", "はしる"),
            ("奔った", "はしった"),
            ("奔って", "はしって"),
            ("奔らない", "はしらない"),
            ("奔れば", "はしれば"),
            ("奔ろう", "はしろう"),
            ("乞うた", "こうた"),
            ("乞うて", "こうて"),
        ] {
            assert_eq!(words.words.get(surface).map(String::as_str), Some(expected));
        }
        assert!(!words.words.contains_key("今日"));
        assert!(!words.words.contains_key("生物"));
        for (surface, reading, expected) in [
            ("勇気", "ゆうき", pairs(&[("勇", "ゆう"), ("気", "き")])),
            ("言葉", "ことば", pairs(&[("言", "こと"), ("葉", "ば")])),
            (
                "大丈夫",
                "だいじょうぶ",
                pairs(&[("大", "だい"), ("丈", "じょう"), ("夫", "ぶ")]),
            ),
            (
                "蝶々",
                "ちょうちょう",
                pairs(&[("蝶", "ちょう"), ("々", "ちょう")]),
            ),
            (
                "即興",
                "そっきょう",
                pairs(&[("即", "そっ"), ("興", "きょう")]),
            ),
        ] {
            assert_eq!(kanji.align(surface, reading), Some(expected));
        }
    }

    #[test]
    fn external_component_can_be_installed_after_missing_or_invalid_files() {
        let stamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let directory = std::env::temp_dir().join(format!(
            "japanese-component-retry-{}-{stamp}",
            std::process::id()
        ));
        std::fs::create_dir_all(&directory).unwrap();
        let dictionary = directory.join("ipadic-reading.bin.gz");
        let word_cache = OnceLock::new();
        let kanji_cache = OnceLock::new();
        let original = pairs(&[("勇気", "ゆうき"), ("と", "と"), ("奔", "奔"), ("る", "る")]);
        assert_eq!(
            enrich_with_caches(
                &dictionary,
                "勇気と奔る",
                original.clone(),
                &word_cache,
                &kanji_cache
            ),
            original
        );
        assert!(word_cache.get().is_none() && kanji_cache.get().is_none());
        std::fs::write(directory.join(ResourceKind::Kanji.file_name()), b"invalid").unwrap();
        assert!(cached_resource(&directory, ResourceKind::Kanji, &kanji_cache).is_none());
        assert!(kanji_cache.get().is_none());
        std::fs::write(
            directory.join(ResourceKind::Kanji.file_name()),
            include_bytes!("../assets/kanji-reading-v1.json.gz"),
        )
        .unwrap();
        assert_eq!(
            enrich_with_caches(
                &dictionary,
                "勇気",
                pairs(&[("勇気", "ゆうき")]),
                &word_cache,
                &kanji_cache
            ),
            pairs(&[("勇", "ゆう"), ("気", "き")])
        );
        assert!(kanji_cache.get().is_some() && word_cache.get().is_none());
        std::fs::write(directory.join(ResourceKind::Words.file_name()), b"invalid").unwrap();
        assert!(cached_resource(&directory, ResourceKind::Words, &word_cache).is_none());
        assert!(word_cache.get().is_none());
        std::fs::write(
            directory.join(ResourceKind::Words.file_name()),
            include_bytes!("../assets/supplemental-reading-v1.json.gz"),
        )
        .unwrap();
        assert_eq!(
            enrich_with_caches(
                &dictionary,
                "勇気と奔る",
                original,
                &word_cache,
                &kanji_cache
            ),
            pairs(&[
                ("勇", "ゆう"),
                ("気", "き"),
                ("と", "と"),
                ("奔", "はし"),
                ("る", "る")
            ])
        );
        assert!(word_cache.get().is_some());
    }
}
