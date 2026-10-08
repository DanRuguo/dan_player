#include <windows.h>
#include <iostream>
#include <string>
#include "../taskbar_lyrics_paint.h"

#define CHECK(value) do { if (!(value)) { std::cerr << "FAIL line " << __LINE__ << ": " << #value << '\n'; return 1; } } while (0)

int wmain(int argc, wchar_t** argv) {
  using namespace desktop_integration;
  using namespace taskbar_lyrics;
  CHECK(argc == 5);
  NativeFontPolicy policy;
  const std::array<const wchar_t*, 4> families{L"Source Han Sans SC", L"Google Sans", L"Source Han Sans JP", L"Pretendard"};
  for (size_t i = 0; i < families.size(); ++i) policy.faces[i] = {families[i], argv[i + 1]};
  PopupFonts fonts;
  CHECK(fonts.Configure(policy)); CHECK(!fonts.Configure(policy));
  const HDC dc = CreateCompatibleDC(nullptr); CHECK(dc);
  fonts.Ensure(96);
  std::wcout << L"Policy UI native face " << fonts.face() << L", snapshot present " << fonts.policy().has_value() << L'\n';
  for (int i = 0; i < 4; ++i) {
    LOGFONTW font{};
    CHECK(GetObjectW(fonts.ForLanguage(static_cast<FontLanguage>(i)), sizeof(font), &font));
    std::wcout << L"Requested " << families[i] << L", GDI configured " << font.lfFaceName << L'\n';
    CHECK(std::wstring(font.lfFaceName) == families[i]);
    const auto old_font = SelectObject(dc, fonts.ForLanguage(static_cast<FontLanguage>(i)));
    const auto file = CreateFileW(argv[i + 1], GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    CHECK(file != INVALID_HANDLE_VALUE);
    const auto bytes = GetFileSize(file, nullptr);
    CHECK(bytes != INVALID_FILE_SIZE && GetFontData(dc, 0, 0, nullptr, 0) == bytes);
    std::vector<unsigned char> expected(bytes), realized(bytes);
    DWORD read = 0; CHECK(ReadFile(file, expected.data(), bytes, &read, nullptr) && read == bytes);
    CHECK(CloseHandle(file));
    CHECK(GetFontData(dc, 0, 0, realized.data(), bytes) == bytes && expected == realized);
    SelectObject(dc, old_font);
  }
  std::wcout << L"PASS four private native family registrations\n";

  const std::wstring mixed = std::wstring(320, L'A') + L"\u6b4c\u8a5e\u304b\u306a\ud55c\uae00 e\u0301 \U0001f469\u200d\U0001f4bb";
  auto mask = RasterText(dc, fonts, mixed, 480, 40, 96, true, {{0, 1000, mixed}});
  CHECK(mask.shaping && mask.shaping->text == mixed && !mask.pixels.empty());
  bool latin = false, japanese = false, korean = false;
  for (const auto& run : mask.shaping->runs) {
    LOGFONTW actual{}; CHECK(GetObjectW(run.font, sizeof(actual), &actual));
    CHECK(std::wstring(actual.lfFaceName) == families[static_cast<size_t>(run.language)]);
    latin |= run.language == FontLanguage::kEn;
    japanese |= run.language == FontLanguage::kJa;
    korean |= run.language == FontLanguage::kKo;
    CHECK(run.begin == 0 || mixed[run.begin] < 0xdc00 || mixed[run.begin] > 0xdfff);
  }
  CHECK(latin && japanese && korean && mask.words.size() == 1);
  std::wcout << L"PASS long mixed paragraph uses every requested script face\n";

  for (const auto language : {FontLanguage::kZh, FontLanguage::kJa, FontLanguage::kKo}) {
    policy.language = language;
    const auto runs = FontTextRuns(L"\u5171\u6709\u6f22\u5b57", policy);
    CHECK(runs.size() == 1 && runs.front().language == language);
  }
  policy.language = FontLanguage::kEn;
  CHECK(FontTextRuns(L"\u5171\u6709\u6f22\u5b57", policy).front().language == FontLanguage::kZh);
  CHECK(FontTextRuns(L"\u5171\u6709\u6f22\u5b57\ud55c\uae00", policy).front().language == FontLanguage::kKo);
  CHECK(FontTextRuns(L"\u5171\u6709\u6f22\u5b57\u304b\u306a", policy).front().language == FontLanguage::kJa);
  std::wcout << L"PASS Han locale and sentence context\n";

  const auto long_japanese = std::wstring(2300, L'\u6f22') + L"\u304b\u306a";
  auto long_mask = RasterText(dc, fonts, long_japanese, 480, 40, 96, true);
  CHECK(long_mask.long_text && long_mask.long_text->han_context == FontLanguage::kJa);
  CHECK(long_mask.shaping->runs.front().language == FontLanguage::kJa);
  CHECK(SelectTextChunk(long_mask, 1000, 0, 1000, dc, fonts, 480, 96, true));
  CHECK(long_mask.shaping->runs.front().language == FontLanguage::kJa);
  long_mask = {};
  std::wcout << L"PASS bounded long text retains whole-sentence Han context\n";

  const auto same = mask.shaping.get();
  const auto pristine = mask.shaping->logical_widths;
  CHECK(SetTextViewport(mask, 320));
  MapWords(mask, mixed, {{0, 1500, mixed}});
  CHECK(PaintPage(mask, 120));
  CHECK(mask.shaping.get() == same && mask.shaping->logical_widths == pristine && mask.words.size() == 1);
  int final_x = 0; CHECK(SUCCEEDED(mask.shaping->CpToX(static_cast<int>(mixed.size()) - 1, TRUE, &final_x)));
  CHECK(final_x + mask.padding <= mask.natural_width);
  std::wcout << L"PASS viewport paging and authored UTF16 timing reuse shaping\n";

  auto wrapped = RasterWrappedText(dc, fonts, mixed, 96, 160, 96, {{0, 1000, mixed}}, 0, 0, 1000);
  CHECK(wrapped.wrapped && !wrapped.pixels.empty() && !wrapped.words.empty());
  CHECK(wrapped.wrapped->shaping->text == mixed && wrapped.wrapped->rows.size() > 4);
  CHECK(SelectWrappedPage(wrapped, 1000, 0, 1000, dc, fonts));
  CHECK(!wrapped.words.empty() && wrapped.words.back().end == 1);
  CHECK(!SelectWrappedPage(wrapped, 1000, 0, 1000, dc, fonts));
  wrapped = {};
  std::wcout << L"PASS narrow wrapped taskbar pages use the same mixed fonts and timings\n";

  auto rtl = RasterText(dc, fonts, L"ABC \u0645\u0631\u062d\u0628\u0627 DEF", 500, 40, 96, true,
      {{0, 100, L"ABC "}, {100, 100, L"\u0645\u0631\u062d\u0628\u0627"}, {200, 100, L" DEF"}});
  CHECK(rtl.shaping && rtl.words.size() == 3 && rtl.words[1].leading > rtl.words[1].trailing);
  CHECK(std::count_if(rtl.pixels.begin(), rtl.pixels.end(), [](auto x) { return x != 0; }) > 20);
  std::wcout << L"PASS bidi caret and system fallback\n";

  mask = {}; rtl = {};
  policy.mixed_scripts = false; policy.language = FontLanguage::kEn;
  CHECK(fonts.Configure(policy));
  auto shared = RasterText(dc, fonts, L"Latin \u6b4c\u8a5e \ud55c\uae00", 480, 40, 144, true);
  CHECK(shared.shaping && !shared.pixels.empty());
  for (const auto& run : shared.shaping->runs) CHECK(run.language == FontLanguage::kEn);
  std::wcout << L"PASS shared font mode keeps Unicode font linking\n";
  shared = {};

  policy.base_fallback = policy.faces[0];
  const auto originals = policy.faces;
  for (auto& face : policy.faces) face = originals[1];
  CHECK(fonts.Configure(policy));
  auto fallback = RasterText(dc, fonts, L"Latin \u6b4c\u8a5e", 480, 40, 96, true);
  CHECK(fallback.shaping && !fallback.pixels.empty());
  CHECK(std::any_of(fallback.shaping->runs.begin(), fallback.shaping->runs.end(), [](const auto& run) { return run.fallback; }));
  for (const auto& run : fallback.shaping->runs) if (run.fallback) {
    LOGFONTW font{}; CHECK(GetObjectW(run.font, sizeof(font), &font));
    CHECK(std::wstring(font.lfFaceName) == families[0]);
  }
  fallback = {};
  policy.faces = originals;
  std::wcout << L"PASS shared Latin font uses privately registered base fallback\n";

  policy.mixed_scripts = true;
  CHECK(fonts.Configure(policy));
  NativeTextLayout clusters;
  const std::wstring clustered = L"e\u0301\u6b4c\U0001f469\u200d\U0001f4bb\ud55c\U0001f1fa\U0001f1f8";
  CHECK(clusters.Shape(fonts, clustered, 96, 16));
  CHECK(!clusters.attributes[1].fCharStop && !clusters.attributes[4].fCharStop &&
      !clusters.attributes[5].fCharStop && !clusters.attributes[6].fCharStop && !clusters.attributes[7].fCharStop);
  CHECK(!clusters.attributes[11].fCharStop);
  std::wcout << L"PASS combining and emoji boundaries remain indivisible\n";
  clusters.Clear();

  for (const std::wstring cluster : {L"\u1112\u1161\u11ab", L"\u2764\ufe0f", L"\U0001f469\u200d\U0001f4bb", L"\U0001f1fa\U0001f1f8",
      L"\U0001f3f4\U000e0067\U000e0062\U000e0065\U000e006e\U000e0067\U000e007f", L"\u0600\u6b4c"}) {
    CHECK(FontClusterEnd(cluster, 0) == cluster.size());
    NativeTextLayout shaped;
    CHECK(shaped.Shape(fonts, cluster, 96, 16));
    CHECK(shaped.runs.size() == 1 && shaped.runs.front().begin == 0 && shaped.runs.front().end == static_cast<int>(cluster.size()));
    for (size_t cp = 1; cp < cluster.size(); ++cp) CHECK(!shaped.attributes[cp].fCharStop && !shaped.attributes[cp].fSoftBreak);
  }
  std::wcout << L"PASS decomposed Hangul and emoji tag VS ZWJ flag Prepend clusters\n";

  NativeTextLayout alternating;
  std::wstring switching;
  for (int i = 0; i < 1000; ++i) switching += L"A\u6b4c";
  const auto before_switching = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
  CHECK(alternating.Shape(fonts, switching, 96, 16));
  CHECK(alternating.runs.size() == 2000);
  CHECK(GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS) <= before_switching + 6);
  alternating.Clear();
  std::wcout << L"PASS pathological mixed runs share bounded sized font handles\n";

  NativeTextCache cache;
  BITMAPINFO info{}; info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = 160; info.bmiHeader.biHeight = -40;
  info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32;
  void* pixels = nullptr;
  const auto bitmap = CreateDIBSection(nullptr, &info, DIB_RGB_COLORS, &pixels, nullptr, 0);
  CHECK(bitmap && pixels); const auto old = SelectObject(dc, bitmap);
  SetTextColor(dc, RGB(20, 60, 100));
  CHECK(cache.Draw(dc, fonts, mixed, {0, 0, 160, 40}, 96));
  const auto steady = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
  for (int i = 0; i < 500; ++i) { SetTextColor(dc, RGB(i % 255, 60, 100)); CHECK(cache.Draw(dc, fonts, mixed, {0, 0, 160, 40}, 96)); }
  CHECK(GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS) == steady);
  std::wcout << L"PASS tray ellipsis and hover paints reuse GDI resources\n";
  cache.Clear(); SelectObject(dc, old); DeleteObject(bitmap);

  fonts.Clear();
  const auto retired = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
  for (int i = 0; i < 30; ++i) {
    CHECK(fonts.Configure(policy));
    {
      auto value = RasterText(dc, fonts, mixed, 480, 40, i % 2 ? 96 : 192, true);
      CHECK(value.shaping && !value.pixels.empty());
    }
    fonts.Clear();
  }
  CHECK(GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS) <= retired + 1);
  DeleteDC(dc);
  std::wcout << L"PASS snapshot and DPI retirement release fonts and analyses\n";
  return 0;
}
