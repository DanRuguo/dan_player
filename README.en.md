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

<p>A Windows x64 music player for library organization, lyrics and desktop listening.<br>
Local playback comes first, with online music and custom sources alongside it.</p>

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
  <a href="https://github.com/DanRuguo/dan_player/releases">Previous releases</a> ·
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
    <img src="docs/images/library-light-wide.png" alt="Dan Player library and playback controls, using the Chinese interface and fictional data" width="1200">
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

| Release | Best for | Download |
| --- | --- | --- |
| **Latest stable** | Everyday use and upgrades; check the release page for its version | [Installer, portable ZIP & checksums](https://github.com/DanRuguo/dan_player/releases/latest) |

**Installer:** run the setup program; in-place upgrades are supported. **Portable:** extract the entire ZIP and launch `Dan Player.exe`—do not copy only the executable. Desktop lyrics run in a separate process launched from the same executable.

The current portable ZIP includes FFmpeg, three offline Japanese reading datasets (the main dictionary, vocabulary supplement and kanji-reading supplement), and their licenses for previews, trimming and offline readings. The slim installer excludes these two component categories and preserves components already installed. You can download them manually from the player, with fixed-size and SHA-256 verification. FFmpeg uses the [standalone 26.0.5 component](https://github.com/DanRuguo/dan_player/releases/tag/v26.0.5); the reading data is available separately on the [26.1.1 release page](https://github.com/DanRuguo/dan_player/releases/tag/v26.1.1).

> **Downloads & signing:** project-built executables use an RCEIT.Inc self-signed certificate, so Windows may still display a trust warning. The installer does not automatically install a trusted certificate. To upgrade from an older signing certificate, download the new installer manually. Preview releases do not replace the stable release marked Latest. Back up your player data through the app's backup and restore settings before upgrading.

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

- **Library and search:** Browse artists, albums, formats and folders; use multiword, pinyin and typo-tolerant search, CUE tracks, multi-disc ordering, batch metadata editing and library health checks.
- **Playlists and queues:** Nested and smart playlists, drag ordering, saved queues and undo; import local audio references from M3U, M3U8, PLS or XSPF, and export M3U8 or a folder with music files.
- **Up next:** Up to four translucent cards use two columns in wide windows and one in narrow windows. Click to locate the exact queue entry, or expand to see up to ten determined upcoming tracks. The setting controls only the lyrics-page preview; the playback-bar popup has none.
- **Playback and segments:** Equalizer, loudness normalization, independent pitch shifting, speed changes that preserve pitch, per-track resume, A–B loops and library-wide bookmarks; optional crossfade, a same-album crossfade exemption, and skipping leading or trailing silence.
- **Lyric editing and reading:** Word highlighting, translation, Japanese readings, full-text search and timing adjustment; tap-to-time and text editors with revisions, locking and ruby layout for long lines.
- **Artwork and categories:** Embedded or same-folder artwork and animated GIFs; soft contour glow and local water-drop refraction on the large playback cover, plus category tile glow, mixed sizes and custom ordering.
- **Spectrum and motion:** Rounded bars or smoothly changing pixel spectra around artwork and along the progress bar; ten animation controls, reduced motion, hidden-view suspension, refresh-rate and power-saving settings. Interactive guides demonstrate spectra, progress and lyrics.
- **Desktop experience:** Four languages, light/dark themes, artwork colors, shortcuts and a mini player; highlighted desktop or taskbar lyrics, with one/two-line taskbar layouts and optional playback buttons. The two lyric surfaces are mutually exclusive.
- **Statistics and organization:** Ratings, personal tags, listening rankings, folder notes and storage breakdowns; compilations grouped by album artist, separate music/cache categories and optional CPU/GPU/memory monitoring.
- **Backup and restore:** Select music, library data, playlists, statistics, settings and caches for a `.bak` file, with optional encryption, selective restore and cancellation; shared music files are stored once.

Lyrics and comments use local content and caches first by default. Automatic online access is optional; manual searches, refreshes and batch caching can still make network requests.

Online music and custom sources complement local listening. Custom services provide capabilities such as search and lyrics according to what they explicitly declare. See the [custom music source API](docs/custom-music-source-api.md) for integration details.

Main, desktop and taskbar lyrics share letter spacing. Generated Japanese readings align with kanji, preserve the original lyrics and existing annotations, and use a separate derived cache; settings also offer bulk processing of saved lyrics. With automatic online access on, generation tries online first and falls back offline. With it off, explicitly choose online or offline in the reading tools or bulk dialog. Online generation needs your own Yahoo! JAPAN Client ID and sends the text to that service; credentials are stored only on your computer. Offline dictionaries have limits with unknown words, names and ambiguous readings; review and revise the result when needed.

<a id="screenshots"></a>

## Interface gallery

### Up next and spectrum guide

These renders use actual components, the English interface and fictional data. The spectrum is a guide demonstration, not a live audio sample.

| Four translucent upcoming cards | Rounded and pixel spectrum guide |
| --- | --- |
| ![English upcoming preview with four translucent cards in two columns](docs/images/feature-upcoming-en.png) | ![English interactive guide showing rounded and pixel spectra](docs/images/feature-spectrum-guide-en.png) |

### Manual and on-demand monitoring

These real component renders use the Chinese interface, fictional resource samples and example paths.

| Everyday operations | Playback queue and interactive example |
| --- | --- |
| ![Instructions for music, categories and playlists](docs/images/manual-common-library.png) | ![Progress seeking example and queue instructions](docs/images/manual-playback-demo.png) |

| Resource monitoring across surfaces | Cache storage categories |
| --- | --- |
| ![Shared resource monitoring in the sidebar and backup settings](docs/images/process-resource-locations.png) | ![Cache and player data storage categories in statistics](docs/images/cache-storage-statistics.png) |

### Two ways to edit lyrics

| Tap to time: prepare text | Tap to time: word timing in a narrow window |
| --- | --- |
| ![Chinese tap editor with lyrics, translation and pronunciation input](docs/images/lyric-tap-text-zh.png) | ![Chinese tap editor timing words in a narrow window](docs/images/lyric-tap-words-narrow-zh.png) |

| Text editor: lyric markup | Text editor: word preview |
| --- | --- |
| ![Chinese text editor showing QRC lyric markup](docs/images/lyric-code-editor-zh.png) | ![Chinese text editor showing a word-timed preview](docs/images/lyric-editor-preview-zh.png) |

### Organize your collection, your way

| Playlists & collections | Appearance & settings |
| --- | --- |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/playlists-dark-wide.png"><img src="docs/images/playlists-light-wide.png" alt="Playlist organization in the Chinese interface" width="600"></picture> | <picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/settings-dark-wide.png"><img src="docs/images/settings-light-wide.png" alt="Themes and grouped settings in the Chinese interface" width="600"></picture> |

### Find a track and focus on its lyrics

| Search & history | Mini player & lyrics |
| --- | --- |
| ![Search page content rendered from Flutter widgets, with centered history chips in English](docs/images/search-history-en.png) | ![Mini player and lyrics with fictional demonstration content](docs/images/feature-mini-lyrics-dark.png) |

### Rediscover your library through listening history

![Music statistics and rankings in the Chinese interface with fictional data](docs/images/statistics-rankings-light.png)

<sub>These images render actual Flutter widgets with isolated demonstration data. The search image shows the English page content area and example history, not a complete native window; other examples mostly use the Chinese interface. They illustrate layout and features, not live audio or native desktop effects. See the <a href="docs/images/README.md">full gallery</a> for more themes, window sizes and all four interface languages.</sub>

### Category tiles and getting started

<picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/feature-category-tiles-dark.png"><img src="docs/images/feature-category-tiles-light.png" alt="Independent category views and mixed cover sizes with fictional demo data" width="1200"></picture>

| First-run guide: choose a language and try playback controls | Selective restore of player data and local music |
| --- | --- |
| ![First-run guide: choose a language and try playback controls](docs/images/feature-onboarding-en.png) | ![Selective restore of player data and local music](docs/images/feature-restore-en.png) |

<a id="quick-start"></a>

## Getting started

**Add music.** Import audio files or folders, then browse them from the music, category and playlist pages. Organize your collection with nested playlists and drag-to-reorder.

**Keep your own ratings and tags.** Open the category page and choose **Personal library → Songs** to see tracks you have rated or given personal tags. Filter by date, rating or tag. Personal ratings and tags are stored in player data and **are not written to music files**. The metadata-editing and batch-tag tools do change file metadata, so review the changes before saving.

**Save a favorite moment.** In the Now Playing page, open the playback bookmarks dialog from the More menu to save the current position or an A–B segment. Find your saved entries under **Personal library → All bookmarks** on the category page. The play button there starts at the saved position; to restore an A–B loop, select that segment in the corresponding track's playback bookmarks dialog.

**Back up your data.** Use backup and restore in Settings to save selected player data and local music, with optional encryption and selective restoration. Updating the program and backing up your data are separate operations: application files in the installation directory do not replace backups of your library, playlists and settings.

Split large collections by folder. Keep the password safe; each encrypted backup must be smaller than about 64 GiB.

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

The linked gallery and API documentation are currently in Chinese. Replace the sample service address with your own deployment. Before reporting a problem, check [existing Issues](https://github.com/DanRuguo/dan_player/issues), then use the [issue templates](https://github.com/DanRuguo/dan_player/issues/new/choose). Include the player version, reproduction steps and, when relevant, interface language, window size or display scaling. For playback problems, attach a redacted diagnostic export. Do not upload private music files, credentials or complete personal directory paths.

<a id="development"></a>

## Development & building

Built with **Flutter, Rust and BASS**. Development requires Flutter, Rust and the Visual Studio Desktop development with C++ workload. See [pubspec.yaml](pubspec.yaml) for Dart constraints and [pubspec.lock](pubspec.lock) / [rust/Cargo.lock](rust/Cargo.lock) for resolved dependencies. The Windows workflow is defined in [Windows CI](.github/workflows/windows_ci.yml).

<details>
<summary><strong>Source layout, debugging and focused checks</strong></summary>

| Directory | Purpose |
| --- | --- |
| [lib/](lib/) | Main interface, library, playback services and data models |
| [third_party/desktop_lyric/](third_party/desktop_lyric/) | Shared desktop lyrics, fonts and Windows host |
| [rust/](rust/), [rust_builder/](rust_builder/) | Tag processing, Flutter/Rust bridging and Cargokit support |
| [windows/](windows/), [installer/](installer/) | Windows integration and native Inno installer components |
| [scripts/](scripts/) | Dependency preparation, building, signing and artifact verification |
| [assets/](assets/), [shaders/](shaders/), [docs/](docs/) | Interface assets, shaders, API documentation and public images |

Run from the repository root with an isolated data directory so debugging does not affect your everyday library and settings:

```powershell
$env:DAN_PLAYER_DATA_DIR = [IO.Path]::GetFullPath((Join-Path (Get-Location).Path '../tool/qa-local/readme-debug'))
flutter pub get
flutter run -d windows
```

Prepare the BASS runtime before launching; see `scripts/prepare_bass_runtime.ps1` and `scripts/prepare_bass_fx_runtime.ps1`. Keep machine-specific SDK, cache and signing paths outside the source repository.

Prepare isolated fixtures for the current change and select existing entry points for focused Dart/Widget, Rust or Windows checks; do not restore retired historical test suites. Use `flutter test --no-pub <test-entry>` for Dart and `cargo test --manifest-path rust/Cargo.toml --locked <test-filter>` for Rust. Render actual UI components at the affected languages, widths and text scales; native captures need a separate verification window. Widget rendering does not replace real audio-device or Windows desktop integration checks.

</details>

<details>
<summary><strong>Windows builds & releases</strong></summary>

The release scripts expect the source in `dan_player/`, a sibling `tool/` directory for toolchains and caches, and `dist/` for output. `build_windows_release.ps1` prepares dependencies, checks reusable source and artifact receipts, builds Windows binaries, verifies fonts and runtimes, and optionally signs or assembles packages. It does not replace focused regression checks.

```powershell
# From the source repository in the workspace described above, without a signing certificate:
.\scripts\build_windows_release.ps1 -SkipSigning
```

`-SkipPackaging` skips portable-package assembly; `-NoRestore` reuses restored dependencies. Signed releases require a separately configured certificate. Build the installer with `scripts/build_windows_installer.ps1`; verify the portable package and installer with `verify_local_release.ps1` and `verify_windows_installer.ps1`, respectively.

Reuse valid checks and build artifacts for the same code state; rerun only the necessary stages after a failure. After signing, verify the source commit, test receipts, artifact SHA-256 and signatures, then perform only the required GitHub publishing steps. Previews remain prereleases and do not replace the stable Latest release. Simplify the process without removing essential verification.

Default local assembly does not include FFmpeg. To bundle it, prepare the fixed runtime described by `scripts/ffmpeg_runtime_manifest.json`, then use `scripts/assemble_windows_release.ps1 -IncludeOptionalComponents`. `prepare_ffmpeg_runtime.ps1` only verifies and copies an existing cache; it does not download it.

</details>

Maintain only necessary, long-lived documentation. Keep machine-local development notes, historical QA output, temporary logs, tool caches, personal data and signing private keys out of the source repository. Public interface images live in `docs/images/`; update their references when the assets change.

<a id="license"></a>

## License & acknowledgments

This project is distributed under [LICENSE](LICENSE). Third-party components retain their own licensing terms; BASS use and distribution must follow its official license.

The main player and desktop lyrics share font resources, with one common selection, separate choices for the four UI languages, and script-aware fonts for mixed text. Bundled [Source Han Sans SC / JP](licenses/SOURCE-HAN-SANS/PROVENANCE.md), [Google Sans](licenses/GOOGLE-SANS/PROVENANCE.md) and [Pretendard](licenses/PRETENDARD/PROVENANCE.md) are distributed under the SIL Open Font License 1.1; original licenses and provenance accompany both portable and installer packages. The internal compatibility alias `DanPingFangSC` refers to Source Han Sans SC, not an Apple font.

Dan Player is based on [Ferry-200/coriander_player](https://github.com/Ferry-200/coriander_player). Thanks to the original author for the player foundation, library structure and lyrics experience. We also acknowledge [desktop_lyric](https://github.com/Ferry-200/desktop_lyric), [music_api_dart](https://github.com/Ferry-200/music_api_dart), [BASS](https://www.un4seen.com/bass.html), [Lofty](https://crates.io/crates/lofty), [flutter_rust_bridge](https://pub.dev/packages/flutter_rust_bridge), [Flutter](https://flutter.dev/) and Material Design.

Offline dictionary licenses and provenance: [IPADIC](licenses/IPADIC/PROVENANCE.md) / [EDRDG](licenses/EDRDG/PROVENANCE.md) and [Lindera](licenses/LINDERA/LICENSE). Online readings: [Web Services by Yahoo! JAPAN](https://developer.yahoo.co.jp/sitemap/).

<sub>Badges are provided by <a href="https://shields.io/">Shields.io</a>. Downloads count Release asset downloads, not unique users or installations. Framework badges identify the technologies used, not minimum supported versions.</sub>
