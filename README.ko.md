<div align="center">

<p>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/player-icon-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="docs/images/player-icon-light.png">
    <img src="docs/images/player-icon-light.png" alt="Dan Player 앱 아이콘" width="128">
  </picture>
</p>

<h1>Dan Player</h1>

<p><strong>나만의 로컬 음악 컬렉션을 위한 플레이어.</strong></p>

<p>Material 3 Expressive 디자인을 적용한 로컬 중심 Windows x64 음악 플레이어로,<br>
라이브러리 정리, 한·영·일 발음 주석 가사, 고음질 오디오 제어와 저전력 데스크톱 환경을 함께 제공합니다.</p>

<p align="center">
  <a href="https://github.com/DanRuguo/dan_player/releases/latest"><img src="https://img.shields.io/github/v/release/DanRuguo/dan_player?style=flat&amp;labelColor=374151&amp;label=stable&amp;logo=github&amp;logoColor=white&amp;color=2563EB" alt="최신 안정 버전"></a>
  <a href="https://github.com/DanRuguo/dan_player/releases"><img src="https://img.shields.io/github/v/release/DanRuguo/dan_player?style=flat&amp;labelColor=374151&amp;include_prereleases&amp;filter=v%2A-snapshot.%2A&amp;sort=semver&amp;label=preview&amp;color=D97706" alt="최신 snapshot 미리 보기 버전"></a>
  <a href="https://github.com/DanRuguo/dan_player/releases"><img src="https://img.shields.io/github/downloads/DanRuguo/dan_player/total?style=flat&amp;labelColor=374151&amp;label=downloads&amp;color=059669" alt="GitHub Release 에셋 다운로드 수"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/DanRuguo/dan_player?style=flat&amp;labelColor=374151&amp;label=license&amp;color=64748B" alt="프로젝트 라이선스"></a>
</p>

<p align="center">
  <a href="#download"><img src="https://img.shields.io/badge/platform-Windows%20x64-0078D4?style=flat&amp;labelColor=374151" alt="플랫폼: Windows x64"></a>
  <a href="#development"><img src="https://img.shields.io/badge/Flutter-UI-02569B?style=flat&amp;labelColor=374151&amp;logo=flutter&amp;logoColor=white" alt="Flutter: UI"></a>
  <a href="#development"><img src="https://img.shields.io/badge/Rust-Bridge-B45309?style=flat&amp;labelColor=374151&amp;logo=rust&amp;logoColor=white" alt="Rust: 네이티브 연결"></a>
  <a href="https://www.un4seen.com/bass.html"><img src="https://img.shields.io/badge/BASS-Audio-6750A4?style=flat&amp;labelColor=374151" alt="BASS: 오디오 재생"></a>
</p>

<p>
  <a href="https://github.com/DanRuguo/dan_player/releases/latest"><strong>안정 버전 다운로드</strong></a> ·
  <a href="https://github.com/DanRuguo/dan_player/releases">미리 보기 및 전체 릴리스</a> ·
  <a href="https://github.com/DanRuguo/dan_player/releases">변경 내용</a> ·
  <a href="https://github.com/DanRuguo/dan_player/issues/new/choose">문제 보고</a>
</p>

<p>
  <a href="README.md">简体中文</a> ·
  <a href="README.en.md">English</a> ·
  <a href="README.ja.md">日本語</a> ·
  <strong>한국어</strong>
</p>

</div>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/library-dark-wide.png">
    <source media="(prefers-color-scheme: light)" srcset="docs/images/library-light-wide.png">
    <img src="docs/images/library-light-wide.png" alt="가상 데이터를 사용한 Dan Player 음악 홈 화면과 Material 3 Expressive 컨트롤" width="1200">
  </picture>
</p>

<p align="center">
  <a href="#download">다운로드</a> ·
  <a href="#features">특징</a> ·
  <a href="#screenshots">화면 미리 보기</a> ·
  <a href="#quick-start">시작하기</a> ·
  <a href="#development">개발 및 빌드</a>
</p>

<a id="download"></a>

## 다운로드 및 설치

| 채널 | 용도 | 다운로드 |
| --- | --- | --- |
| **최신 안정 버전** | 일상적인 감상과 덮어쓰기 업데이트 | [안정 버전 설치 프로그램, 포터블 ZIP 및 체크섬](https://github.com/DanRuguo/dan_player/releases/latest) |
| **미리 보기 버전 (Snapshot)** | 최신 UI 개편, 발음 주석 가사 및 오디오 기능 체험 | [미리 보기 릴리스 및 선택 구성 요소](https://github.com/DanRuguo/dan_player/releases) |

**설치 버전**은 Material 3 Expressive 설치 마법사를 제공하며 기존에 설치한 확장 구성 요소를 유지한 채 업데이트할 수 있습니다. **포터블 버전**은 ZIP 전체를 압축 해제한 뒤 `Dan Player.exe`를 실행하세요(EXE 파일만 따로 복사하지 마세요). 바탕 화면 가사는 같은 실행 파일에서 별도 프로세스로 실행됩니다.

전체 포터블 ZIP에는 무손실 경량화된 **오디오 전용 FFmpeg 7.1.1**과 **오프라인 일본어 읽기 데이터 3종**(기본 사전·어휘 보충·한자 읽기 보충) 및 라이선스가 포함되어 변환, 미리 듣기/자르기와 오프라인 후리가나 생성을 바로 사용할 수 있습니다. 경량 설치 프로그램은 이 두 가지 대용량 구성 요소를 제외하지만, 필요할 때 설정에서 내려받아 파일 크기와 SHA-256을 검증한 뒤 `tool` 폴더에 설치하고 재검사합니다(현재 미리 보기 구성 요소는 [v26.1.2-snapshot.8 릴리스 페이지](https://github.com/DanRuguo/dan_player/releases/tag/v26.1.2-snapshot.8)에서 제공). **1 MB 미만의 오프라인 영어 국제음성기호(IPA) 사전은 두 버전 모두 기본 내장되어 별도 다운로드가 필요 없습니다.**

> **다운로드 및 서명 안내:** 프로젝트 실행 파일은 RCEIT.Inc 자체 서명 인증서를 사용하므로 Windows에서 신뢰 경고가 표시될 수 있습니다. 설치 프로그램은 루트 인증서를 자동으로 설치하지 않습니다. 미리 보기 버전은 Latest 안정 버전을 대체하지 않으며, 업데이트 전 백업 및 복원에서 개인 데이터를 백업하는 것을 권장합니다.

<a id="download-verification"></a>

<details>
<summary><strong>SHA-256으로 다운로드 파일 확인</strong></summary>

같은 Release에서 프로그램과 해당 체크섬(`SHA256SUMS` 또는 `.exe.sha256`)을 받아 해시를 비교하세요.

```powershell
Get-FileHash -LiteralPath '.\DanPlayer-VERSION-Setup-x64.exe' -Algorithm SHA256
```

해시 일치는 배포 에셋과 내용이 같음을 확인해 주며 Windows의 인증서 신뢰와는 별개입니다. 출처가 불분명한 파일을 실행하기 위해 시스템 보안 기능을 끄지 마세요.

</details>

<a id="features"></a>

## 특징

- **라이브러리와 구문 검색:** 아티스트·앨범·비트레이트·길이·언어·형식·소스·폴더별 탐색과 함께 멀티 디스크 구분 헤더 및 부제, Opus/컨테이너 유효 비트레이트 보완, CUE 분할 트랙, 메타데이터 일괄 편집, 라이브러리 상태 점검을 지원합니다. 검색 화면은 다중 단어·병음·오타 허용 검색, 5가지 빠른 필터 캡슐, 원클릭 검색 기록 비우기를 제공합니다.
- **4가지 재생목록 보기와 대기열 일괄 편집:** 계층형·스마트 재생목록과 드래그 정렬을 목록/사각 그리드/원형 커버/트리 4가지 보기와 커버 전환 추적으로 지원합니다. 대기열 다중·범위·검색 선택 후 다음/맨 뒤로 이동, 삭제, 저장·내보내기와 실행 취소/다시 실행이 가능하며 M3U/M3U8/PLS/XSPF를 가져올 수 있습니다.
- **오디오 일괄 변환 및 내보내기:** 원본 복사 또는 MP3/Opus/FLAC 변환, 음질 프리셋, CUE 분할, 진행률 및 취소를 지원하며 순서와 중복을 유지하는 상대 경로 M3U8을 생성합니다(변환 시 FFmpeg 필요, 원본 파일 유지).
- **고음질 재생과 구간 반복:** 10밴드 이퀄라이저(Electronic/Acoustic/Commute 등 프리셋 및 가져오기/내보내기 지원), ReplayGain 음량 평준화, 독립 음높이 조절, 피치 유지 속도 조절, WASAPI 단독 모드, 곡별 이어 듣기, A–B 구간 반복과 전체 북마크, 크로스페이드(같은 앨범 제외 가능) 및 앞뒤 무음 건너뛰기를 제공합니다.
- **일본어 후리가나·영어 IPA 가사와 2종 편집기:** 단어별 강조, 밀리초 허용 번역 정렬, 오프라인 일본어 후리가나와 **내장 오프라인 영어 IPA 발음 기호**(기본, `/…/`, `[…]` 3가지 스타일, 한·영·일 혼합 행 동시 표시 및 오프라인 일괄 생성)를 지원합니다. LRC/QRC/KRC/TTML(`itunes:timing` 포함) 및 내장 가사 폴백, 2패스 셰이더 연속 상하 블러, 탭 타이밍 편집기와 코드 편집기를 갖췄습니다.
- **커버 광원 효과와 매끄러운 화면 전환:** 내장·폴더 커버와 애니메이션 GIF, 윤곽 빛·물방울 굴절·탭 물결 효과를 지원합니다. 분류 전환 시 GPU 오프스크린 교차 디졸브로 어두운 환경의 깜빡임을 없애고, 앨범 상세와 아티스트 상세 간 `192×192` 정렬 양방향 커버 비행 및 연관 카드 즉시 재생을 제공합니다.
- **스펙트럼·모션·저전력 설계:** 둥근 막대와 픽셀 스펙트럼, 10가지 애니메이션 제어, 동작 줄이기, 창 숨김 시 클록 정지, 적응형/고정 주사율 제한, 절전 프리셋 및 선택적 XAudio2 터치 효과음을 제공합니다.
- **Material 3 Expressive 데스크톱 통합:** 4개 언어 가변 폭 타이포그래피, 밝고 어두운 테마와 커버 색상 추출, 미니 플레이어, 커버와 재생 버튼을 담은 안티앨리어싱 시스템 트레이 메뉴, 상호 배타적으로 동작하는 바탕 화면/작업 표시줄 가사(초기 빈 Windows SMTC 숨김 포함)를 지원합니다.
- **통계·저장 공간 분석·15일 로그 진단:** 히어로 배너, 핵심 KPI 카드, 24시간 분포, 90일 요일별 습관과 메달 순위표를 제공하며, 원본 파일을 건드리지 않는 개인 평점·태그, 공유 CPU/GPU/RAM 모니터, 캐시 분류 용량, **15일 자동 삭제 및 밀리초 타임스탬프 일별 로그**와 개인 경로 마스킹을 갖춘 팝업형 ‘문제 보고’ 창을 지원합니다.
- **암호화 백업 및 선택 복원:** 음악 폴더, 라이브러리, 재생목록, 통계, 설정, 캐시를 선택해 `.bak` 파일로 암호화 백업·중복 제거·선택 복원할 수 있습니다.

가사와 댓글은 기본적으로 로컬 파일과 저장된 캐시를 우선합니다. 자동 온라인 조회는 선택 사항이며 일시적 오류 시 곡별 지수 백오프를 적용하고 수동 새로고침 시 즉시 재시도합니다. 연동 규격은 [사용자 지정 음악 소스 API](docs/custom-music-source-api.md)를 참고하세요.

<a id="screenshots"></a>

## 화면 미리 보기

### 분류 모자이크 타일, 멀티 디스크 앨범 상세 및 계층형 재생목록

<picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/feature-category-tiles-dark.png"><img src="docs/images/feature-category-tiles-light.png" alt="가상 데모 데이터를 사용한 분류 모자이크 커버 타일과 Material 3 Expressive 캡슐 툴바" width="1200"></picture>

| 계층형 재생목록과 4가지 보기 모드 | 멀티 디스크 앨범 상세 및 연관 아티스트 즉시 재생 |
| --- | --- |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/playlists-dark-wide.png"><img src="docs/images/playlists-light-wide.png" alt="원형 커버와 하위 재생목록을 보여주는 재생목록 화면" width="600"></picture> | ![Disc 1/2 구분 헤더, 총 재생 시간, 연관 아티스트 카드를 표시하는 앨범 상세 화면](docs/images/feature-album-detail-dark.png) |

### 일본어 후리가나 + 영어 IPA 가사, 10밴드 EQ 및 스펙트럼

| 일본어 후리가나 + 영어 IPA 몰입형 가사 | 10밴드 이퀄라이저와 신규 프리셋 |
| --- | --- |
| ![커버 광원 효과와 일본어 가나·영어 IPA 발음 기호를 함께 보여주는 재생 화면](docs/images/feature-now-playing-lyrics-dark.png) | ![대역별 캡슐과 Electronic / Acoustic / Commute 프리셋을 갖춘 10밴드 EQ](docs/images/feature-equalizer-dark.png) |

| 다음 네 곡의 반투명 카드 | 둥근 막대와 픽셀 스펙트럼 가이드 |
| --- | --- |
| ![한국어 다음 곡 미리 보기: 네 개의 반투명 카드를 두 열로 표시](docs/images/feature-upcoming-ko.png) | ![한국어 사용 가이드의 둥근 막대와 픽셀 스펙트럼 시연](docs/images/feature-spectrum-guide-ko.png) |

### 통합 발음 주석 설정, 미니 플레이어 및 두 가지 가사 편집기

| 가사 후리가나 및 영어 IPA 통합 설정 | 미니 플레이어와 이중 언어 가사 |
| --- | --- |
| ![일본어 후리가나와 내장 영어 IPA 스타일·일괄 생성을 통합한 설정 카드](docs/images/feature-lyric-annotations-light.png) | ![커버, 번역 가사, 캡슐 컨트롤을 갖춘 미니 플레이어](docs/images/feature-mini-lyrics-dark.png) |

| 눌러서 타이밍 지정: 본문·번역·발음 준비 | 눌러서 타이밍 지정: 좁은 창에서 단어 기록 |
| --- | --- |
| ![가사 본문, 번역, 발음을 입력하는 탭 편집기](docs/images/lyric-tap-text-zh.png) | ![좁은 창에서 단어 타이밍을 기록하는 탭 편집기](docs/images/lyric-tap-words-narrow-zh.png) |

| 코드 편집기: QRC 가사 코드 | 코드 편집기: 단어 동기화 미리 보기 |
| --- | --- |
| ![QRC 가사 코드를 편집하는 화면](docs/images/lyric-code-editor-zh.png) | ![단어별 가사 동기화 미리 보기 화면](docs/images/lyric-editor-preview-zh.png) |

### 빠른 검색 필터, 폴더 트리 및 청취 통계

| 빠른 구문 필터와 검색 기록 비우기 | 폴더 트리와 디렉터리 트랙 |
| --- | --- |
| ![한국어 검색 페이지: 빠른 필터 캡슐, 기록 비우기, 가운데 정렬된 기록 칩](docs/images/search-history-ko.png) | ![폴더 계층 트리와 곡 목록 화면](docs/images/feature-folders-light.png) |

| 청취 통계 요약과 24시간 분포 | 메달 순위표와 청취 습관 |
| --- | --- |
| ![히어로 배너, KPI 그리드, 24시간 차트를 담은 통계 화면](docs/images/feature-statistics-light.png) | ![메달 배지 순위와 청취 분석을 보여주는 통계 화면](docs/images/statistics-rankings-light.png) |

### 외관 설정, 15일 로그 문제 보고, 리소스 모니터 및 선택 복원

| 외관 및 그룹별 설정 | 문제 보고 팝업과 15일 타임스탬프 로그 |
| --- | --- |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/settings-dark-wide.png"><img src="docs/images/settings-light-wide.png" alt="그룹별 설정과 언어별 가변 폭 세그먼트 컨트롤" width="600"></picture> | ![한국어 문제 보고 창: 유형 캡슐, 개인 경로 숨김, 15일 밀리초 로그 필터](docs/images/feature-report-issue-ko.png) |

| 사이드바·설정 공유 리소스 모니터링 | 캐시 및 임시 파일 용량 분류 |
| --- | --- |
| ![사이드바 스파크라인과 설정의 CPU·GPU·RAM 모니터링](docs/images/process-resource-locations.png) | ![캐시, 사용자 데이터, 임시 파일 용량 분류](docs/images/cache-storage-statistics.png) |

| 사용 가이드: 일상적인 라이브러리 조작 | 사용 가이드: 탐색 및 대기열 시연 |
| --- | --- |
| ![음악, 분류, 재생목록 조작 안내](docs/images/manual-common-library.png) | ![재생 위치 시연과 대기열 정리 안내](docs/images/manual-playback-demo.png) |

| 첫 실행 안내: 언어 선택과 재생 체험 | 암호화 백업 선택 복원 |
| --- | --- |
| ![한국어 첫 실행 인터랙티브 안내](docs/images/feature-onboarding-ko.png) | ![한국어 플레이어 데이터 및 로컬 음악 선택 복원 창](docs/images/feature-restore-ko.png) |

<sub>모든 이미지는 실제 Flutter 위젯과 격리된 데모 데이터를 오프스크린으로 렌더링한 예시이며, 실시간 오디오 하드웨어나 Windows 네이티브 합성 검증 결과가 아닙니다. 밝고 어두운 테마, 창 크기, 4개 언어 전체 64장 이미지는 <a href="docs/images/README.md">화면 갤러리</a>에서 확인하세요.</sub>

<a id="quick-start"></a>

## 시작하기

**음악 추가.** 오디오 파일이나 폴더를 가져온 뒤 음악, 분류, 재생목록, 폴더 화면에서 탐색하고 계층형 재생목록과 드래그 정렬로 정리하세요.

**개인 평점과 태그 관리.** **분류 → 개인 라이브러리 → 곡**에서 평점이나 개인 태그로 필터링할 수 있습니다. 개인 평점과 태그는 플레이어 데이터에만 저장되며 **원본 오디오 파일에는 기록되지 않습니다**(메타데이터 편집 및 일괄 태그 편집은 파일 태그를 수정합니다).

**좋아하는 구간 저장.** 재생 화면의 더 보기 메뉴에서 재생 북마크를 열어 위치나 A–B 구간을 저장하고 **분류 → 개인 라이브러리 → 모든 북마크**에서 모아 볼 수 있습니다.

**데이터 백업.** 설정의 백업 및 복원에서 플레이어 데이터와 음악 폴더를 암호화된 `.bak` 파일로 백업·선택 복원할 수 있습니다(단일 암호화 백업은 약 64 GiB 미만).

<details>
<summary><strong>자주 사용하는 단축키</strong></summary>

| 키 | 동작 |
| --- | --- |
| `Space` | 재생 / 일시 정지 |
| `Ctrl + Left` / `Ctrl + Right` | 이전 곡 / 다음 곡 |
| `Left` / `Right` | 5초 뒤로 / 앞으로 이동 |
| `Ctrl + M` | 미니 플레이어 전환 |
| `F11` | 전체 화면 전환 |
| `F1` | 단축키 보기 |

</details>

<a id="documentation"></a>

## 문서 및 피드백

[화면 갤러리](docs/images/README.md) · [사용자 지정 음악 소스 API](docs/custom-music-source-api.md) · [go-music-api 설정 예시](docs/examples/go-music-api-jamendo.json) · [전체 릴리스](https://github.com/DanRuguo/dan_player/releases)

문제를 제보하기 전에 [기존 Issues](https://github.com/DanRuguo/dan_player/issues)를 확인하거나, **설정 → 업데이트 및 정보 → 문제 보고**에서 최근 15일간의 타임스탬프 로그를 필터링해(개인 경로 기본 숨김) [GitHub 이슈 초안](https://github.com/DanRuguo/dan_player/issues/new/choose)을 열어 제출하세요. 개인 음악 파일이나 인증 정보는 업로드하지 마세요.

<a id="development"></a>

## 개발 및 빌드

**Flutter, Rust, BASS**로 제작되었습니다. Dart 제약은 [pubspec.yaml](pubspec.yaml), 의존성 잠금은 [pubspec.lock](pubspec.lock)과 [rust/Cargo.lock](rust/Cargo.lock), CI는 [Windows CI](.github/workflows/windows_ci.yml)를 확인하세요.

<details>
<summary><strong>소스 구조, 디버깅 및 집중 검사</strong></summary>

| 디렉터리 | 용도 |
| --- | --- |
| [lib/](lib/) | 기본 UI, 라이브러리, 발음 가사, 진단 로그, 재생 서비스 및 모델 |
| [third_party/desktop_lyric/](third_party/desktop_lyric/) | 공용 바탕 화면 가사, 4개 언어 카탈로그, 내장 글꼴 및 Windows 호스트 |
| [rust/](rust/), [rust_builder/](rust_builder/) | 태그/표지 분석, 사전 빌드 도구, Flutter/Rust 브리지 및 Cargokit |
| [windows/](windows/), [installer/](installer/) | Windows 트레이/터치음 호스트 및 Material 3 Expressive 설치 프로그램 |
| [scripts/](scripts/) | 런타임 준비, 모듈 패키징, 빌드, 서명 및 검증 스크립트 |
| [assets/](assets/), [shaders/](shaders/), [docs/](docs/) | 내장 영어 IPA 사전, 셰이더, API 문서 및 공개 갤러리 이미지 |

독립된 데이터 폴더로 실행합니다:

```powershell
$env:DAN_PLAYER_DATA_DIR = [IO.Path]::GetFullPath((Join-Path (Get-Location).Path '../tool/qa-local/readme-debug'))
flutter pub get
flutter run -d windows
```

`scripts/prepare_bass_runtime.ps1`과 `scripts/prepare_bass_fx_runtime.ps1`로 BASS 런타임을 준비하고, `flutter test --no-pub <test-entry>` 및 `cargo test --manifest-path rust/Cargo.toml --locked <test-filter>`로 관련 범위를 검증합니다.

</details>

<details>
<summary><strong>Windows 빌드 및 배포</strong></summary>

```powershell
.\scripts\build_windows_release.ps1 -SkipSigning
```

설치 프로그램은 `scripts/build_windows_installer.ps1`로 빌드하고 `verify_local_release.ps1`, `verify_windows_installer.ps1`로 검증합니다. 포터블 패키지에 선택 구성 요소를 포함할 때는 `scripts/assemble_windows_release.ps1 -IncludeOptionalComponents`를 사용합니다.

</details>

<a id="license"></a>

## 라이선스 및 감사의 말

이 프로젝트는 [LICENSE](LICENSE)에 따라 배포되며 BASS 사용과 배포는 공식 라이선스를 따릅니다.

내장 [Source Han Sans SC / JP](licenses/SOURCE-HAN-SANS/PROVENANCE.md), [Google Sans](licenses/GOOGLE-SANS/PROVENANCE.md), [Pretendard](licenses/PRETENDARD/PROVENANCE.md)는 SIL Open Font License 1.1로 배포됩니다(`DanPingFangSC`는 Source Han Sans SC의 내부 호환 별칭이며 Apple 글꼴을 포함하지 않습니다).

[Ferry-200/coriander_player](https://github.com/Ferry-200/coriander_player)를 기반으로 개발되었으며 [desktop_lyric](https://github.com/Ferry-200/desktop_lyric), [music_api_dart](https://github.com/Ferry-200/music_api_dart), [BASS](https://www.un4seen.com/bass.html), [Lofty](https://crates.io/crates/lofty), [flutter_rust_bridge](https://pub.dev/packages/flutter_rust_bridge), [Flutter](https://flutter.dev/), Material Design에 감사드립니다.

내장 영어 IPA 사전 출처: [CMUDict](licenses/CMUDICT/PROVENANCE.md). 오프라인 일본어 사전 출처: [IPADIC](licenses/IPADIC/PROVENANCE.md) / [EDRDG](licenses/EDRDG/PROVENANCE.md), [Lindera](licenses/LINDERA/LICENSE). 온라인 읽기: [Web Services by Yahoo! JAPAN](https://developer.yahoo.co.jp/sitemap/).

<sub>배지는 <a href="https://shields.io/">Shields.io</a>에서 제공하며, 다운로드 수는 고유 설치 수를 의미하지 않습니다.</sub>
