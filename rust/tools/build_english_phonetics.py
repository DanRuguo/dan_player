#!/usr/bin/env python3
"""Build DanPlayer's compact offline English IPA lexicon (DANENG01).

Input:  CMU Pronouncing Dictionary (cmudict.dict, BSD-2-Clause)
Output: Gzipped DANENG01 blocked prefix-compressed binary lexicon
        (assets/dictionaries/cmudict_ipa.bin.gz)

Usage:
    python3 rust/tools/build_english_phonetics.py \
        --input cmudict.dict \
        --output assets/dictionaries/cmudict_ipa.bin.gz
"""

from __future__ import annotations

import argparse
import gzip
import os
import re
import struct
import sys
from pathlib import Path

MAGIC = b"DANENG01"
BLOCK_SIZE = 32

CONSONANT_IPA = {
    "B": "b",
    "CH": "tʃ",
    "D": "d",
    "DH": "ð",
    "F": "f",
    "G": "ɡ",
    "HH": "h",
    "JH": "dʒ",
    "K": "k",
    "L": "l",
    "M": "m",
    "N": "n",
    "NG": "ŋ",
    "P": "p",
    "R": "r",
    "S": "s",
    "SH": "ʃ",
    "T": "t",
    "TH": "θ",
    "V": "v",
    "W": "w",
    "Y": "j",
    "Z": "z",
    "ZH": "ʒ",
}

VOWELS = {
    "AA",
    "AE",
    "AH",
    "AO",
    "AW",
    "AY",
    "EH",
    "ER",
    "EY",
    "IH",
    "IY",
    "OW",
    "OY",
    "UH",
    "UW",
}

# Valid English syllable onsets (ARPABET consonant tuples) for Maximal Onset.
VALID_ONSETS_2 = {
    ("P", "L"), ("P", "R"), ("P", "Y"),
    ("B", "L"), ("B", "R"), ("B", "Y"),
    ("T", "R"), ("T", "W"), ("T", "Y"),
    ("D", "R"), ("D", "W"), ("D", "Y"),
    ("K", "L"), ("K", "R"), ("K", "W"), ("K", "Y"),
    ("G", "L"), ("G", "R"), ("G", "W"), ("G", "Y"),
    ("F", "L"), ("F", "R"), ("F", "Y"),
    ("V", "Y"),
    ("TH", "R"), ("TH", "W"),
    ("SH", "R"),
    ("S", "P"), ("S", "T"), ("S", "K"), ("S", "M"),
    ("S", "N"), ("S", "L"), ("S", "W"), ("S", "F"), ("S", "Y"),
    ("M", "Y"), ("N", "Y"), ("HH", "Y"), ("HH", "W"), ("L", "Y"),
}

VALID_ONSETS_3 = {
    ("S", "P", "L"), ("S", "P", "R"), ("S", "P", "Y"),
    ("S", "T", "R"), ("S", "T", "Y"),
    ("S", "K", "L"), ("S", "K", "R"), ("S", "K", "W"), ("S", "K", "Y"),
}

# Closed set of genuine 1- and 2-letter English words to avoid false positives
# on romaji, pinyin, Spanish/French particles, or obscure acronyms in CMUDict.
ALLOWED_SHORT_WORDS = {
    # 1-letter
    "a", "i",
    # 2-letter
    "ad", "ah", "am", "an", "as", "at", "aw", "ax",
    "be", "by",
    "dj", "do",
    "eh", "ex",
    "go",
    "ha", "he", "hi", "hm",
    "id", "if", "in", "is", "it",
    "me", "my",
    "no",
    "of", "oh", "ok", "on", "or", "ow", "ox",
    "so",
    "to", "tv",
    "uh", "um", "up", "us",
    "we",
    "ya", "ye", "yo",
}

# Curated lyric-friendly ARPABET overrides & additions.
# Overrides disambiguate homographs toward their overwhelmingly common lyric
# pronunciation and add colloquial song contractions absent from CMUDict.
CURATED_ARPABET = {
    # Disambiguate common function words & homographs for song lyrics
    "a": "AH0",
    "the": "DH AH0",
    "live": "L IH1 V",
    "read": "R IY1 D",
    "lead": "L IY1 D",
    "wind": "W IH1 N D",
    "close": "K L OW1 S",
    "tear": "T IH1 R",
    "tears": "T IH1 R Z",
    "bow": "B AW1",
    "minute": "M IH1 N AH0 T",
    "present": "P R EH1 Z AH0 N T",
    "record": "R EH1 K ER0 D",
    "use": "Y UW1 Z",
    "excuse": "IH0 K S K Y UW1 Z",
    "refuse": "R IH0 F Y UW1 Z",
    "wound": "W UW1 N D",
    "dove": "D AH1 V",
    "bass": "B EY1 S",
    "row": "R OW1",
    "sow": "S OW1",
    "polish": "P AA1 L IH0 SH",
    "desert": "D EH1 Z ER0 T",
    "content": "K AA1 N T EH0 N T",
    "object": "AA1 B JH EH0 K T",
    "project": "P R AA1 JH EH0 K T",
    "perfect": "P ER1 F IH0 K T",
    "separate": "S EH1 P R AH0 T",
    "alternate": "AO1 L T ER0 N AH0 T",
    "graduate": "G R AE1 JH AH0 W AH0 T",
    # Colloquial lyric contractions & vocalizations
    "ain't": "EY1 N T",
    "gonna": "G AH1 N AH0",
    "wanna": "W AA1 N AH0",
    "gotta": "G AA1 T AH0",
    "kinda": "K AY1 N D AH0",
    "sorta": "S AO1 R T AH0",
    "outta": "AW1 T AH0",
    "lemme": "L EH1 M IY0",
    "gimme": "G IH1 M IY0",
    "dunno": "D AH0 N OW1",
    "tryna": "T R AY1 N AH0",
    "finna": "F IH1 N AH0",
    "betcha": "B EH1 CH AH0",
    "gotcha": "G AA1 CH AH0",
    "whatcha": "W AH1 CH AH0",
    "coulda": "K UH1 D AH0",
    "woulda": "W UH1 D AH0",
    "shoulda": "SH UH1 D AH0",
    "musta": "M AH1 S T AH0",
    "oughta": "AO1 T AH0",
    "lotta": "L AA1 T AH0",
    "y'all": "Y AO1 L",
    "ya'll": "Y AO1 L",
    "c'mon": "K AH0 M AA1 N",
    "cause": "K AO1 Z",
    "til": "T IH1 L",
    "o'er": "AO1 R",
    "e'er": "EH1 R",
    "ne'er": "N EH1 R",
    "ma'am": "M AE1 M",
    "o'clock": "AH0 K L AA1 K",
    "yeah": "Y AE1",
    "yea": "Y EY1",
    "nah": "N AA1",
    "nope": "N OW1 P",
    "yep": "Y EH1 P",
    "yup": "Y AH1 P",
    "whoa": "W OW1",
    "woah": "W OW1",
    "ooh": "UW1",
    "aah": "AA1",
    "uhh": "AH1",
    "huh": "HH AH1",
    "hmm": "HH M",
    "mmm": "M",
    "shh": "SH",
    "hey": "HH EY1",
    "aye": "AY1",
    "ayy": "EY1",
    "ok": "OW2 K EY1",
    "okay": "OW2 K EY1",
    "tv": "T IY1 V IY1",
    "dj": "D IY1 JH EY1",
    "vip": "V IY1 AY1 P IY1",
    "usa": "Y UW1 EH1 S EY1",
    "uk": "Y UW1 K EY1",
    "hm": "HH M",
    # Common lyric g-dropping participles
    "lovin": "L AH1 V IH0 N",
    "dancin": "D AE1 N S IH0 N",
    "singin": "S IH1 NG IH0 N",
    "runnin": "R AH1 N IH0 N",
    "fallin": "F AO1 L IH0 N",
    "dreamin": "D R IY1 M IH0 N",
    "waitin": "W EY1 T IH0 N",
    "cryin": "K R AY1 IH0 N",
    "tryin": "T R AY1 IH0 N",
    "flyin": "F L AY1 IH0 N",
    "feelin": "F IY1 L IH0 N",
    "nothin": "N AH1 TH IH0 N",
    "somethin": "S AH1 M TH IH0 N",
    "comin": "K AH1 M IH0 N",
    "goin": "G OW1 IH0 N",
    "doin": "D UW1 IH0 N",
    "sayin": "S EY1 IH0 N",
    "playin": "P L EY1 IH0 N",
    "stayin": "S T EY1 IH0 N",
    "lookin": "L UH1 K IH0 N",
    "talkin": "T AO1 K IH0 N",
    "walkin": "W AO1 K IH0 N",
    "thinkin": "TH IH1 NG K IH0 N",
    "movin": "M UW1 V IH0 N",
    "shinin": "SH AY1 N IH0 N",
    "burnin": "B ER1 N IH0 N",
    "turnin": "T ER1 N IH0 N",
    "holdin": "HH OW1 L D IH0 N",
    "breathin": "B R IY1 DH IH0 N",
    "livin": "L IH1 V IH0 N",
    "givin": "G IH1 V IH0 N",
    "takin": "T EY1 K IH0 N",
    "makin": "M EY1 K IH0 N",
    "breakin": "B R EY1 K IH0 N",
    "shakin": "SH EY1 K IH0 N",
    "chillin": "CH IH1 L IH0 N",
    "rollin": "R OW1 L IH0 N",
    "ridin": "R AY1 D IH0 N",
    "hidin": "HH AY1 D IH0 N",
    "callin": "K AO1 L IH0 N",
    "ballin": "B AO1 L IH0 N",
    "dyin": "D AY1 IH0 N",
    "lyin": "L AY1 IH0 N",
    "buyin": "B AY1 IH0 N",
    "gettin": "G EH1 T IH0 N",
    "sittin": "S IH1 T IH0 N",
    "hittin": "HH IH1 T IH0 N",
    "lettin": "L EH1 T IH0 N",
    "tellin": "T EH1 L IH0 N",
    "yellin": "Y EH1 L IH0 N",
    "workin": "W ER1 K IH0 N",
    "hurtin": "HH ER1 T IH0 N",
    "watchin": "W AA1 CH IH0 N",
    "catchin": "K AE1 CH IH0 N",
    "wishin": "W IH1 SH IH0 N",
    "kissin": "K IH1 S IH0 N",
    "missin": "M IH1 S IH0 N",
    "hopin": "HH OW1 P IH0 N",
    "smokin": "S M OW1 K IH0 N",
    "jokin": "JH OW1 K IH0 N",
    "drivin": "D R AY1 V IH0 N",
    "vibin": "V AY1 B IH0 N",
    "trippin": "T R IH1 P IH0 N",
    "slippin": "S L IH1 P IH0 N",
    "sippin": "S IH1 P IH0 N",
    "flippin": "F L IH1 P IH0 N",
    "poppin": "P AA1 P IH0 N",
    "stoppin": "S T AA1 P IH0 N",
    "droppin": "D R AA1 P IH0 N",
    "rockin": "R AA1 K IH0 N",
    "knockin": "N AA1 K IH0 N",
    "stomp": "S T AA1 M P",
    "vibe": "V AY1 B",
    "vibes": "V AY1 B Z",
    "vibing": "V AY1 B IH0 NG",
    "selfie": "S EH1 L F IY0",
    "selfies": "S EH1 L F IY0 Z",
    "playlist": "P L EY1 L IH0 S T",
    "playlists": "P L EY1 L IH0 S T S",
    "podcast": "P AA1 D K AE2 S T",
    "podcasts": "P AA1 D K AE2 S T S",
    "emoji": "IH0 M OW1 JH IY0",
    "emojis": "IH0 M OW1 JH IY0 Z",
    "wifi": "W AY1 F AY2",
    "anime": "AE1 N AH0 M EY2",
    "tiktok": "T IH1 K T AA2 K",
    "instagram": "IH1 N S T AH0 G R AE2 M",
    "spotify": "S P AA1 T AH0 F AY2",
    "youtube": "Y UW1 T UW2 B",
}

KEY_PATTERN = re.compile(r"^[a-z]+(?:'[a-z]+)*$")


def parse_phone(token: str) -> tuple[str, int | None]:
    if token and token[-1] in ("0", "1", "2"):
        return token[:-1], int(token[-1])
    return token, None


def vowel_to_ipa(base: str, stress: int, is_word_final: bool) -> str:
    if base == "AA":
        return "ɑː"
    if base == "AE":
        return "æ"
    if base == "AH":
        return "ə" if stress == 0 else "ʌ"
    if base == "AO":
        return "ɔː"
    if base == "AW":
        return "aʊ"
    if base == "AY":
        return "aɪ"
    if base == "EH":
        return "ɛ"
    if base == "ER":
        return "ər" if stress == 0 else "ɜːr"
    if base == "EY":
        return "eɪ"
    if base == "IH":
        return "ɪ"
    if base == "IY":
        return "i" if stress == 0 else "iː"
    if base == "OW":
        return "oʊ"
    if base == "OY":
        return "ɔɪ"
    if base == "UH":
        return "ʊ"
    if base == "UW":
        return "u" if stress == 0 else "uː"
    raise ValueError(f"Unknown vowel phoneme: {base}")


def split_intervocalic_cluster(cluster: list[str]) -> int:
    """Return index where the onset of the next syllable begins."""
    n = len(cluster)
    if n == 0:
        return 0
    if n == 1:
        # NG cannot start an English syllable onset.
        return 1 if cluster[0] == "NG" else 0
    if n >= 3 and tuple(cluster[-3:]) in VALID_ONSETS_3:
        return n - 3
    if n >= 2 and tuple(cluster[-2:]) in VALID_ONSETS_2:
        return n - 2
    if cluster[-1] == "NG":
        return n
    return n - 1


def arpabet_to_ipa(phones: list[str]) -> str:
    parsed = [parse_phone(p) for p in phones]
    vowel_indices = [i for i, (base, stress) in enumerate(parsed) if base in VOWELS]

    if not vowel_indices:
        # Rare vocalizations like "hmm" / "shh"
        return "".join(CONSONANT_IPA[base] for base, _ in parsed if base in CONSONANT_IPA)

    # Syllabify into (onset, vowel_idx, coda) slices.
    syllables: list[tuple[list[str], int, list[str]]] = []
    n_vowels = len(vowel_indices)
    onset_start = 0

    for s_idx, v_pos in enumerate(vowel_indices):
        onset = [parsed[i][0] for i in range(onset_start, v_pos)]
        if s_idx + 1 < n_vowels:
            next_v = vowel_indices[s_idx + 1]
            inter = [parsed[i][0] for i in range(v_pos + 1, next_v)]
            split_at = split_intervocalic_cluster(inter)
            coda = inter[:split_at]
            onset_start = v_pos + 1 + split_at
        else:
            coda = [parsed[i][0] for i in range(v_pos + 1, len(parsed))]
        syllables.append((onset, v_pos, coda))

    out: list[str] = []
    for s_idx, (onset, v_pos, coda) in enumerate(syllables):
        v_base, v_stress = parsed[v_pos]
        stress = 0 if v_stress is None else v_stress

        if n_vowels >= 2:
            if stress == 1:
                out.append("ˈ")
            elif stress == 2:
                # Suppress secondary stress mark on a bare word-final open OW2
                # immediately following a primary-stressed syllable
                # (e.g., shadow ˈʃædoʊ, window ˈwɪndoʊ, tomorrow təˈmɑːroʊ).
                suppress_ow2 = (
                    s_idx == n_vowels - 1
                    and v_base == "OW"
                    and not coda
                    and s_idx > 0
                    and (parsed[syllables[s_idx - 1][1]][1] == 1)
                )
                if not suppress_ow2:
                    out.append("ˌ")

        for c in onset:
            out.append(CONSONANT_IPA[c])
        is_word_final = (s_idx == n_vowels - 1) and (not coda)
        out.append(vowel_to_ipa(v_base, stress, is_word_final))
        for c in coda:
            out.append(CONSONANT_IPA[c])

    return "".join(out)


def load_cmudict(path: Path) -> dict[str, str]:
    entries: dict[str, str] = {}
    with path.open("r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith(";;;"):
                continue
            # Strip inline comments (`# ...`)
            comment_pos = line.find("#")
            if comment_pos != -1:
                line = line[:comment_pos].strip()
                if not line:
                    continue
            parts = line.split()
            if len(parts) < 2:
                continue
            word = parts[0].lower()
            # Keep only primary pronunciation (skip variant suffixes like word(2))
            if "(" in word:
                continue
            if not KEY_PATTERN.match(word):
                continue
            if len(word) <= 2 and word not in ALLOWED_SHORT_WORDS:
                continue
            if word in entries:
                continue
            phones = parts[1:]
            try:
                ipa = arpabet_to_ipa(phones)
            except KeyError:
                continue
            if not ipa:
                continue
            entries[word] = ipa

    # Apply curated lyric overrides & colloquial additions
    for word, arpa in CURATED_ARPABET.items():
        entries[word] = arpabet_to_ipa(arpa.split())

    return entries


def encode_daneng01(entries: dict[str, str]) -> bytes:
    sorted_items = sorted(entries.items(), key=lambda kv: kv[0].encode("ascii"))
    blocks: list[bytes] = []

    for start in range(0, len(sorted_items), BLOCK_SIZE):
        chunk = sorted_items[start : start + BLOCK_SIZE]
        buf = bytearray()
        prev_key = b""
        for idx, (word, ipa) in enumerate(chunk):
            key_b = word.encode("ascii")
            ipa_b = ipa.encode("utf-8")
            if len(key_b) > 255 or len(ipa_b) > 255:
                raise ValueError(f"Entry too long: {word} -> {ipa}")
            if idx == 0:
                buf.append(len(key_b))
                buf.extend(key_b)
                buf.append(len(ipa_b))
                buf.extend(ipa_b)
            else:
                shared = 0
                limit = min(len(prev_key), len(key_b), 255)
                while shared < limit and prev_key[shared] == key_b[shared]:
                    shared += 1
                suffix = key_b[shared:]
                buf.append(shared)
                buf.append(len(suffix))
                buf.extend(suffix)
                buf.append(len(ipa_b))
                buf.extend(ipa_b)
            prev_key = key_b
        blocks.append(bytes(buf))

    block_count = len(blocks)
    if block_count > 65535:
        raise ValueError(f"Too many blocks: {block_count}")

    offsets = bytearray()
    payload = bytearray()
    for blk in blocks:
        offsets.extend(struct.pack("<I", len(payload)))
        payload.extend(blk)

    header = struct.pack("<8sIHH", MAGIC, len(sorted_items), BLOCK_SIZE, block_count)
    return header + bytes(offsets) + bytes(payload)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path, help="Path to cmudict.dict")
    parser.add_argument(
        "--output", required=True, type=Path, help="Output .bin.gz file path"
    )
    parser.add_argument(
        "--verify-samples",
        action="store_true",
        help="Print sample IPA outputs for sanity checking",
    )
    args = parser.parse_args()

    entries = load_cmudict(args.input)
    raw = encode_daneng01(entries)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    # Deterministic gzip (mtime=0) for reproducible builds.
    with args.output.open("wb") as raw_out:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw_out, compresslevel=9, mtime=0) as gz:
            gz.write(raw)

    gz_size = args.output.stat().st_size
    block_count = (len(entries) + BLOCK_SIZE - 1) // BLOCK_SIZE
    print(
        f"Built {args.output}: {len(entries)} entries, {block_count} blocks, "
        f"raw={len(raw)} bytes, gzip={gz_size} bytes"
    )

    if args.verify_samples:
        samples = [
            "a", "i", "the", "love", "world", "night", "tomorrow", "shadow",
            "window", "follow", "memory", "beautiful", "remember", "forever",
            "moonlight", "understand", "everything", "hello", "goodbye", "dream",
            "baby", "happy", "music", "heart", "soul", "water", "never",
            "always", "believe", "through", "thought", "enough", "laughter",
            "live", "wind", "tears", "close", "gonna", "wanna", "ain't",
            "y'all", "c'mon", "lovin", "dancin", "playlist", "selfie",
            "ka", "ki", "ko", "na", "de", "la", "le", "el",
        ]
        for w in samples:
            print(f"  {w:14s} -> {entries.get(w, '<ABSENT>')}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
