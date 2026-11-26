<div align="center">

<p>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/player-icon-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="docs/images/player-icon-light.png">
    <img src="docs/images/player-icon-light.png" alt="Dan Player のアプリアイコン" width="128">
  </picture>
</p>

<h1>Dan Player</h1>

<p><strong>ローカルの音楽コレクションのために。</strong></p>

<p>Material 3 Expressive を採用した Windows x64 向けのローカル優先音楽プレーヤー。<br>
ライブラリ整理、日英の発音注釈付き歌詞、高音質再生、低負荷なデスクトップ連携を両立します。</p>

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
  <a href="https://github.com/DanRuguo/dan_player/releases">プレビュー版・全リリース</a> ·
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
    <img src="docs/images/library-light-wide.png" alt="架空データを使用した Dan Player の音楽ホーム画面と Material 3 Expressive コントロール" width="1200">
  </picture>
</p>

<p align="center">
  <a href="#download">ダウンロード</a> ·
  <a href="#features">特長</a> ·
  <a href="#screenshots">インターフェース</a> ·
  <a href="#quick-start">使い始める</a> ·
  <a href="#development">開発とビルド</a>
</p>

<a id="download"></a>

## ダウンロードとインストール

| チャンネル | 用途 | ダウンロード |
| --- | --- | --- |
| **最新安定版** | 日常利用と上書き更新 | [安定版インストーラー・ポータブル ZIP・チェックサム](https://github.com/DanRuguo/dan_player/releases/latest) |
| **プレビュー版（Snapshot）** | 最新の UI 刷新・発音ルビ・音声機能を試す | [プレビュー版と追加コンポーネント](https://github.com/DanRuguo/dan_player/releases) |

**インストーラー版**は Material 3 Expressive のセットアップ画面を備え、導入済みコンポーネントを保ったまま更新できます。**ポータブル版**は ZIP 全体を展開して `Dan Player.exe` を起動してください（EXE 単体だけをコピーしないでください）。デスクトップ歌詞は同じ実行ファイルから別プロセスとして起動します。

完全ポータブル版には、ロスレス軽量化した**音声専用 FFmpeg 7.1.1** と**オフライン日本語読みデータ 3 種**（主辞書・語彙補完・漢字読み補完）およびライセンスを同梱しており、変換・切り出し・オフラインの読み仮名生成をすぐに利用できます。軽量インストーラーにはこの 2 種類の大型コンポーネントを含めませんが、設定から必要時に取得でき、ファイルサイズと SHA-256 を検証して `tool` に導入・再検証します（現在のプレビュー用コンポーネントは [v26.1.2-snapshot.8 のリリースページ](https://github.com/DanRuguo/dan_player/releases/tag/v26.1.2-snapshot.8)で配布）。**1 MB 未満のオフライン英語国際音声記号（IPA）辞書は両エディションに内蔵されており、追加ダウンロードは不要です。**

> **ダウンロードと署名について**：本プロジェクトの実行ファイルは RCEIT.Inc の自己署名証明書を使用しているため、Windows に信頼性の警告が表示される場合があります。インストーラーがルート証明書を自動登録することはありません。プレビュー版は Latest の安定版を置き換えません。更新前にバックアップと復元から個人データを保存することをおすすめします。

<a id="download-verification"></a>

<details>
<summary><strong>SHA-256 でダウンロードしたファイルを確認する</strong></summary>

同じ Release からプログラムと対応するチェックサムを取得し、ポータブル ZIP は `SHA256SUMS`、インストーラーは同名の `.exe.sha256` と照合してください。

```powershell
Get-FileHash -LiteralPath '.\DanPlayer-VERSION-Setup-x64.exe' -Algorithm SHA256
```

ハッシュの一致は公開アセットと同じ内容であることを示しますが、Windows による証明書の信頼とは別です。不明なファイルを実行するためにシステムのセキュリティ機能を無効にしないでください。

</details>

<a id="features"></a>

## 特長

- **ライブラリと構文検索：** アーティスト・アルバム・ビットレート・長さ・言語・形式・ソース・フォルダー別の閲覧に加え、複数ディスクの見出しとサブタイトル、Opus／コンテナの実効ビットレート補完、CUE 分割、メタデータ一括編集、ライブラリの健全性確認に対応。検索画面には複数語・ピンイン・誤字許容一致、5 種のクイック絞り込みピル、ワンクリック履歴消去を備えます。
- **4 表示プレイリストとキュー一括整理：** 階層型・スマートプレイリストとドラッグ整列を、リスト／グリッド／円形カバー／ツリーの 4 表示とカバー追従アニメーション付きで提供。キューは範囲選択・検索結果選択からの一括移動、削除、保存、書き出しと取り消し・やり直しに対応し、M3U／M3U8／PLS／XSPF を取り込めます。
- **音声の一括変換・書き出し：** 元ファイルのコピーまたは MP3／Opus／FLAC 変換、音質プリセット、CUE 分割、進捗とキャンセルに対応し、順序と重複を保持した相対パス M3U8 を出力します（変換には FFmpeg が必要で、元ファイルは変更しません）。
- **高品位再生と区間ツール：** 10 バンド EQ（Electronic／Acoustic／Commute などのプリセットと入出力に対応）、ReplayGain、独立ピッチ変更、音程維持の速度変更、WASAPI 排他出力、曲別レジューム、A–B リピート、全曲ブックマーク、クロスフェード（同一アルバム除外可）、曲頭・曲末の無音スキップを搭載。
- **日英ルビ付き歌詞と 2 種類のエディター：** 単語単位の強調、ミリ秒許容の翻訳ペアリング、オフライン日本語ルビ、および**内蔵オフライン英語 IPA 発音表記**（標準・`/…/`・`[…]` の 3 スタイル、日英混在行での同時表示とオフライン一括生成に対応）。LRC／QRC／KRC／TTML（`itunes:timing` 対応）と埋め込み歌詞のフォールバック、2 パスシェーダーによる滑らかな上下端ブラー、タップ編集・コード編集を備えます。
- **ジャケット演出とシームレス遷移：** 埋め込み画像・フォルダー内カバー・GIF に対応し、輪郭グロー・水滴屈折・タップ波紋を描画。分類切り替えは GPU オフスクリーン交差フェードで暗転ちらつきを抑え、アルバム詳細とアーティスト詳細は `192×192` で揃えた双方向カバー飛行と関連カード即再生に対応します。
- **スペクトラム・動き・省電力：** 丸みのあるバーとピクセルスペクトラム、10 系統のアニメーション制御、視差効果の軽減、非表示時の描画停止、可変／固定フレームレート上限、省電力プリセット、任意の XAudio2 タッチ効果音を提供します。
- **Material 3 Expressive デスクトップ連携：** 4 言語に応じた可変幅レイアウト、明暗テーマとカバー配色、ミニプレーヤー、カバーと再生操作を備えたアンチエイリアス対応システムトレイメニュー、排他切り替えのデスクトップ歌詞／タスクバー歌詞（起動直後の空の Windows SMTC 表示も抑止）。
- **統計・容量内訳・15 日間ログ診断：** ヒーロー集計・KPI カード・24 時間分布・90 日間の曜日別傾向・メダル付きランキングに加え、音楽ファイルを書き換えない個人評価・タグ、共有の CPU／GPU／メモリ監視、キャッシュ分類表示、**15 日間自動整理・ミリ秒タイムスタンプ付き日次ログ**と個人パス秘匿を備えた「問題を報告」ポップアップを搭載。
- **暗号化バックアップと選択復元：** 音楽フォルダー、ライブラリ、プレイリスト、統計、設定、キャッシュを選んで `.bak` に保存し、パスワード暗号化・重複排除・選択復元・キャンセルに対応します。

歌詞とコメントはローカルと保存済みキャッシュを優先します。自動オンライン取得は任意で有効化でき、一時的な通信失敗時は曲ごとに指数バックオフし、手動更新で即座に再試行します。連携仕様は[カスタム音楽ソース API](docs/custom-music-source-api.md)をご覧ください。

<a id="screenshots"></a>

## インターフェース

### 分類モザイクタイル・複数ディスク詳細・階層プレイリスト

<picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/feature-category-tiles-dark.png"><img src="docs/images/feature-category-tiles-light.png" alt="分類モザイクタイルと Material 3 Expressive ツールバー（架空のデモデータ）" width="1200"></picture>

| 階層プレイリストと 4 つの表示モード | 複数ディスク詳細と関連アーティスト即再生 |
| --- | --- |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/playlists-dark-wide.png"><img src="docs/images/playlists-light-wide.png" alt="円形カバーとサブプレイリストを備えたプレイリスト画面" width="600"></picture> | ![Disc 1/2 セクション見出し・合計時間・関連アーティストカードを表示するアルバム詳細](docs/images/feature-album-detail-dark.png) |

### 日本語ルビ＋英語 IPA 歌詞・10 バンド EQ・スペクトラム

| 日本語ルビ＋英語 IPA の歌詞表示 | 10 バンド EQ とシーン別プリセット |
| --- | --- |
| ![ジャケットの光演出と日本語かな・英語 IPA を同時表示する再生画面](docs/images/feature-now-playing-lyrics-dark.png) | ![帯域カプセルと Electronic / Acoustic / Commute プリセットを備えた 10 バンド EQ](docs/images/feature-equalizer-dark.png) |

| 半透明カードで次の 4 曲を表示 | 丸いバーとピクセルのスペクトラムガイド |
| --- | --- |
| ![日本語 UI の次曲プレビュー：半透明の 4 枚のカードを 2 列に表示](docs/images/feature-upcoming-ja.png) | ![日本語 UI の操作ガイド：丸いバーとピクセルのスペクトラム](docs/images/feature-spectrum-guide-ja.png) |

### 統合ルビ／IPA 設定・ミニプレーヤー・2 種類の歌詞編集

| 歌詞の読み仮名・英語 IPA 統合設定 | ミニプレーヤーと対訳歌詞 |
| --- | --- |
| ![日本語ルビと内蔵英語 IPA のスタイル・一括生成をまとめた設定カード](docs/images/feature-lyric-annotations-light.png) | ![ミニプレーヤーでのカバー・対訳歌詞・カプセル操作](docs/images/feature-mini-lyrics-dark.png) |

| タップ編集：本文・翻訳・発音の準備 | タップ編集：狭い画面での単語タイミング |
| --- | --- |
| ![タップ編集のテキスト・翻訳・読み入力](docs/images/lyric-tap-text-zh.png) | ![狭いウィンドウでの単語ごとのタイミング記録](docs/images/lyric-tap-words-narrow-zh.png) |

| コード編集：QRC 歌詞コード | コード編集：単語同期プレビュー |
| --- | --- |
| ![QRC コード編集画面](docs/images/lyric-code-editor-zh.png) | ![単語単位の同期プレビュー画面](docs/images/lyric-editor-preview-zh.png) |

### クイック検索・フォルダーツリー・再生統計

| クイック検索ピルと履歴の一括消去 | フォルダーツリーと楽曲一覧 |
| --- | --- |
| ![日本語の検索ページ：クイック絞り込みピル、履歴消去、中央揃えの履歴チップ](docs/images/search-history-ja.png) | ![フォルダー階層ツリーとトラック一覧](docs/images/feature-folders-light.png) |

| 音楽統計サマリーと 24 時間分布 | メダル付きランキングと再生傾向 |
| --- | --- |
| ![統計画面のヒーローバナー、KPI カード、24 時間グラフ](docs/images/feature-statistics-light.png) | ![統計画面のランキングと聴取傾向](docs/images/statistics-rankings-light.png) |

### 外観設定・15 日間ログ問題報告・リソース監視・復元

| 外観とグループ別設定 | 問題を報告ポップアップと 15 日間ログ |
| --- | --- |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/settings-dark-wide.png"><img src="docs/images/settings-light-wide.png" alt="グループ別設定と可変幅セグメントコントロール" width="600"></picture> | ![日本語 UI の問題を報告ダイアログ：分類ピル、個人パス秘匿、15 日間ミリ秒ログ](docs/images/feature-report-issue-ja.png) |

| サイドバーと設定で共有するリソース監視 | キャッシュと一時ファイルの容量内訳 |
| --- | --- |
| ![サイドバーのスパークラインと設定画面の CPU・GPU・メモリ監視](docs/images/process-resource-locations.png) | ![キャッシュ・ユーザーデータ・一時ファイルの容量内訳](docs/images/cache-storage-statistics.png) |

| 操作ガイド：日常のライブラリ操作 | 操作ガイド：シークとキュー整理デモ |
| --- | --- |
| ![音楽・分類・プレイリストの操作説明](docs/images/manual-common-library.png) | ![再生位置の体験デモとキュー整理ガイド](docs/images/manual-playback-demo.png) |

| 初回ガイド：言語選択と再生体験 | 暗号化バックアップからの選択復元 |
| --- | --- |
| ![日本語の初回オンボーディング画面](docs/images/feature-onboarding-ja.png) | ![日本語のプレーヤーデータ・音楽フォルダー選択復元画面](docs/images/feature-restore-ja.png) |

<sub>画像はすべて実際の Flutter ウィジェットと隔離されたデモデータによるオフスクリーン描画であり、実音声デバイスや Windows ネイティブ合成の検証結果ではありません。明暗テーマ・ウィンドウ幅・4 言語の全 64 枚は<a href="docs/images/README.md">画像ギャラリー</a>をご覧ください。</sub>

<a id="quick-start"></a>

## 使い始める

**音楽を追加する。** ファイルやフォルダーを取り込み、音楽・分類・プレイリスト・フォルダー画面から閲覧します。階層プレイリストとドラッグ操作で整理できます。

**個人の評価とタグを残す。** **「分類 → 個人ライブラリ → 楽曲」** で評価や個人タグを付けた曲を絞り込めます。個人の評価・タグはプレーヤーデータに保存され、**音楽ファイルには書き込まれません**（メタデータ編集や一括タグ編集はファイルタグを変更します）。

**お気に入りの区間を保存する。** 再生画面のその他メニューから再生ブックマークを開き、現在位置や A–B 区間を保存して **「分類 → 個人ライブラリ → すべてのブックマーク」** からいつでも呼び出せます。

**データをバックアップする。** 設定のバックアップと復元から、個人データとローカル音楽を暗号化 `.bak` として保存・選択復元できます（暗号化バックアップ 1 個は約 64 GiB 未満）。

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

問題を報告する際は、[既存の Issues](https://github.com/DanRuguo/dan_player/issues) を確認するか、「設定 → 更新とバージョン情報 → 問題を報告」から過去 15 日間のタイムスタンプ付きログを絞り込み（個人ディレクトリパスは既定で秘匿）、[GitHub の下書き](https://github.com/DanRuguo/dan_player/issues/new/choose)を開いて送信してください。私的な音楽ファイルや認証情報は公開しないでください。

<a id="development"></a>

## 開発とビルド

**Flutter・Rust・BASS** を使用しています。Dart 制約は [pubspec.yaml](pubspec.yaml)、依存バージョンは [pubspec.lock](pubspec.lock) と [rust/Cargo.lock](rust/Cargo.lock)、CI は [Windows CI](.github/workflows/windows_ci.yml) を参照してください。

<details>
<summary><strong>ソース構成・デバッグ・検証</strong></summary>

| ディレクトリ | 用途 |
| --- | --- |
| [lib/](lib/) | 主 UI、ライブラリ、発音注釈歌詞、診断ログ、再生サービス、モデル |
| [third_party/desktop_lyric/](third_party/desktop_lyric/) | 共用のデスクトップ歌詞、4 言語カタログ、内蔵フォント、Windows ホスト |
| [rust/](rust/)、[rust_builder/](rust_builder/) | タグ／カバー解析、辞書構築ツール、Flutter/Rust 連携、Cargokit |
| [windows/](windows/)、[installer/](installer/) | Windows トレイ／タッチ音統合と Material 3 Expressive インストーラー |
| [scripts/](scripts/) | ランタイム準備、モジュール作成、ビルド、署名、成果物検証 |
| [assets/](assets/)、[shaders/](shaders/)、[docs/](docs/) | 内蔵英語 IPA 辞書、シェーダー、API 文書、公開ギャラリー画像 |

独立したデータディレクトリを指定して実行します：

```powershell
$env:DAN_PLAYER_DATA_DIR = [IO.Path]::GetFullPath((Join-Path (Get-Location).Path '../tool/qa-local/readme-debug'))
flutter pub get
flutter run -d windows
```

BASS ランタイムは `scripts/prepare_bass_runtime.ps1` と `scripts/prepare_bass_fx_runtime.ps1` で用意し、必要な範囲を `flutter test --no-pub <test-entry>` と `cargo test --manifest-path rust/Cargo.toml --locked <test-filter>` で確認します。

</details>

<details>
<summary><strong>Windows ビルドとリリース</strong></summary>

```powershell
.\scripts\build_windows_release.ps1 -SkipSigning
```

インストーラーは `scripts/build_windows_installer.ps1` で作成し、`verify_local_release.ps1` と `verify_windows_installer.ps1` で検証します。ポータブル版への追加コンポーネント同梱には `scripts/assemble_windows_release.ps1 -IncludeOptionalComponents` を使用します。

</details>

<a id="license"></a>

## ライセンスと謝辞

本プロジェクトは [LICENSE](LICENSE) に従って配布します。BASS の利用と配布は公式ライセンスに従ってください。

内蔵の [Source Han Sans SC／JP](licenses/SOURCE-HAN-SANS/PROVENANCE.md)、[Google Sans](licenses/GOOGLE-SANS/PROVENANCE.md)、[Pretendard](licenses/PRETENDARD/PROVENANCE.md) は SIL Open Font License 1.1 で配布します（`DanPingFangSC` は Source Han Sans SC の互換エイリアスで、Apple フォントは含みません）。

[Ferry-200/coriander_player](https://github.com/Ferry-200/coriander_player) を基に開発しており、[desktop_lyric](https://github.com/Ferry-200/desktop_lyric)、[music_api_dart](https://github.com/Ferry-200/music_api_dart)、[BASS](https://www.un4seen.com/bass.html)、[Lofty](https://crates.io/crates/lofty)、[flutter_rust_bridge](https://pub.dev/packages/flutter_rust_bridge)、[Flutter](https://flutter.dev/)、Material Design に感謝します。

内蔵英語 IPA 辞書の出典：[CMUDict](licenses/CMUDICT/PROVENANCE.md)。オフライン日本語辞書の出典：[IPADIC](licenses/IPADIC/PROVENANCE.md) / [EDRDG](licenses/EDRDG/PROVENANCE.md)・[Lindera](licenses/LINDERA/LICENSE)。オンライン読み仮名：[Web Services by Yahoo! JAPAN](https://developer.yahoo.co.jp/sitemap/)。

<sub>バッジは <a href="https://shields.io/">Shields.io</a> を利用しています。ダウンロード数は利用者数とは異なり、技術バッジは最低対応 OS バージョンを示すものではありません。</sub>
