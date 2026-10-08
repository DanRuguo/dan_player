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

<p>라이브러리 정리, 가사 표시, 데스크톱 사용 경험을 갖춘 Windows x64 음악 플레이어입니다.<br>
로컬 재생을 중심으로 온라인 음악과 사용자 지정 소스도 지원합니다.</p>

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
  <a href="https://github.com/DanRuguo/dan_player/releases">이전 릴리스</a> ·
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
    <img src="docs/images/library-light-wide.png" alt="중국어 인터페이스와 가상 데이터를 사용한 Dan Player 라이브러리 및 재생 컨트롤" width="1200">
  </picture>
</p>

<p align="center">
  <a href="#download">다운로드</a> ·
  <a href="#features">주요 기능</a> ·
  <a href="#screenshots">화면 미리 보기</a> ·
  <a href="#quick-start">시작하기</a> ·
  <a href="#development">개발 및 빌드</a>
</p>

<a id="download"></a>

## 다운로드 및 설치

| 버전 | 용도 | 다운로드 |
| --- | --- | --- |
| **최신 안정 버전** | 일상적인 사용과 업데이트. 버전은 릴리스 페이지에서 확인 | [설치 프로그램, 포터블 ZIP 및 체크섬](https://github.com/DanRuguo/dan_player/releases/latest) |
| **26.0.6 · 릴리스 기록** | 작업 표시줄 가사와 사용 설명서의 업데이트 기록 | [26.0.6 배포 파일](https://github.com/DanRuguo/dan_player/releases/tag/v26.0.6) |
| **26.0.5 · 이전 버전** | 이전 정식 버전과 별도 FFmpeg 구성 요소 | [이전 배포 파일](https://github.com/DanRuguo/dan_player/releases/tag/v26.0.5) |

**설치 버전**은 설치 프로그램을 실행하면 되며, 기존 설치를 업데이트할 수 있습니다. **포터블 버전**은 ZIP 전체를 압축 해제한 뒤 `Dan Player.exe`를 실행하세요. EXE 파일만 따로 복사하지 마세요. 바탕 화면 가사는 동일한 실행 파일에서 별도 프로세스로 실행됩니다.

가사 미리 듣기와 자르기에 필요한 FFmpeg는 선택 사항입니다. 직접 다운로드할 때 [26.0.5에 공개한 별도 구성 요소 패키지](https://github.com/DanRuguo/dan_player/releases/tag/v26.0.5)를 재사용하고 고정된 크기와 SHA-256을 검증합니다. 설치 프로그램과 포터블 ZIP에는 중복해서 포함하지 않습니다.

> **다운로드 및 서명 안내:** 프로젝트에서 빌드한 실행 파일은 RCEIT.Inc 자체 서명 인증서를 사용하므로 Windows에 신뢰 관련 경고가 나타날 수 있습니다. 설치 프로그램은 신뢰할 수 있는 인증서를 자동으로 설치하지 않습니다. 이전 서명을 사용하는 버전에서 업데이트할 때는 새 설치 프로그램을 직접 다운로드하세요. 미리 보기 버전은 Latest로 표시된 안정 버전을 대체하지 않습니다. 업데이트 전에 앱의 백업 및 복원 설정에서 개인 데이터를 백업하는 것이 좋습니다.

<a id="download-verification"></a>

<details>
<summary><strong>SHA-256으로 다운로드 파일 확인</strong></summary>

동일한 Release 페이지에서 프로그램과 `SHA256SUMS`를 다운로드하세요. 설치 프로그램이나 ZIP의 SHA-256을 계산한 뒤 체크섬 파일 및 GitHub 에셋 다이제스트와 비교하세요. 아래 예시의 파일명은 실제 다운로드한 파일명으로 바꾸세요.

```powershell
Get-FileHash -LiteralPath '.\DanPlayer-VERSION-Setup-x64.exe' -Algorithm SHA256
```

해시가 일치하면 공개된 배포 파일과 내용이 같다는 뜻이며, Windows가 서명 인증서를 신뢰한다는 뜻은 아닙니다. 다운로드 출처를 확인하고, 출처가 불분명한 파일을 실행하기 위해 시스템 보안 기능을 끄지 마세요.

</details>

<a id="features"></a>

## 주요 기능

곡 하나를 찾을 때도, 전체 컬렉션을 정리할 때도 같은 음악 라이브러리를 중심으로 작업할 수 있습니다.

| 영역 | 주요 기능 |
| --- | --- |
| **라이브러리 및 검색** | 아티스트, 앨범, 형식, 폴더별 탐색. 곡 검색, 메타데이터 일괄 편집 및 라이브러리 상태 확인. |
| **재생목록 및 대기열** | 계층형 재생목록, 드래그 순서 변경, 스마트 조건, M3U8 가져오기와 내보내기. 대기열 저장, 작업 실행 취소 및 재생목록 복원. |
| **가사** | 가사 검색, 편집, 수정본 관리, 잠금, 타이밍 보정. 전체 텍스트 검색, 바탕 화면 가사 및 미니 플레이어 표시. |
| **재생 및 위치 이동** | CUE 트랙 재생, 이퀄라이저, 음량 평준화, 곡별 이어 듣기, A–B 구간 반복. 재생 위치나 구간을 저장하고 모든 북마크에서 통합 관리. |
| **개인 음악 데이터** | 개인 평점과 태그, 필터링. 음악을 듣는 시간대, 곡 순위, 라이브러리 구성 및 파일 용량 확인. |
| **Windows 사용 경험** | 앨범 아트 기반 색상, 밝은 테마와 어두운 테마, 4개 언어 인터페이스. 단축키, 미니 창, 작업 표시줄 미리 보기 및 재생 진단. |

이 기능들은 26.0.5 정식 버전에 포함되어 있습니다. 실제 배포 파일에 포함된 기능은 해당 [Release 변경 내용](https://github.com/DanRuguo/dan_player/releases)을 확인하세요.

온라인 음악과 사용자 지정 소스는 로컬 음악 감상을 보완합니다. 사용자 지정 서비스는 명시적으로 선언한 기능에 따라 검색이나 가사 등을 제공합니다. 연결 방법은 [사용자 지정 음악 소스 API](docs/custom-music-source-api.md)를 참고하세요.

### 26.0.6

- 작업 표시줄 가사는 한 줄·두 줄, 단어 강조, 빈 영역 전환, 시스템 색상과 선택형 캡슐 재생 버튼을 지원합니다. 바탕 화면 가사와는 동시에 표시하지 않습니다.
- 음악·캐시 폴더에 표시용 메모를 지정하고 탐색, 복구 가능한 이동, 용량 통계를 사용할 수 있습니다. 캐시 분류는 통계 페이지의 새로고침을 공유합니다.
- 사용 가이드에 자주 쓰는 기능과 두 가사 편집 방식의 전체 절차를 보강했습니다. 재생 위치와 가사 애니메이션을 직접 체험할 수 있으며, 첫 사용 안내 후 설명서 위치를 알려 줍니다.
- 선택형 CPU·GPU·메모리 모니터링을 백업 설정, 사이드바, 가사 화면에 표시할 수 있습니다. 표시 방식과 간격을 공유하고 보이는 동안만 측정하며, 공간이 충분하면 탐색 메뉴 위치를 유지합니다.

- 눌러서 타이밍을 지정하는 가사 편집에서 일반 텍스트로 저장할 때 번역과 발음이 빠진다는 점을 확인하고 본문만 저장합니다. 행·단어 타이밍 작업을 계속하면 보조 내용을 유지할 수 있습니다.
- 기존 텍스트 편집기는 긴 무손실 가사를 화면에 다시 그릴 때 중복 파싱과 임시 JSON 생성을 줄였습니다. 두 편집 방식의 넓은 창과 좁은 창 렌더링 예시를 추가했습니다.
- 가사와 댓글은 기본적으로 로컬 내용과 캐시를 우선 사용합니다. 설정에서 자동 접속을 켤 수 있으며 수동 검색·새로고침·일괄 캐시도 계속 사용할 수 있습니다.

### 26.0.5의 새 기능

- **검색 기록:** 검색창을 위로 올리고 중복을 제외한 기록 칩을 가운데 정렬했습니다. 자동으로 줄을 바꾸며 좁은 창에서는 오래된 기록을 숨깁니다. 클릭하면 다시 검색하고, 오른쪽 클릭이나 길게 누른 뒤 ×를 누르면 삭제합니다.
- **가사와 댓글:** 기본적으로 로컬 콘텐츠와 캐시를 우선 사용하며 자동 접속은 설정에서 켤 수 있습니다. 가사 수동 검색, 댓글 새로고침·추가 로딩, 분류·제공처 변경 시에도 접속할 수 있습니다. 업데이트 중에는 아이콘이 회전하고 성공·실패를 공통 알림 말풍선으로 표시합니다.
- **재생 조작:** 진행 막대의 멀티터치, 드래그 취소, 탐색 실패 후 복구를 개선했습니다. 재생 세션이 바뀌면 이전 드래그로 위치가 바뀌지 않습니다. 가사 드래그 중 재구성을 줄이고, 재생목록 전환 준비 중 스크롤해도 보기 변경을 유지합니다.
- **분류 타일:** 직사각형 커버를 1×1, 2×1, 1×2, 2×2로 설정하고 드래그로 순서를 바꾸거나 빈칸 자동 채우기를 사용할 수 있습니다. 제목은 커버 안에 직접 표시하며 이미지 밝기에 따라 글자색을 선택합니다.
- **백업 및 복원:** 폴더별 로컬 음악, 라이브러리 인덱스, 재생목록, 통계, 설정, 캐시를 선택해 하나의 `.bak` 파일로 저장하고 암호로 암호화할 수 있습니다. 복원 시에도 폴더와 데이터를 다시 선택하거나 한 번에 모두 선택할 수 있습니다. 암호를 안전하게 보관하세요. 암호화된 백업 하나는 약 64 GiB 미만이어야 하며, 큰 컬렉션은 폴더별로 나누어 백업할 수 있습니다.
- **성능 설정과 시작 안내:** 절전 또는 고성능 모드를 켰다가 끄면 관련 설정을 이전 상태로 복원합니다. 화면 갱신율과 스펙트럼 막대 수를 설정할 수 있으며, 첫 사용 안내를 추가하고 시작 화면 시간을 줄였습니다.

재생목록 보기, 음량 패널, 메뉴, Windows 흐림 효과 전환, 창 크기 복원도 개선했습니다. 타일 배치와 글자색 분석은 필요할 때만 계산하고 결과를 캐시하며, 타일 애니메이션이 끝나면 갱신을 멈춥니다. 실제 전력 소비는 기기와 설정에 따라 달라집니다.

<a id="screenshots"></a>

## 화면 미리 보기

### 설명서와 필요할 때만 작동하는 모니터링

실제 구성 요소를 중국어 인터페이스로 렌더링한 예시입니다. 사용량과 경로는 가상 데이터입니다.

| 자주 쓰는 기능 안내 | 재생 대기열과 직접 조작하는 예시 |
| --- | --- |
| ![음악, 분류, 재생목록 조작 안내](docs/images/manual-common-library.png) | ![재생 위치 예시와 대기열 조작 안내](docs/images/manual-playback-demo.png) |

| 여러 위치에서 리소스 모니터링 | 캐시 용량 분류 |
| --- | --- |
| ![사이드바와 백업 설정이 공유하는 리소스 모니터링](docs/images/process-resource-locations.png) | ![통계 화면의 캐시 및 플레이어 데이터 용량 분류](docs/images/cache-storage-statistics.png) |

### 두 가지 가사 편집 방식

| 눌러서 타이밍 지정: 텍스트 준비 | 눌러서 타이밍 지정: 좁은 창에서 단어 기록 |
| --- | --- |
| ![중국어 인터페이스의 가사 본문, 번역, 발음 입력](docs/images/lyric-tap-text-zh.png) | ![중국어 인터페이스의 좁은 창에서 단어 타이밍 지정](docs/images/lyric-tap-words-narrow-zh.png) |

| 텍스트 편집: 가사 코드 | 텍스트 편집: 단어 미리 보기 |
| --- | --- |
| ![중국어 인터페이스의 QRC 가사 코드 편집](docs/images/lyric-code-editor-zh.png) | ![중국어 인터페이스의 단어별 가사 미리 보기](docs/images/lyric-editor-preview-zh.png) |

### 나만의 방식으로 컬렉션 정리

| 재생목록 및 컬렉션 | 외관 및 설정 |
| --- | --- |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/playlists-dark-wide.png"><img src="docs/images/playlists-light-wide.png" alt="중국어 인터페이스의 재생목록 관리 화면" width="600"></picture> | <picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/settings-dark-wide.png"><img src="docs/images/settings-light-wide.png" alt="중국어 인터페이스의 테마 및 그룹별 설정" width="600"></picture> |

### 듣고 싶은 곡을 찾고 가사에 집중

| 검색 및 기록 | 미니 플레이어 및 가사 |
| --- | --- |
| ![실제 Flutter 위젯으로 렌더링한 한국어 검색 페이지 콘텐츠 영역과 가운데 정렬된 기록 칩](docs/images/search-history-ko.png) | ![가상 데이터를 사용한 미니 플레이어와 가사 화면](docs/images/feature-mini-lyrics-dark.png) |

### 청취 기록으로 라이브러리 다시 발견하기

![가상 데이터를 사용한 중국어 인터페이스의 음악 통계 및 순위](docs/images/statistics-rankings-light.png)

<sub>실제 Flutter 위젯을 격리된 데모 데이터로 렌더링했습니다. 검색 이미지는 한국어 페이지의 콘텐츠 영역과 예시 기록이며, 네이티브 창 전체를 캡처한 화면이 아닙니다. 다른 예시는 주로 중국어 인터페이스를 사용합니다. 배치와 기능을 소개하는 이미지로, 실시간 오디오나 Windows 네이티브 효과의 검증 결과는 아닙니다. 테마, 창 너비, 4개 언어 예시는 <a href="docs/images/README.md">화면 갤러리</a>에서 확인하세요.</sub>

### 분류 타일과 시작 안내

<picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/feature-category-tiles-dark.png"><img src="docs/images/feature-category-tiles-light.png" alt="분류별 보기 설정과 다양한 표지 크기. 가상 데모 데이터 사용" width="1200"></picture>

| 첫 실행 안내: 언어 선택과 재생 조작 체험 | 플레이어 데이터와 로컬 음악 선택 복원 |
| --- | --- |
| ![첫 실행 안내: 언어 선택과 재생 조작 체험](docs/images/feature-onboarding-ko.png) | ![플레이어 데이터와 로컬 음악 선택 복원](docs/images/feature-restore-ko.png) |

<a id="quick-start"></a>

## 시작하기

**음악 추가.** 음악 파일이나 폴더를 가져온 뒤 곡, 분류, 재생목록 화면에서 탐색하세요. 계층형 재생목록과 드래그 순서 변경으로 컬렉션을 정리할 수 있습니다.

**개인 평점과 태그 관리.** 26.0.5 정식 버전에서는 분류 화면의 **개인 라이브러리 → 곡**에서 평점이나 개인 태그를 지정한 곡을 확인하고 날짜, 평점, 태그로 필터링할 수 있습니다. 개인 평점과 태그는 플레이어 데이터에 저장되며 **음악 파일에는 기록되지 않습니다**. 반면 메타데이터 편집과 태그 일괄 편집은 파일의 메타데이터를 변경하므로 저장 전에 변경 내용을 확인하세요.

**좋아하는 순간 저장.** 현재 재생 화면의 더 보기 메뉴에서 재생 북마크 창을 열어 현재 위치나 A–B 구간을 저장하세요. 저장한 항목은 분류 화면의 **개인 라이브러리 → 모든 북마크**에서 찾을 수 있습니다. 이 목록의 재생 버튼은 저장된 시작 위치부터 재생합니다. A–B 반복 구간을 복원하려면 해당 곡의 재생 북마크 창에서 그 구간을 선택하세요.

**데이터 백업.** 설정의 백업 및 복원 기능에서 플레이어 데이터와 로컬 음악을 선택해 저장할 수 있으며, 암호화와 선택 복원을 지원합니다. 프로그램 업데이트와 개인 데이터 백업은 서로 다른 작업입니다. 설치 폴더의 프로그램 파일은 라이브러리, 재생목록, 설정의 백업을 대신하지 않습니다.

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

연결된 갤러리와 API 문서는 현재 중국어로 제공됩니다. 설정 예시의 서비스 주소는 직접 배포한 서비스 주소로 바꾸세요. 문제를 보고하기 전에 [기존 Issues](https://github.com/DanRuguo/dan_player/issues)를 확인한 뒤 [신고 양식](https://github.com/DanRuguo/dan_player/issues/new/choose)을 사용하세요. 플레이어 버전, 재현 단계, 필요한 경우 인터페이스 언어와 창 크기 또는 디스플레이 배율을 알려 주세요. 재생 문제에는 개인정보를 제거한 진단 자료를 첨부할 수 있습니다. 개인 음악 파일, 인증 정보, 개인 폴더의 전체 경로는 공개하지 마세요.

<a id="development"></a>

## 개발 및 빌드

**Flutter, Rust, BASS**를 사용합니다. 개발에는 Flutter, Rust, Visual Studio의 C++를 사용한 데스크톱 개발 워크로드가 필요합니다. Dart 버전 제약은 [pubspec.yaml](pubspec.yaml), 결정된 의존성 버전은 [pubspec.lock](pubspec.lock)과 [rust/Cargo.lock](rust/Cargo.lock)을 확인하세요. Windows 지속적 통합 워크플로는 [Windows CI](.github/workflows/windows_ci.yml)에 정의되어 있습니다.

<details>
<summary><strong>소스 구조, 디버깅 및 필요한 범위의 검사</strong></summary>

| 디렉터리 | 용도 |
| --- | --- |
| [lib/](lib/) | 기본 인터페이스, 라이브러리, 재생 서비스 및 데이터 모델 |
| [third_party/desktop_lyric/](third_party/desktop_lyric/) | path 의존성으로 공유하는 바탕 화면 가사 및 Windows 호스트 |
| [rust/](rust/), [rust_builder/](rust_builder/) | 태그 처리, Flutter/Rust 연결 및 Cargokit 빌드 지원 |
| [windows/](windows/) | 기본 Windows 호스트, 작업 표시줄 및 시스템 통합 |
| [installer/](installer/) | Inno 설치 프로그램, 네이티브 구성 요소 및 설치 트랜잭션 테스트 |
| [test/](test/), [test/support/](test/support/) | Dart/Widget 회귀, 격리된 테스트 데이터 및 렌더링 도우미 |
| [integration_test/](integration_test/), [test_driver/](test_driver/) | Windows Profile 표시 테스트 및 드라이버 |
| [scripts/](scripts/) | 의존성 준비, 빌드, 검증 및 릴리스 스크립트 |
| [assets/](assets/), [shaders/](shaders/) | 제품 리소스, 글꼴 및 셰이더 |
| [docs/](docs/) | API 문서, 설정 예시 및 공개 인터페이스 이미지 |

변경 범위에 맞는 진입점을 선택하세요. 일반 `flutter test`에는 `integration_test/`가 포함되지 않습니다.

| 검사 범위 | 진입점 및 대상 |
| --- | --- |
| Dart/Widget | `flutter test --no-pub test/<module>_test.dart`. 저장소 테스트의 개별 데이터 주입을 따르고 모의 디렉터리를 전역 설정으로 덮어쓰지 않습니다 |
| Rust | `cargo test --manifest-path rust/Cargo.toml --locked` |
| Windows 표시 | [verify_native_display_regressions.ps1](scripts/verify_native_display_regressions.ps1)은 선택된 Profile 표시 회귀를 실행합니다. 다른 진입점은 [integration_test/](integration_test/)를 확인하세요 |
| Windows C++ | 개별 대상은 [기본 호스트 CMake](windows/runner/CMakeLists.txt)와 [바탕 화면 가사 CMake](third_party/desktop_lyric/windows/runner/CMakeLists.txt)에 정의되어 있습니다 |
| 설치 프로그램 | [verify_installer_native.ps1](scripts/verify_installer_native.ps1)은 네이티브 구성 요소를 검사합니다. [installer/tests/](installer/tests/)에는 UI, 새 설치, 업데이트 및 제거 샌드박스 스크립트도 있습니다 |
| 릴리스 정책 | [test_validation_pipeline.ps1](scripts/test_validation_pipeline.ps1), [CI 재개](scripts/test_windows_ci_resume.py), [분류 감사](scripts/test_audit_classification_metadata.py)의 오프라인 회귀 |

저장소 루트에서 실행하세요. 디버깅이 평소 사용하는 라이브러리와 설정에 영향을 주지 않도록 별도 데이터 디렉터리를 사용합니다.

```powershell
$env:DAN_PLAYER_DATA_DIR = [IO.Path]::GetFullPath((Join-Path (Get-Location).Path '../tool/qa-local/readme-debug'))
flutter pub get
flutter run -d windows
```

실행 전에 BASS 런타임을 준비하세요. 관련 스크립트는 `scripts/prepare_bass_runtime.ps1`과 `scripts/prepare_bass_fx_runtime.ps1`입니다. 컴퓨터별 SDK, 런타임 캐시, 서명 설정 경로는 소스 저장소 밖의 로컬 `DEVELOPMENT.md`에만 기록합니다.

검사 단계를 간소화하고 관련 변경 사항을 모듈별로 묶어서 검증하세요. 기능을 하나 추가할 때마다 전체 회귀 테스트, 빌드, 서명을 반복하지 마세요. 예를 들어 통계와 상세 화면 레이아웃 변경은 다음과 같이 확인할 수 있습니다.

```powershell
flutter test test/statistics_visualization_test.dart test/detail_diagnostics_layout_test.dart --no-pub
```

통합 단계에서는 `scripts/verify_interaction_regressions.ps1`을 사용합니다. UI 변경 사항은 실제 Flutter 위젯을 렌더링하여 확인해야 합니다. 공개 이미지는 `scripts/render_public_ui.ps1`과 격리된 가상 데이터로 생성하며, 언어, 창 너비, 글자 배율을 확인합니다. 위젯 렌더링은 실제 오디오 장치 및 Windows 데스크톱 통합 검증을 대신하지 않습니다.

</details>

<details>
<summary><strong>Windows 빌드 및 배포</strong></summary>

기존 배포 스크립트는 소스를 `dan_player/`에, 같은 상위 폴더의 `tool/`에 도구 체인과 캐시를, `dist/`에 결과물을 두는 작업 공간 구조를 전제로 합니다. `build_windows_release.ps1`은 의존성과 배포 조건을 확인하고 Windows 앱을 빌드한 뒤 글꼴과 런타임을 검증합니다.

```powershell
# 위 작업 공간 구조에서 서명 인증서가 없는 경우, 소스 저장소에서 실행:
.\scripts\build_windows_release.ps1 -SkipSigning
```

`-SkipPackaging`은 포터블 패키지 조립을 건너뛰고, `-NoRestore`는 이미 복원된 의존성을 재사용합니다. 서명된 릴리스에는 별도의 인증서 설정이 필요합니다. 설치 프로그램은 `scripts/build_windows_installer.ps1`로 빌드하고, 포터블 패키지와 설치 프로그램은 각각 `verify_local_release.ps1`, `verify_windows_installer.ps1`로 검증합니다.

같은 코드 상태에서는 유효한 검사 결과와 빌드 결과물을 재사용하고, 실패 시 필요한 단계만 다시 실행하세요. 서명 후 소스 커밋, 테스트 검증 기록, 결과물 SHA-256 및 서명을 확인한 뒤 필요한 GitHub 배포 절차만 수행합니다. 미리 보기 버전은 prerelease로 유지하고 안정 버전의 Latest를 대체하지 않습니다. 절차를 줄이기 위해 필수 검증을 생략하지 마세요.

</details>

장기적으로 필요한 문서만 유지합니다. 로컬 개발 메모, 과거 QA 결과, 임시 로그, 도구 캐시, 개인 데이터, 서명 개인 키는 소스 저장소에 포함하지 않습니다. 공개 인터페이스 이미지는 `docs/images/`에 모으고, 이미지가 바뀌면 참조도 함께 업데이트합니다.

<a id="license"></a>

## 라이선스 및 감사의 말

이 프로젝트는 [LICENSE](LICENSE)에 따라 배포됩니다. 타사 구성 요소에는 각자의 라이선스 조건이 적용되며, BASS 사용과 배포는 공식 라이선스를 따라야 합니다.

내장 UI 글꼴은 Noto Sans CJK SC이며 SIL Open Font License 1.1에 따라 배포합니다. [글꼴 라이선스와 출처](licenses/NOTO-SANS-CJK/PROVENANCE.md)는 포터블 버전과 설치 프로그램에 함께 제공합니다. 기존 설정과의 호환성을 위해 이전 리소스 경로와 내부 별칭을 유지하며, 표시 이름은 Noto Sans CJK SC입니다.

Dan Player는 [Ferry-200/coriander_player](https://github.com/Ferry-200/coriander_player)를 기반으로 개발되었습니다. 플레이어 기반, 라이브러리 구조, 가사 기능을 제공한 원작자에게 감사드립니다. 또한 [desktop_lyric](https://github.com/Ferry-200/desktop_lyric), [music_api_dart](https://github.com/Ferry-200/music_api_dart), [BASS](https://www.un4seen.com/bass.html), [Lofty](https://crates.io/crates/lofty), [flutter_rust_bridge](https://pub.dev/packages/flutter_rust_bridge), [Flutter](https://flutter.dev/), Material Design에 감사드립니다.

<sub>배지는 <a href="https://shields.io/">Shields.io</a>를 사용합니다. 다운로드 수는 Release 에셋의 다운로드 횟수이며 사용자 수나 설치 수가 아닙니다. 기술 배지는 사용 기술을 나타내며 최소 지원 버전을 의미하지 않습니다.</sub>
