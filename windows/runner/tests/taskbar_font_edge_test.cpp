#include <windows.h>
#include <iostream>
#include <set>
#include <string>
#include "../taskbar_lyrics_paint.h"

namespace {
int failures = 0;
bool Check(bool value, const char* reason) {
  if (!value) { ++failures; std::cerr << "FAIL " << reason << '\n'; }
  return value;
}
bool CompleteChunks(const taskbar_lyrics::LongText& source) {
  std::set<int> stops{0};
  for (size_t at = 0; at < source.text.size();) {
    at = desktop_integration::FontClusterEnd(source.text, at);
    stops.insert(static_cast<int>(at));
  }
  int previous = 0;
  for (const auto& chunk : source.chunks) {
    if (chunk.first != previous || chunk.second <= chunk.first ||
        chunk.second - chunk.first > 2048 || !stops.count(chunk.second)) return false;
    previous = chunk.second;
  }
  return previous == static_cast<int>(source.text.size());
}
void UntimedCase(HDC dc, desktop_integration::PopupFonts& fonts,
                 const std::wstring& cluster, int prefix, const char* name) {
  const int before = failures;
  const auto text = std::wstring(prefix, L'A') + cluster + std::wstring(30, L'B');
  const auto divided = taskbar_lyrics::DivideLongText(text, {});
  Check(CompleteChunks(*divided), name);
  auto mask = taskbar_lyrics::RasterText(dc, fonts, text, 240, 32, 96, true);
  Check(mask.long_text && mask.shaping && !mask.pixels.empty(), "actual long raster is available");
  if (mask.long_text && mask.shaping) {
    // Read in the middle of the boundary cluster. Its complete glyph must be
    // present on the current horizontal chunk and the wrapped side-taskbar.
    const double position = (prefix + cluster.size() * .5) * 1000.0 / text.size();
    taskbar_lyrics::SelectTextChunk(mask, position, 0, 1000, dc, fonts, 240, 96, true);
    Check(mask.shaping && mask.shaping->text.find(cluster) != std::wstring::npos,
          "horizontal page retains the complete boundary cluster");
    auto wrapped = taskbar_lyrics::RasterWrappedText(dc, fonts, text, 120, 160, 96, {}, position, 0, 1000);
    Check(wrapped.wrapped && wrapped.wrapped->shaping &&
          wrapped.wrapped->shaping->text.find(cluster) != std::wstring::npos,
          "wrapped page retains the complete boundary cluster");
  }
  if (failures == before) std::cout << "PASS " << name << '\n';
}
}

int wmain(int argc, wchar_t** argv) {
  using namespace desktop_integration;
  using namespace taskbar_lyrics;
  if (!Check(argc == 5, "four controlled font paths are required")) return 1;
  NativeFontPolicy policy;
  const std::array<const wchar_t*, 4> families{L"Source Han Sans SC", L"Google Sans", L"Source Han Sans JP", L"Pretendard"};
  for (size_t i = 0; i < families.size(); ++i) policy.faces[i] = {families[i], argv[i + 1]};
  policy.base_fallback = policy.faces[0];
  PopupFonts fonts;
  Check(fonts.Configure(policy), "controlled private font snapshot configures");
  const HDC dc = CreateCompatibleDC(nullptr);
  if (!Check(dc != nullptr, "native measuring DC is available")) return 1;

  UntimedCase(dc, fonts, L"\u1112\u1161\u11ab", 2047, "long decomposed Hangul boundary");
  UntimedCase(dc, fonts, L"\U0001f1fa\U0001f1f8", 2046, "long regional-indicator flag boundary");
  UntimedCase(dc, fonts, L"\U0001f3f4\U000e0067\U000e0062\U000e0065\U000e006e\U000e0067\U000e007f", 2046,
              "long emoji tag-sequence boundary");

  {
    const int before = failures;
    const std::wstring cluster = L"\u1112\u1161\u11ab";
    const auto prefix = std::wstring(2047, L'A');
    const auto text = prefix + cluster + L"BBBB";
    const std::vector<TaskbarLyricWord> words{{0, 1000, prefix}, {1000, 1000, cluster.substr(0, 1)},
                                             {2000, 1000, cluster.substr(1) + L"BBBB"}};
    const auto divided = DivideLongText(text, words);
    Check(CompleteChunks(*divided), "authored word ends cannot split a Hangul grapheme");
    Check(divided->words.size() == words.size(), "authored word timings survive chunk projection");
    auto mask = RasterText(dc, fonts, text, 240, 32, 96, true, words);
    SelectTextChunk(mask, 1500, 0, 3000, dc, fonts, 240, 96, true);
    Check(mask.shaping && mask.shaping->text.find(cluster) != std::wstring::npos,
          "authored horizontal page keeps the entire grapheme");
    Check(mask.words.size() == 2 && mask.words[0].start == 1000 && mask.words[1].start == 2000,
          "authored words retain their original starts after page handoff");
    if (failures == before) std::cout << "PASS timed word-boundary Hangul handoff\n";
  }

  {
    const int before = failures;
    const auto resources = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
    for (int i = 0; i < 20; ++i) {
      const auto text = std::wstring(2047, L'A') + L"\u1112\u1161\u11abBBBB";
      auto mask = RasterText(dc, fonts, text, 240, 32, 96, true);
      SelectTextChunk(mask, 1000, 0, 1000, dc, fonts, 240, 96, true);
      Check(mask.shaping && !mask.pixels.empty(), "boundary chunk retires after real page handoff");
    }
    Check(GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS) <= resources + 1,
          "repeated boundary page handoff releases GDI resources");
    std::wstring oversized = L"\U0001f469";
    for (int i = 0; i < 2000; ++i) oversized += L"\u200d\U0001f469";
    oversized += L'B';
    const auto divided = DivideLongText(oversized, {});
    int previous = 0;
    for (const auto& chunk : divided->chunks) {
      Check(chunk.first == previous && chunk.second > previous && chunk.second - previous <= 2048,
            "a pathological oversized cluster keeps the existing shaping cap");
      Check(chunk.second == static_cast<int>(oversized.size()) ||
            oversized[chunk.second] < 0xdc00 || oversized[chunk.second] > 0xdfff,
            "bounded fallback does not split a UTF-16 surrogate pair");
      previous = chunk.second;
    }
    Check(previous == static_cast<int>(oversized.size()), "bounded fallback preserves the complete source");
    if (failures == before) std::cout << "PASS boundary paging retains bounded resource lifetime\n";
  }
  fonts.Clear();
  DeleteDC(dc);
  std::cout << "taskbar font edge groups: 5, failed assertions: " << failures << '\n';
  return failures == 0 ? 0 : 1;
}
