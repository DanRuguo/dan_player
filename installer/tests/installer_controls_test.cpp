#include <windows.h>
#include <iostream>
#include <filesystem>
#include <string>

extern "C" int __stdcall DP_StyleButton(HWND, COLORREF, COLORREF, BOOL, int);
extern "C" void __stdcall DP_CloseControls();
extern "C" int __stdcall DP_LoadPrivateFont(const wchar_t*, wchar_t*, int);
extern "C" void __stdcall DP_CloseBrand();

namespace {
COLORREF parent_color = RGB(243,243,243);
LRESULT CALLBACK SurfaceProcedure(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_ERASEBKGND || message == WM_PRINTCLIENT) {
    RECT bounds{}; GetClientRect(window, &bounds);
    HBRUSH brush = CreateSolidBrush(parent_color);
    FillRect(reinterpret_cast<HDC>(wparam), &bounds, brush); DeleteObject(brush);
    return 1;
  }
  return DefWindowProcW(window,message,wparam,lparam);
}
}

int wmain(int argc, wchar_t** argv) {
  if (argc != 3) return 2;
  namespace fs = std::filesystem;
  const auto fixture = fs::absolute(argv[2]) / (L"font-" + std::to_wstring(GetTickCount64()));
  bool sandbox = false; for (const auto& part : fixture) if (part == L"qa-installer") sandbox = true;
  if (!sandbox) return 11;
  fs::create_directories(fixture);
  const auto font_copy = fixture / L"private-font-fixture.ttf";
  fs::copy_file(fs::path(argv[1]), font_copy);
  WNDCLASSW owner_class{}; owner_class.lpfnWndProc=SurfaceProcedure;
  owner_class.hInstance=GetModuleHandleW(nullptr); owner_class.lpszClassName=L"DanInstallerTestSurface";
  RegisterClassW(&owner_class);
  HWND owner = CreateWindowExW(0, owner_class.lpszClassName, L"hidden installer control test",
      WS_OVERLAPPED, 0, 0, 800, 600, nullptr, nullptr, nullptr, nullptr);
  if (!owner) return 3;
  unsigned passed = 0;
  for (const bool dark : {false,true}) for (const int dpi : {96, 120, 144, 192}) {
    parent_color=dark?RGB(32,32,32):RGB(243,243,243);
    const int width = MulDiv(200, dpi, 96), height = MulDiv(23, dpi, 96);
    HWND button = CreateWindowExW(0, L"BUTTON", L"安装(&I)", WS_CHILD | WS_TABSTOP,
        0, 0, width, height, owner, nullptr, nullptr, nullptr);
    if (!button || !DP_StyleButton(button, RGB(255,255,255), RGB(30,70,140), TRUE, MulDiv(6,dpi,96))) return 4;
    HDC dc = CreateCompatibleDC(nullptr);
    BITMAPINFO info{}; info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = width; info.bmiHeader.biHeight = -height;
    info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32; info.bmiHeader.biCompression = BI_RGB;
    void* bits = nullptr;
    HBITMAP image = CreateDIBSection(dc, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
    if (!image) return 5;
    const auto previous = SelectObject(dc, image);
    SendMessageW(button, WM_PRINTCLIENT, reinterpret_cast<WPARAM>(dc), PRF_CLIENT);
    HIGHCONTRASTW contrast{sizeof(contrast),0,nullptr};
    SystemParametersInfoW(SPI_GETHIGHCONTRAST,sizeof(contrast),&contrast,0);
    if (!(contrast.dwFlags & HCF_HIGHCONTRASTON) &&
        (GetPixel(dc, 0, 0) != parent_color ||
         GetPixel(dc,width-1,0) != parent_color ||
         GetPixel(dc,0,height-1) != parent_color ||
         GetPixel(dc,width-1,height-1) != parent_color ||
         GetPixel(dc,width/2,height/4) != RGB(30,70,140))) return 6;
    // Enabled secondary buttons must not look disabled when the Windows accent
    // is too close to the current surface. Exercise the real glyph renderer.
    SetWindowTextW(button,L"MMMM");
    if(!DP_StyleButton(button,RGB(255,255,255),parent_color,FALSE,MulDiv(6,dpi,96)))return 13;
    SendMessageW(button,WM_PRINTCLIENT,reinterpret_cast<WPARAM>(dc),PRF_CLIENT);
    if(!(contrast.dwFlags&HCF_HIGHCONTRASTON)) {
      unsigned readable_ink=0;
      const COLORREF expected=dark?RGB(255,255,255):RGB(0,0,0);
      for(int y=height/4;y<height*3/4;++y)for(int x=width/3;x<width*2/3;++x)
        if(GetPixel(dc,x,y)==expected)++readable_ink;
      if(readable_ink<8||!IsWindowEnabled(button))return 14;
    }
    if (IsWindowVisible(owner) || IsWindowVisible(button)) return 7;
    SelectObject(dc,previous); DeleteObject(image); DeleteDC(dc); DestroyWindow(button);
    ++passed; std::cout << "PASS hidden rounded BUTTON " << (dark?"dark ":"light ") << dpi << " DPI; parent-matched corners and readable enabled secondary glyphs\n";
  }
  wchar_t family[128]{};
  if (DP_LoadPrivateFont(font_copy.c_str(), family, 128) <= 0) return 8;
  // Delete only the newly copied QA font, never the source asset. An active
  // private font must continue working without holding its temporary file.
  if (!DeleteFileW(font_copy.c_str())) return 12;
  ++passed; std::cout << "PASS private memory font holds no temporary file lock\n";
  HFONT font = CreateFontW(-20,0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,
      OUT_TT_ONLY_PRECIS,CLIP_DEFAULT_PRECIS,ANTIALIASED_QUALITY,DEFAULT_PITCH,family);
  HDC dc = CreateCompatibleDC(nullptr); const auto previous = SelectObject(dc,font);
  wchar_t actual[128]{}; GetTextFaceW(dc,128,actual);
  const bool exact = std::wstring(actual) == family && std::wstring(actual) == L".萍方-简";
  SelectObject(dc,previous); DeleteObject(font); DeleteDC(dc);
  if (!exact) return 9;
  ++passed; std::cout << "PASS actual private font family selected by GDI\n";
  // VCL owns each button's bold font. Styling and teardown must borrow that
  // exact HFONT, including when a primary button is restyled as secondary.
  HFONT bold=CreateFontW(-20,0,0,0,FW_BOLD,FALSE,FALSE,FALSE,DEFAULT_CHARSET,
      OUT_TT_ONLY_PRECIS,CLIP_DEFAULT_PRECIS,ANTIALIASED_QUALITY,DEFAULT_PITCH,family);
  HWND bold_button=CreateWindowExW(0,L"BUTTON",L"完成(&F)",WS_CHILD,0,0,160,31,owner,nullptr,nullptr,nullptr);
  if(!bold||!bold_button)return 15;
  SendMessageW(bold_button,WM_SETFONT,reinterpret_cast<WPARAM>(bold),FALSE);
  for(const BOOL primary:{TRUE,FALSE}) {
    if(!DP_StyleButton(bold_button,RGB(32,32,32),RGB(160,190,255),primary,6))return 16;
    const auto borrowed=reinterpret_cast<HFONT>(SendMessageW(bold_button,WM_GETFONT,0,0));
    LOGFONTW metrics{};
    if(borrowed!=bold||GetObjectW(borrowed,sizeof(metrics),&metrics)!=sizeof(metrics)||
        metrics.lfWeight<FW_SEMIBOLD||std::wstring(metrics.lfFaceName)!=family)return 17;
  }
  DP_CloseControls();
  if(GetObjectType(bold)!=OBJ_FONT)return 18;
  DestroyWindow(bold_button);DeleteObject(bold);
  ++passed; std::cout << "PASS primary/secondary styles preserve caller-owned bold private HFONT through teardown\n";
  // Repeated style replacement/destruction must not leave a HWND subclass or
  // graphics resource pointing into a subsequently unloaded DLL.
  const DWORD before = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
  for (int i=0; i<120; ++i) {
    HWND button = CreateWindowExW(0,L"BUTTON",L"test",WS_CHILD,0,0,200,44,owner,nullptr,nullptr,nullptr);
    DP_StyleButton(button,RGB(32,32,32),RGB(160,190,255),FALSE,12);
    DP_StyleButton(button,RGB(32,32,32),RGB(160,190,255),TRUE,16);
    DestroyWindow(button);
  }
  DP_CloseControls(); DP_CloseBrand(); DestroyWindow(owner);
  if (GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS) > before + 2) return 10;
  ++passed; std::cout << "PASS repeated hidden control teardown bounded GDI resources\n";
  std::cout << "RESULT " << passed << " control scenarios passed; no windows shown\n";
  return 0;
}
