# Bundled original font resources

The shared desktop_lyric package is the only asset owner. Main-player and desktop-lyrics consumers use the same original font files. Font internals, glyphs, names and copyright notices are unchanged. No local subsetting, conversion or variable-font instancing was performed.

## Source Han Sans SC

- Upstream: https://github.com/adobe-fonts/source-han-sans
- Release: `2.005R`
- Commit: `6c709ca72d3d7c46ab42ebecc1a26e7d69595a37`
- Original path: `OTF/SimplifiedChinese/SourceHanSansSC-Regular.otf`
- Original Git blob: `8113ad53da18b6a08b133c6c460ae1d818a0f865`
- Bytes: `16529832`
- SHA-256: `f1d8611151880c6c336aabeac4640ef434fa13cbfbf1ffe82d0a71b2a5637256`
- Shared source asset: `third_party/desktop_lyric/assets/fonts/PingFangSC-Regular.ttf`
- Flutter alias: `DanPingFangSC`

## Source Han Sans JP

- Upstream: https://github.com/adobe-fonts/source-han-sans
- Release: `2.005R`
- Commit: `6c709ca72d3d7c46ab42ebecc1a26e7d69595a37`
- Original path: `SubsetOTF/JP/SourceHanSansJP-Regular.otf`
- Original Git blob: `5c11ef7a56fca42de83614aa7480304814b295d7`
- Bytes: `4562224`
- SHA-256: `40d1b760d1135539f6b6e0ee2b9f415de6d97576f7676840b06306c7c190c074`
- Shared source asset: `third_party/desktop_lyric/assets/fonts/SourceHanSansJP-Regular.otf`
- Flutter alias: `DanSourceHanJP`

Original license path: `LICENSE.txt`

Original license Git blob: `3ff0ccaba06857bf292ade9a50f16a0f02b3b8d4`

License SHA-256: `fcac737e761ec63dbfbdce11030a1780161920d80315edba9c8beff1c2bac5a2`

The legacy PingFangSC-Regular.ttf filename and DanPingFangSC alias identify the unchanged full Source Han Sans SC OpenType/CFF resource, not an Apple font. The Japanese resource is Adobe's original JP regional subset, not a locally modified subset.

The application source license does not replace the font's SIL Open Font License 1.1. Portable and installer payloads preserve the original OFL and this provenance.
