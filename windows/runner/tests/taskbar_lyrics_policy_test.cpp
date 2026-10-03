#include "../taskbar_lyrics_policy.h"
#include "../taskbar_lyrics_paint.h"
#include "../taskbar_lyrics.h"
#include <iostream>
#include <fstream>
#include <numeric>

namespace {
int checks = 0;
#define CHECK(value) do { ++checks; if (!(value)) { std::cerr << "Failed line " << __LINE__ << ": " #value "\n"; return 1; } } while(false)
int Ink(const taskbar_lyrics::TextMask& text) {
  return static_cast<int>(std::count_if(text.pixels.begin(), text.pixels.end(), [](auto value) { return value != 0; }));
}
}

// No HWND/Explorer/settings/input mutation. Exercises the same native glyph
// cache used by the overlay, including fallback, timeline and full-text pages.
int wmain(int argc, wchar_t** argv) {
  using namespace taskbar_lyrics;
  const RECT monitor{0, 0, 2560, 1440}, bar{0, 1392, 2560, 1440};
  const std::vector<RECT> controls{{6, 1392, 158, 1440}, {1126, 1392, 1435, 1440}, {2166, 1392, 2560, 1440}};
  auto gap = FreeArea(bar, monitor, controls, 96);
  CHECK(gap && gap->left == 170 && gap->right == 1114 && gap->top == 1392);
  CHECK(!FreeArea(bar, monitor, {}, 96));
  CHECK(!FreeArea({0, 1438, 2560, 1486}, monitor, controls, 96));
  CHECK(FreeArea({0, 0, 48, 1440}, monitor, controls, 96).has_value()); // Vertical taskbars are supported.
  CHECK(!FreeArea(bar, monitor, controls, 0));
  CHECK(!FreeArea(bar, monitor, {{0, 1392, 2560, 1440}}, 96));
  const RECT second_monitor{-2560, -100, 0, 1340}, second_bar{-2560, 1292, 0, 1340};
  auto shifted = controls;
  for (auto& rect : shifted) OffsetRect(&rect, -2560, -100);
  gap = FreeArea(second_bar, second_monitor, shifted, 96);
  CHECK(gap && gap->left == -2390 && gap->right == -1446);
  std::vector<RECT> scaled = controls;
  for (auto& rect : scaled) { rect.left *= 2; rect.top *= 2; rect.right *= 2; rect.bottom *= 2; }
  gap = FreeArea({0, 2784, 5120, 2880}, {0, 0, 5120, 2880}, scaled, 192);
  CHECK(gap && gap->left == 340 && gap->right == 2228);
  CHECK(CoversMonitor({0, 0, 2560, 1440}, monitor, 96));
  CHECK(!CoversMonitor({0, 0, 2550, 1400}, monitor, 96));
  CHECK(LineEntrance(0).opacity == 0 && LineEntrance(0).dy == 4);
  CHECK(std::abs(LineEntrance(90).opacity - .875) < 1e-9);
  CHECK(LineEntrance(180).opacity == 1 && LineEntrance(180).dy == 0);
  CHECK(LineEntrance(0, false).opacity == 1 && LineEntrance(0, false).dy == 0);
  CHECK(RowProgress(0) < 1e-6 && RowProgress(560) > .999999);
  CHECK(RowProgress(100) < RowProgress(200) && RowProgress(200) < RowProgress(400));
  TextMask single_pixel;
  single_pixel.width = single_pixel.height = 1; single_pixel.natural_width = 1;
  single_pixel.pixels = {200};
  std::uint32_t fractional[2]{};
  std::vector<unsigned char> fractional_columns;
  CompositeText(fractional, 1, 2, single_pixel, .5, 0, 1, false, 0,
      RGB(255, 255, 255), fractional_columns);
  CHECK((fractional[0] >> 24) == 100 && (fractional[1] >> 24) == 100);
  fractional[0] = fractional[1] = 0;
  CompositeText(fractional, 1, 2, single_pixel, 0, 0, 1, false, 0,
      RGB(255, 255, 255), fractional_columns);
  CHECK((fractional[0] >> 24) == 200 && fractional[1] == 0);
  CHECK(ValidWords(L"你好A", {{0, 100, L"你"}, {100, 100, L"好A"}}));
  CHECK(!ValidWords(L"你好A", {{0, 100, L"你"}, {100, 100, L"好"}}));
  CHECK(ValidWords(L"A", {{-1000, 500, L"A"}}));
  CHECK(!ValidWords(L"A", {{-(1LL << 53) - 1, 100, L"A"}}));
  CHECK(!ValidWords(L"A", {{0, -1, L"A"}}));
  CHECK(!ValidWords(L"AB", {{100, 100, L"A"}, {0, 100, L"B"}}));
  TaskbarLyrics off;
  const auto resources = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
  CHECK(off.Set(false, L"", 0, L"", L"", false, false, {}, L"", 0, 1, L"", L"", 0, 0, 0));
  CHECK(GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS) == resources);
  desktop_integration::PopupFonts fonts;
  if (argc > 1) { fonts.Configure(L"DanPingFangSC", argv[1]); CHECK(fonts.private_font_loaded()); }
  const HDC dc = CreateCompatibleDC(nullptr);
  CHECK(dc);
  for (const wchar_t* line : {L"歌词首尾完整", L"Complete first and final glyphs", L"日本語の歌詞", L"한국어 가사", L"مرحبا بالعالم", L"A\U0001f600B"}) {
    auto text = RasterText(dc, fonts, line, 700, 24, 96, false);
    CHECK(Ink(text) > 10);
    CHECK(text.shaping && text.natural_width > 8);
    CHECK(text.pixels.size() == static_cast<size_t>(text.width) * text.height);
  }
  auto timed = RasterText(dc, fonts, L"你Wi好", 700, 24, 96, true,
      {{0, 100, L"你"}, {100, 200, L"Wi"}, {300, 100, L"好"}});
  CHECK(Ink(timed) > 20 && timed.words.size() == 3);
  CHECK(timed.words[0].leading < timed.words[0].trailing);
  CHECK(timed.words.back().trailing <= timed.natural_width);
  CHECK(!HighlightAt(timed, timed.words[0].leading, -1));
  CHECK(HighlightAt(timed, timed.words[0].leading, 100));
  CHECK(!HighlightAt(timed, timed.words[2].leading, 200));
  CHECK(HighlightAt(timed, timed.words[2].leading, 400));
  CHECK(WordsRemaining(timed, 399) && !WordsRemaining(timed, 400));
  CHECK(timed.words[1].trailing - timed.words[1].leading != timed.words[0].trailing - timed.words[0].leading);
  const auto pristine = timed.pixels;
  for (int at = 0; at <= 400; ++at) HighlightAt(timed, at % timed.natural_width, at);
  CHECK(timed.pixels == pristine);
  auto long_line = RasterText(dc, fonts, std::wstring(16000, L'W'), 360, 24, 96, false);
  CHECK(long_line.paged && long_line.long_text && Ink(long_line) > 20);
  CHECK(PaintPage(long_line, long_line.natural_width - long_line.width));
  CHECK(long_line.origin == long_line.natural_width - long_line.width && Ink(long_line) > 20);
  CHECK(long_line.long_text->text.size() == 16000);
  CHECK(long_line.shaping->text.size() <= 2048);
  CHECK(SelectTextChunk(long_line, 1000, 0, 1000, dc, fonts, 360, 96, false));
  CHECK(long_line.chunk == static_cast<int>(long_line.long_text->chunks.size()) - 1 && Ink(long_line) > 20);
  auto legal = RasterText(dc, fonts, std::wstring(2 * 1024 * 1024, L'A'), 360, 24, 96, true);
  CHECK(legal.long_text && legal.long_text->text.size() == 2 * 1024 * 1024);
  CHECK(legal.pixels.size() <= 720 * 24 && legal.shaping->text.size() <= 2048);
  int prior = 0;
  for (const auto& range : legal.long_text->chunks) {
    CHECK(range.first == prior && range.second > range.first && range.second - range.first <= 2048);
    prior = range.second;
  }
  CHECK(prior == 2 * 1024 * 1024);
  CHECK(SelectTextChunk(legal, 1000, 0, 1000, dc, fonts, 360, 96, true));
  CHECK(legal.chunk == static_cast<int>(legal.long_text->chunks.size()) - 1 && Ink(legal) > 20);
  std::vector<unsigned char> columns;
  for (int at : {0, 100, 150, 399, 400}) {
    HighlightColumns(timed, 0, 700, at, columns);
    for (int x = 0; x < timed.natural_width; ++x) CHECK(static_cast<bool>(columns[x]) == HighlightAt(timed, x, at));
  }
  legal = {};
  timed = {}; long_line = {};
  fonts.Clear(); DeleteDC(dc);
  std::cout << "taskbar lyrics policy/shaping checks: " << checks << " PASS\n";
  return 0;
}
