#include <windows.h>
#include <algorithm>
#include <cmath>
#include <iostream>
#include <filesystem>
#include <string>
#include <vector>

extern "C" int __stdcall DP_StyleButton(HWND, COLORREF, COLORREF, BOOL, int);
extern "C" void __stdcall DP_CloseControls();
extern "C" int __stdcall DP_LoadPrivateFont(const wchar_t*, wchar_t*, int);
extern "C" void __stdcall DP_CloseBrand();

namespace {
COLORREF parent_color = RGB(243,243,243);
std::string current_case = "initialization";
int Fail(int code, const std::string& message) {
  std::cerr << "FAIL code=" << code << " case=" << current_case << " "
            << message << " win32=" << GetLastError() << '\n';
  return code;
}
double Luminance(COLORREF color) {
  const auto linear=[](BYTE component) {
    const double channel=component/255.0;
    return channel<=.04045?channel/12.92:std::pow((channel+.055)/1.055,2.4);
  };
  return .2126*linear(GetRValue(color))+.7152*linear(GetGValue(color))+.0722*linear(GetBValue(color));
}
double Contrast(COLORREF a,COLORREF b) {
  const double x=Luminance(a),y=Luminance(b);
  return ((std::max)(x,y)+.05)/((std::min)(x,y)+.05);
}
int CheckShape(HDC dc,int width,int height,COLORREF center) {
  const COLORREF corners[]={GetPixel(dc,0,0),GetPixel(dc,width-1,0),
      GetPixel(dc,0,height-1),GetPixel(dc,width-1,height-1)};
  for(int i=0;i<4;++i)if(corners[i]!=parent_color)
    return Fail(6,"corner="+std::to_string(i)+" actualRGB="+std::to_string(corners[i])+
        " expectedParentRGB="+std::to_string(parent_color));
  // Only sample a blank-caption render: a tall glyph may cover this point.
  const auto sample=GetPixel(dc,width/2,height/4);
  if(sample!=center)return Fail(6,"blank fill actualRGB="+std::to_string(sample)+
      " expectedRGB="+std::to_string(center));
  return 0;
}
int CheckGlyphs(HWND button,HDC dc,const wchar_t* caption,int width,int height,COLORREF background) {
  SetWindowTextW(button,L"");
  SendMessageW(button,WM_PRINTCLIENT,reinterpret_cast<WPARAM>(dc),PRF_CLIENT);
  std::vector<COLORREF> baseline;
  baseline.reserve(static_cast<size_t>(width)*height);
  for(int y=0;y<height;++y)for(int x=0;x<width;++x)baseline.push_back(GetPixel(dc,x,y));
  const auto previous=SelectObject(dc,reinterpret_cast<HFONT>(SendMessageW(button,WM_GETFONT,0,0)));
  RECT text{};
  const int measured=DrawTextW(dc,caption,-1,&text,DT_CALCRECT|DT_SINGLELINE);
  SelectObject(dc,previous);
  if(measured<=0||text.right>width||text.bottom>height)
    return Fail(19,"caption does not fit: text="+std::to_string(text.right)+"x"+
        std::to_string(text.bottom)+" button="+std::to_string(width)+"x"+std::to_string(height));
  SetWindowTextW(button,caption);
  SendMessageW(button,WM_PRINTCLIENT,reinterpret_cast<WPARAM>(dc),PRF_CLIENT);
  unsigned changed=0,readable=0;
  double strongest=1;
  // Compare only the centered measured text box (plus one rounding pixel).
  // Antialiased text need not contain any exactly-black/white pixels.
  const int text_width=static_cast<int>(text.right),text_height=static_cast<int>(text.bottom);
  const int left=(std::max)(0,(width-text_width)/2-1),top=(std::max)(0,(height-text_height)/2-1);
  const int right=(std::min)(width,left+text_width+2),bottom=(std::min)(height,top+text_height+2);
  for(int y=top;y<bottom;++y)for(int x=left;x<right;++x) {
    const auto color=GetPixel(dc,x,y);
    if(color==baseline[static_cast<size_t>(y)*width+x])continue;
    ++changed;
    const auto contrast=Contrast(color,background);
    strongest=(std::max)(strongest,contrast);
    if(contrast>=4.5)++readable;
  }
  if(changed<8||readable<8||!IsWindowEnabled(button))
    return Fail(14,"caption changed="+std::to_string(changed)+" readableAA="+
        std::to_string(readable)+" strongestContrast="+std::to_string(strongest)+
        " enabled="+std::to_string(IsWindowEnabled(button)));
  return 0;
}
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

int Run(int argc, wchar_t** argv) {
  if (argc != 3) return Fail(2,"Expected source font and qa-installer sandbox arguments");
  namespace fs = std::filesystem;
  const auto fixture = fs::absolute(argv[2]) / (L"font-" + std::to_wstring(GetTickCount64()));
  bool sandbox = false; for (const auto& part : fixture) if (part == L"qa-installer") sandbox = true;
  if (!sandbox) return Fail(11,"Fixture is not in an explicit qa-installer sandbox");
  fs::create_directories(fixture);
  const auto font_copy = fixture / L"private-font-fixture.ttf";
  fs::copy_file(fs::path(argv[1]), font_copy);
  WNDCLASSW owner_class{}; owner_class.lpfnWndProc=SurfaceProcedure;
  owner_class.hInstance=GetModuleHandleW(nullptr); owner_class.lpszClassName=L"DanInstallerTestSurface";
  if(!RegisterClassW(&owner_class))return Fail(3,"Cannot register hidden owner class");
  HWND owner = CreateWindowExW(0, owner_class.lpszClassName, L"hidden installer control test",
      WS_OVERLAPPED, 0, 0, 800, 600, nullptr, nullptr, nullptr, nullptr);
  if (!owner) return Fail(3,"Cannot create hidden owner window");
  unsigned passed = 0;
  wchar_t family[128]{};
  current_case="private memory font";
  if (DP_LoadPrivateFont(font_copy.c_str(), family, 128) <= 0)
    return Fail(8,"Cannot load embedded private font");
  // Delete only our newly copied QA font. All matrix renders below must keep
  // working from memory, independently of installed fonts or a temporary file.
  if (!DeleteFileW(font_copy.c_str())) return Fail(12,"Private font retains temporary file lock");
  ++passed; std::cout << "PASS private memory font holds no temporary file lock\n";
  HIGHCONTRASTW contrast{sizeof(contrast),0,nullptr};
  if(!SystemParametersInfoW(SPI_GETHIGHCONTRAST,sizeof(contrast),&contrast,0))
    return Fail(20,"Cannot query high-contrast mode");
  const bool high_contrast=(contrast.dwFlags&HCF_HIGHCONTRASTON)!=0;
  if(high_contrast)std::cout<<"INFO native high-contrast fallback; custom palette assertions skipped\n";
  for (const bool dark : {false,true}) for (const int dpi : {96, 120, 144, 192}) {
    parent_color=dark?RGB(32,32,32):RGB(243,243,243);
    const int width = MulDiv(200, dpi, 96), height = MulDiv(23, dpi, 96);
    for(const int font_height:{11,13,15})for(const int weight:{FW_NORMAL,FW_BOLD}) {
    current_case=std::string(dark?"dark":"light")+" dpi="+std::to_string(dpi)+
        " fontHeight="+std::to_string(font_height)+" weight="+std::to_string(weight);
    HWND button = CreateWindowExW(0, L"BUTTON", L"", WS_CHILD | WS_TABSTOP,
        0, 0, width, height, owner, nullptr, nullptr, nullptr);
    HFONT matrix_font=CreateFontW(-MulDiv(font_height,dpi,96),0,0,0,weight,FALSE,FALSE,FALSE,
        DEFAULT_CHARSET,OUT_TT_ONLY_PRECIS,CLIP_DEFAULT_PRECIS,ANTIALIASED_QUALITY,DEFAULT_PITCH,family);
    if(!button||!matrix_font)return Fail(4,"Cannot create hidden button/private HFONT");
    SendMessageW(button,WM_SETFONT,reinterpret_cast<WPARAM>(matrix_font),FALSE);
    // Match production's actual theme fallback; a headless worker need not
    // have an active desktop theme service to recover an intentionally wrong white fallback.
    if (!DP_StyleButton(button, parent_color, RGB(30,70,140), TRUE, MulDiv(6,dpi,96)))
      return Fail(4,"Cannot install primary button style");
    HDC dc = CreateCompatibleDC(nullptr);
    BITMAPINFO info{}; info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = width; info.bmiHeader.biHeight = -height;
    info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32; info.bmiHeader.biCompression = BI_RGB;
    void* bits = nullptr;
    HBITMAP image = CreateDIBSection(dc, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
    if (!dc||!image) return Fail(5,"Cannot create hidden DIB canvas");
    const auto previous = SelectObject(dc, image);
    const auto previous_font=SelectObject(dc,matrix_font);
    wchar_t matrix_family[128]{};
    const int family_length=GetTextFaceW(dc,128,matrix_family);
    SelectObject(dc,previous_font);
    if(family_length<=0||std::wstring(matrix_family)!=family)
      return Fail(9,"Matrix selected a fallback instead of the embedded private font");
    SendMessageW(button, WM_PRINTCLIENT, reinterpret_cast<WPARAM>(dc), PRF_CLIENT);
    if (!high_contrast) {
      if(const int failure=CheckShape(dc,width,height,RGB(30,70,140)))return failure;
      if(const int failure=CheckGlyphs(button,dc,L"安装(&I)",width,height,RGB(30,70,140)))return failure;
    }
    // Enabled secondary buttons must not look disabled when the Windows accent
    // is too close to the current surface. Exercise the real glyph renderer.
    SetWindowTextW(button,L"");
    if(!DP_StyleButton(button,parent_color,parent_color,FALSE,MulDiv(6,dpi,96)))
      return Fail(13,"Cannot install secondary button style");
    SendMessageW(button,WM_PRINTCLIENT,reinterpret_cast<WPARAM>(dc),PRF_CLIENT);
    if(!high_contrast) {
      if(const int failure=CheckShape(dc,width,height,parent_color))return failure;
      if(const int failure=CheckGlyphs(button,dc,L"MMMM",width,height,parent_color))return failure;
    }
    if (IsWindowVisible(owner) || IsWindowVisible(button)) return Fail(7,"A fixture became visible");
    SelectObject(dc,previous); DeleteObject(image); DeleteDC(dc); DestroyWindow(button);
    DeleteObject(matrix_font);
    }
    ++passed; std::cout << "PASS hidden rounded BUTTON " << (dark?"dark ":"light ") << dpi
        << " DPI; 6 explicit font size/weight variants, blank shape + real AA glyphs\n";
  }
  current_case="actual private font family";
  HFONT font = CreateFontW(-20,0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,
      OUT_TT_ONLY_PRECIS,CLIP_DEFAULT_PRECIS,ANTIALIASED_QUALITY,DEFAULT_PITCH,family);
  HDC dc = CreateCompatibleDC(nullptr);
  if(!font||!dc)return Fail(9,"Cannot create font selection probe");
  const auto previous = SelectObject(dc,font);
  wchar_t actual[128]{}; GetTextFaceW(dc,128,actual);
  const bool exact = std::wstring(actual) == family && std::wstring(actual) == L".萍方-简";
  SelectObject(dc,previous); DeleteObject(font); DeleteDC(dc);
  if (!exact) return Fail(9,"Actual private font family is not .萍方-简");
  ++passed; std::cout << "PASS actual private font family selected by GDI\n";
  // VCL owns each button's bold font. Styling and teardown must borrow that
  // exact HFONT, including when a primary button is restyled as secondary.
  current_case="borrowed bold font";
  HFONT bold=CreateFontW(-20,0,0,0,FW_BOLD,FALSE,FALSE,FALSE,DEFAULT_CHARSET,
      OUT_TT_ONLY_PRECIS,CLIP_DEFAULT_PRECIS,ANTIALIASED_QUALITY,DEFAULT_PITCH,family);
  HWND bold_button=CreateWindowExW(0,L"BUTTON",L"完成(&F)",WS_CHILD,0,0,160,31,owner,nullptr,nullptr,nullptr);
  if(!bold||!bold_button)return Fail(15,"Cannot create borrowed bold font fixture");
  SendMessageW(bold_button,WM_SETFONT,reinterpret_cast<WPARAM>(bold),FALSE);
  for(const BOOL primary:{TRUE,FALSE}) {
    if(!DP_StyleButton(bold_button,RGB(32,32,32),RGB(160,190,255),primary,6))
      return Fail(16,"Cannot restyle caller-owned font fixture");
    const auto borrowed=reinterpret_cast<HFONT>(SendMessageW(bold_button,WM_GETFONT,0,0));
    LOGFONTW metrics{};
    if(borrowed!=bold||GetObjectW(borrowed,sizeof(metrics),&metrics)!=sizeof(metrics)||
        metrics.lfWeight<FW_SEMIBOLD||std::wstring(metrics.lfFaceName)!=family)
      return Fail(17,"Styling replaced or weakened caller-owned bold HFONT");
  }
  DP_CloseControls();
  if(GetObjectType(bold)!=OBJ_FONT)return Fail(18,"Styling teardown deleted borrowed HFONT");
  DestroyWindow(bold_button);DeleteObject(bold);
  ++passed; std::cout << "PASS primary/secondary styles preserve caller-owned bold private HFONT through teardown\n";
  // Repeated style replacement/destruction must not leave a HWND subclass or
  // graphics resource pointing into a subsequently unloaded DLL.
  current_case="repeated teardown";
  const DWORD before = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
  for (int i=0; i<120; ++i) {
    HWND button = CreateWindowExW(0,L"BUTTON",L"test",WS_CHILD,0,0,200,44,owner,nullptr,nullptr,nullptr);
    if(!button||!DP_StyleButton(button,RGB(32,32,32),RGB(160,190,255),FALSE,12)||
        !DP_StyleButton(button,RGB(32,32,32),RGB(160,190,255),TRUE,16))
      return Fail(10,"Cannot create/restyle teardown fixture iteration="+std::to_string(i));
    DestroyWindow(button);
  }
  DP_CloseControls(); DP_CloseBrand(); DestroyWindow(owner);
  const DWORD after=GetGuiResources(GetCurrentProcess(),GR_GDIOBJECTS);
  if (after > before + 2) return Fail(10,"GDI growth before="+std::to_string(before)+" after="+std::to_string(after));
  ++passed; std::cout << "PASS repeated hidden control teardown bounded GDI resources\n";
  std::cout << "RESULT " << passed << " control scenarios passed (48 font/theme/DPI variants); no windows shown\n";
  return 0;
}

int wmain(int argc,wchar_t** argv) {
  try{return Run(argc,argv);}
  catch(const std::exception& error){return Fail(21,error.what());}
}
