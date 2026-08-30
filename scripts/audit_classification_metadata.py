"""Read-only ID3/Vorbis classification audit; emits aggregate counts, not lyrics.

Usage: python scripts/audit_classification_metadata.py <music-directory>
Only metadata blocks are read. No source files, settings, or index are written.
The optional --descriptors mode emits private absolute paths and tag values for
an isolated local probe. Never commit or publish its stdout or captured logs.
"""

import collections
import json
import pathlib
import re
import struct
import sys


def syncsafe(value):
    result = 0
    for byte in value:
        result = (result << 7) | (byte & 127)
    return result


def id3_text(value):
    if not value:
        return ""
    encoding = {0: "latin-1", 1: "utf-16", 2: "utf-16-be", 3: "utf-8"}[value[0]]
    return value[1:].decode(encoding, errors="replace").strip("\x00\ufeff ")


def terminated(value, width):
    for index in range(0, len(value) - width + 1, width):
        if value[index : index + width] == b"\0" * width:
            return value[:index], value[index + width :]
    return value, b""


def ape_metadata(stream, tags):
    """Inspect an optional APEv2 footer, including before an ID3v1 trailer."""
    length = stream.seek(0, 2)
    footer_end = length
    if length >= 128:
        stream.seek(length - 128)
        if stream.read(3) == b"TAG":
            footer_end -= 128
    if footer_end < 32:
        return
    stream.seek(footer_end - 32)
    footer = stream.read(32)
    if footer[:8] != b"APETAGEX":
        return
    _, size, count = struct.unpack_from("<III", footer, 8)
    if size < 32 or size > min(footer_end, 64 * 1024 * 1024):
        raise ValueError("invalid_ape_size")
    stream.seek(footer_end - size)
    data = stream.read(size - 32)
    position = 0
    for _ in range(count):
        value_length, flags = struct.unpack_from("<II", data, position)
        position += 8
        key_end = data.index(b"\0", position)
        key = data[position:key_end].decode("ascii", errors="replace").upper()
        position = key_end + 1
        value = data[position:position + value_length]
        position += value_length
        if ((flags >> 1) & 3) == 0:
            tags["APE_" + key].append(value.decode("utf-8", errors="replace"))
    tags["composer"] += tags["APE_COMPOSER"]
    tags["language"] += tags["APE_LANGUAGE"]
    tags["lyrics"] += tags["APE_LYRICS"] + tags["APE_UNSYNCEDLYRICS"]


def metadata(file):
    tags = collections.defaultdict(list)
    with file.open("rb") as stream:
        header = stream.read(10)
        if header[:3] == b"ID3":
            version, flags = header[3], header[5]
            length = syncsafe(header[6:10])
            if length > 64 * 1024 * 1024:
                raise ValueError("oversized_id3")
            data = stream.read(length)
            if flags & 0x80:
                data = data.replace(b"\xff\0", b"\xff")
            position = 0
            if flags & 0x40 and version >= 3:
                position = syncsafe(data[:4]) if version == 4 else 4 + int.from_bytes(data[:4], "big")
            while position + (6 if version == 2 else 10) <= len(data):
                header_size = 6 if version == 2 else 10
                identifier_size = 3 if version == 2 else 4
                frame = data[position : position + header_size]
                name = frame[:identifier_size].decode("ascii", errors="replace")
                if not re.fullmatch(r"[A-Z0-9]{3,4}", name):
                    break
                size = syncsafe(frame[4:8]) if version == 4 else int.from_bytes(frame[identifier_size:identifier_size + (3 if version == 2 else 4)], "big")
                body = data[position + header_size : position + header_size + size]
                position += header_size + size
                if not body:
                    continue
                if name in {"USLT", "ULT"}:
                    width = 2 if body[0] in (1, 2) else 1
                    _, lyric = terminated(body[4:], width)
                    tags["lyrics"].append(id3_text(body[:1] + lyric))
                elif name.startswith("T"):
                    text = id3_text(body)
                    if name in {"TXXX", "TXX"}:
                        key, _, value = text.partition("\x00")
                        tags[key.upper()].append(value)
                    else:
                        tags[name].append(text)
            tags["composer"] += tags["TCOM"] + tags["TCM"] + tags["COMPOSER"]
            tags["language"] += tags["TLAN"] + tags["TLA"] + tags["LANGUAGE"]
            tags["lyrics"] += tags["LYRICS"] + tags["UNSYNCEDLYRICS"]
        elif header[:4] == b"fLaC":
            stream.seek(4)
            while True:
                block = stream.read(4)
                if len(block) != 4:
                    break
                kind = block[0] & 127
                size = int.from_bytes(block[1:], "big")
                if kind == 4:
                    data = stream.read(size)
                    offset = 4 + struct.unpack_from("<I", data)[0]
                    count = struct.unpack_from("<I", data, offset)[0]
                    offset += 4
                    for _ in range(count):
                        length = struct.unpack_from("<I", data, offset)[0]
                        offset += 4
                        text = data[offset : offset + length].decode("utf-8", errors="replace")
                        offset += length
                        key, _, value = text.partition("=")
                        tags[key.upper()].append(value)
                else:
                    stream.seek(size, 1)
                if block[0] & 128:
                    break
            tags["composer"] += tags["COMPOSER"]
            tags["language"] += tags["LANGUAGE"]
            tags["lyrics"] += tags["LYRICS"] + tags["UNSYNCEDLYRICS"]
        ape_metadata(stream, tags)
    return tags


def main():
    counts = collections.Counter()
    language_tags = collections.Counter()
    credit_labels = collections.Counter()
    failures = collections.Counter()
    tag_counts = collections.Counter()
    extension_keys = collections.Counter()
    for file in pathlib.Path(sys.argv[1]).rglob("*"):
        if not file.is_file() or file.suffix.lower() not in {".mp3", ".flac"}:
            continue
        counts["audio_files"] += 1
        try:
            tags = metadata(file)
            tag_counts.update(key for key, values in tags.items() if any(values))
            for value in tags["EXTEND"]:
                try:
                    decoded = json.loads(value)
                    if isinstance(decoded, dict):
                        extension_keys.update(decoded.keys())
                except (ValueError, TypeError):
                    extension_keys["non_json"] += 1
            composers = [value for value in tags["composer"] if value.strip()]
            contributors = [value for value in
                tags["TPE1"] + tags["TP1"] + tags["ARTIST"] + tags["APE_ARTIST"]
                if value.strip() and value.strip().upper() != "UNKNOWN"]
            if composers:
                counts["composer_tag_tracks"] += 1
            if contributors:
                counts["contributing_artist_tag_tracks"] += 1
            for value in tags["language"]:
                language_tags[value] += 1
            if any(value.strip() for value in tags["language"]):
                counts["language_tag_tracks"] += 1
            lyrics = "\n".join(tags["lyrics"])
            sidecar = file.with_suffix(".lrc")
            if sidecar.is_file():
                counts["sidecar_lrc_tracks"] += 1
            if not lyrics.strip():
                if not composers and contributors:
                    counts["contributor_fallback_tracks"] += 1
                continue
            counts["embedded_lyric_tracks"] += 1
            if "\ufffd" in lyrics:
                counts["lyric_decoding_replacement_tracks"] += 1
            credit_found = False
            seen_times = set()
            duplicate_times = False
            for line in lyrics.splitlines():
                timestamps = re.findall(r"\[(\d+:\d+(?:\.\d+)?)\]", line)
                if any(value in seen_times for value in timestamps):
                    duplicate_times = True
                seen_times.update(timestamps)
                text = re.sub(r"\[[\d:.]+\]", "", line).strip()
                credit = re.match(r"^(作曲|词曲|詞曲|曲|Composer|Composed by|Music by|Composition|作曲者|작곡)\s*[:：]\s*(.+)$", text, re.IGNORECASE)
                if credit:
                    credit_found = True
                    credit_labels[credit.group(1).lower()] += 1
            if credit_found:
                counts["explicit_composer_lyric_tracks"] += 1
                if not composers:
                    counts["composer_recoverable_without_tag_tracks"] += 1
            if duplicate_times:
                counts["duplicate_timestamp_lyric_tracks"] += 1
            if not composers and not credit_found and contributors:
                counts["contributor_fallback_tracks"] += 1
        except (OSError, ValueError, KeyError, IndexError, struct.error) as error:
            failure = type(error).__name__
            if isinstance(error, OSError) and isinstance(error.errno, int):
                failure += f" (errno={error.errno})"
            failures[failure] += 1
    print(json.dumps({"counts": counts, "language_tag_values": language_tags, "composer_credit_labels": credit_labels, "extension_keys": extension_keys, "tag_counts": tag_counts, "failures": failures}, ensure_ascii=True, indent=2))


def descriptor_json():
    """Private paths/tags for a local probe, not publishable logs; no lyrics."""
    descriptors = []
    for file in pathlib.Path(sys.argv[1]).rglob("*"):
        if not file.is_file() or file.suffix.lower() not in {".mp3", ".flac"}:
            continue
        tags = metadata(file)

        def first(*keys):
            for key in keys:
                for value in tags[key]:
                    if value.strip() and value.strip().upper() != "UNKNOWN":
                        return value.strip()
            return None

        descriptors.append({
            "path": str(file.resolve()),
            "title": first("TIT2", "TT2", "TITLE", "APE_TITLE") or file.name,
            "artist": first("TPE1", "TP1", "ARTIST", "APE_ARTIST", "TPE2", "ALBUMARTIST", "composer") or "UNKNOWN",
            "album": first("TALB", "TAL", "ALBUM", "APE_ALBUM") or "UNKNOWN",
            "composer": first("composer"),
            "album_artist": first("TPE2", "ALBUMARTIST", "APE_ALBUMARTIST"),
            "language": first("language"),
        })
    print(json.dumps(descriptors, ensure_ascii=True))


if __name__ == "__main__":
    descriptor_json() if "--descriptors" in sys.argv[2:] else main()
