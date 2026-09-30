// Exercise the production progress subclass on an owned, never-switched-to
// desktop. Parent-background callbacks expose whether an incomplete frame is
// being drawn to the window or to an offscreen DC.
#include <windows.h>
#include <commctrl.h>
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

extern "C" int __stdcall DP_ProgressCreate(HWND, COLORREF, COLORREF);
extern "C" void __stdcall DP_ProgressSet(int, int);
extern "C" void __stdcall DP_ProgressClose();

namespace {
COLORREF parent_color = RGB(243, 243, 243);
bool observing_paint = false;
unsigned background_callbacks = 0, exposed_backgrounds = 0;

LRESULT CALLBACK ParentProcedure(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_ERASEBKGND || message == WM_PRINTCLIENT) {
    const HDC dc = reinterpret_cast<HDC>(wparam);
    if (observing_paint) {
      ++background_callbacks;
      if (GetObjectType(dc) != OBJ_MEMDC) ++exposed_backgrounds;
    }
    RECT bounds{}; GetClientRect(window, &bounds);
    const HBRUSH brush = CreateSolidBrush(parent_color);
    FillRect(dc, &bounds, brush); DeleteObject(brush);
    return 1;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

struct Surface {
  HDC dc = nullptr;
  HBITMAP bitmap = nullptr;
  HGDIOBJ previous = nullptr;
  unsigned char* pixels = nullptr;
  int width, height;
  Surface(int w, int h) : width(w), height(h) {
    dc = CreateCompatibleDC(nullptr);
    BITMAPINFO info{}; info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = w; info.bmiHeader.biHeight = -h;
    info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    bitmap = CreateDIBSection(dc, &info, DIB_RGB_COLORS,
        reinterpret_cast<void**>(&pixels), nullptr, 0);
    if (dc && bitmap) previous = SelectObject(dc, bitmap);
  }
  ~Surface() {
    if (previous) SelectObject(dc, previous);
    if (bitmap) DeleteObject(bitmap);
    if (dc) DeleteDC(dc);
  }
  bool Valid() const { return dc && bitmap && previous && pixels; }
  void Save(const std::filesystem::path& path) const {
    BITMAPFILEHEADER file{}; file.bfType = 0x4d42;
    file.bfOffBits = sizeof(file) + sizeof(BITMAPINFOHEADER);
    file.bfSize = file.bfOffBits + static_cast<DWORD>(width * height * 4);
    BITMAPINFOHEADER info{}; info.biSize = sizeof(info); info.biWidth = width;
    info.biHeight = -height; info.biPlanes = 1; info.biBitCount = 32;
    info.biCompression = BI_RGB;
    std::ofstream output(path, std::ios::binary);
    output.write(reinterpret_cast<const char*>(&file), sizeof(file));
    output.write(reinterpret_cast<const char*>(&info), sizeof(info));
    output.write(reinterpret_cast<const char*>(pixels), static_cast<std::streamsize>(width * height * 4));
    if (!output) throw std::runtime_error("Cannot save owned progress frame");
  }
};

bool CheckFrame(HWND progress, int width, int height, int value, COLORREF accent) {
  Surface frame(width, height);
  if (!frame.Valid()) return false;
  SendMessageW(progress, WM_PRINTCLIENT, reinterpret_cast<WPARAM>(frame.dc), PRF_CLIENT);
  const COLORREF track = parent_color == RGB(32, 32, 32) ? RGB(83, 83, 83) : RGB(216, 216, 216);
  if (GetPixel(frame.dc, width / 2, height / 2) != (value > 50 ? accent : track)) {
    std::cerr << "center value=" << value << " actual=" << GetPixel(frame.dc, width / 2, height / 2) << " track=" << track << " accent=" << accent << '\n'; return false;
  }
  if (value >= 35 && GetPixel(frame.dc, width / 4, height / 2) != accent) return false;
  for (const auto& point : std::vector<POINT>{{0, 0}, {width - 1, 0}})
    if (GetPixel(frame.dc, point.x, point.y) != parent_color) { std::cerr << "corner " << point.x << ',' << point.y << " actual=" << GetPixel(frame.dc, point.x, point.y) << " parent=" << parent_color << '\n'; return false; }
  return true;
}

int Run(int argc, wchar_t** argv) {
  namespace fs = std::filesystem;
  if (argc != 2) throw std::runtime_error("Expected qa-installer sandbox argument");
  const fs::path root = fs::absolute(argv[1]);
  bool sandbox = false;
  for (const auto& part : root) if (part == L"qa-installer") sandbox = true;
  if (!sandbox) throw std::runtime_error("Fixture must be inside qa-installer");
  const fs::path evidence = root / (L"progress-" + std::to_wstring(GetTickCount64()));
  fs::create_directories(evidence);
  const HDESK original = GetThreadDesktop(GetCurrentThreadId());
  const std::wstring name = L"DanPlayerProgressQA-" + std::to_wstring(GetCurrentProcessId());
  const HDESK desktop = CreateDesktopW(name.c_str(), nullptr, nullptr, 0, GENERIC_ALL, nullptr);
  if (!desktop || !SetThreadDesktop(desktop)) throw std::runtime_error("Private desktop unavailable; no fallback");
  INITCOMMONCONTROLSEX common{sizeof(common), ICC_PROGRESS_CLASS};
  if (!InitCommonControlsEx(&common)) throw std::runtime_error("Cannot initialize progress control");
  WNDCLASSW owner_class{}; owner_class.lpfnWndProc = ParentProcedure;
  owner_class.hInstance = GetModuleHandleW(nullptr); owner_class.lpszClassName = L"DanInstallerProgressSurface";
  if (!RegisterClassW(&owner_class)) throw std::runtime_error("Cannot register owned surface");
  const HWND owner = CreateWindowExW(0, owner_class.lpszClassName, L"private progress QA",
      WS_POPUP | WS_VISIBLE, 0, 0, 900, 120, nullptr, nullptr, owner_class.hInstance, nullptr);
  if (!owner) throw std::runtime_error("Cannot create private owner");
  HIGHCONTRASTW contrast{sizeof(contrast), 0, nullptr};
  SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(contrast), &contrast, 0);
  if ((contrast.dwFlags & HCF_HIGHCONTRASTON) != 0) throw std::runtime_error("Custom-painter fixture requires high contrast off; system unchanged");
  std::ofstream log(evidence / L"paint-destinations.tsv");
  log << "theme\tdpi\tprogress\tparentCallbacks\texposedBackgrounds\n";
  const COLORREF accent = RGB(83, 88, 172);
  unsigned frames = 0;
  bool all_buffered = true;
  for (const bool dark : {false, true}) for (const int dpi : {96, 120, 144, 192}) {
    parent_color = dark ? RGB(32, 32, 32) : RGB(243, 243, 243);
    const int outer_width = MulDiv(440, dpi, 96), outer_height = MulDiv(8, dpi, 96);
    const HWND progress = CreateWindowExW(0, PROGRESS_CLASSW, L"", WS_CHILD | WS_VISIBLE,
        0, 0, outer_width, outer_height, owner, nullptr, owner_class.hInstance, nullptr);
    if (!progress || !DP_ProgressCreate(progress, parent_color, accent)) throw std::runtime_error("Cannot subclass actual native progress");
    RECT client{}; GetClientRect(progress, &client);
    const int width = client.right, height = client.bottom;
    SendMessageW(progress, PBM_SETRANGE32, 0, 1000);
    for (const int value : {0, 1, 35, 99, 100, 35, 0}) {
      // Inno also updates its native gauge before the custom callback. Exercise
      // those invalidations, including requests to erase the whole control.
      background_callbacks = 0; exposed_backgrounds = 0;
      observing_paint = true;
      SendMessageW(progress, PBM_SETPOS, value * 10, 0);
      DP_ProgressSet(value, 100);
      RedrawWindow(progress, nullptr, nullptr, RDW_INVALIDATE | RDW_ERASE | RDW_UPDATENOW);
      observing_paint = false;
      log << (dark ? "dark" : "light") << '\t' << dpi << '\t' << value << '\t'
          << background_callbacks << '\t' << exposed_backgrounds << '\n';
      all_buffered = all_buffered && background_callbacks > 0 && exposed_backgrounds == 0;
      if (!CheckFrame(progress, width, height, value, accent)) throw std::runtime_error("Progress geometry/palette/corners differ from parent");
      Surface frame(width, height);
      if (!frame.Valid()) throw std::runtime_error("Cannot allocate frame capture");
      SendMessageW(progress, WM_PRINTCLIENT, reinterpret_cast<WPARAM>(frame.dc), PRF_CLIENT);
      frame.Save(evidence / ((dark ? L"dark-" : L"light-") + std::to_wstring(dpi) + L"-" + std::to_wstring(frames) + L".bmp"));
      ++frames;
    }
    ValidateRect(progress, nullptr);
    DP_ProgressSet(1, 1000);  // Same integer percentage: no extra paint.
    DP_ProgressSet(12, 0);   // Invalid total: leave the current frame intact.
    if (GetUpdateRect(progress, nullptr, FALSE)) throw std::runtime_error("Unchanged/invalid progress schedules a repaint");
    DP_ProgressSet(-1, 100);
    DP_ProgressSet(INT_MAX, 1);
    UpdateWindow(progress);
    if (!CheckFrame(progress, width, height, 100, accent)) throw std::runtime_error("Progress does not clamp safely");
    SetWindowPos(progress, nullptr, 0, 0, outer_width + 7, outer_height + 3,
        SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    GetClientRect(progress, &client);
    DP_ProgressSet(35, 100); UpdateWindow(progress);
    if (!CheckFrame(progress, client.right, client.bottom, 35, accent)) throw std::runtime_error("Resized progress loses its current value or parent surface");
    Surface clipped(client.right, client.bottom);
    if (!clipped.Valid()) throw std::runtime_error("Cannot allocate clipped frame");
    const COLORREF untouched = RGB(12, 34, 56);
    HBRUSH sentinel = CreateSolidBrush(untouched); FillRect(clipped.dc, &client, sentinel); DeleteObject(sentinel);
    RECT partial{client.right / 8, 0, client.right / 3, client.bottom};
    IntersectClipRect(clipped.dc, partial.left, partial.top, partial.right, partial.bottom);
    SendMessageW(progress, WM_PRINTCLIENT, reinterpret_cast<WPARAM>(clipped.dc), PRF_CLIENT);
    SelectClipRgn(clipped.dc, nullptr);
    if (GetPixel(clipped.dc, client.right / 4, client.bottom / 2) != accent ||
        GetPixel(clipped.dc, client.right / 2, client.bottom / 2) != untouched)
      throw std::runtime_error("Progress repaint ignores destination clipping");
    background_callbacks = 0; exposed_backgrounds = 0; observing_paint = true;
    InvalidateRect(progress, &partial, FALSE); UpdateWindow(progress);
    observing_paint = false;
    all_buffered = all_buffered && background_callbacks > 0 && exposed_backgrounds == 0;
    // Let GDI+/UxTheme initialize their per-control drawing caches before
    // measuring resource growth across a second complete update cycle.
    for (int value = 0; value < 1000; ++value) { DP_ProgressSet(value % 101, 100); UpdateWindow(progress); }
    GdiFlush();
    const DWORD before = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
    for (int value = 0; value < 1000; ++value) { DP_ProgressSet(value % 101, 100); UpdateWindow(progress); }
    GdiFlush();
    const DWORD after = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
    if (after > before + 2) { std::cerr << "GDI before=" << before << " after=" << after << '\n'; throw std::runtime_error("Repeated progress painting leaks GDI resources"); }
    DP_ProgressClose(); DestroyWindow(progress);
  }
  DP_ProgressClose(); DestroyWindow(owner);
  if (!SetThreadDesktop(original) || !CloseDesktop(desktop)) throw std::runtime_error("Cannot release private desktop");
  std::cout << "RESULT " << frames << " production progress frames; private desktop released; evidence=" << evidence.string() << '\n';
  if (!all_buffered) { std::cerr << "FAIL incomplete progress background reached a window DC (see paint-destinations.tsv)\n"; return 1; }
  std::cout << "PASS parent reconstruction stays offscreen during WM_PAINT; native PBM updates, palette/corners, deduplication, clamping, resize/clipping and GDI lifetime\n";
  return 0;
}
}

int wmain(int argc, wchar_t** argv) {
  try { return Run(argc, argv); }
  catch (const std::exception& error) { std::cerr << "FAIL " << error.what() << " win32=" << GetLastError() << '\n'; return 2; }
}
