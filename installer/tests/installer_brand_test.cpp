#include <windows.h>
#include <filesystem>
#include <iostream>
#include <fstream>
#include <string>

extern "C" int __stdcall DP_ShowBrand(HWND,int,int,COLORREF,const wchar_t*,void(__stdcall*)());
extern "C" void __stdcall DP_CloseBrand();
namespace {
COLORREF surface=RGB(235,240,245);
LRESULT CALLBACK ParentProcedure(HWND window,UINT message,WPARAM wparam,LPARAM lparam) {
  if(message==WM_ERASEBKGND||message==WM_PRINTCLIENT) {
    RECT bounds{};GetClientRect(window,&bounds);HBRUSH brush=CreateSolidBrush(surface);
    FillRect(reinterpret_cast<HDC>(wparam),&bounds,brush);DeleteObject(brush);return 1;
  }
  return DefWindowProcW(window,message,wparam,lparam);
}
bool CheckFrame(HWND child) {
  constexpr int width=640,height=400;
  HDC dc=CreateCompatibleDC(nullptr);BITMAPINFO info{};
  info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);info.bmiHeader.biWidth=width;
  info.bmiHeader.biHeight=-height;info.bmiHeader.biPlanes=1;info.bmiHeader.biBitCount=32;
  void* bytes=nullptr;HBITMAP image=CreateDIBSection(dc,&info,DIB_RGB_COLORS,&bytes,nullptr,0);
  if(!image){DeleteDC(dc);return false;}
  const auto previous=SelectObject(dc,image);
  SendMessageW(child,WM_PRINTCLIENT,reinterpret_cast<WPARAM>(dc),PRF_CLIENT);
  bool same=true;
  for(const auto& point:{POINT{0,0},POINT{width-1,0},POINT{0,height-1},POINT{width-1,height-1}})
    same=same&&GetPixel(dc,point.x,point.y)==surface;
  unsigned ink=0;for(int y=30;y<height-30;y+=3)for(int x=30;x<width-30;x+=3)
    if(GetPixel(dc,x,y)!=surface)++ink;
  if(!same||ink<=100)std::cerr<<"Frame mismatch: corners="<<same<<" ink="<<ink
      <<" colors="<<GetPixel(dc,0,0)<<","<<GetPixel(dc,width-1,0)<<","<<GetPixel(dc,0,height-1)
      <<","<<GetPixel(dc,width-1,height-1)<<" expected="<<surface<<"\n";
  wchar_t render_root[32768]{};
  if(GetEnvironmentVariableW(L"DAN_INSTALLER_BRAND_RENDER",render_root,32768)) {
    std::filesystem::create_directories(render_root);
    const auto output=std::filesystem::path(render_root)/
        (GetRValue(surface)<128?L"installer-brand-dark.bmp":L"installer-brand-light.bmp");
    BITMAPFILEHEADER header{};header.bfType=0x4d42;
    header.bfOffBits=sizeof(header)+sizeof(info.bmiHeader);
    header.bfSize=header.bfOffBits+width*height*4;
    std::ofstream file(output,std::ios::binary);
    file.write(reinterpret_cast<const char*>(&header),sizeof(header));
    file.write(reinterpret_cast<const char*>(&info.bmiHeader),sizeof(info.bmiHeader));
    file.write(static_cast<const char*>(bytes),width*height*4);
  }
  SelectObject(dc,previous);DeleteObject(image);DeleteDC(dc);
  return same&&ink>100;
}
}
int wmain(int argc,wchar_t** argv) {
  if(argc!=2)return 2;
  WNDCLASSW cls{};cls.lpfnWndProc=ParentProcedure;cls.hInstance=GetModuleHandleW(nullptr);
  cls.lpszClassName=L"DanInstallerBrandTestSurface";RegisterClassW(&cls);
  HWND owner=CreateWindowExW(0,cls.lpszClassName,L"hidden branding test",WS_OVERLAPPED,
      0,0,800,600,nullptr,nullptr,cls.hInstance,nullptr);
  if(!owner)return 3;
  RECT actual{};GetClientRect(owner,&actual);
  if(actual.right<640||actual.bottom<400)return 8;
  unsigned passed=0;
  for(const bool dark:{false,true}) {
    surface=dark?RGB(31,37,42):RGB(235,240,245);
    if(!DP_ShowBrand(owner,640,400,surface,argv[1],nullptr))return 4;
    HWND child=GetWindow(owner,GW_CHILD);
    Sleep(350);
    if(!CheckFrame(child))return 5;
    ++passed;std::cout<<"PASS "<<(dark?"dark":"light")<<" player icon and name with four parent-matched corners\n";
    if(IsWindowVisible(owner))return 7;
    DP_CloseBrand();
  }
  DestroyWindow(owner);
  std::cout<<"RESULT "<<passed<<" original-asset logo scenarios passed; no windows shown or images changed\n";
  return 0;
}
