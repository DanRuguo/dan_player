// QA DLL only: ask the exact Inno HWNDs to paint into memory. No desktop DC,
// screen capture, global theme changes, installation, or user-window traversal.
#include "installer_core.h"
#include "installer_paint.h"
#include <objidl.h>
#include <gdiplus.h>
#include <set>
#include <fstream>

using namespace dan::installer;
namespace {
using Callback=void(__stdcall*)();
HWND timer_window=nullptr;
Callback timer_callback=nullptr;
fs::path render_directory;
RECT directory_next_bounds{};
constexpr UINT_PTR kTimer=0xD4A7;
struct Surface {
  HDC dc=CreateCompatibleDC(nullptr);
  HBITMAP bitmap=nullptr; HGDIOBJ previous=nullptr; void* pixels=nullptr;
  int width,height;
  explicit Surface(HWND window,bool whole=false) : width(0),height(0) {
    RECT rect{};
    if(whole)GetWindowRect(window,&rect);else GetClientRect(window,&rect);
    width=rect.right-rect.left;height=rect.bottom-rect.top;
    if(!dc||width<=0||height<=0||width>4096||height>4096) return;
    BITMAPINFO info{};info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth=width;info.bmiHeader.biHeight=-height;
    info.bmiHeader.biPlanes=1;info.bmiHeader.biBitCount=32;
    bitmap=CreateDIBSection(dc,&info,DIB_RGB_COLORS,&pixels,nullptr,0);
    if(bitmap) previous=SelectObject(dc,bitmap);
  }
  ~Surface(){ if(previous)SelectObject(dc,previous);if(bitmap)DeleteObject(bitmap);if(dc)DeleteDC(dc); }
};
void CALLBACK RenderTimer(HWND window,UINT,UINT_PTR id,DWORD) {
  KillTimer(window,id);timer_window=nullptr;
  const auto callback=timer_callback;timer_callback=nullptr;
  if(callback)callback();
}
bool Sandbox(const fs::path& path) {
  for(const auto& part:path)if(part==L"qa-installer")return true;
  return false;
}
struct StyledPaint { HDC dc; RECT root; };
BOOL CALLBACK PaintStyledChild(HWND window,LPARAM value) {
  wchar_t name[128]{};GetClassNameW(window,name,128);
  if(!IsWindowVisible(window)||
      (std::wstring(name)!=L"TNewStaticText"&&std::wstring(name)!=L"TNewCheckBox"))return TRUE;
  const auto* target=reinterpret_cast<const StyledPaint*>(value);
  RECT bounds{};GetWindowRect(window,&bounds);
  const int saved=SaveDC(target->dc);
  SetViewportOrgEx(target->dc,bounds.left-target->root.left,bounds.top-target->root.top,nullptr);
  IntersectClipRect(target->dc,0,0,bounds.right-bounds.left,bounds.bottom-bounds.top);
  RECT client{};GetClientRect(window,&client);
  // WM_PRINT may already have drawn an unstyled caption. Reconstruct only this
  // exact child's parent surface before its transparent themed paint; otherwise
  // two different glyph rasters are composited and look like duplicated text.
  PaintParentSurface(window,target->dc,client,GetPixel(target->dc,0,0));
  // VCL style hooks paint WM_PAINT into a caller-supplied HDC. Their stock
  // WM_PRINT path does not always apply themed checkbox captions.
  SendMessageW(window,WM_PAINT,reinterpret_cast<WPARAM>(target->dc),0);
  RestoreDC(target->dc,saved);
  return TRUE;
}
}
extern "C" __declspec(dllexport) int __stdcall DP_QA_ScheduleFrame(HWND window,int delay,Callback callback) {
  if(timer_window)KillTimer(timer_window,kTimer);
  timer_window=nullptr;timer_callback=nullptr;
  if(!IsWindow(window)||delay<1||delay>3000||!callback)return 0;
  timer_window=window;timer_callback=callback;
  return SetTimer(window,kTimer,static_cast<UINT>(delay),RenderTimer)?1:0;
}
extern "C" __declspec(dllexport) void __stdcall DP_QA_CancelFrame() {
  if(timer_window)KillTimer(timer_window,kTimer);
  timer_window=nullptr;timer_callback=nullptr;
}
extern "C" __declspec(dllexport) int __stdcall DP_QA_Capture(HWND window,const wchar_t* file) {
  try {
    if(!file||!IsWindow(window))return 0;
    const fs::path path=fs::absolute(file);
    if(!Sandbox(path)||path.extension()!=L".png"||fs::exists(path))return 0;
    CheckNoReparsePoints(path);
    render_directory=path.parent_path();
    Surface surface(window,true);if(!surface.bitmap)return 0;
    RECT bounds{0,0,surface.width,surface.height};
    HBRUSH sentinel=CreateSolidBrush(RGB(255,0,255));
    FillRect(surface.dc,&bounds,sentinel);DeleteObject(sentinel);
    SendMessageW(window,WM_PRINT,reinterpret_cast<WPARAM>(surface.dc),PRF_NONCLIENT|PRF_CLIENT|PRF_CHILDREN|PRF_ERASEBKGND);
    StyledPaint styled{surface.dc,{}};GetWindowRect(window,&styled.root);
    EnumChildWindows(window,PaintStyledChild,reinterpret_cast<LPARAM>(&styled));
    // A white/black/sentinel blank WM_PRINT result is not an accepted render.
    std::set<DWORD> colors;
    const auto pixels=static_cast<const DWORD*>(surface.pixels);
    for(int i=0;i<surface.width*surface.height;i+=7)colors.insert(pixels[i]&0xffffff);
    if(colors.size()<12)return 0;
    ULONG_PTR token=0;Gdiplus::GdiplusStartupInput input;
    if(Gdiplus::GdiplusStartup(&token,&input,nullptr)!=Gdiplus::Ok)return 0;
    bool saved=false;
    {
      Gdiplus::Bitmap image(surface.bitmap,nullptr);
      CLSID png{0x557cf406,0x1a04,0x11d3,{0x9a,0x73,0x00,0x00,0xf8,0x1e,0xf3,0x2e}};
      saved=image.Save(path.c_str(),&png,nullptr)==Gdiplus::Ok;
    }
    Gdiplus::GdiplusShutdown(token);return saved?1:0;
  } catch(...){return 0;}
}
extern "C" __declspec(dllexport) int __stdcall DP_QA_ControlCorners(HWND window) {
  if(!IsWindow(window))return 0;
  Surface actual(window),parent(window);if(!actual.bitmap||!parent.bitmap)return 0;
  RECT bounds{0,0,actual.width,actual.height};
  PaintParentSurface(window,parent.dc,bounds,RGB(255,0,255));
  SendMessageW(window,WM_PRINTCLIENT,reinterpret_cast<WPARAM>(actual.dc),PRF_CLIENT);
  bool same=true;
  for(const auto& point:{POINT{0,0},POINT{actual.width-1,0},
      POINT{0,actual.height-1},POINT{actual.width-1,actual.height-1}})
    if(GetPixel(actual.dc,point.x,point.y)!=GetPixel(parent.dc,point.x,point.y))same=false;
  if(!render_directory.empty()) {
    wchar_t title[128]{};GetWindowTextW(window,title,128);
    RECT rect{};GetWindowRect(window,&rect);
    std::ofstream log(render_directory/L"control-pixels.tsv",std::ios::app);
    log<<ToUtf8(title)<<'\t'<<actual.width<<'x'<<actual.height<<'\t'<<rect.left<<','<<rect.top
       <<'\t'<<std::hex<<GetPixel(actual.dc,0,0)<<'\t'<<GetPixel(parent.dc,0,0)
       <<'\t'<<(same?"PASS":"FAIL")<<'\n';
  }
  return same?1:0;
}
extern "C" __declspec(dllexport) int __stdcall DP_QA_ButtonFont(HWND window,HWND reference) {
  const HFONT font=reinterpret_cast<HFONT>(SendMessageW(window,WM_GETFONT,0,0));
  const HFONT inherited=reinterpret_cast<HFONT>(SendMessageW(reference,WM_GETFONT,0,0));
  LOGFONTW actual{},base{};
  if(!IsWindow(window)||!font||!inherited||GetObjectW(font,sizeof(actual),&actual)!=sizeof(actual)||
      GetObjectW(inherited,sizeof(base),&base)!=sizeof(base)||render_directory.empty())return 0;
  Surface surface(window);if(!surface.bitmap)return 0;
  const auto previous=SelectObject(surface.dc,font);
  wchar_t face[LF_FACESIZE]{},caption[256]{};
  GetTextFaceW(surface.dc,LF_FACESIZE,face);
  const int count=GetWindowTextW(window,caption,256);
  RECT measured{};DrawTextW(surface.dc,caption,count,&measured,DT_SINGLELINE|DT_CALCRECT);
  SelectObject(surface.dc,previous);
  const bool valid=actual.lfWeight>=FW_SEMIBOLD&&actual.lfHeight==base.lfHeight&&
      std::wstring(actual.lfFaceName)==base.lfFaceName&&std::wstring(face)==base.lfFaceName&&
      measured.right>0&&measured.bottom>0&&measured.right<=surface.width-4&&measured.bottom<=surface.height-2;
  std::ofstream log(render_directory/L"button-fonts.tsv",std::ios::app);
  log<<ToUtf8(caption)<<"\tweight="<<actual.lfWeight<<"\tfamily="<<ToUtf8(face)
     <<"\theight="<<actual.lfHeight<<"\ttext="<<measured.right<<','<<measured.bottom
     <<"\tcontrol="<<surface.width<<','<<surface.height<<'\t'<<(valid?"PASS":"FAIL")<<'\n';
  return valid?1:0;
}
extern "C" __declspec(dllexport) int __stdcall DP_QA_DirectoryGeometry(
    HWND edit,HWND browse,HWND desktop,HWND start,HWND note,HWND next,HWND back,HWND cancel,HWND disk_space) {
  const HWND controls[]{edit,browse,desktop,start,note,next,back,cancel,disk_space};
  RECT bounds[9]{};bool valid=true;
  for(int i=0;i<9;++i) {
    const HWND parent=GetParent(controls[i]);
    if(!IsWindow(controls[i])||!parent||!GetWindowRect(controls[i],&bounds[i]))return 0;
    RECT client{};GetClientRect(parent,&client);
    MapWindowPoints(parent,nullptr,reinterpret_cast<POINT*>(&client),2);
    const auto& r=bounds[i];
    valid=valid&&r.left>=client.left&&r.top>=client.top&&r.right<=client.right&&r.bottom<=client.bottom;
  }
  directory_next_bounds=bounds[5];
  const LONG centers=(bounds[0].top+bounds[0].bottom)-(bounds[1].top+bounds[1].bottom);
  valid=valid&&centers>=-2&&centers<=2&&bounds[0].right<bounds[1].left&&
      bounds[2].top>bounds[1].bottom&&bounds[3].top>bounds[2].bottom&&
      bounds[4].top>bounds[3].bottom&&bounds[4].bottom<bounds[8].top;
  for(int i=5;i<8;++i)for(int j=i+1;j<8;++j) {
    RECT intersection{};if(IntersectRect(&intersection,&bounds[i],&bounds[j]))valid=false;
  }
  if(!render_directory.empty()) {
    std::ofstream log(render_directory/L"geometry.tsv");
    log<<"dpi\t"<<GetDpiForWindow(edit)<<"\ncenter-delta-px\t"<<centers/2.0<<'\n';
    const char* names[]{"edit","browse","desktop","start","note","next","back","cancel","disk-space"};
    for(int i=0;i<9;++i)log<<names[i]<<'\t'<<bounds[i].left<<','<<bounds[i].top<<','
        <<bounds[i].right<<','<<bounds[i].bottom<<'\n';
    log<<"bounds-centers-spacing\t"<<(valid?"PASS":"FAIL")<<'\n';
  }
  return valid?1:0;
}
extern "C" __declspec(dllexport) int __stdcall DP_QA_FooterGeometry(
    HWND content,HWND next,HWND back,HWND cancel,const wchar_t* name) {
  RECT body{};if(!GetWindowRect(content,&body)||!name||render_directory.empty())return 0;
  std::ofstream log(render_directory/(std::wstring(name)+L"-footer.tsv"));
  log<<"body\t"<<body.left<<','<<body.top<<','<<body.right<<','<<body.bottom<<'\n';
  bool valid=true;unsigned painted=0;
  for(const HWND button:{next,back,cancel}) {
    if(!IsWindowVisible(button))continue;
    ++painted;
    RECT rect{},parent{};GetWindowRect(button,&rect);GetClientRect(GetParent(button),&parent);
    MapWindowPoints(GetParent(button),nullptr,reinterpret_cast<POINT*>(&parent),2);
    Surface surface(button);if(!surface.bitmap)return 0;
    RECT client{0,0,surface.width,surface.height};HBRUSH sentinel=CreateSolidBrush(RGB(255,0,255));
    FillRect(surface.dc,&client,sentinel);DeleteObject(sentinel);
    // Reproduce the effective client paint region after parent clipping and
    // the higher, sibling notebook's opaque body. WM_PRINT alone ignores this
    // z-order occlusion and previously gave a false all-visible screenshot.
    const int saved=SaveDC(surface.dc);
    IntersectClipRect(surface.dc,parent.left-rect.left,parent.top-rect.top,
        parent.right-rect.left,parent.bottom-rect.top);
    ExcludeClipRect(surface.dc,body.left-rect.left,body.top-rect.top,
        body.right-rect.left,body.bottom-rect.top);
    SendMessageW(button,WM_PRINTCLIENT,reinterpret_cast<WPARAM>(surface.dc),PRF_CLIENT);
    RestoreDC(surface.dc,saved);
    unsigned clipped=0;
    const auto* pixels=static_cast<const DWORD*>(surface.pixels);
    for(int i=0;i<surface.width*surface.height;++i)if((pixels[i]&0xffffff)==0xff00ff)++clipped;
    wchar_t caption[128]{};GetWindowTextW(button,caption,128);
    log<<ToUtf8(caption)<<'\t'<<rect.left<<','<<rect.top<<','<<rect.right<<','<<rect.bottom
       <<"\tclipped-pixels="<<clipped<<'\n';
    valid=valid&&clipped==0;
  }
  valid=valid&&painted>0;
  log<<"painted-controls\t"<<painted<<"\npaint-region\t"<<(valid?"PASS":"FAIL")<<'\n';return valid?1:0;
}
extern "C" __declspec(dllexport) int __stdcall DP_QA_FinishedGeometry(HWND label,HWND open,HWND remove,HWND finish,int width_limit) {
  if(render_directory.empty()||!IsWindowVisible(open)||!IsWindowVisible(remove)||!IsWindowVisible(finish))return 0;
  RECT text{},first{},second{},last{},parent{},footer{},intersection{};
  GetWindowRect(label,&text);GetWindowRect(open,&first);GetWindowRect(remove,&second);
  GetWindowRect(finish,&last);
  GetClientRect(GetParent(label),&parent);
  MapWindowPoints(GetParent(label),nullptr,reinterpret_cast<POINT*>(&parent),2);
  GetClientRect(GetParent(finish),&footer);
  MapWindowPoints(GetParent(finish),nullptr,reinterpret_cast<POINT*>(&footer),2);
  bool valid=!IntersectRect(&intersection,&first,&second);
  for(const auto& rect:{first,second})valid=valid&&rect.left>=text.left&&rect.right<=text.right&&
      rect.top>=text.bottom&&rect.bottom<=parent.bottom&&rect.right-rect.left<=width_limit&&
      abs((rect.left+rect.right)-(text.left+text.right))<=2;
  valid=valid&&first.right-first.left==second.right-second.left;
  const LONG center_delta=(last.left+last.right)-(text.left+text.right);
  const bool native_size_position=directory_next_bounds.right>directory_next_bounds.left&&
      last.top==directory_next_bounds.top&&last.bottom==directory_next_bounds.bottom&&
      last.right-last.left==directory_next_bounds.right-directory_next_bounds.left;
  valid=valid&&abs(center_delta)<=2&&last.left>=footer.left&&last.right<=footer.right&&
      last.top>=footer.top&&last.bottom<=footer.bottom&&native_size_position;
  std::ofstream log(render_directory/L"finished-actions.tsv");
  const RECT all[]{text,first,second,last,parent,footer};const char* names[]{"text","open","delete","finish","page","footer-parent"};
  for(int i=0;i<6;++i)log<<names[i]<<'\t'<<all[i].left<<','<<all[i].top<<','<<all[i].right<<','<<all[i].bottom<<'\n';
  log<<"finish-center-delta-px\t"<<center_delta/2.0<<'\n';
  log<<"native-top-height-width-unchanged\t"<<(native_size_position?"PASS":"FAIL")<<'\n';
  log<<"content-actions\t"<<(valid?"PASS":"FAIL")<<'\n';return valid?1:0;
}
extern "C" __declspec(dllexport) int __stdcall DP_QA_Graphic(HWND parent,int left,int top,int width,int height,const wchar_t* name) {
  if(!IsWindow(parent)||!name||render_directory.empty()||width<=0||height<=0)return 0;
  Surface surface(parent);if(!surface.bitmap)return 0;
  if(left<0||top<0||left+width>surface.width||top+height>surface.height)return 0;
  SendMessageW(parent,WM_ERASEBKGND,reinterpret_cast<WPARAM>(surface.dc),0);
  SendMessageW(parent,WM_PRINTCLIENT,reinterpret_cast<WPARAM>(surface.dc),PRF_CLIENT|PRF_CHILDREN);
  const COLORREF background=GetPixel(surface.dc,0,0);
  bool corners=true;
  for(const auto& p:{POINT{left,top},POINT{left+width-1,top},
      POINT{left,top+height-1},POINT{left+width-1,top+height-1}})
    corners=corners&&GetPixel(surface.dc,p.x,p.y)==background;
  unsigned ink=0;for(int y=top;y<top+height;y+=2)for(int x=left;x<left+width;x+=2)
    if(GetPixel(surface.dc,x,y)!=background)++ink;
  const bool valid=corners&&ink>8;
  std::ofstream log(render_directory/L"brand-pixels.tsv",std::ios::app);
  log<<ToUtf8(name)<<'\t'<<left<<','<<top<<','<<width<<','<<height<<"\tink="<<ink
     <<"\tcorners="<<corners<<'\t'<<(valid?"PASS":"FAIL")<<'\n';
  return valid?1:0;
}
