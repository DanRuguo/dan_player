"""Build Dan's reading-only IPADIC from the pinned upstream release archive.

No vocabulary or segmentation costs are removed. Only unused display features
are replaced by '*'; identical reading records share storage. The original
NOTICE.txt must be distributed by the application alongside Lindera's license.
"""
import argparse, gzip, hashlib, io, pathlib, struct, zipfile
EXPECTED_SHA = "5ed4bba6b429030b0387df67d40d5751d35dedef0306f4bac6d957cad5f04b72"
PARTS = ("metadata.json", "char_def.bin", "dict.trie", "dict.vals", "dict.valsidx",
         "dict.words", "dict.wordsidx", "matrix.mtx", "unk.bin")

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
        fields = original[offset + 4:offset + 4 + length].decode("utf8").split("\0")
        if len(fields) != 9:
            raise ValueError("Unexpected upstream detail schema")
        detail = "\0".join(["*"] * 7 + [fields[7], "*"]).encode("utf8")
        if detail not in shared:
            shared[detail] = len(words)
            words += struct.pack("<I", len(detail)) + detail
        indexes += struct.pack("<I", shared[detail])
    files["dict.words"], files["dict.wordsidx"] = words, indexes
    pack = bytearray(b"DANIPAD2")
    for name in PARTS:
        data = files[name]
        pack += struct.pack("<I", len(data)) + data
    result = bytearray(gzip.compress(pack, compresslevel=9, mtime=0))
    result[9] = 255  # Fixed OS byte makes Windows/Linux header identical.
    output.write_bytes(result)
    print(f"{len(index) // 4} entries; packed={len(pack)}; gzip={len(result)}; sha256={hashlib.sha256(result).hexdigest()}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("upstream_zip", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    args = parser.parse_args()
    build(args.upstream_zip, args.output)