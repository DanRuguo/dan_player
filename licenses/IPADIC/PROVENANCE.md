# Offline Japanese reading dictionary

The native Japanese reading worker uses the Windows analyzer when it returns a
complete result, and can fall back to Lindera 6.2.0 with the optional IPADIC
dictionary module. The analyzer shares the existing Rust DLL; the dictionary is
not embedded in the DLL. The complete portable package includes the data module;
the slim installer leaves it optional and preserves an existing copy. The verified compressed
module is read into memory only on the first fallback request. Installation is
explicit, supports a manual local copy, and does not install another executable.

- Upstream: https://github.com/lindera/lindera/releases/tag/v6.2.0
- Original archive: `lindera-ipadic-6.2.0.zip`
- Original archive bytes: `10519550`
- Original archive SHA-256: `5ed4bba6b429030b0387df67d40d5751d35dedef0306f4bac6d957cad5f04b72`
- Source dictionary: `mecab-ipadic-2.7.0-20070801`, in Lindera format version 2.
- Generated resource: `rust/assets/ipadic-reading.bin.gz`
- Resource bytes: `7180257`
- Resource SHA-256: `a8acd8b6352774fe3f6ac3fdbec59313ce04b548dad84340c17f0ee4bfab6e43`

All 392,126 word entries, trie, values, costs, character definitions, unknown-word
rules and metadata are retained. Of the nine word-detail fields, only the reading
is used by this feature. The other eight are replaced with `*`; duplicate detail
records share storage and the word-detail index is rewritten accordingly.
Vocabulary, segmentation costs and readings are not trimmed. The packed resource
contains nine length-prefixed parts after the `DANIPAD2` header and uses
deterministic gzip compression.

Rebuild from the pinned original archive with:

```powershell
python rust/tools/build_japanese_dictionary.py path/to/lindera-ipadic-6.2.0.zip rust/assets/ipadic-reading.bin.gz
```

`NOTICE.txt` is copied byte for byte from the original dictionary archive and
includes the NAIST and ICOT distribution conditions and warranty disclaimer.
The analyzer's original MIT license is in `licenses/LINDERA/LICENSE`. These
notices apply separately from the application source license.
