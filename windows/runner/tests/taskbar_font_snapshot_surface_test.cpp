#include "../taskbar_lyrics.h"
#include "taskbar_lyrics_test_windows.h"
#include <iostream>

#define CHECK(value) do { if (!(value)) { std::cerr << "FAIL line " << __LINE__ << ": " << #value << '\n'; return 1; } } while (0)
namespace {
void Pump(DWORD milliseconds) {
  const auto end = GetTickCount64() + milliseconds;
  do {
    MSG message;
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) { TranslateMessage(&message); DispatchMessageW(&message); }
    MsgWaitForMultipleObjects(0, nullptr, FALSE, 2, QS_ALLINPUT);
  } while (GetTickCount64() < end);
}
struct FakeBar {
  HWND window = nullptr;
  FakeBar() {
    WNDCLASSW cls{}; cls.lpszClassName = L"DanPlayer.FontSnapshot.QA.Bar"; cls.hInstance = GetModuleHandleW(nullptr);
    cls.lpfnWndProc = DefWindowProcW; cls.hbrBackground = static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)); RegisterClassW(&cls);
    window = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, cls.lpszClassName, L"", WS_POPUP,
        80, 400, 940, 48, nullptr, nullptr, cls.hInstance, nullptr);
    ShowWindow(window, SW_SHOWNOACTIVATE); UpdateWindow(window);
  }
  ~FakeBar() { if (window) DestroyWindow(window); }
  std::vector<RECT> Occupied() const {
    RECT rect{}; GetWindowRect(window, &rect);
    return {{rect.left, rect.top, rect.left + 20, rect.bottom}, {rect.right - 20, rect.top, rect.right, rect.bottom}};
  }
};
}
int wmain(int argc, wchar_t** argv) {
  using namespace desktop_integration;
  CHECK(argc == 5);
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  NativeFontPolicy policy;
  const std::array<const wchar_t*, 4> families{L"Source Han Sans SC", L"Google Sans", L"Source Han Sans JP", L"Pretendard"};
  for (size_t i = 0; i < families.size(); ++i) policy.faces[i] = {families[i], argv[i + 1]};
  policy.base_fallback = policy.faces[0];
  FakeBar bar;
  CHECK(bar.window);
  TaskbarLyrics surface;
  const auto foreground = GetForegroundWindow();
  const std::wstring text = L"Hello e\u0301 \u6b4c\u8a5e\u304b\u306a \ud55c\uae00\u1112\u1161\u11ab";
  const auto send = [&]() {
    return surface.Set(true, text, 0xff008ebd, L"legacy-ignored", L"", false, false,
        {{0, 4000, text}}, text, 1250, 1, L"source", L"line", 5, 0, 4000,
        L"start", L"Next track", false, false, 0, true, L"player", false, false,
        false, true, false, policy);
  };
  CHECK(send()); surface.UseBarForTesting(bar.window, bar.Occupied()); Pump(250);
  const auto window = FindOwnedTaskbarWindow(L"DanPlayer.TaskbarLyrics.v1");
  CHECK(window && IsWindowVisible(window));
  CHECK(surface.ShapingForTesting() && !surface.PixelsForTesting().empty());
  const auto count = surface.RasterCountForTesting();
  const auto shaping = surface.ShapingForTesting();
  const auto pixels = surface.PixelsForTesting();
  const auto frames = surface.MotionFramesForTesting();
  for (int i = 0; i < 12; ++i) CHECK(send());
  Pump(100);
  CHECK(surface.RasterCountForTesting() == count && surface.ShapingForTesting() == shaping);
  CHECK(surface.PixelsForTesting() == pixels && surface.MotionFramesForTesting() == frames);
  std::cout << "PASS actual TaskbarLyrics Set equal font snapshots preserve cached paused frame\n";

  policy.mixed_scripts = false; policy.language = FontLanguage::kEn;
  for (auto& face : policy.faces) face = policy.faces[1];
  CHECK(send()); Pump(70);
  CHECK(surface.RasterCountForTesting() == count + 1);
  CHECK(!surface.PixelsForTesting().empty() && !surface.LineAnimatingForTesting());
  const auto changed_count = surface.RasterCountForTesting();
  CHECK(send()); Pump(70); CHECK(surface.RasterCountForTesting() == changed_count);
  CHECK(GetForegroundWindow() == foreground);
  surface.Close(); Pump(100);
  CHECK(!FindOwnedTaskbarWindow(L"DanPlayer.TaskbarLyrics.v1"));
  std::cout << "PASS actual font replacement rerasterizes once and shutdown retires the surface\n";
  return 0;
}
