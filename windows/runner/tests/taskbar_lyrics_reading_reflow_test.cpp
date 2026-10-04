#include "../taskbar_lyrics.h"
#include "taskbar_lyrics_test_windows.h"
#include <gdiplus.h>
#include <iostream>

namespace {
int checks = 0;
#define CHECK(value) do { ++checks; if (!(value)) { std::cerr << "Failed line " << __LINE__ << ": " #value "\n"; return 1; } } while (false)
void Pump(DWORD duration) {
  const auto end = GetTickCount64() + duration;
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
    WNDCLASSW type{}; type.lpszClassName = L"DanPlayer.TaskbarLyrics.QA.ReflowBar";
    type.hInstance = GetModuleHandleW(nullptr); type.lpfnWndProc = DefWindowProcW;
    type.hbrBackground = static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
    RegisterClassW(&type);
    window = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
        type.lpszClassName, L"", WS_POPUP, 80, 400, 940, 48, nullptr, nullptr, type.hInstance, nullptr);
    ShowWindow(window, SW_SHOWNOACTIVATE); UpdateWindow(window);
  }
  ~FakeBar() { if (window) DestroyWindow(window); }
  RECT Bounds() const { RECT value{}; GetWindowRect(window, &value); return value; }
  std::vector<RECT> Occupied() const {
    const auto value = Bounds();
    return {{value.left, value.top, value.left + 20, value.bottom},
        {value.right - 20, value.top, value.right, value.bottom}};
  }
};
HWND Surface() { return FindOwnedTaskbarWindow(L"DanPlayer.TaskbarLyrics.v1"); }
bool Save(TaskbarLyrics& surface, const std::wstring& path) {
  RECT bounds{}; if (!GetWindowRect(Surface(), &bounds)) return false;
  const int width = bounds.right - bounds.left, height = bounds.bottom - bounds.top;
  auto pixels = surface.PixelsForTesting(); if (pixels.empty()) return false;
  Gdiplus::Bitmap image(width, height, width * 4, PixelFormat32bppARGB, reinterpret_cast<BYTE*>(pixels.data()));
  const CLSID png{0x557cf406, 0x1a04, 0x11d3, {0x9a, 0x73, 0x00, 0x00, 0xf8, 0x1e, 0xf3, 0x2e}};
  return image.Save(path.c_str(), &png, nullptr) == Gdiplus::Ok;
}
struct Frame {
  const ULONGLONG started = GetTickCount64();
  std::wstring text = L"歌 Lyrics 가사 · 0123456789 · " + std::wstring(120, L'歌');
  std::wstring next, line = L"line";
  bool playing = true, show_next = true;
  std::int64_t revision = 1;
  double frozen = 0;
  bool Send(TaskbarLyrics& surface, const std::wstring& font) const {
    const double position = playing ? static_cast<double>(GetTickCount64() - started) : frozen;
    return surface.Set(true, text, 0xff008ebd, L"DanPingFangSC", font, true, playing, {}, next,
        position, 1, L"same-source", line, revision, 0, 0, L"start", L"", false, false, 0, !playing,
        L"player", false, false, false, show_next);
  }
};
int Reflow(const std::wstring& font, const std::wstring& output) {
  FakeBar bar; TaskbarLyrics surface; Frame frame;
  CHECK(frame.Send(surface, font)); surface.UseBarForTesting(bar.window, bar.Occupied()); Pump(2600);
  CHECK(IsWindowVisible(Surface()));
  const int before = surface.ReadOffsetForTesting(); CHECK(before > 20);
  CHECK(Save(surface, output + L"/same-line-before.png"));
  frame.next = L"新的预览 · New preview · 새 미리보기";
  CHECK(frame.Send(surface, font)); CHECK(surface.ReadOffsetForTesting() >= before - 1);
  Pump(70); const int after = surface.ReadOffsetForTesting();
  std::cout << "preview reading before=" << before << " after=" << after << '\n';
  CHECK(after >= before - 1); CHECK(after <= before + 5);
  CHECK(Save(surface, output + L"/same-line-preview-after.png"));
  frame.frozen = static_cast<double>(GetTickCount64() - frame.started); frame.playing = false; ++frame.revision;
  CHECK(frame.Send(surface, font)); const int paused = surface.ReadOffsetForTesting();
  frame.show_next = false; CHECK(frame.Send(surface, font)); Pump(80);
  CHECK(surface.ReadOffsetForTesting() == paused);
  CHECK(Save(surface, output + L"/same-line-paused-single.png"));
  frame.playing = true; ++frame.revision; CHECK(frame.Send(surface, font)); Pump(70);
  CHECK(surface.ReadOffsetForTesting() >= paused - 1);
  const int resumed = surface.ReadOffsetForTesting();
  ++frame.revision; CHECK(frame.Send(surface, font)); CHECK(surface.ReadOffsetForTesting() == 0);
  Pump(1900); CHECK(surface.ReadOffsetForTesting() > 5);
  frame.line = L"new-line"; CHECK(frame.Send(surface, font)); CHECK(surface.ReadOffsetForTesting() == 0);
  std::cout << "same-line resume=" << resumed << ", explicit seek/new line reset=0\n";
  surface.Close(); CHECK(!Surface());
  std::cout << "same-line reflow: " << checks << " checks PASS\n"; return 0;
}
int Geometry(const std::wstring& font, const std::wstring& output) {
  FakeBar bar; TaskbarLyrics surface; Frame frame;
  CHECK(frame.Send(surface, font)); surface.UseBarForTesting(bar.window, bar.Occupied()); Pump(2600);
  const int before = surface.ReadOffsetForTesting(); CHECK(before > 20);
  CHECK(Save(surface, output + L"/geometry-before.png"));
  const auto previous = bar.Bounds();
  CHECK(SetWindowPos(bar.window, nullptr, 0, 0, 780, 48, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE));
  surface.UseBarForTesting(bar.window, bar.Occupied()); Pump(70);
  const int after = surface.ReadOffsetForTesting();
  std::cout << "geometry reading before=" << before << " after=" << after << '\n';
  CHECK(after >= before - 1); CHECK(after <= before + 5);
  RECT bounds{}; CHECK(GetWindowRect(Surface(), &bounds)); const auto bar_bounds = bar.Bounds();
  CHECK(bounds.left >= bar_bounds.left + 20 && bounds.right <= bar_bounds.right - 20);
  CHECK(bounds.right - bounds.left < previous.right - previous.left);
  CHECK(Save(surface, output + L"/geometry-after.png"));
  const auto pixels = surface.PixelsForTesting();
  CHECK(std::count_if(pixels.begin(), pixels.end(), [](auto value) { return value >> 24; }) > 30);
  surface.Close(); CHECK(!Surface());
  std::cout << "geometry reflow: " << checks << " checks PASS\n"; return 0;
}
}
int wmain(int argc, wchar_t** argv) {
  if (argc != 4) return 2;
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  Gdiplus::GdiplusStartupInput input; ULONG_PTR token = 0;
  if (Gdiplus::GdiplusStartup(&token, &input, nullptr) != Gdiplus::Ok) return 2;
  const int result = wcscmp(argv[1], L"--same-line") == 0 ? Reflow(argv[2], argv[3]) :
      wcscmp(argv[1], L"--geometry") == 0 ? Geometry(argv[2], argv[3]) : 2;
  Gdiplus::GdiplusShutdown(token); return result;
}
