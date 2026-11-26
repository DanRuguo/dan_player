# Offline Japanese reading dictionary

The native Japanese reading worker uses the Windows analyzer when it returns a
complete result, and can fall back to Lindera 6.2.0 with the optional IPADIC
dictionary module. The analyzer shares the existing Rust DLL; the dictionary is
not embedded in the DLL. Additional lexical/character readings are separate
files in the same optional module; see [EDRDG provenance](../EDRDG/PROVENANCE.md).
The complete portable package includes the data module;
the slim installer leaves it optional and preserves an existing copy. The verified compressed
module is read into memory only on the first fallback request. Installation is
explicit, supports a manual local copy, and does not install another executable.

- Upstream: https://github.com/lindera/lindera/releases/tag/v6.2.0
- Original archive: `lindera-ipadic-6.2.0.zip`
- Original archive bytes: `10519550`
- Original archive SHA-256: `5ed4bba6b429030b0387df67d40d5751d35dedef0306f4bac6d957cad5f04b72`
- Source dictionary: `mecab-ipadic-2.7.0-20070801`, in Lindera format version 2.
- Generated resource: `rust/assets/ipadic-reading.bin.gz`
- Resource bytes: `5185623`
- Resource SHA-256: `bc2e100b3d11e41038dd3fbaacfbd843c081a3d18c6105320220b36a667b7ee9`

All 392,126 word entries, trie, values, costs, character definitions, unknown-word
rules and metadata are retained. Of the nine word-detail fields, only the reading
is used by this feature. The other eight are replaced with `*`; duplicate detail
records share compact 1-byte Katakana storage, and integer tables (`vals`, `valsidx`,
`wordsidx`, `matrix.mtx`) use lossless delta/2D prediction and byte-plane splitting
after the `DANIPAD3` header before deterministic gzip compression, reconstructing
identical Lindera runtime buffers on load. Legacy `DANIPAD2` (`a8acd8b6...`) remains
accepted for previously installed slim-installer copies.

Rebuild from the pinned original archive with:

```powershell
python rust/tools/build_japanese_dictionary.py path/to/lindera-ipadic-6.2.0.zip rust/assets/ipadic-reading.bin.gz
```

`NOTICE.txt` is copied byte for byte from the original dictionary archive and
includes the NAIST and ICOT distribution conditions and warranty disclaimer.
The analyzer's original MIT license is in `licenses/LINDERA/LICENSE`. These
notices apply separately from the application source license.
