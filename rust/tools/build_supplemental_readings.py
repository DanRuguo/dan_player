"""Derive offline lexical/kanji readings from pinned EDRDG XML snapshots.

The derived data is CC BY-SA 4.0. No definitions, translations, names, or
guessed character pronunciations are included. Reading restrictions are kept;
conflicting pronunciations never become an automatic lexical fallback.
The two resources load separately so ordinary known words need no large map.
Refresh by fetching official JMdict_e.gz and kanjidic2.xml.gz, checking their
headers/provenance, running this tool with their SHA-256 values, and reviewing
the resulting counts/hashes and the pronunciation regression checks.
"""
import argparse
from collections import defaultdict
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import unicodedata
import xml.etree.ElementTree as ET

MAX_XML = 256 * 1024 * 1024
MAX_RESOURCE = 64 * 1024 * 1024

def han(text):
    return any(0x3400 <= ord(c) <= 0x9fff or 0xf900 <= ord(c) <= 0xfaff or
               0x20000 <= ord(c) <= 0x323af for c in text)

def hira(text):
    return ''.join(chr(ord(c) - 0x60) if 0x30a1 <= ord(c) <= 0x30f6 else c
                   for c in unicodedata.normalize('NFKC', text))

def kana(text):
    return bool(text) and all(0x3041 <= ord(c) <= 0x3096 or c in 'ーゝゞ' for c in text)

def pinned_xml(path, expected):
    raw = path.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != expected.lower():
        raise ValueError(f'Unpinned source {path}: {digest}')
    with gzip.GzipFile(fileobj=io.BytesIO(raw)) as source:
        xml = source.read(MAX_XML + 1)
    if len(xml) > MAX_XML:
        raise ValueError('Source XML bound exceeded')
    # Keep standardized POS/reading-info entity *codes* instead of their prose
    # descriptions. The five XML built-ins/numeric escapes remain standard XML.
    xml = re.sub(rb'&([A-Za-z][A-Za-z0-9_-]*);',
                 lambda match: match.group(0) if match.group(1) in
                 (b'amp', b'lt', b'gt', b'quot', b'apos') else match.group(1), xml)
    return xml, digest

def verb_forms(surface, reading, tags):
    if not surface or not reading:
        return
    godan = {'う': ('わ', 'い', 'え', 'お', 'って', 'った'),
             'く': ('か', 'き', 'け', 'こ', 'いて', 'いた'),
             'ぐ': ('が', 'ぎ', 'げ', 'ご', 'いで', 'いだ'),
             'す': ('さ', 'し', 'せ', 'そ', 'して', 'した'),
             'つ': ('た', 'ち', 'て', 'と', 'って', 'った'),
             'ぬ': ('な', 'に', 'ね', 'の', 'んで', 'んだ'),
             'ぶ': ('ば', 'び', 'べ', 'ぼ', 'んで', 'んだ'),
             'む': ('ま', 'み', 'め', 'も', 'んで', 'んだ'),
             'る': ('ら', 'り', 'れ', 'ろ', 'って', 'った')}
    if surface[-1] != reading[-1]:
        return
    stem, yomi = surface[:-1], reading[:-1]
    if tags.intersection({'v1', 'v1-s'}) and surface.endswith('る'):
        for tail in ('', 'て', 'た', 'ない', 'なかった', 'れば', 'よう',
                     'ます', 'ません', 'ました', 'ましょう', 'られる'):
            yield stem + tail, yomi + tail
    if any(tag.startswith('v5') for tag in tags) and surface[-1] in godan:
        a, i, e, o, te, ta = godan[surface[-1]]
        if 'v5k-s' in tags:
            te, ta = 'って', 'った'
        if 'v5u-s' in tags:
            te, ta = 'うて', 'うた'
        for tail in (a, i, e, o, te, ta, a + 'ない', a + 'なかった',
                     i + 'ます', i + 'ません', i + 'ました', i + 'ましょう',
                     e + 'ば', e + 'る', o + 'う'):
            yield stem + tail, yomi + tail

def derive_words(xml):
    pronunciations = defaultdict(set)
    entries = 0
    def add(surface, reading):
        if han(surface) and kana(reading) and len(surface) <= 64:
            pronunciations[surface].add(reading)
    for _, entry in ET.iterparse(io.BytesIO(xml), events=('end',)):
        if entry.tag != 'entry':
            continue
        entries += 1
        surfaces = [node.findtext('keb') for node in entry.findall('k_ele')]
        senses = []
        inherited_tags = set()
        for sense in entry.findall('sense'):
            explicit_tags = {pos.text for pos in sense.findall('pos')}
            if explicit_tags:
                inherited_tags = explicit_tags
            senses.append((inherited_tags,
                           {node.text for node in sense.findall('stagk')},
                           {node.text for node in sense.findall('stagr')}))
        for node in entry.findall('r_ele'):
            if node.find('re_nokanji') is not None:
                continue
            reading = hira(node.findtext('reb') or '')
            restrictions = {item.text for item in node.findall('re_restr')}
            for surface in surfaces:
                if not surface or restrictions and surface not in restrictions:
                    continue
                add(surface, reading)
                tags = set().union(*(tags for tags, kanji_restr, kana_restr in senses
                    if (not kanji_restr or surface in kanji_restr) and
                       (not kana_restr or node.findtext('reb') in kana_restr)))
                for form, yomi in verb_forms(surface, reading, tags):
                    add(form, yomi)
        entry.clear()
    unique = {surface: next(iter(readings)) for surface, readings in pronunciations.items()
              if len(readings) == 1}
    return dict(sorted(unique.items())), dict(sourceEntries=entries,
        surfaceForms=len(pronunciations), uniqueForms=len(unique),
        ambiguousForms=len(pronunciations) - len(unique))

def derive_kanji(xml):
    result = {}
    for _, entry in ET.iterparse(io.BytesIO(xml), events=('end',)):
        if entry.tag != 'character':
            continue
        literal = entry.findtext('literal') or ''
        if len(literal) != 1 or not han(literal):
            entry.clear()
            continue
        readings = set()
        for node in entry.findall('reading_meaning/rmgroup/reading'):
            if node.get('r_type') not in ('ja_on', 'ja_kun'):
                continue
            # Okurigana stays in source Kana. The stem identifies the Han part.
            reading = hira((node.text or '').strip('-').split('.')[0])
            if kana(reading):
                readings.add(reading)
        if readings:
            result[literal] = sorted(readings)
        entry.clear()
    return dict(sorted(result.items()))

def write_resource(path, field, values, source):
    blob = json.dumps(dict(version=1, **{field: values}, source=source),
                      ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode('utf8')
    if len(blob) > MAX_RESOURCE:
        raise ValueError(f'Derived resource exceeds bound: {len(blob)}')
    compressed = bytearray(gzip.compress(blob, compresslevel=9, mtime=0))
    compressed[9] = 255
    path.write_bytes(compressed)
    return dict(path=str(path), entries=len(values), rawBytes=len(blob),
                bytes=len(compressed), sha256=hashlib.sha256(compressed).hexdigest())

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('jmdict', type=Path)
    parser.add_argument('kanjidic', type=Path)
    parser.add_argument('--jmdict-sha256', required=True)
    parser.add_argument('--kanjidic-sha256', required=True)
    parser.add_argument('--output-directory', type=Path, required=True)
    parser.add_argument('--receipt', type=Path, required=True)
    args = parser.parse_args()
    jmdict, jmdict_hash = pinned_xml(args.jmdict, args.jmdict_sha256)
    kanjidic, kanjidic_hash = pinned_xml(args.kanjidic, args.kanjidic_sha256)
    words, counts = derive_words(jmdict)
    kanji = derive_kanji(kanjidic)
    source = dict(jmdictSha256=jmdict_hash, kanjidicSha256=kanjidic_hash)
    args.output_directory.mkdir(parents=True, exist_ok=True)
    resources = [write_resource(args.output_directory / 'supplemental-reading-v1.json.gz', 'words', words, source),
                 write_resource(args.output_directory / 'kanji-reading-v1.json.gz', 'kanji', kanji, source)]
    report = dict(schemaVersion=1, source=source, counts=counts, resources=resources)
    args.receipt.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
    print(json.dumps(report, ensure_ascii=False, indent=2))

if __name__ == '__main__':
    main()
