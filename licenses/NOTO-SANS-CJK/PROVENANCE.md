# Bundled UI font

The main player and desktop lyrics bundle the unmodified **Noto Sans CJK SC Regular 2.004** font under the SIL Open Font License 1.1. Its original copyright notices are embedded in the font's name table and reproduced in `NOTICE.txt`; the upstream license is included as `OFL.txt`.

- Upstream: https://github.com/notofonts/noto-cjk
- Release: `Sans2.004`
- Commit: `523d033d6cb47f4a80c58a35753646f5c3608a78`
- Original path: `Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf`
- Upstream Git blob: `dc15562470b4f842321894787a0d066879ccff8b`
- Size: `16437364` bytes
- SHA-256: `2c76254f6fc379fddfce0a7e84fb5385bb135d3e399294f6eeb6680d0365b74b`
- Original license path: `LICENSE`
- License SHA-256: `6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2`

For existing settings, font loaders, native interfaces and test fixtures, the Flutter family alias `DanPingFangSC` and the asset paths `assets/fonts/PingFangSC-Regular.ttf` in both projects are retained as compatibility identifiers. The actual bytes are the OpenType/CFF Noto font above; they are not an Apple PingFang font. No font internals, glyphs, names or copyright notices have been modified. Windows private-font loading resolves its real family name.

The player source license does not replace the font's OFL license. Signed portable and installer payloads include this provenance and the upstream license in `licenses/NOTO-SANS-CJK/`.
