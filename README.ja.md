<div align="center">

<p>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/images/RCE_logo_white.png">
    <source media="(prefers-color-scheme: light)" srcset="assets/images/RCE_logo_transparent.png">
    <img src="assets/images/RCE_logo_transparent.png" alt="RCE ブランドロゴ" width="128">
  </picture>
</p>

<h1>Dan Player</h1>

<p><strong>ローカルの音楽コレクションのために。</strong></p>

<p>ライブラリ整理、歌詞表示、デスクトップでの操作にこだわった Windows x64 向け音楽プレーヤー。<br>
ローカル再生を中心に、オンライン音楽やカスタムソースも利用できます。</p>

<p align="center">
  <a href="https://github.com/DanRuguo/dan_player/releases/latest"><img src="https://img.shields.io/github/v/release/DanRuguo/dan_player?style=flat&amp;labelColor=374151&amp;label=stable&amp;logo=github&amp;logoColor=white&amp;color=2563EB" alt="最新の安定版"></a>
  <a href="https://github.com/DanRuguo/dan_player/releases"><img src="https://img.shields.io/github/v/release/DanRuguo/dan_player?style=flat&amp;labelColor=374151&amp;include_prereleases&amp;filter=v%2A-snapshot.%2A&amp;sort=semver&amp;label=preview&amp;color=D97706" alt="最新の snapshot プレビュー版"></a>
  <a href="https://github.com/DanRuguo/dan_player/releases"><img src="https://img.shields.io/github/downloads/DanRuguo/dan_player/total?style=flat&amp;labelColor=374151&amp;label=downloads&amp;color=059669" alt="GitHub Release アセットのダウンロード数"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/DanRuguo/dan_player?style=flat&amp;labelColor=374151&amp;label=license&amp;color=64748B" alt="プロジェクトのライセンス"></a>
</p>

<p align="center">
  <a href="#download"><img src="https://img.shields.io/badge/platform-Windows%20x64-0078D4?style=flat&amp;labelColor=374151" alt="対応環境：Windows x64"></a>
  <a href="#development"><img src="https://img.shields.io/badge/Flutter-UI-02569B?style=flat&amp;labelColor=374151&amp;logo=flutter&amp;logoColor=white" alt="Flutter：UI"></a>
  <a href="#development"><img src="https://img.shields.io/badge/Rust-Bridge-B45309?style=flat&amp;labelColor=374151&amp;logo=rust&amp;logoColor=white" alt="Rust：ネイティブ連携"></a>
  <a href="https://www.un4seen.com/bass.html"><img src="https://img.shields.io/badge/BASS-Audio-6750A4?style=flat&amp;labelColor=374151" alt="BASS：音声再生"></a>
</p>

<p>
  <a href="https://github.com/DanRuguo/dan_player/releases/latest"><strong>安定版をダウンロード</strong></a> ·
  <a href="https://github.com/DanRuguo/dan_player/releases/tag/v26.0.5-snapshot.3">プレビュー版を試す</a> ·
  <a href="https://github.com/DanRuguo/dan_player/releases">更新内容</a> ·
  <a href="https://github.com/DanRuguo/dan_player/issues/new/choose">問題を報告</a>
</p>

<p>
  <a href="README.md">简体中文</a> ·
  <a href="README.en.md">English</a> ·
  <strong>日本語</strong> ·
  <a href="README.ko.md">한국어</a>
</p>

</div>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/library-dark-wide.png">
    <source media="(prefers-color-scheme: light)" srcset="docs/images/library-light-wide.png">
    <img src="docs/images/library-light-wide.png" alt="中国語 UI と架空のデータを使用した Dan Player のライブラリと再生コントロール" width="1200">
  </picture>
</p>

<p align="center">
  <a href="#download">ダウンロード</a> ·
  <a href="#features">主な機能</a> ·
  <a href="#screenshots">インターフェース</a> ·
  <a href="#quick-start">使い始める</a> ·
  <a href="#development">開発とビルド</a>
</p>

<a id="download"></a>

## ダウンロードとインストール

| バージョン | 用途 | ダウンロード |
| --- | --- | --- |
| **26.0.4 · 安定版** | 日常の音楽再生に。正式リリースを使いたい方へ | [インストーラー・ポータブル ZIP・チェックサム](https://github.com/DanRuguo/dan_player/releases/tag/v26.0.4) |
| **26.0.5-snapshot.3 · プレビュー版** | 個人ライブラリや全曲のブックマーク管理など、次の安定版に向けた新機能を試したい方へ | [インストーラー・ポータブル ZIP・チェックサム](https://github.com/DanRuguo/dan_player/releases/tag/v26.0.5-snapshot.3) |

**インストーラー版**はセットアップを実行してください。既存のインストールを更新できます。**ポータブル版**は ZIP 全体を展開して `Dan Player.exe` を起動してください。EXE だけを取り出さないでください。26.0.5 プレビュー版では、デスクトップ歌詞は同じ実行ファイルから別プロセスとして起動します。

> **ダウンロードと署名について**：本プロジェクトの実行ファイルには RCEIT.Inc の自己署名証明書を使用しているため、Windows に信頼性の警告が表示される場合があります。インストーラーが信頼済み証明書を自動で登録することはありません。古い署名のバージョンから更新する場合は、新しいインストーラーを手動でダウンロードしてください。プレビュー版は Latest の安定版を置き換えません。更新前に、アプリのバックアップと復元設定から個人データを保存することをおすすめします。

<a id="download-verification"></a>

<details>
<summary><strong>SHA-256 でダウンロードしたファイルを確認する</strong></summary>

同じ Release ページからプログラムと `SHA256SUMS` をダウンロードします。インストーラーまたは ZIP の SHA-256 を計算し、チェックサムファイルと GitHub のアセットダイジェストに一致することを確認してください。以下のファイル名は、実際にダウンロードしたものに置き換えてください。

```powershell
Get-FileHash -LiteralPath '.\DanPlayer-VERSION-Setup-x64.exe' -Algorithm SHA256
```

ハッシュの一致は公開アセットと同じ内容であることを示しますが、Windows が署名証明書を信頼することとは別です。入手元を確認し、不明なファイルを実行するためにシステムのセキュリティ機能を無効にしないでください。

</details>

<a id="features"></a>

## 主な機能

1 曲を探すときも、コレクション全体を整理するときも、同じ音楽ライブラリを中心に操作できます。

| 分野 | できること |
| --- | --- |
| **ライブラリと検索** | アーティスト・アルバム・形式・フォルダー別に閲覧。楽曲検索、メタデータの一括編集、ライブラリの状態確認に対応。 |
| **プレイリストとキュー** | 階層型プレイリスト、ドラッグによる並べ替え、スマート条件、M3U8 の入出力。キューの保存、操作の取り消し、プレイリストの復元。 |
| **歌詞** | 歌詞の検索・編集・改訂・ロック・タイミング調整。全文検索、デスクトップ歌詞、ミニプレーヤーでの表示。 |
| **再生と位置指定** | CUE トラック再生、イコライザー、音量の均一化、曲ごとの続きからの再生、A–B リピート。再生位置や区間を保存し、全曲のブックマークをまとめて管理。 |
| **個人の音楽データ** | 個人の評価とタグ、絞り込み。聴いている時間帯、楽曲ランキング、ライブラリの構成、ファイルの使用容量を確認。 |
| **Windows での操作** | ジャケットに合わせた配色、ライト／ダークテーマ、4 言語の画面表示。ショートカット、ミニウィンドウ、タスクバープレビュー、再生診断。 |

この一覧は現在のリポジトリを基準としており、一部の機能は 26.0.5 プレビュー版で利用できます。配布パッケージに含まれる機能は、対応する [Release の更新内容](https://github.com/DanRuguo/dan_player/releases)をご確認ください。

オンライン音楽やカスタムソースも、ローカルでの再生を補う機能として利用できます。カスタムサービスは、明示的に宣言した機能に応じて検索や歌詞などを提供します。接続方法は[カスタム音楽ソース API](docs/custom-music-source-api.md)をご覧ください。

<a id="screenshots"></a>

## インターフェース

### コレクションを、自分の使い方に合わせて整理

| プレイリストとコレクション | 外観と設定 |
| --- | --- |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/playlists-dark-wide.png"><img src="docs/images/playlists-light-wide.png" alt="中国語 UI のプレイリスト管理画面" width="600"></picture> | <picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/settings-dark-wide.png"><img src="docs/images/settings-light-wide.png" alt="中国語 UI のテーマとグループ別設定" width="600"></picture> |

### 聴きたい曲を見つけ、歌詞に集中

| 楽曲検索 | ミニプレーヤーと歌詞 |
| --- | --- |
| ![架空の楽曲を使った中国語 UI の検索画面](docs/images/feature-search-dark.png) | ![架空のデータを使ったミニプレーヤーと歌詞表示](docs/images/feature-mini-lyrics-dark.png) |

### 再生記録から、自分のライブラリを再発見

![架空のデータを使った中国語 UI の音楽統計とランキング](docs/images/statistics-rankings-light.png)

<sub>画像はリポジトリ内の既存リソースを使用しています。実際の Flutter ウィジェットを架空の楽曲と隔離データでレンダリングしたもので、リアルタイム音声や Windows ネイティブ効果の動作検証を示すものではありません。掲載画像は中国語 UI ですが、アプリは英語・日本語・韓国語にも対応しています。明暗テーマ、ウィンドウ幅、その他の機能は<a href="docs/images/README.md">画像ギャラリー</a>で確認できます。</sub>

<a id="quick-start"></a>

## 使い始める

**音楽を追加する。** 音楽ファイルまたはフォルダーを取り込み、楽曲・分類・プレイリストの各画面から閲覧します。階層型プレイリストやドラッグでの並べ替えを使って整理できます。

**自分の評価とタグを付ける。** 26.0.5 プレビュー版では、分類画面の **「個人ライブラリ → 楽曲」** で、評価や個人タグを付けた曲を表示し、日付・評価・タグで絞り込めます。個人の評価とタグはプレーヤーのデータに保存され、**音楽ファイルには書き込まれません**。一方、メタデータ編集やタグの一括編集はファイルの内容を変更するため、保存前に変更のプレビューを確認してください。

**好きな瞬間を残す。** 再生中の画面で、その他メニューから再生ブックマークのダイアログを開き、現在位置または A–B 区間を保存します。保存した項目は、分類画面の **「個人ライブラリ → すべてのブックマーク」** で検索できます。この一覧の再生ボタンは保存した開始位置から再生します。A–B リピートを復元する場合は、該当する曲の再生ブックマークダイアログでその区間を選択してください。

**データをバックアップする。** 設定のバックアップと復元機能でプレーヤーのデータを保存します。プログラムの更新と個人データのバックアップは別の操作です。インストール先のプログラムファイルは、ライブラリ・プレイリスト・設定のバックアップの代わりにはなりません。

<details>
<summary><strong>よく使うショートカット</strong></summary>

| キー | 操作 |
| --- | --- |
| `Space` | 再生／一時停止 |
| `Ctrl + Left` / `Ctrl + Right` | 前の曲／次の曲 |
| `Left` / `Right` | 5 秒戻る／進む |
| `Ctrl + M` | ミニプレーヤーを切り替え |
| `F11` | 全画面表示を切り替え |
| `F1` | ショートカット一覧を表示 |

</details>

<a id="documentation"></a>

## ドキュメントとフィードバック

[画像ギャラリー](docs/images/README.md) · [カスタム音楽ソース API](docs/custom-music-source-api.md) · [go-music-api 設定例](docs/examples/go-music-api-jamendo.json) · [すべてのリリース](https://github.com/DanRuguo/dan_player/releases)

リンク先のギャラリーと API ドキュメントは現在、中国語で提供しています。設定例のサービスアドレスは、ご自身で配置したサービスのものに置き換えてください。問題を報告する際は、まず[既存の Issues](https://github.com/DanRuguo/dan_player/issues)を確認し、[報告テンプレート](https://github.com/DanRuguo/dan_player/issues/new/choose)を使用してください。プレーヤーのバージョン、再現手順、必要に応じて表示言語・ウィンドウサイズ・表示スケールを記載してください。再生に関する問題には、個人情報を除いた診断データを添付できます。私的な音楽ファイル、認証情報、個人の完全なディレクトリパスは公開しないでください。

<a id="development"></a>

## 開発とビルド

**Flutter・Rust・BASS** を使用しています。開発には Flutter、Rust、および Visual Studio の「C++ によるデスクトップ開発」ワークロードが必要です。Dart の制約は [pubspec.yaml](pubspec.yaml)、解決済みの依存バージョンは [pubspec.lock](pubspec.lock) と [rust/Cargo.lock](rust/Cargo.lock) をご確認ください。Windows の継続的インテグレーションは [Windows CI](.github/workflows/windows_ci.yml) に定義しています。

<details>
<summary><strong>ソース構成・デバッグ・対象を絞った確認</strong></summary>

| ディレクトリ | 用途 |
| --- | --- |
| `lib/` | UI、ライブラリ、再生サービス |
| `rust/`、`rust_builder/` | タグ処理と Flutter/Rust の橋渡し |
| `windows/`、`installer/` | Windows 統合とインストーラー |
| `third_party/` | 同梱コンポーネントとライセンス情報 |
| `test/`、`test_driver/` | 自動テスト |
| `scripts/` | ビルド・検証・リリース用スクリプト |
| `docs/` | API ドキュメント、設定例、UI 画像 |

リポジトリのルートで実行してください。日常使用しているライブラリと設定に影響しないよう、独立したデータディレクトリを使用します。

```powershell
$env:DAN_PLAYER_DATA_DIR = [IO.Path]::GetFullPath((Join-Path (Get-Location).Path '../tool/qa-data/readme-debug'))
flutter pub get
flutter run -d windows
```

起動前に BASS ランタイムを準備してください。関連スクリプトは `scripts/prepare_bass_runtime.ps1` と `scripts/prepare_bass_fx_runtime.ps1` です。マシン固有の SDK、ランタイムキャッシュ、署名設定のパスは、ソースリポジトリ外のローカル `DEVELOPMENT.md` にのみ記録します。

確認手順は必要な範囲に絞り、関連する変更をモジュール単位でまとめて検証します。機能を 1 つ追加するたびに全体の回帰テスト・ビルド・署名を繰り返さないでください。統計と詳細レイアウトの変更なら、例えば次のテストを実行します。

```powershell
flutter test test/statistics_visualization_test.dart test/detail_diagnostics_layout_test.dart --no-pub
```

統合時の確認には `scripts/verify_interaction_regressions.ps1` を使用します。UI の変更は、実際の Flutter ウィジェットをレンダリングして確認してください。公開画像は `scripts/render_public_ui.ps1` と隔離された架空のデータで生成し、表示言語・ウィンドウ幅・文字倍率を確認します。ウィジェットのレンダリングは、実際の音声機器や Windows デスクトップ統合の検証を置き換えません。

</details>

<details>
<summary><strong>Windows ビルドとリリース</strong></summary>

既存のリリーススクリプトは、ソースを `dan_player/`、同階層の `tool/` をツールチェーンとキャッシュ、`dist/` を出力先とするワークスペース構成を想定しています。`build_windows_release.ps1` は依存関係とリリース条件を確認し、Windows アプリをビルドしてフォントとランタイムを検証します。

```powershell
# 上記のワークスペース構成で、署名証明書なしの場合にソースリポジトリから実行:
.\scripts\build_windows_release.ps1 -SkipSigning
```

`-SkipPackaging` はポータブルパッケージの作成を省略し、`-NoRestore` は復元済みの依存関係を再利用します。署名付きリリースには証明書の別途設定が必要です。インストーラーは `scripts/build_windows_installer.ps1` で作成し、ポータブル版とインストーラーはそれぞれ `verify_local_release.ps1`、`verify_windows_installer.ps1` で検証します。

同じコード状態では、有効な検証結果とビルド成果物を再利用し、失敗した場合も必要な段階だけを再実行します。署名後にソースコミット、テストの検証記録、成果物の SHA-256 と署名を確認してから、必要な GitHub 公開手順のみを実行してください。プレビュー版は prerelease のままとし、安定版の Latest を置き換えません。手順の簡略化を理由に、重要な検証を省略しないでください。

</details>

長期的に必要なドキュメントだけを維持します。ローカルの開発メモ、過去の QA 出力、一時ログ、ツールキャッシュ、個人データ、署名用秘密鍵はソースリポジトリに含めません。公開 UI 画像は `docs/images/` に集約し、画像を変更した際は参照も更新します。

<a id="license"></a>

## ライセンスと謝辞

本プロジェクトは [LICENSE](LICENSE) に従って配布します。サードパーティーのコンポーネントには、それぞれのライセンス条件が適用されます。BASS の利用と配布は公式ライセンスに従ってください。

Dan Player は [Ferry-200/coriander_player](https://github.com/Ferry-200/coriander_player) を基に開発しています。プレーヤーの基盤、ライブラリ構造、歌詞表示を提供してくださった原作者に感謝します。また、[desktop_lyric](https://github.com/Ferry-200/desktop_lyric)、[music_api_dart](https://github.com/Ferry-200/music_api_dart)、[BASS](https://www.un4seen.com/bass.html)、[Lofty](https://crates.io/crates/lofty)、[flutter_rust_bridge](https://pub.dev/packages/flutter_rust_bridge)、[Flutter](https://flutter.dev/)、Material Design にも感謝します。

<sub>バッジは <a href="https://shields.io/">Shields.io</a> を利用しています。ダウンロード数は Release アセットのダウンロード回数であり、利用者数やインストール数ではありません。技術バッジは使用技術を示し、最低対応バージョンを示すものではありません。</sub>
