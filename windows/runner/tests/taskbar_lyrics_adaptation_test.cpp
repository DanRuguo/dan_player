#include "../taskbar_lyrics.h"
#include "taskbar_lyrics_test_windows.h"
#include "../taskbar_lyrics_policy.h"
#include <iostream>
#include <gdiplus.h>
#include <dwmapi.h>

namespace {
int checks = 0;
#define CHECK(value) do { ++checks; if (!(value)) { std::cerr << "Failed line " << __LINE__ << ": " #value "\n"; return 1; } } while(false)
void Pump(DWORD duration) {
  const auto deadline = GetTickCount64() + duration;
  do {
    MSG message;
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message); DispatchMessageW(&message);
    }
    MsgWaitForMultipleObjects(0, nullptr, FALSE, 5, QS_ALLINPUT);
  } while (GetTickCount64() < deadline);
}
HWND Surface() {
  const HWND window = FindOwnedTaskbarWindow(L"DanPlayer.TaskbarLyrics.v1");
  DWORD process = 0; GetWindowThreadProcessId(window, &process);
  return process == GetCurrentProcessId() ? window : nullptr;
}
bool WaitVisible() {
  const auto deadline = GetTickCount64() + 4000;
  while (GetTickCount64() < deadline) {
    Pump(10);
    if (Surface() && IsWindowVisible(Surface())) return true;
  }
  return false;
}
std::vector<std::uint32_t> Capture(HWND window, RECT* bounds) {
  DwmFlush(); GdiFlush();
  if (!GetWindowRect(window, bounds)) return {};
  const int width = bounds->right - bounds->left, height = bounds->bottom - bounds->top;
  BITMAPINFO info{}; info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = width; info.bmiHeader.biHeight = -height;
  info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32;
  void* storage = nullptr;
  const HBITMAP bitmap = CreateDIBSection(nullptr, &info, DIB_RGB_COLORS, &storage, nullptr, 0);
  const HDC screen = GetDC(nullptr), memory = CreateCompatibleDC(screen);
  if (!bitmap || !storage || !screen || !memory) return {};
  const auto old = SelectObject(memory, bitmap);
  const BOOL copied = BitBlt(memory, 0, 0, width, height, screen, bounds->left, bounds->top, SRCCOPY | CAPTUREBLT);
  GdiFlush();
  std::vector<std::uint32_t> pixels;
  if (copied) {
    const auto* data = static_cast<std::uint32_t*>(storage);
    pixels.assign(data, data + static_cast<size_t>(width) * height);
    for (auto& pixel : pixels) pixel |= 0xff000000;
  }
  SelectObject(memory, old); DeleteObject(bitmap); DeleteDC(memory); ReleaseDC(nullptr, screen);
  return pixels;
}
bool Save(std::vector<std::uint32_t>& pixels, int width, int height, const std::wstring& path) {
  if (pixels.empty()) return false;
  Gdiplus::Bitmap image(width, height, width * 4, PixelFormat32bppARGB, reinterpret_cast<BYTE*>(pixels.data()));
  const CLSID png{0x557cf406, 0x1a04, 0x11d3, {0x9a, 0x73, 0x00, 0x00, 0xf8, 0x1e, 0xf3, 0x2e}};
  return image.Save(path.c_str(), &png, nullptr) == Gdiplus::Ok;
}
int Difference(const std::vector<std::uint32_t>& a, const std::vector<std::uint32_t>& b) {
  if (a.size() != b.size()) return -1;
  int count = 0;
  for (size_t index = 0; index < a.size(); ++index) if (a[index] != b[index]) ++count;
  return count;
}
int Ink(const std::vector<std::uint32_t>& pixels) {
  return static_cast<int>(std::count_if(pixels.begin(), pixels.end(), [](auto pixel) {
    const int red = (pixel >> 16) & 255, green = (pixel >> 8) & 255, blue = pixel & 255;
    return blue > red + 15 && green > red + 10;
  }));
}
std::uint64_t BlueEnergy(const std::vector<std::uint32_t>& pixels) {
  std::uint64_t energy = 0;
  for (const auto pixel : pixels) energy += pixel & 255;
  return energy;
}
POINT FirstInk(const std::vector<std::uint32_t>& pixels, int width) {
  POINT result{width, static_cast<LONG>(pixels.size() / width)};
  for (size_t index = 0; index < pixels.size(); ++index) {
    const auto pixel = pixels[index];
    if (static_cast<int>(pixel & 255) > static_cast<int>((pixel >> 16) & 255) + 15) {
      result.x = std::min(result.x, static_cast<LONG>(index % width));
      result.y = std::min(result.y, static_cast<LONG>(index / width));
    }
  }
  return result;
}
}

// Own native surface only. No Explorer/settings/input mutation and no reads of
// user music, preferences, UIA names or automation identifiers.
int wmain(int argc, wchar_t** argv) {
  using namespace taskbar_lyrics;
  if (argc == 2 && std::wstring(argv[1]) == L"--legacy-vertical-area") {
    const RECT monitor{0, 0, 2560, 1440}, bar{0, 0, 48, 1440};
    const std::vector<RECT> controls{{6, 1392, 158, 1440}, {1126, 1392, 1435, 1440}, {2166, 1392, 2560, 1440}};
    const auto areas = EligibleAreas(bar, monitor, controls, 96);
    CHECK(areas.size() == 1);
    CHECK(areas[0].left == 0 && areas[0].top == 12 && areas[0].right == 48 && areas[0].bottom == 1380);
    const auto selected = FreeArea(bar, monitor, controls, 96);
    CHECK(selected && selected->left == 0 && selected->top == 12 && selected->right == 48 && selected->bottom == 972);
    std::cout << "legacy vertical area: " << checks << " checks PASS\n";
    return 0;
  }
  CHECK(argc == 3);
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  ULONG_PTR gdiplus = 0; Gdiplus::GdiplusStartupInput input;
  CHECK(Gdiplus::GdiplusStartup(&gdiplus, &input, nullptr) == Gdiplus::Ok);
  const std::wstring output = argv[2];
  const RECT monitor{0, 0, 2560, 1440}, bottom{0, 1392, 2560, 1440};
  const std::vector<RECT> occupied{{0,1392,160,1440}, {1126,1392,1435,1440}, {2166,1392,2560,1440}};
  const auto areas = EligibleAreas(bottom, monitor, occupied, 96);
  CHECK(areas.size() == 2 && areas[0].left == 172 && areas[1].left == 1447);
  CHECK(SelectedArea(areas, false, 0) == 0 && SelectedArea(areas, false, 1) == 1 && SelectedArea(areas, false, 2) == 0);
  CHECK(SelectedArea(areas, false, 65535) == 1);
  auto switched = FreeArea(bottom, monitor, occupied, 96, Placement::kEnd, 1);
  CHECK(switched && switched->left == areas[1].left && switched->right == areas[1].right);
  CHECK(SelectedArea({areas[1]}, false, 65535) == 0);
  const RECT wide{0,0,2400,48};
  const std::vector<RECT> three{{0,0,100,48},{700,0,800,48},{1400,0,1500,48},{2300,0,2400,48}};
  const auto choices = EligibleAreas(wide, {0,0,2400,1200}, three, 96);
  CHECK(choices.size() == 3 && SelectedArea(choices, false, 0) == 2);
  CHECK(SelectedArea(choices, false, 1) == 0 && SelectedArea(choices, false, 2) == 1);
  const RECT huge_gap{0,0,2000,48};
  CHECK(PlaceArea(huge_gap, false, 96, Placement::kStart).left == 0);
  CHECK(PlaceArea(huge_gap, false, 96, Placement::kCenter).left == 520);
  CHECK(PlaceArea(huge_gap, false, 96, Placement::kEnd).left == 1040);
  CHECK(EligibleAreas({0,0,2560,30}, monitor, {{0,0,160,30},{1000,0,1200,30},{2400,0,2560,30}}, 96).size() == 2);
  CHECK(EligibleAreas({0,1438,2560,1486}, monitor, occupied, 96).empty());
  const RECT side{0,0,48,1440};
  const std::vector<RECT> side_buttons{{0,0,48,150},{0,500,48,600},{0,1300,48,1440}};
  const auto side_areas = EligibleAreas(side, monitor, side_buttons, 96);
  CHECK(side_areas.size() == 2 && side_areas[0].top == 162 && side_areas[1].bottom == 1288);
  CHECK(SelectedArea(side_areas, true, 0) == 1 && SelectedArea(side_areas, true, 1) == 0);
  CHECK(EligibleAreas({2512,0,2560,1440}, monitor, {{2512,0,2560,150},{2512,500,2560,600},{2512,1300,2560,1440}}, 96).size() == 2);
  const auto compact = LayoutContent(360,30,96,false,true,true);
  CHECK(compact.lyrics.left == 20 && compact.lyrics.right == 360 && compact.row_height == 30 && compact.metadata.left == compact.metadata.right);
  const auto normal = LayoutContent(960,48,96,false,true,true);
  CHECK(normal.lyrics.left == 20 && normal.metadata.left == 680 && normal.row_height == 24);
  const auto column = LayoutContent(48,600,96,true,true,true);
  CHECK(column.lyrics.top == 20 && column.lyrics.bottom == 536 && column.metadata.top == 536 && column.row_height == 258);
  desktop_integration::PopupFonts fonts; CHECK(fonts.Configure(L"DanPingFangSC", argv[1]));
  const HDC dc = CreateCompatibleDC(nullptr); CHECK(dc);
  auto short_line = RasterText(dc,fonts,L"短句",944,24,96,true);
  auto short_column = RasterWrappedText(dc,fonts,L"短句",48,200,96,{},0,0,1000);
  POINT horizontal_origins[3]{}, vertical_origins[3]{};
  int preset = 0;
  for (auto placement : {Placement::kStart,Placement::kCenter,Placement::kEnd}) {
    auto destination = ContentOffset(944,24,short_line.natural_width,VisibleTextHeight(short_line),false,placement);
    std::vector<std::uint32_t> pixels(944*24,0xff202020);
    std::vector<unsigned char> columns;
    CompositeText(pixels.data(),944,24,short_line,0,0,1,false,0,RGB(98,187,223),columns,destination.x,944-destination.x);
    horizontal_origins[preset]=FirstInk(pixels,944);
    CHECK(Save(pixels,944,24,output+L"/fake-horizontal-align-"+std::to_wstring(preset)+L".png"));
    destination=ContentOffset(48,200,short_column.natural_width,VisibleTextHeight(short_column),true,placement);
    pixels.assign(48*200,0xff202020);
    CompositeText(pixels.data(),48,200,short_column,destination.y,0,1,false,0,RGB(98,187,223),columns);
    vertical_origins[preset]=FirstInk(pixels,48);
    CHECK(Save(pixels,48,200,output+L"/fake-vertical-align-"+std::to_wstring(preset++)+L".png"));
  }
  CHECK(horizontal_origins[1].x > horizontal_origins[0].x+200 && horizontal_origins[2].x > horizontal_origins[1].x+200);
  CHECK(vertical_origins[1].y > vertical_origins[0].y+50 && vertical_origins[2].y > vertical_origins[1].y+50);
  short_line={};short_column={};
  int figure = 0;
  for (const auto& text : std::vector<std::wstring>{L"歌词正确换行与字形", L"Complete words wrap naturally", L"日本語の歌詞を改行", L"한국어 가사를 줄바꿈합니다", L"A\U0001f600e\u0301B مرحبا"}) {
    for (UINT scale : {96u,192u}) {
      const int width = MulDiv(48, scale, 96), height = MulDiv(320, scale, 96);
      auto glyph = RasterWrappedText(dc, fonts, text, width, height, scale, {}, 0, 0, 1000);
      CHECK(glyph.wrapped && glyph.wrapped->source->text == text && !glyph.pixels.empty());
      CHECK(glyph.pixels.size() == static_cast<size_t>(width) * height && glyph.wrapped->rows.size() > 1);
      int last = 0;
      for (const auto& range : glyph.wrapped->rows) {
        CHECK(range.first == last && range.second > range.first);
        if (range.second < static_cast<int>(text.size())) CHECK(!(text[range.second] >= 0xdc00 && text[range.second] <= 0xdfff));
        last = range.second;
      }
      CHECK(last == static_cast<int>(text.size()));
      std::vector<std::uint32_t> pixels(static_cast<size_t>(width) * height, 0xff202020);
      std::vector<unsigned char> columns;
      CompositeText(pixels.data(), width, height, glyph, 0, 0, 1, true, 0, RGB(98,187,223), columns, 0, width, true, RGB(255,255,255));
      CHECK(Ink(pixels) > 20 && glyph.outline.size() == glyph.pixels.size());
      CHECK(Save(pixels, width, height, output + L"/fake-side-font-" + std::to_wstring(figure++) + L".png"));
    }
  }
  const std::wstring timed_text = L"真实词时间跨多行高亮";
  auto timed = RasterWrappedText(dc, fonts, timed_text, 48, 300, 96,
      {{-100,500,L"真实词"},{400,600,L"时间跨多行"},{1000,500,L"高亮"}}, 0, 0, 1500);
  CHECK(timed.words.size() > 3 && WordsRemaining(timed,1499) && !WordsRemaining(timed,1500));
  CHECK(std::any_of(timed.words.begin(),timed.words.end(),[](const auto& word){return word.begin > 0 && word.end <= 1;}));
  std::vector<std::uint32_t> partial(48*300,0xff202020), complete=partial;
  std::vector<unsigned char> columns;
  CompositeText(partial.data(),48,300,timed,0,0,1,true,450,RGB(98,187,223),columns);
  CompositeText(complete.data(),48,300,timed,0,0,1,true,1500,RGB(98,187,223),columns);
  CHECK(Difference(partial,complete) > 10 && BlueEnergy(complete) > BlueEnergy(partial) + 1000);
  CHECK(Save(partial,48,300,output+L"/fake-side-word-partial.png"));
  CHECK(Save(complete,48,300,output+L"/fake-side-word-complete.png"));
  auto paged = RasterWrappedText(dc,fonts,std::wstring(18000,L'W')+L"END",48,160,96,{},0,0,1000);
  CHECK(paged.wrapped && paged.pixels.size() == 48*160 && paged.wrapped->shaping->text.size() <= 2048);
  CHECK(SelectWrappedPage(paged,1000,0,1000,dc,fonts));
  CHECK(paged.wrapped->chunk == static_cast<int>(paged.wrapped->source->chunks.size())-1);
  CHECK(!SelectWrappedPage(paged,1000,0,1000,dc,fonts));
  paged = {}; timed = {}; fonts.Clear(); DeleteDC(dc);
  const HWND foreground = GetForegroundWindow();
  TaskbarLyrics lyrics;
  CHECK(lyrics.Set(true, L"稳定歌词 · Stable text", 0xff62bbdf,
      L"DanPingFangSC", argv[1], false, false, {}, L"下一句 · Next line",
      1000, 1, L"qa-source", L"0", 0, 0, 4000));
  CHECK(WaitVisible());
  // Explorer may finish its first-show Z-order adjustment after 80 ms; the
  // production recovery is bounded to three 80 ms attempts, never idle polls.
  Pump(300);
  const HWND surface = Surface(); CHECK(surface);
  CHECK((GetWindowLongPtrW(surface,GWL_STYLE)&WS_CHILD) && GetParent(surface)==FindWindowW(L"Shell_TrayWnd",nullptr));
  using WindowBand = BOOL (WINAPI*)(HWND,DWORD*);
  const auto band_api = reinterpret_cast<WindowBand>(GetProcAddress(GetModuleHandleW(L"user32.dll"),"GetWindowBand"));
  if (band_api) {
    DWORD ours=0,shell=0;
    band_api(surface,&ours); band_api(FindWindowW(L"Shell_TrayWnd",nullptr),&shell);
    std::cout << "read-only bands ours=" << ours << " shell=" << shell << " shell-style=" << GetWindowLongPtrW(FindWindowW(L"Shell_TrayWnd",nullptr),GWL_EXSTYLE) << '\n';
  }
  RECT before{}; CHECK(GetWindowRect(surface, &before));
  auto stable = Capture(surface,&before); CHECK(Ink(stable)>20);
  // A same-geometry Shell/settings refresh must leave the verified old buffer
  // visible while its independent UIA worker checks the latest occupied area.
  lyrics.EnvironmentChanged();
  CHECK(IsWindowVisible(surface));
  RECT after{}; CHECK(GetWindowRect(surface, &after) && EqualRect(&before, &after));
  auto refreshed = Capture(surface,&after); CHECK(Difference(stable,refreshed) == 0);
  CHECK(Save(refreshed,after.right-after.left,after.bottom-after.top,output+L"/real-stable-refresh.png"));
  CHECK(WaitVisible());
  CHECK(GetForegroundWindow() == foreground);
  lyrics.Close(); Pump(700);
  CHECK(!Surface());
  auto frame = [&](std::wstring text,std::wstring next,std::wstring identity,double position,bool playing=true,bool paused=false,std::int64_t revision=0) {
    return lyrics.Set(true,std::move(text),0xff62bbdf,L"DanPingFangSC",argv[1],true,playing,{},std::move(next),position,1,
        L"qa-handoff",std::move(identity),revision,0,4000,L"auto",L"Next: Sample track",true,true,0,paused);
  };
  CHECK(frame(L"上一句 · Previous",L"当前句 · Current",L"0",0));
  CHECK(WaitVisible()); Pump(240);
  CHECK(frame(L"当前句 · Current",L"下一句 · Following",L"1",300));
  RECT handoff_bounds{};
  auto start = Capture(Surface(),&handoff_bounds); CHECK(Ink(start)>20);
  CHECK(Save(start,handoff_bounds.right-handoff_bounds.left,handoff_bounds.bottom-handoff_bounds.top,output+L"/real-handoff-000.png"));
  Pump(90);
  lyrics.EnvironmentChanged(); CHECK(IsWindowVisible(Surface()));
  auto middle=Capture(Surface(),&handoff_bounds); CHECK(Difference(start,middle)>50);
  CHECK(Save(middle,handoff_bounds.right-handoff_bounds.left,handoff_bounds.bottom-handoff_bounds.top,output+L"/real-handoff-090.png"));
  Pump(190);
  auto late=Capture(Surface(),&handoff_bounds); CHECK(Difference(middle,late)>50);
  CHECK(Save(late,handoff_bounds.right-handoff_bounds.left,handoff_bounds.bottom-handoff_bounds.top,output+L"/real-handoff-280.png"));
  Pump(320);
  auto end=Capture(Surface(),&handoff_bounds); CHECK(Ink(end)>20);
  CHECK(Save(end,handoff_bounds.right-handoff_bounds.left,handoff_bounds.bottom-handoff_bounds.top,output+L"/real-handoff-600.png"));
  CHECK(frame(L"当前句 · Current",L"下一句 · Following",L"1",900,false,true,1));
  auto paused=Capture(Surface(),&handoff_bounds); CHECK(Ink(paused)>20);
  CHECK(Save(paused,handoff_bounds.right-handoff_bounds.left,handoff_bounds.bottom-handoff_bounds.top,output+L"/real-paused-stroke.png"));
  CHECK(frame(L"当前句 · Current",L"下一句 · Following",L"1",900,false,false,1));
  auto stalled=Capture(Surface(),&handoff_bounds);
  CHECK(Difference(paused,stalled)>5);
  CHECK(Save(stalled,handoff_bounds.right-handoff_bounds.left,handoff_bounds.bottom-handoff_bounds.top,output+L"/real-stalled-no-pause.png"));
  POINT actual_origins[3]{}; int alignment=0;
  for (const auto* placement : {L"start",L"center",L"end"}) {
    CHECK(lyrics.Set(true,L"短句",0xff62bbdf,L"DanPingFangSC",argv[1],false,false,{},L"",900,1,
        L"qa-handoff",L"alignment",1,0,4000,placement,L"Next: Sample track",true,true,0,false));
    auto picture=Capture(Surface(),&handoff_bounds); CHECK(Ink(picture)>20);
    actual_origins[alignment]=FirstInk(picture,handoff_bounds.right-handoff_bounds.left);
    CHECK(Save(picture,handoff_bounds.right-handoff_bounds.left,handoff_bounds.bottom-handoff_bounds.top,
        output+L"/real-horizontal-align-"+std::to_wstring(alignment++)+L".png"));
  }
  CHECK(actual_origins[1].x > actual_origins[0].x+100 && actual_origins[2].x > actual_origins[1].x+100);
  const auto layout=lyrics.GetLayout(); CHECK(layout.area_count>0 && layout.area_index>=0);
  if (layout.area_count>1) {
    const int previous_index=layout.area_index;
    CHECK(lyrics.Set(true,L"另一空区",0xff62bbdf,L"DanPingFangSC",argv[1],false,false,{},L"",900,1,
        L"qa-handoff",L"other-area",1,0,4000,L"start",L"",true,true,1,false));
    CHECK(lyrics.GetLayout().area_index != previous_index);
    auto picture=Capture(Surface(),&handoff_bounds); CHECK(Ink(picture)>20);
    CHECK(Save(picture,handoff_bounds.right-handoff_bounds.left,handoff_bounds.bottom-handoff_bounds.top,output+L"/real-other-safe-area.png"));
  }
  lyrics.Close(); Pump(700);
  CHECK(lyrics.GetLayout().area_count==0 && !Surface());
  CHECK(GetForegroundWindow()==foreground);
  Gdiplus::GdiplusShutdown(gdiplus);
  std::cout << "taskbar adaptation: " << checks << " checks PASS\n";
  return 0;
}
