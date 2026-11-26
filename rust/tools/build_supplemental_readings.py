"""Derive offline lexical/kanji readings from pinned EDRDG XML snapshots.

The derived data is CC BY-SA 4.0. No definitions, translations, names, or
guessed character pronunciations are included. Reading restrictions are kept;
conflicting pronunciations never become an automatic lexical fallback.
The two resources load separately so ordinary known words need no large map,
and the lexical resource uses columnar front-coded DANJPSUP v2 binary blocks.
"""
import argparse
from collections import defaultdict
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import struct
import unicodedata
import xml.etree.ElementTree as ET

MAX_XML = 256 * 1024 * 1024
MAX_RESOURCE = 64 * 1024 * 1024
SUP_BLOCK = 32


def han(text):
    return any(
        0x3400 <= ord(c) <= 0x9FFF
        or 0xF900 <= ord(c) <= 0xFAFF
        or 0x20000 <= ord(c) <= 0x323AF
        for c in text
    )


def hira(text):
    return "".join(
        chr(ord(c) - 0x60) if 0x30A1 <= ord(c) <= 0x30F6 else c
        for c in unicodedata.normalize("NFKC", text)
    )


def kana(text):
    return bool(text) and all(
        0x3041 <= ord(c) <= 0x3096 or c in "ーゝゞ" for c in text
    )


def encode_hiragana_bytes(text: str) -> bytes:
    out = bytearray()
    for ch in text:
        cp = ord(ch)
        if 0x3041 <= cp <= 0x3096:
            out.append(1 + (cp - 0x3041))
        elif cp == 0x30FC:
            out.append(87)
        elif cp == 0x309D:
            out.append(88)
        elif cp == 0x309E:
            out.append(89)
        elif cp == 0x3099:
            out.append(90)
        elif cp == 0x309A:
            out.append(91)
        else:
            raise ValueError(f"Unsupported kana codepoint: U+{cp:04X}")
    return bytes(out)


def pinned_xml(path, expected):
    raw = path.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != expected.lower():
        raise ValueError(f"Unpinned source {path}: {digest}")
    with gzip.GzipFile(fileobj=io.BytesIO(raw)) as source:
        xml = source.read(MAX_XML + 1)
    if len(xml) > MAX_XML:
        raise ValueError("Source XML bound exceeded")
    xml = re.sub(
        rb"&([A-Za-z][A-Za-z0-9_-]*);",
        lambda match: match.group(0)
        if match.group(1) in (b"amp", b"lt", b"gt", b"quot", b"apos")
        else match.group(1),
        xml,
    )
    return xml, digest


def verb_forms(surface, reading, tags):
    if not surface or not reading:
        return
    godan = {
        "う": ("わ", "い", "え", "お", "って", "った"),
        "く": ("か", "き", "け", "こ", "いて", "いた"),
        "ぐ": ("が", "ぎ", "げ", "ご", "いで", "いだ"),
        "す": ("さ", "し", "せ", "そ", "して", "した"),
        "つ": ("た", "ち", "て", "と", "って", "った"),
        "ぬ": ("な", "に", "ね", "の", "んで", "んだ"),
        "ぶ": ("ば", "び", "べ", "ぼ", "んで", "んだ"),
        "む": ("ま", "み", "め", "も", "んで", "んだ"),
        "る": ("ら", "り", "れ", "ろ", "って", "った"),
    }
    if surface[-1] != reading[-1]:
        return
    stem, yomi = surface[:-1], reading[:-1]
    if tags.intersection({"v1", "v1-s"}) and surface.endswith("る"):
        for tail in (
            "",
            "て",
            "た",
            "ない",
            "なかった",
            "れば",
            "よう",
            "ます",
            "ません",
            "ました",
            "ましょう",
            "られる",
        ):
            yield stem + tail, yomi + tail
    if any(tag.startswith("v5") for tag in tags) and surface[-1] in godan:
        a, i, e, o, te, ta = godan[surface[-1]]
        if "v5k-s" in tags:
            te, ta = "って", "った"
        if "v5u-s" in tags:
            te, ta = "うて", "うた"
        for tail in (
            a,
            i,
            e,
            o,
            te,
            ta,
            a + "ない",
            a + "なかった",
            i + "ます",
            i + "ません",
            i + "ました",
            i + "ましょう",
            e + "ば",
            e + "る",
            o + "う",
        ):
            yield stem + tail, yomi + tail


def derive_words(xml):
    pronunciations = defaultdict(set)
    entries = 0

    def add(surface, reading):
        if han(surface) and kana(reading) and len(surface) <= 64:
            pronunciations[surface].add(reading)

    for _, entry in ET.iterparse(io.BytesIO(xml), events=("end",)):
        if entry.tag != "entry":
            continue
        entries += 1
        surfaces = [node.findtext("keb") for node in entry.findall("k_ele")]
        senses = []
        inherited_tags = set()
        for sense in entry.findall("sense"):
            explicit_tags = {pos.text for pos in sense.findall("pos")}
            if explicit_tags:
                inherited_tags = explicit_tags
            senses.append(
                (
                    inherited_tags,
                    {node.text for node in sense.findall("stagk")},
                    {node.text for node in sense.findall("stagr")},
                )
            )
        for node in entry.findall("r_ele"):
            if node.find("re_nokanji") is not None:
                continue
            reading = hira(node.findtext("reb") or "")
            restrictions = {item.text for item in node.findall("re_restr")}
            for surface in surfaces:
                if not surface or restrictions and surface not in restrictions:
                    continue
                add(surface, reading)
                tags = set().union(
                    *(
                        tags
                        for tags, kanji_restr, kana_restr in senses
                        if (not kanji_restr or surface in kanji_restr)
                        and (
                            not kana_restr
                            or node.findtext("reb") in kana_restr
                        )
                    )
                )
                for form, yomi in verb_forms(surface, reading, tags):
                    add(form, yomi)
        entry.clear()
    unique = {
        surface: next(iter(readings))
        for surface, readings in pronunciations.items()
        if len(readings) == 1
    }
    return (
        dict(sorted(unique.items(), key=lambda kv: kv[0].encode("utf8"))),
        dict(
            sourceEntries=entries,
            surfaceForms=len(pronunciations),
            uniqueForms=len(unique),
            ambiguousForms=len(pronunciations) - len(unique),
        ),
    )


def derive_kanji(xml):
    result = {}
    for _, entry in ET.iterparse(io.BytesIO(xml), events=("end",)):
        if entry.tag != "character":
            continue
        literal = entry.findtext("literal") or ""
        if len(literal) != 1 or not han(literal):
            entry.clear()
            continue
        readings = set()
        for node in entry.findall("reading_meaning/rmgroup/reading"):
            if node.get("r_type") not in ("ja_on", "ja_kun"):
                continue
            reading = hira((node.text or "").strip("-").split(".")[0])
            if kana(reading):
                readings.add(reading)
        if readings:
            result[literal] = sorted(readings)
        entry.clear()
    return dict(sorted(result.items()))


def write_danjpsup_words(path: Path, words: dict[str, str], source: dict[str, str]):
    items = sorted(words.items(), key=lambda kv: kv[0].encode("utf8"))
    jm_sha = bytes.fromhex(source["jmdictSha256"])
    kj_sha = bytes.fromhex(source["kanjidicSha256"])
    col_ls, col_ns, col_sb = bytearray(), bytearray(), bytearray()
    col_lr, col_nr, col_rb = bytearray(), bytearray(), bytearray()
    prev_s, prev_r = b"", b""
    for idx, (surface, reading) in enumerate(items):
        sb = surface.encode("utf8")
        rb = encode_hiragana_bytes(reading)
        if not (1 <= len(sb) <= 255 and 1 <= len(rb) <= 255):
            raise ValueError("Supplemental word exceeds 255-byte entry bound")
        if idx % SUP_BLOCK == 0:
            col_ns.append(len(sb))
            col_sb.extend(sb)
            col_nr.append(len(rb))
            col_rb.extend(rb)
        else:
            ls = 0
            while ls < len(prev_s) and ls < len(sb) and prev_s[ls] == sb[ls]:
                ls += 1
            lr = 0
            while lr < len(prev_r) and lr < len(rb) and prev_r[lr] == rb[lr]:
                lr += 1
            col_ls.append(ls)
            col_ns.append(len(sb) - ls)
            col_sb.extend(sb[ls:])
            col_lr.append(lr)
            col_nr.append(len(rb) - lr)
            col_rb.extend(rb[lr:])
        prev_s, prev_r = sb, rb

    blob = bytearray()
    blob.extend(
        struct.pack("<8sIII32s32s", b"DANJPSUP", 2, len(items), SUP_BLOCK, jm_sha, kj_sha)
    )
    for col in (col_ls, col_ns, col_sb, col_lr, col_nr, col_rb):
        blob.extend(struct.pack("<I", len(col)))
        blob.extend(col)
    if len(blob) > MAX_RESOURCE:
        raise ValueError(f"Derived resource exceeds bound: {len(blob)}")
    compressed = bytearray(gzip.compress(bytes(blob), compresslevel=9, mtime=0))
    compressed[9] = 255
    path.write_bytes(compressed)
    return dict(
        path=str(path),
        entries=len(items),
        rawBytes=len(blob),
        bytes=len(compressed),
        sha256=hashlib.sha256(compressed).hexdigest(),
    )


def write_json_resource(path: Path, field: str, values: dict, source: dict):
    blob = json.dumps(
        dict(version=1, **{field: values}, source=source),
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf8")
    if len(blob) > MAX_RESOURCE:
        raise ValueError(f"Derived resource exceeds bound: {len(blob)}")
    compressed = bytearray(gzip.compress(blob, compresslevel=9, mtime=0))
    compressed[9] = 255
    path.write_bytes(compressed)
    return dict(
        path=str(path),
        entries=len(values),
        rawBytes=len(blob),
        bytes=len(compressed),
        sha256=hashlib.sha256(compressed).hexdigest(),
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("jmdict", type=Path)
    parser.add_argument("kanjidic", type=Path)
    parser.add_argument("--jmdict-sha256", required=True)
    parser.add_argument("--kanjidic-sha256", required=True)
    parser.add_argument("--output-directory", type=Path, required=True)
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args()
    jmdict, jmdict_hash = pinned_xml(args.jmdict, args.jmdict_sha256)
    kanjidic, kanjidic_hash = pinned_xml(args.kanjidic, args.kanjidic_sha256)
    words, counts = derive_words(jmdict)
    kanji = derive_kanji(kanjidic)
    source = dict(jmdictSha256=jmdict_hash, kanjidicSha256=kanjidic_hash)
    args.output_directory.mkdir(parents=True, exist_ok=True)
    resources = [
        write_danjpsup_words(
            args.output_directory / "supplemental-reading-v2.bin.gz", words, source
        ),
        write_json_resource(
            args.output_directory / "kanji-reading-v1.json.gz", "kanji", kanji, source
        ),
    ]
    report = dict(schemaVersion=2, source=source, counts=counts, resources=resources)
    args.receipt.write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf8"
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
