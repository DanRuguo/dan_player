#include "../taskbar_lyrics.h"
#include "taskbar_lyrics_test_windows.h"
#include <iostream>
#include <limits>
#define CHECK(v) do { if (!(v)) { std::cerr << "FAIL " << __LINE__ << ": " << #v << '\n'; return 1; } } while (0)
namespace {
struct PrivateDesktop {
  HDESK original = GetThreadDesktop(GetCurrentThreadId());
  HDESK owned = nullptr;
  PrivateDesktop() {
    const auto name = L"DanPlayer.LetterSpacing.QA." + std::to_wstring(GetCurrentProcessId());
    owned = CreateDesktopW(name.c_str(), nullptr, nullptr, 0, GENERIC_ALL, nullptr);
    if (owned && !SetThreadDesktop(owned)) { CloseDesktop(owned); owned = nullptr; }
  }
  ~PrivateDesktop() {
    if (owned) { SetThreadDesktop(original); CloseDesktop(owned); }
  }
};
int Clusters(const std::wstring& text) {
  int count = 0;
  for (size_t at = 0; at < text.size(); ++count) at = desktop_integration::FontClusterEnd(text, at);
  return count;
}
void Pump(DWORD milliseconds) {
  const auto end = GetTickCount64() + milliseconds;
  do {
    MSG message;
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message); DispatchMessageW(&message);
    }
    MsgWaitForMultipleObjects(0, nullptr, FALSE, 2, QS_ALLINPUT);
  } while (GetTickCount64() < end);
}
struct FakeBar {
  HWND window = nullptr;
  FakeBar() {
    WNDCLASSW cls{}; cls.lpszClassName = L"DanPlayer.LetterSpacing.QA.Bar";
    cls.hInstance = GetModuleHandleW(nullptr); cls.lpfnWndProc = DefWindowProcW;
    RegisterClassW(&cls);
    window = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, cls.lpszClassName,
        L"", WS_POPUP, 80, 400, 940, 48, nullptr, nullptr, cls.hInstance, nullptr);
    ShowWindow(window, SW_SHOWNOACTIVATE); UpdateWindow(window);
  }
  ~FakeBar() { if (window) DestroyWindow(window); }
  std::vector<RECT> Occupied() const {
    RECT rect{}; GetWindowRect(window, &rect);
    return {{rect.left, rect.top, rect.left + 20, rect.bottom},
        {rect.right - 20, rect.top, rect.right, rect.bottom}};
  }
};
}
int wmain(int argc, wchar_t** argv) {
  using namespace desktop_integration;
  using namespace taskbar_lyrics;
  CHECK(argc == 5);
  PrivateDesktop desktop; CHECK(desktop.owned);
  NativeFontPolicy policy;
  const std::array<const wchar_t*, 4> families{
      L"Source Han Sans SC", L"Google Sans", L"Source Han Sans JP", L"Pretendard"};
  for (size_t i = 0; i < families.size(); ++i) policy.faces[i] = {families[i], argv[i + 1]};
  policy.base_fallback = policy.faces[0];
  PopupFonts fonts; fonts.Configure(policy);
  const HDC dc = CreateCompatibleDC(nullptr); CHECK(dc);
  const std::array<std::wstring, 4> samples{
      L"\u6b4c\u8a5e\u95f4\u8ddd e\u0301X",
      L"\u6b4c\u8a5e\u304b\u306a English",
      L"\ud55c\uae00 \u1112\u1161\u11ab e\u0301",
      L"ABC \u05e9\u05dc\u05d5\u05dd \u0645\u0631\u062d\u0628\u0627 \U0001f469\U0001f3fd\u200d\U0001f680"};
  for (const auto& text : samples) for (const UINT dpi : {96u, 144u}) {
    auto natural = RasterText(dc, fonts, text, 720, 48, dpi, true, {{0, 4000, text}});
    auto zero = RasterText(dc, fonts, text, 720, 48, dpi, true, {{0, 4000, text}}, 16, true, std::nullopt, 0);
    CHECK(natural.shaping && zero.shaping && natural.pixels == zero.pixels);
    for (const double spacing : {.5, 3.0}) {
      auto tracked = RasterText(dc, fonts, text, 720, 48, dpi, true, {{0, 4000, text}}, 16, true, std::nullopt, spacing);
      CHECK(tracked.shaping && tracked.shaping->text == text && !tracked.pixels.empty());
      CHECK(tracked.shaping->measured.cx == natural.shaping->measured.cx +
          static_cast<int>(std::round((Clusters(text) - 1) * spacing * dpi / 96.0)));
      CHECK(tracked.words.size() == 1 && tracked.words[0].start == 0 && tracked.words[0].length == 4000);
      for (size_t at = 0; at < text.size();) {
        const auto end = FontClusterEnd(text, at);
        for (size_t inner = at + 1; inner < end; ++inner) CHECK(!tracked.shaping->attributes[inner].fCharStop);
        int leading = 0, trailing = 0;
        CHECK(SUCCEEDED(tracked.shaping->CpToX(static_cast<int>(at), FALSE, &leading)));
        CHECK(SUCCEEDED(tracked.shaping->CpToX(static_cast<int>(end - 1), TRUE, &trailing)));
        CHECK(std::abs(trailing - leading) > 0);
        at = end;
      }
      const auto shaping = tracked.shaping;
      CHECK(SetTextViewport(tracked, 170) && tracked.shaping == shaping);
      CHECK(SetTextViewport(tracked, 169) && tracked.shaping == shaping);
      std::cout << "PASS native cluster tracking, glyph coverage and retained width\n";
    }
  }
  const std::wstring long_text = std::wstring(2300, L'W') + L"\u7ec8\u70b9";
  auto paged = RasterText(dc, fonts, long_text, 180, 40, 96, true,
      {{0, 5000, long_text}}, 16, true, std::nullopt, 2.5);
  CHECK(paged.long_text && paged.letter_spacing == 2.5);
  CHECK(SelectTextChunk(paged, 5000, 0, 5000, dc, fonts, 180, 96, true));
  CHECK(paged.chunk > 0 && paged.letter_spacing == 2.5 && !paged.pixels.empty());
  CHECK(paged.shaping->text.find(L"\u7ec8\u70b9") != std::wstring::npos);
  std::cout << "PASS long lyric chunk keeps tracking and complete final glyphs\n";
  auto wrapped = RasterWrappedText(dc, fonts, samples[1], 110, 140, 96,
      {{0, 4000, samples[1]}}, 0, 0, 4000, 16, 3);
  CHECK(wrapped.wrapped && wrapped.letter_spacing == 3 && !wrapped.pixels.empty());
  SelectWrappedPage(wrapped, 4000, 0, 4000, dc, fonts);
  CHECK(wrapped.wrapped->first_row + 140 / wrapped.wrapped->pitch >= static_cast<int>(wrapped.wrapped->rows.size()));
  CHECK(!wrapped.words.empty());
  std::cout << "PASS narrow wrapped lyric keeps tracking and authored word coverage\n";
  CHECK(!RasterText(dc, fonts, samples[0], 160, 40, 96, true, {}, 16, true,
      std::nullopt, std::numeric_limits<double>::quiet_NaN()).shaping);
  DeleteDC(dc);
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  FakeBar bar; CHECK(bar.window);
  TaskbarLyrics surface;
  double spacing = 0;
  const auto send = [&]() {
    return surface.Set(true, samples[1], 0xff008ebd, L"", L"", false, false,
        {{0, 4000, samples[1]}}, samples[1], 1250, 1, L"source", L"line", 5, 0, 4000,
        L"start", L"", false, false, 0, true, L"player", false, false,
        false, true, false, policy, spacing);
  };
  CHECK(send()); surface.UseBarForTesting(bar.window, bar.Occupied()); Pump(250);
  CHECK(surface.ShapingForTesting() && !surface.PixelsForTesting().empty());
  const auto count = surface.RasterCountForTesting();
  const auto before = surface.PixelsForTesting();
  spacing = 3; CHECK(send()); Pump(70);
  CHECK(surface.RasterCountForTesting() == count + 1 && surface.PixelsForTesting() != before);
  const auto shape = surface.ShapingForTesting();
  for (int i = 0; i < 10; ++i) CHECK(send());
  Pump(100);
  CHECK(surface.RasterCountForTesting() == count + 1 && surface.ShapingForTesting() == shape);
  CHECK(!surface.LineAnimatingForTesting() && !surface.LayoutAnimatingForTesting());
  surface.Close(); Pump(100);
  CHECK(!FindOwnedTaskbarWindow(L"DanPlayer.TaskbarLyrics.v1"));
  std::cout << "PASS actual TaskbarLyrics spacing invalidates once and paused surface stays idle\n";
  return 0;
}
