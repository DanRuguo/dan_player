"""Build Dan's reading-only IPADIC (DANIPAD3) from the pinned upstream archive.

No vocabulary or segmentation costs are removed. Only unused display features
are replaced by '*'; identical reading records share compact Katakana storage,
and integer tables use lossless delta + byte-plane / 2D planar prediction so
deterministic gzip achieves higher compression while reconstructing identical
Lindera runtime buffers. The original NOTICE.txt must be distributed alongside
Lindera's license.
"""
import argparse
import gzip
import hashlib
import io
import pathlib
import struct
import zipfile

EXPECTED_SHA = "5ed4bba6b429030b0387df67d40d5751d35dedef0306f4bac6d957cad5f04b72"
PARTS = (
    "metadata.json",
    "char_def.bin",
    "dict.trie",
    "dict.vals",
    "dict.valsidx",
    "dict.words",
    "dict.wordsidx",
    "matrix.mtx",
    "unk.bin",
)


def _split_planes(data: bytes, width: int) -> bytes:
    if len(data) % width != 0:
        raise ValueError("Invalid plane width alignment")
    mv = memoryview(data)
    return b"".join(bytes(mv[p::width]) for p in range(width))


def pack_danipad3(files: dict[str, bytes]) -> bytes:
    vals = files["dict.vals"]
    if len(vals) % 10:
        raise ValueError("Invalid dict.vals alignment")
    n_vals = len(vals) // 10
    dwids, dlids, drids, dcosts = [], [], [], []
    pw = pl = pc = 0
    for i in range(n_vals):
        wid, lid, rid, cost = struct.unpack_from("<IHHh", vals, i * 10)
        u_cost = cost & 0xFFFF
        dwids.append((wid - pw) & 0xFFFFFFFF)
        dlids.append((lid - pl) & 0xFFFF)
        drids.append((rid - lid) & 0xFFFF)
        dcosts.append((u_cost - pc) & 0xFFFF)
        pw, pl, pc = wid, lid, u_cost
    vals_packed = (
        struct.pack("<I", n_vals)
        + _split_planes(struct.pack(f"<{n_vals}I", *dwids), 4)
        + _split_planes(struct.pack(f"<{n_vals}H", *dlids), 2)
        + _split_planes(struct.pack(f"<{n_vals}H", *drids), 2)
        + _split_planes(struct.pack(f"<{n_vals}H", *dcosts), 2)
    )

    vidx = files["dict.valsidx"]
    if len(vidx) % 8:
        raise ValueError("Invalid dict.valsidx alignment")
    nv = len(vidx) // 8
    da0, da1 = [], []
    pa0 = pa1 = 0
    for i in range(nv):
        a0, a1 = struct.unpack_from("<II", vidx, i * 8)
        da0.append((a0 - pa0) & 0xFFFFFFFF)
        da1.append((a1 - pa1) & 0xFFFFFFFF)
        pa0, pa1 = a0, a1
    valsidx_packed = (
        struct.pack("<I", nv)
        + _split_planes(struct.pack(f"<{nv}I", *da0), 4)
        + _split_planes(struct.pack(f"<{nv}I", *da1), 4)
    )

    words, widx = files["dict.words"], files["dict.wordsidx"]
    if len(widx) % 4:
        raise ValueError("Invalid dict.wordsidx alignment")
    nw = len(widx) // 4
    pos = 0
    yomis = []
    off_to_yid = {}
    while pos < len(words):
        off_to_yid[pos] = len(yomis)
        ln = struct.unpack_from("<I", words, pos)[0]
        fields = words[pos + 4 : pos + 4 + ln].decode("utf8").split("\0")
        if len(fields) != 9:
            raise ValueError("Unexpected detail schema")
        yomis.append(fields[7])
        pos += 4 + ln

    yomi_lens = bytearray()
    yomi_stream = bytearray()
    for yomi in yomis:
        eb = bytearray()
        for ch in yomi:
            cp = ord(ch)
            if 0x30A1 <= cp <= 0x30FC:
                eb.append(0x80 + (cp - 0x30A1))
            elif 0 < cp < 0x80:
                eb.append(cp)
            else:
                u8 = ch.encode("utf8")
                eb.append(0xFF)
                eb.append(len(u8))
                eb.extend(u8)
        if len(eb) > 255:
            raise ValueError("Oversized yomi entry")
        yomi_lens.append(len(eb))
        yomi_stream.extend(eb)

    dyids = []
    pyid = 0
    for i in range(nw):
        yid = off_to_yid[struct.unpack_from("<I", widx, i * 4)[0]]
        dyids.append((yid - pyid) & 0xFFFFFFFF)
        pyid = yid
    words_packed = (
        struct.pack("<III", len(yomis), nw, len(yomi_stream))
        + bytes(yomi_lens)
        + bytes(yomi_stream)
        + _split_planes(struct.pack(f"<{nw}I", *dyids), 4)
    )

    mtx = files["matrix.mtx"]
    magic, rows, cols = struct.unpack_from("<HHH", mtx, 0)
    if magic != 0xFFFF or 6 + rows * cols * 2 != len(mtx):
        raise ValueError("Unexpected matrix.mtx layout")
    grid = struct.unpack_from(f"<{rows * cols}h", mtx, 6)
    d2 = []
    for i, val in enumerate(grid):
        r, c = divmod(i, cols)
        if r == 0 and c == 0:
            pred = 0
        elif r == 0:
            pred = grid[i - 1]
        elif c == 0:
            pred = grid[i - cols]
        else:
            pred = grid[i - 1] + grid[i - cols] - grid[i - cols - 1]
        d2.append((val - pred) & 0xFFFF)
    matrix_packed = mtx[:6] + _split_planes(struct.pack(f"<{len(d2)}H", *d2), 2)

    pack = bytearray(b"DANIPAD3")
    for chunk in (
        files["metadata.json"],
        files["char_def.bin"],
        files["dict.trie"],
        vals_packed,
        valsidx_packed,
        words_packed,
        matrix_packed,
        files["unk.bin"],
    ):
        pack += struct.pack("<I", len(chunk)) + chunk
    return bytes(pack)


def build(source: pathlib.Path, output: pathlib.Path):
    raw = source.read_bytes()
    if hashlib.sha256(raw).hexdigest() != EXPECTED_SHA:
        raise ValueError("Expected official lindera-ipadic-6.2.0.zip")
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        files = {name: archive.read("lindera-ipadic/" + name) for name in PARTS}
    words, indexes, shared = bytearray(), bytearray(), {}
    original, index = files["dict.words"], files["dict.wordsidx"]
    if len(index) % 4:
        raise ValueError("Invalid upstream word index")
    for word_id in range(len(index) // 4):
        offset = struct.unpack_from("<I", index, word_id * 4)[0]
        length = struct.unpack_from("<I", original, offset)[0]
        fields = original[offset + 4 : offset + 4 + length].decode("utf8").split("\0")
        if len(fields) != 9:
            raise ValueError("Unexpected upstream detail schema")
        detail = "\0".join(["*"] * 7 + [fields[7], "*"]).encode("utf8")
        if detail not in shared:
            shared[detail] = len(words)
            words += struct.pack("<I", len(detail)) + detail
        indexes += struct.pack("<I", shared[detail])
    files["dict.words"], files["dict.wordsidx"] = bytes(words), bytes(indexes)
    pack = pack_danipad3(files)
    result = bytearray(gzip.compress(pack, compresslevel=9, mtime=0))
    result[9] = 255  # Fixed OS byte makes Windows/Linux header identical.
    output.write_bytes(result)
    print(
        f"{len(index) // 4} entries; packed={len(pack)}; "
        f"gzip={len(result)}; sha256={hashlib.sha256(result).hexdigest()}"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("upstream_zip", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    args = parser.parse_args()
    build(args.upstream_zip, args.output)
