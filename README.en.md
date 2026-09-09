<div align="center">

<p>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/images/RCE_logo_white.png">
    <source media="(prefers-color-scheme: light)" srcset="assets/images/RCE_logo_transparent.png">
    <img src="assets/images/RCE_logo_transparent.png" alt="RCE brand logo" width="128">
  </picture>
</p>

<h1>Dan Player</h1>

<p><strong>Designed for your local music collection.</strong></p>

<p>A Windows x64 music player for library organization, lyrics and desktop listening.<br>
Local playback comes first, with online music and custom sources alongside it.</p>

<p align="center">
  <a href="https://github.com/DanRuguo/dan_player/releases/latest"><img src="https://img.shields.io/github/v/release/DanRuguo/dan_player?style=flat&amp;labelColor=374151&amp;label=stable&amp;logo=github&amp;logoColor=white&amp;color=2563EB" alt="Latest stable release"></a>
  <a href="https://github.com/DanRuguo/dan_player/releases"><img src="https://img.shields.io/github/v/release/DanRuguo/dan_player?style=flat&amp;labelColor=374151&amp;include_prereleases=true&amp;filter=v%2A-snapshot.%2A&amp;sort=semver&amp;label=preview&amp;color=D97706" alt="Latest snapshot preview"></a>
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
  <a href="https://github.com/DanRuguo/dan_player/releases/tag/v26.0.5-snapshot.3">Try the preview</a> ·
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
  <a href="#features">Features</a> ·
  <a href="#screenshots">Interface gallery</a> ·
  <a href="#quick-start">Getting started</a> ·
  <a href="#development">Development</a>
</p>

<a id="download"></a>

## Download & install

| Release | Best for | Download |
| --- | --- | --- |
| **26.0.4 · Stable** | Everyday listening with an official stable release | [Installer, portable ZIP & checksums](https://github.com/DanRuguo/dan_player/releases/tag/v26.0.4) |
| **26.0.5-snapshot.3 · Preview** | Trying personal library tools, library-wide bookmarks and other additions before the next stable release | [Installer, portable ZIP & checksums](https://github.com/DanRuguo/dan_player/releases/tag/v26.0.5-snapshot.3) |

**Installer:** run the setup program; in-place upgrades are supported. **Portable:** extract the entire ZIP and launch `Dan Player.exe`—do not copy only the executable. In the 26.0.5 preview, desktop lyrics run in a separate process launched from the same executable.

> **Downloads & signing:** project-built executables use an RCEIT.Inc self-signed certificate, so Windows may still display a trust warning. The installer does not automatically install a trusted certificate. To upgrade from an older signing certificate, download the new installer manually. Preview releases do not replace the stable release marked Latest. Back up your player data through the app's backup and restore settings before upgrading.

<a id="download-verification"></a>

<details>
<summary><strong>Verify a download with SHA-256</strong></summary>

Download the program and `SHA256SUMS` from the same Release page. Calculate the SHA-256 of the installer or ZIP and compare it with the checksum file and the GitHub asset digest. Replace the example filename below with the name of the file you downloaded:

```powershell
Get-FileHash -LiteralPath '.\DanPlayer-VERSION-Setup-x64.exe' -Algorithm SHA256
```

Matching hashes confirm that the file matches the published asset; they do not make Windows trust the signing certificate. Check the download source rather than disabling system security features to run an untrusted file.

</details>

<a id="features"></a>

## Features

From finding a track to organizing an entire collection, everyday tools work around the same music library.

| Area | What you can do |
| --- | --- |
| **Library & search** | Browse by artist, album, format or folder; search tracks, edit metadata in batches and check library health. |
| **Playlists & queues** | Organize nested playlists, reorder by dragging, use smart conditions and exchange M3U8 playlists; save queues, undo changes and recover playlists. |
| **Lyrics** | Match, edit, revise, lock and synchronize lyrics; search their full text and read them in desktop lyrics or the mini player. |
| **Playback & navigation** | Play CUE tracks, use the equalizer and loudness normalization, resume individual tracks and loop A–B segments; save positions or segments and manage them in All bookmarks. |
| **Personal music data** | Add personal ratings and tags, filter your collection, and explore listening times, track rankings, library composition and disk usage. |
| **Windows experience** | Enjoy artwork-based colors, light and dark themes, and four interface languages; use keyboard shortcuts, a mini window, taskbar previews and playback diagnostics. |

This overview describes the current repository. Some features require the 26.0.5 preview; check the corresponding [Release notes](https://github.com/DanRuguo/dan_player/releases) for what is included in a published package.

Online music and custom sources complement local listening. Custom services provide capabilities such as search and lyrics according to what they explicitly declare. See the [custom music source API](docs/custom-music-source-api.md) for integration details.

<a id="screenshots"></a>

## Interface gallery

### Organize your collection, your way

| Playlists & collections | Appearance & settings |
| --- | --- |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/playlists-dark-wide.png"><img src="docs/images/playlists-light-wide.png" alt="Playlist organization in the Chinese interface" width="600"></picture> | <picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/settings-dark-wide.png"><img src="docs/images/settings-light-wide.png" alt="Themes and grouped settings in the Chinese interface" width="600"></picture> |

### Find a track and focus on its lyrics

| Track search | Mini player & lyrics |
| --- | --- |
| ![Track search in the Chinese interface with fictional tracks](docs/images/feature-search-dark.png) | ![Mini player and lyrics with fictional demonstration content](docs/images/feature-mini-lyrics-dark.png) |

### Rediscover your library through listening history

![Music statistics and rankings in the Chinese interface with fictional data](docs/images/statistics-rankings-light.png)

<sub>These existing repository images render production Flutter widgets with fictional tracks and isolated data. They illustrate the interface, not live audio or native desktop-effects testing. The screenshots use the Chinese interface; the app also offers English, Japanese and Korean. See the <a href="docs/images/README.md">full gallery</a> for more light/dark themes, window sizes and feature previews.</sub>

<a id="quick-start"></a>

## Getting started

**Add music.** Import audio files or folders, then browse them from the music, category and playlist pages. Organize your collection with nested playlists and drag-to-reorder.

**Keep your own ratings and tags.** In the 26.0.5 preview, open the category page and choose **Personal library → Songs** to see tracks you have rated or given personal tags. Filter by date, rating or tag. Personal ratings and tags are stored in player data and **are not written to music files**. The metadata-editing and batch-tag tools do change file metadata, so review the changes before saving.

**Save a favorite moment.** In the Now Playing page, open the playback bookmarks dialog from the More menu to save the current position or an A–B segment. Find your saved entries under **Personal library → All bookmarks** on the category page. The play button there starts at the saved position; to restore an A–B loop, select that segment in the corresponding track's playback bookmarks dialog.

**Back up your data.** Use backup and restore in Settings to save player data. Updating the program and backing up your data are separate operations: application files in the installation directory do not replace backups of your library, playlists and settings.

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
<summary><strong>Source layout, debugging & focused checks</strong></summary>

| Directory | Purpose |
| --- | --- |
| `lib/` | Interface, library and playback services |
| `rust/`, `rust_builder/` | Tag processing and Flutter/Rust bridging |
| `windows/`, `installer/` | Windows integration and installer |
| `third_party/` | Bundled components and their license information |
| `test/`, `test_driver/` | Automated tests |
| `scripts/` | Build, verification and release scripts |
| `docs/` | API documentation, examples and interface images |

Run the following from the repository root. Use an isolated data directory so debugging does not affect your everyday library and settings:

```powershell
$env:DAN_PLAYER_DATA_DIR = [IO.Path]::GetFullPath((Join-Path (Get-Location).Path '../tool/qa-data/readme-debug'))
flutter pub get
flutter run -d windows
```

Prepare the BASS runtime before launching; the relevant scripts are `scripts/prepare_bass_runtime.ps1` and `scripts/prepare_bass_fx_runtime.ps1`. Machine-specific SDK, runtime-cache and signing paths belong in a local `DEVELOPMENT.md` outside the source repository.

Keep checks focused and batch related changes by module. Do not run the full regression suite, build and signing process after every feature. For example, statistics and detail-layout changes can be checked with:

```powershell
flutter test test/statistics_visualization_test.dart test/detail_diagnostics_layout_test.dart --no-pub
```

Use `scripts/verify_interaction_regressions.ps1` at integration checkpoints. UI changes must be reviewed using rendered production Flutter widgets. Public images are generated with `scripts/render_public_ui.ps1` and isolated fictional data; rendering checks cover languages, window widths and text scaling. Widget rendering does not replace testing on real audio devices and Windows desktop integration.

</details>

<details>
<summary><strong>Windows builds & releases</strong></summary>

The existing release scripts expect a workspace with the source in `dan_player/`, a sibling `tool/` directory for toolchains and caches, and `dist/` for output. `build_windows_release.ps1` checks dependencies, runs release gates, builds the Windows app, and verifies fonts and runtime libraries.

```powershell
# From the source repository in the workspace described above, without a signing certificate:
.\scripts\build_windows_release.ps1 -SkipSigning
```

`-SkipPackaging` skips portable-package assembly; `-NoRestore` reuses restored dependencies. Signed releases require a separately configured certificate. Build the installer with `scripts/build_windows_installer.ps1`; verify the portable package and installer with `verify_local_release.ps1` and `verify_windows_installer.ps1`, respectively.

Reuse valid checks and build artifacts for the same code state; rerun only the necessary stages after a failure. After signing, verify the source commit, test receipts, artifact SHA-256 and signatures, then perform only the required GitHub publishing steps. Previews remain prereleases and do not replace the stable Latest release. Simplify the process without removing essential verification.

</details>

Maintain only necessary, long-lived documentation. Keep machine-local development notes, historical QA output, temporary logs, tool caches, personal data and signing private keys out of the source repository. Public interface images live in `docs/images/`; update their references when the assets change.

<a id="license"></a>

## License & acknowledgments

This project is distributed under [LICENSE](LICENSE). Third-party components retain their own licensing terms; BASS use and distribution must follow its official license.

Dan Player is based on [Ferry-200/coriander_player](https://github.com/Ferry-200/coriander_player). Thanks to the original author for the player foundation, library structure and lyrics experience. We also acknowledge [desktop_lyric](https://github.com/Ferry-200/desktop_lyric), [music_api_dart](https://github.com/Ferry-200/music_api_dart), [BASS](https://www.un4seen.com/bass.html), [Lofty](https://crates.io/crates/lofty), [flutter_rust_bridge](https://pub.dev/packages/flutter_rust_bridge), [Flutter](https://flutter.dev/) and Material Design.

<sub>Badges are provided by <a href="https://shields.io/">Shields.io</a>. Downloads count Release asset downloads, not unique users or installations. Framework badges identify the technologies used, not minimum supported versions.</sub>
