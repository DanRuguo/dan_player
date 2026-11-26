<div align="center">

<p>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/player-icon-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="docs/images/player-icon-light.png">
    <img src="docs/images/player-icon-light.png" alt="Dan Player application icon" width="128">
  </picture>
</p>

<h1>Dan Player</h1>

<p><strong>Designed for your local music collection.</strong></p>

<p>A local-first Windows x64 music player crafted with Material 3 Expressive,<br>
combining library organization, bilingual phonetic lyrics, high-fidelity playback and low-power desktop integration.</p>

<p align="center">
  <a href="https://github.com/DanRuguo/dan_player/releases/latest"><img src="https://img.shields.io/github/v/release/DanRuguo/dan_player?style=flat&amp;labelColor=374151&amp;label=stable&amp;logo=github&amp;logoColor=white&amp;color=2563EB" alt="Latest stable release"></a>
  <a href="https://github.com/DanRuguo/dan_player/releases"><img src="https://img.shields.io/github/v/release/DanRuguo/dan_player?style=flat&amp;labelColor=374151&amp;include_prereleases&amp;filter=v%2A-snapshot.%2A&amp;sort=semver&amp;label=preview&amp;color=D97706" alt="Latest snapshot preview"></a>
  <a href="https://github.com/DanRuguo/dan_player/releases"><img src="https://img.shields.io/github/downloads/DanRuguo/dan_player/total?style=flat&amp;labelColor=374151&amp;label=downloads&amp;color=059669" alt="GitHub Release asset downloads"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/DanRuguo/dan_player?style=flat&amp;labelColor=374151&amp;label=license&amp;color=64748B" alt="Project license"></a>
</p>

<p align="center">
  <a href="#download"><img src="https://img.shields.io/badge/platform-Windows%20x64-0078D4?style=flat&amp;labelColor=374151" alt="Platform: Windows x64"></a>
  <a href="#development"><img src="https://img.shields.io/badge/Flutter-UI-02569B?style=flat&amp;labelColor=374151&amp;logo=flutter&amp;logoColor=white" alt="Flutter: UI"></a>
  <a href="#development"><img src="https://img.shields.io/badge/Rust-Bridge-B45309?style=flat&amp;labelColor=374151&amp;logo=rust&amp;logoColor=white" alt="Rust: native bridge"></a>
  <a href="https://www.un4seen.com/bass.html"><img src="https://img.shields.io/badge/BASS-Audio-6750A4?style=flat&amp;labelColor=374151" alt="BASS: audio playback"></a>
</p>

<p>
  <a href="https://github.com/DanRuguo/dan_player/releases/latest"><strong>Download stable</strong></a> ·
  <a href="https://github.com/DanRuguo/dan_player/releases">Previews &amp; all releases</a> ·
  <a href="https://github.com/DanRuguo/dan_player/releases">Release notes</a> ·
  <a href="https://github.com/DanRuguo/dan_player/issues/new/choose">Report an issue</a>
</p>

<p>
  <a href="README.md">简体中文</a> ·
  <strong>English</strong> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a>
</p>

</div>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/library-dark-wide.png">
    <source media="(prefers-color-scheme: light)" srcset="docs/images/library-light-wide.png">
    <img src="docs/images/library-light-wide.png" alt="Dan Player library page with Material 3 Expressive controls and floating playback bar, using fictional demo data" width="1200">
  </picture>
</p>

<p align="center">
  <a href="#download">Download</a> ·
  <a href="#features">Highlights</a> ·
  <a href="#screenshots">Interface gallery</a> ·
  <a href="#quick-start">Getting started</a> ·
  <a href="#development">Development</a>
</p>

<a id="download"></a>

## Download & install

| Channel | Best for | Download |
| --- | --- | --- |
| **Latest stable** | Everyday listening and in-place upgrades | [Stable installer, portable ZIP & checksums](https://github.com/DanRuguo/dan_player/releases/latest) |
| **Preview (Snapshot)** | Trying the latest UI redesign, phonetic lyrics and audio features | [Snapshot releases & optional components](https://github.com/DanRuguo/dan_player/releases) |

**Installer:** features a Material 3 Expressive setup wizard, supports in-place upgrades and preserves optional components already installed. **Portable:** extract the entire ZIP and launch `Dan Player.exe`—do not copy only the executable. Desktop lyrics run in a separate process launched from the same executable.

The full portable ZIP bundles a lossless-slimmed **audio-only FFmpeg 7.1.1 runtime** and **three compact offline Japanese reading datasets** (main dictionary, vocabulary supplement and kanji-reading supplement) with licenses, ready for conversion, trimming and offline readings. The slim installer excludes those two larger packages; you can install either on demand in Settings, where the player verifies file size and SHA-256, installs into `tool`, and re-verifies the runtime (hosted on the [v26.1.2-snapshot.8 release page](https://github.com/DanRuguo/dan_player/releases/tag/v26.1.2-snapshot.8)). **The offline English IPA dictionary is under 1 MB and is built directly into both editions—no extra download required.**

> **Downloads & signing:** project-built executables use an RCEIT.Inc self-signed certificate, so Windows may still display a trust warning. The installer does not automatically install a trusted root certificate. To upgrade from an older signing certificate, download the new installer manually. Preview releases do not replace the stable release marked Latest. Back up your player data through Backup & Restore before upgrading.

<a id="download-verification"></a>

<details>
<summary><strong>Verify a download with SHA-256</strong></summary>

Download the program and its matching checksum from the same Release: use `SHA256SUMS` for the portable ZIP and the matching `.exe.sha256` file for the installer. Calculate the file's SHA-256 and also compare it with the GitHub asset digest. Replace the example filename below with your downloaded filename:

```powershell
Get-FileHash -LiteralPath '.\DanPlayer-VERSION-Setup-x64.exe' -Algorithm SHA256
```

Matching hashes confirm that the file matches the published asset; they do not make Windows trust the signing certificate. Check the download source rather than disabling system security features to run an untrusted file.

</details>

<a id="features"></a>

## Highlights

- **Library & structured search:** Browse artists, albums, bitrates, durations, languages, formats, sources and folders; supports multi-disc section headers and disc subtitles, Opus/container bitrate fallback, CUE tracks, batch metadata editing and library health checks. Search offers multiword, pinyin and typo-tolerant matching, five quick filter pills, and one-tap history clearing.
- **Multi-view playlists & queue batch tools:** Nested playlists, smart rules and drag ordering across list, square grid, circle cover and tree views with cross-view cover flight tracking. Select multiple queue items, Shift-click ranges or pick search matches to move next/last, remove, save or export with full undo/redo. Import M3U, M3U8, PLS and XSPF local references.
- **Batch audio conversion & export:** Copy originals or convert folders to MP3, Opus or FLAC with quality presets, CUE splitting, progress and cancellation, generating a relative-path M3U8 that preserves order and duplicates (conversion requires FFmpeg; originals stay untouched).
- **High-fidelity playback & segments:** 10-band equalizer (including Electronic, Acoustic and Commute presets plus preset import/export), ReplayGain normalization, independent pitch shifting, pitch-preserving speed control, WASAPI exclusive output, per-track resume, A–B loops and library-wide bookmarks; optional crossfade, same-album crossfade exemption and leading/trailing silence skipping.
- **Bilingual phonetic lyrics & editors:** Word-by-word highlighting, millisecond-tolerant bilingual translation alignment, offline Japanese furigana and **built-in offline English IPA phonetics** (plain, `/…/` or `[…]` styles, side-by-side in mixed CJK/English lines, with offline batch generation). Supports LRC, QRC, KRC, TTML (`itunes:timing`) and embedded synced/unsynced lyrics, paired with smooth two-pass shader viewport edge blur plus tap-to-time and code editors.
- **Artwork glow & seamless transitions:** Embedded, multi-name folder covers and animated GIFs; soft contour glow, water-drop refraction and tap ripples on the Now Playing cover; GPU offscreen cross-dissolve on Categories to prevent dark-mode flashes, and pixel-aligned `192×192` Album ↔ Artist transitions with bidirectional cover flight and quick-play related cards.
- **Spectrum, motion & power efficiency:** Rounded bars or smooth pixel spectra around artwork and along the progress bar; ten animation categories, reduced-motion support, hidden-window clock suspension, adaptive/fixed frame-rate caps, power-saving presets and optional XAudio2 touch feedback ticks.
- **Material 3 Expressive desktop experience:** Adaptive four-language typography (`zh`/`en`/`ja`/`ko`), light/dark themes, dynamic cover colors, mini player, redesigned anti-aliased system tray menu with album art and transport controls, and mutually exclusive desktop/taskbar lyrics (with cold-start empty Windows SMTC suppression).
- **Statistics, storage & issue diagnostics:** Gradient hero summary, KPI cards, 24-hour distribution, 90-day weekday habits and medal rankings; non-destructive personal ratings and tags, shared on-demand CPU/GPU/RAM monitors, storage category breakdowns, and a popup **Report an issue** dialog with **15-day auto-pruned millisecond-timestamped daily logs**, personal path redaction and clipboard fallback.
- **Encrypted backup & selective restore:** Save selected music folders, library index, playlists, statistics, settings and caches into a `.bak` archive with optional password encryption, deduplication, selective restore and cancellation.

Lyrics and comments prioritize local files and saved caches by default. Automatic online lookup is opt-in (with per-track exponential backoff on transient timeouts and immediate retry on manual refresh). See the [custom music source API](docs/custom-music-source-api.md) for custom source integration.

Japanese readings and English IPA phonetics are stored in separate derived caches without altering source lyrics. Online Japanese readings use your locally stored Yahoo! JAPAN Client ID; review and revise offline dictionary output for names or ambiguous words when needed.

<a id="screenshots"></a>

## Interface gallery

### Category mosaic tiles, multi-disc albums & playlists

<picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/feature-category-tiles-dark.png"><img src="docs/images/feature-category-tiles-light.png" alt="Category mosaic cover tiles and Material 3 Expressive pill toolbar with fictional demo data" width="1200"></picture>

| Nested playlists & four view modes | Multi-disc album detail & related artist card |
| --- | --- |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/playlists-dark-wide.png"><img src="docs/images/playlists-light-wide.png" alt="Playlists page with circle covers and sub-playlists" width="600"></picture> | ![Multi-disc album detail showing Disc 1/2 headers, total duration and related artist quick-play card](docs/images/feature-album-detail-dark.png) |

### Bilingual phonetic lyrics, 10-band equalizer & spectra

| Immersive lyrics with Japanese furigana + English IPA | 10-band equalizer with Electronic / Acoustic / Commute presets |
| --- | --- |
| ![Now Playing lyrics showing cover glow, Japanese furigana and English IPA phonetics side by side](docs/images/feature-now-playing-lyrics-dark.png) | ![10-band equalizer dialog with tonal band capsules and scene presets](docs/images/feature-equalizer-dark.png) |

| Four translucent upcoming cards | Rounded and pixel spectrum guide |
| --- | --- |
| ![English upcoming preview with four translucent cards in two columns](docs/images/feature-upcoming-en.png) | ![English interactive guide showing rounded and pixel spectra](docs/images/feature-spectrum-guide-en.png) |

### Unified phonetic settings, mini player & two lyric editors

| Unified lyric furigana & IPA settings | Mini player with bilingual lyrics |
| --- | --- |
| ![Settings card unifying Japanese furigana and built-in English IPA styles and batch generation](docs/images/feature-lyric-annotations-light.png) | ![Mini player with artwork, bilingual lyrics and pill controls](docs/images/feature-mini-lyrics-dark.png) |

| Tap to time: prepare text & annotations | Tap to time: word timing in a narrow window |
| --- | --- |
| ![Tap lyric editor with lyrics, translation and pronunciation input](docs/images/lyric-tap-text-zh.png) | ![Tap lyric editor timing words in a narrow window](docs/images/lyric-tap-words-narrow-zh.png) |

| Code editor: QRC lyric markup | Code editor: word-timed preview |
| --- | --- |
| ![Code lyric editor showing QRC markup](docs/images/lyric-code-editor-zh.png) | ![Code lyric editor showing synchronized word preview](docs/images/lyric-editor-preview-zh.png) |

### Structured search, folder tree & listening statistics

| Quick filter pills & clearable search history | Folder tree & directory tracks |
| --- | --- |
| ![English search page with quick syntax pills, clear action and centered history capsules](docs/images/search-history-en.png) | ![Folders page with directory tree and track list](docs/images/feature-folders-light.png) |

| Listening statistics overview & 24-hour chart | Medal rankings & listening habits |
| --- | --- |
| ![Statistics overview with hero banner, KPI grid and 24-hour distribution](docs/images/feature-statistics-light.png) | ![Statistics rankings with medal badges and listening breakdown](docs/images/statistics-rankings-light.png) |

### Appearance, 15-day diagnostic logs, resource monitors & backup

| Appearance & grouped settings | Report an issue popup & 15-day timestamped logs |
| --- | --- |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/settings-dark-wide.png"><img src="docs/images/settings-light-wide.png" alt="Grouped settings with adaptive segmented controls" width="600"></picture> | ![English Report an issue dialog with category pills, path redaction and 15-day millisecond-timestamped logs](docs/images/feature-report-issue-en.png) |

| Shared on-demand CPU/GPU/RAM monitoring | Cache & temporary storage breakdown |
| --- | --- |
| ![Sidebar sparklines and settings process resource monitor](docs/images/process-resource-locations.png) | ![Storage breakdown across caches, user data and temporary files](docs/images/cache-storage-statistics.png) |

| Feature guide: everyday library operations | Feature guide: interactive seek & queue tools |
| --- | --- |
| ![Feature guide instructions for music, categories and playlists](docs/images/manual-common-library.png) | ![Interactive seek demonstration and queue guide](docs/images/manual-playback-demo.png) |

| First-run guide: choose a language & try playback | Selective restore of encrypted backups |
| --- | --- |
| ![English first-run interactive onboarding guide](docs/images/feature-onboarding-en.png) | ![English selective restore dialog for player data and music folders](docs/images/feature-restore-en.png) |

<sub>All renders are produced offscreen from actual Flutter widgets and isolated demonstration data to illustrate layout, themes and features rather than live audio hardware or native desktop compositing. Browse all 64 light/dark, wide/narrow and four-language renders in the <a href="docs/images/README.md">full interface gallery</a>.</sub>

<a id="quick-start"></a>

## Getting started

**Add music.** Import audio files or folders, then browse them across the Music, Categories, Playlists and Folders pages. Organize collections with nested playlists and drag-to-reorder.

**Keep your own ratings and tags.** Open **Categories → Personal library → Songs** to filter rated or tagged tracks by date, rating or tag. Personal ratings and tags stay in player data and **are never written to audio files**, whereas metadata and batch-tag editors modify file tags after showing a preview.

**Save a favorite moment.** Use **More → Playback bookmarks** on the Now Playing page to save a timestamp or an A–B loop, then revisit them under **Categories → Personal library → All bookmarks**.

**Back up your data.** Use Backup & Restore in Settings to export selected player data and music folders with optional encryption and selective restoration (each encrypted `.bak` archive must be under ~64 GiB).

<details>
<summary><strong>Common keyboard shortcuts</strong></summary>

| Key | Action |
| --- | --- |
| `Space` | Play / pause |
| `Ctrl + Left` / `Ctrl + Right` | Previous / next track |
| `Left` / `Right` | Seek backward / forward 5 seconds |
| `Ctrl + M` | Toggle the mini player |
| `F11` | Toggle full screen |
| `F1` | View keyboard shortcuts |

</details>

<a id="documentation"></a>

## Documentation & feedback

[Interface gallery](docs/images/README.md) · [Custom music source API](docs/custom-music-source-api.md) · [go-music-api configuration example](docs/examples/go-music-api-jamendo.json) · [All releases](https://github.com/DanRuguo/dan_player/releases)

Before reporting a problem, check [existing Issues](https://github.com/DanRuguo/dan_player/issues), or open **Settings → Update & About → Report an issue** to filter the last 15 days of timestamped logs (with personal directory paths redacted by default) and open a pre-filled [GitHub issue draft](https://github.com/DanRuguo/dan_player/issues/new/choose). Never upload private audio files, credentials or unredacted personal paths.

<a id="development"></a>

## Development & building

Built with **Flutter, Rust and BASS**. Development requires Flutter, Rust and the Visual Studio Desktop development with C++ workload. See [pubspec.yaml](pubspec.yaml) for Dart constraints, [pubspec.lock](pubspec.lock) and [rust/Cargo.lock](rust/Cargo.lock) for resolved dependencies, and [Windows CI](.github/workflows/windows_ci.yml) for continuous integration.

<details>
<summary><strong>Source layout, debugging and focused checks</strong></summary>

| Directory | Purpose |
| --- | --- |
| [lib/](lib/) | Main UI, library, phonetic lyrics, diagnostics logs, playback services and models |
| [third_party/desktop_lyric/](third_party/desktop_lyric/) | Shared desktop lyrics, four-language catalogs, bundled fonts and Windows host |
| [rust/](rust/), [rust_builder/](rust_builder/) | Tag/artwork readers, dictionary builders, Flutter/Rust bridge and Cargokit |
| [windows/](windows/), [installer/](installer/) | Windows tray/touch-sound host and Material 3 Expressive native installer |
| [scripts/](scripts/) | Runtime preparation, module assembly, builds, signing and verification |
| [assets/](assets/), [shaders/](shaders/), [docs/](docs/) | Built-in English IPA dictionary, shaders, API docs and public gallery images |

Run from the repository root with an isolated data directory:

```powershell
$env:DAN_PLAYER_DATA_DIR = [IO.Path]::GetFullPath((Join-Path (Get-Location).Path '../tool/qa-local/readme-debug'))
flutter pub get
flutter run -d windows
```

Prepare the BASS runtime via `scripts/prepare_bass_runtime.ps1` and `scripts/prepare_bass_fx_runtime.ps1`. Run focused checks with `flutter test --no-pub <test-entry>` and `cargo test --manifest-path rust/Cargo.toml --locked <test-filter>`.

</details>

<details>
<summary><strong>Windows builds & releases</strong></summary>

The release scripts expect the source in `dan_player/`, `tool/` for toolchains/caches, and `dist/` for output:

```powershell
.\scripts\build_windows_release.ps1 -SkipSigning
```

Build the installer with `scripts/build_windows_installer.ps1` and verify artifacts with `verify_local_release.ps1` and `verify_windows_installer.ps1`. Bundle optional components into portable archives via `scripts/assemble_windows_release.ps1 -IncludeOptionalComponents` after preparing the pinned FFmpeg and Japanese reading runtimes.

</details>

Maintain only necessary long-lived documentation; keep local notes, QA output, tool caches, personal data and signing keys out of the source repository.

<a id="license"></a>

## License & acknowledgments

Distributed under [LICENSE](LICENSE). Third-party components retain their own terms; BASS use and distribution must follow its official license.

Bundled [Source Han Sans SC / JP](licenses/SOURCE-HAN-SANS/PROVENANCE.md), [Google Sans](licenses/GOOGLE-SANS/PROVENANCE.md) and [Pretendard](licenses/PRETENDARD/PROVENANCE.md) are distributed under the SIL Open Font License 1.1 (`DanPingFangSC` aliases Source Han Sans SC and includes no Apple font).

Based on [Ferry-200/coriander_player](https://github.com/Ferry-200/coriander_player), with thanks to [desktop_lyric](https://github.com/Ferry-200/desktop_lyric), [music_api_dart](https://github.com/Ferry-200/music_api_dart), [BASS](https://www.un4seen.com/bass.html), [Lofty](https://crates.io/crates/lofty), [flutter_rust_bridge](https://pub.dev/packages/flutter_rust_bridge), [Flutter](https://flutter.dev/) and Material Design.

Built-in English IPA dictionary provenance: [CMUDict](licenses/CMUDICT/PROVENANCE.md). Offline Japanese reading provenance: [IPADIC](licenses/IPADIC/PROVENANCE.md) / [EDRDG](licenses/EDRDG/PROVENANCE.md) and [Lindera](licenses/LINDERA/LICENSE). Online readings: [Web Services by Yahoo! JAPAN](https://developer.yahoo.co.jp/sitemap/).

<sub>Badges by <a href="https://shields.io/">Shields.io</a>. Asset download counts do not equal unique installations; technology badges do not declare minimum supported OS versions.</sub>
