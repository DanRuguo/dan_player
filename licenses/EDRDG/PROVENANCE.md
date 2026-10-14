# Supplemental Japanese readings

Dan Player uses reading data from JMdict and KANJIDIC2, copyright James William
Breen and the Electronic Dictionary Research and Development Group (EDRDG).
The derived reading-only resources are distributed under CC BY-SA 4.0.
This data licence is separate from the application source licence.

- JMdict project: https://www.edrdg.org/wiki/index.php/JMdict-EDICT_Dictionary_Project
- KANJIDIC project: https://www.edrdg.org/wiki/index.php/KANJIDIC_Project
- EDRDG documentation and licence: https://www.edrdg.org/edrdg/licence.html
- CC BY-SA 4.0: https://creativecommons.org/licenses/by-sa/4.0/
- Local original documentation/licence: `LICENCE.html`, `CC-BY-SA-4.0.txt`

## Pinned sources

Both source headers identify creation on 2026-10-14. Sources were retrieved from
the publisher's public download archive on the same date:

| Source | URL | Compressed bytes | SHA-256 |
| --- | --- | ---: | --- |
| JMdict English XML | http://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz | 10585144 | 38de0c1aa1fc6b2f1460189c06182589d03c2610511bbbbf9805b8d869ae9cec |
| KANJIDIC2 XML | http://ftp.edrdg.org/pub/Nihongo/kanjidic2.xml.gz | 1488582 | c1faf3214ba58748757cb297619414d427434ee76b68eaaf31e89d707b4d4ef5 |

## Derivation and use

`rust/tools/build_supplemental_readings.py` retains headword spelling/reading
restrictions, adds standard recorded verb-class stems and conjugations, and
omits conflicting readings for automatic lexical fallback. Of 218,909 JMdict
entries, it derives 531,752 surface forms; 505,327 have a unique pronunciation,
and 26,425 conflicting forms are omitted. No translations are bundled.
KANJIDIC2 supplies Japanese on/kun stems for 12,356 characters; meanings,
Chinese readings, names, stroke/order and dictionary-reference codes are omitted.

The original IPADIC resource and its checksum remain unchanged. The supplemental
data stays in two separate compressed files beside IPADIC inside the optional
reading component. Known contextual readings use only the small
character resource for conservative, uniquely matching mono-ruby alignment.
The larger lexical map loads on the first unknown-Han fallback. No application
network request is introduced by either resource.

| Derived resource | Compressed bytes | SHA-256 |
| --- | ---: | --- |
| `rust/assets/supplemental-reading-v1.json.gz` | 3618558 | f4bf033fb622280875be6199d20d44fe2307310ea41b403a37f30c6b3a23a772 |
| `rust/assets/kanji-reading-v1.json.gz` | 106686 | 18c12298210019c8b620287b0c995ca30d8fad73542ef46d395736f4e29e49d3 |

These resources are modified extracts of the EDRDG data. They remain CC BY-SA
4.0 and may be reused under that licence with this attribution and provenance.

## Refresh procedure

For each application release, check the current official source creation dates.
Download a newer snapshot when available, record its SHA-256, and run the
derivation below with that verified snapshot. Review reading restrictions,
ambiguity counts, size/hash receipts and the pronunciation/UTF-16 regressions;
then update this provenance and the pinned resource catalog. End-user lyric
generation does not download or silently replace dictionary data.

```powershell
python rust/tools/build_supplemental_readings.py path/to/JMdict_e.gz path/to/kanjidic2.xml.gz --jmdict-sha256 <verified-hash> --kanjidic-sha256 <verified-hash> --output-directory rust/assets --receipt path/to/derived-resource.json
```
