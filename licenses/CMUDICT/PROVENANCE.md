# CMU Pronouncing Dictionary (CMUDict) Provenance

- **Upstream project**: Carnegie Mellon University Pronouncing Dictionary (`cmusphinx/cmudict`)
- **Upstream repository**: https://github.com/cmusphinx/cmudict
- **License**: BSD-2-Clause (`LICENSE` in this directory)
- **Source file**: `cmudict.dict`
  - Size: 3,618,488 bytes
  - SHA-256: `81917843c7f44ce2b094ac63873c2c7a4cf802040792c455ba3ca406891c3d22`
- **Compiled DanPlayer asset**: `assets/dictionaries/cmudict_ipa.bin.gz`
  - Format: `DANENG01` blocked prefix-compressed General American IPA lexicon (123,985 entries, 3,875 blocks)
  - Size: 854,480 bytes (gzip level 9, deterministic `mtime=0`)
  - SHA-256: `4686d7e43ba4e4fc9d0e9cbcbbac44763f1c48321ba68a08b5fba5e55ad09171`
  - Generator: `rust/tools/build_english_phonetics.py`
- **Transformations applied**:
  1. Primary ARPABET pronunciations converted to General American IPA with Maximal Onset syllabification and stress placement (`ˈ` / `ˌ`).
  2. Restricted 1- and 2-letter keys to genuine English words to minimize false positives on non-English Latin lyrics.
  3. Added curated song-lyric colloquial contractions and homograph disambiguations.
