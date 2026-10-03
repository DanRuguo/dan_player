#include "../taskbar_lyrics.h"
#include "taskbar_lyrics_test_windows.h"
#include "../taskbar_lyrics_policy.h"
#include "../taskbar_lyrics_button.h"
#include <dwmapi.h>
#include <gdiplus.h>
#include <future>
#include <thread>
#include <wrl/client.h>
#include <iostream>

namespace {
int checks = 0;
#define CHECK(value) do { ++checks; if (!(value)) { std::cerr << "Failed line " << __LINE__ << ": " #value "\n"; return 1; } } while(false)
void Pump(DWORD duration) {
  const auto end = GetTickCount64() + duration;
  do {
    MSG message;
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) { TranslateMessage(&message); DispatchMessageW(&message); }
    MsgWaitForMultipleObjects(0, nullptr, FALSE, 5, QS_ALLINPUT);
  } while (GetTickCount64() < end);
}
HWND Surface() {
  HWND result = FindOwnedTaskbarWindow(L"DanPlayer.TaskbarLyrics.v1");
  DWORD process = 0; GetWindowThreadProcessId(result, &process);
  return process == GetCurrentProcessId() ? result : nullptr;
}
bool WaitVisible() {
  const auto end = GetTickCount64() + 5000;
  do { Pump(10); if (Surface() && IsWindowVisible(Surface())) return true; } while (GetTickCount64() < end);
  return false;
}
bool RightClick(POINT point) {
  INPUT input[2]{};
  input[0].type = input[1].type = INPUT_MOUSE;
  input[0].mi.dwFlags = MOUSEEVENTF_RIGHTDOWN;
  input[1].mi.dwFlags = MOUSEEVENTF_RIGHTUP;
  return SetCursorPos(point.x, point.y) && SendInput(2, input, sizeof(INPUT)) == 2;
}
void Escape() {
  INPUT input[2]{}; input[0].type = input[1].type = INPUT_KEYBOARD;
  input[0].ki.wVk = input[1].ki.wVk = VK_ESCAPE; input[1].ki.dwFlags = KEYEVENTF_KEYUP;
  SendInput(2, input, sizeof(INPUT));
}
HWND Button() {
  const HWND result=FindOwnedTaskbarWindow(L"DanPlayer.TaskbarLyrics.Next.v1");
  DWORD process=0; GetWindowThreadProcessId(result,&process);
  return process==GetCurrentProcessId() ? result : nullptr;
}
bool Click(POINT point) {
  INPUT input[2]{}; input[0].type=input[1].type=INPUT_MOUSE;
  input[0].mi.dwFlags=MOUSEEVENTF_LEFTDOWN; input[1].mi.dwFlags=MOUSEEVENTF_LEFTUP;
  return SetCursorPos(point.x,point.y) && SendInput(2,input,sizeof(INPUT))==2;
}
bool HasShellMenu() {
  bool found=false;
  EnumWindows([](HWND window,LPARAM data)->BOOL {
    wchar_t name[128]{}; GetClassNameW(window,name,128);
    if (IsWindowVisible(window) && (wcscmp(name,L"Xaml_WindowedPopupClass")==0 || wcscmp(name,L"#32768")==0))
      *reinterpret_cast<bool*>(data)=true;
    return TRUE;
  },reinterpret_cast<LPARAM>(&found));
  return found;
}
std::vector<std::uint32_t> Capture(HWND window,RECT& bounds) {
  DwmFlush(); GdiFlush();
  if (!GetWindowRect(window,&bounds)) return {};
  const int width=bounds.right-bounds.left,height=bounds.bottom-bounds.top;
  BITMAPINFO info{}; info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER); info.bmiHeader.biWidth=width;
  info.bmiHeader.biHeight=-height; info.bmiHeader.biPlanes=1; info.bmiHeader.biBitCount=32;
  void* data=nullptr; const auto bitmap=CreateDIBSection(nullptr,&info,DIB_RGB_COLORS,&data,nullptr,0);
  const auto screen=GetDC(nullptr),memory=CreateCompatibleDC(screen);
  std::vector<std::uint32_t> pixels;
  if (bitmap && screen && memory && data) {
    const auto old=SelectObject(memory,bitmap);
    if (BitBlt(memory,0,0,width,height,screen,bounds.left,bounds.top,SRCCOPY|CAPTUREBLT)) {
      GdiFlush(); const auto source=static_cast<std::uint32_t*>(data); pixels.assign(source,source+static_cast<size_t>(width)*height);
      for (auto& pixel:pixels) pixel|=0xff000000;
    }
    SelectObject(memory,old);
  }
  if (bitmap) DeleteObject(bitmap);
  if (memory) DeleteDC(memory);
  if (screen) ReleaseDC(nullptr,screen);
  return pixels;
}
bool Save(std::vector<std::uint32_t> pixels,int width,int height,const std::wstring& path) {
  if (pixels.empty()) return false;
  Gdiplus::Bitmap image(width,height,width*4,PixelFormat32bppARGB,reinterpret_cast<BYTE*>(pixels.data()));
  const CLSID png{0x557cf406,0x1a04,0x11d3,{0x9a,0x73,0x00,0x00,0xf8,0x1e,0xf3,0x2e}};
  return image.Save(path.c_str(),&png,nullptr)==Gdiplus::Ok;
}
bool SaveSurface(HWND window,const std::wstring& path) {
  RECT bounds{}; auto pixels=Capture(window,bounds);
  return Save(std::move(pixels),bounds.right-bounds.left,bounds.bottom-bounds.top,path);
}
int Ink(const std::vector<std::uint32_t>& pixels) {
  return static_cast<int>(std::count_if(pixels.begin(),pixels.end(),[](auto pixel) {
    return static_cast<int>(pixel&255)>static_cast<int>((pixel>>16)&255)+15 &&
        static_cast<int>((pixel>>8)&255)>static_cast<int>((pixel>>16)&255)+10;
  }));
}
struct AccessibleResult { bool success=false,enabled=false,button=false; std::wstring name; HRESULT invoke=E_FAIL; };
AccessibleResult Accessible(HWND window) {
  auto promise=std::make_shared<std::promise<AccessibleResult>>(); auto result=promise->get_future();
  std::thread worker([window,promise] {
    AccessibleResult value;
    const auto initialized=CoInitializeEx(nullptr,COINIT_MULTITHREADED);
    if (SUCCEEDED(initialized)) {
      using Microsoft::WRL::ComPtr;
      ComPtr<IUIAutomation> automation; ComPtr<IUIAutomationElement> element; ComPtr<IUIAutomationInvokePattern> invoke;
      if (SUCCEEDED(CoCreateInstance(CLSID_CUIAutomation8,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&automation)))) {
        ComPtr<IUIAutomation6> bounded; if (SUCCEEDED(automation.As(&bounded))) { bounded->put_ConnectionTimeout(500); bounded->put_TransactionTimeout(500); }
        BOOL enabled=FALSE; CONTROLTYPEID type=0; BSTR name=nullptr;
        if (SUCCEEDED(automation->ElementFromHandle(window,&element)) && SUCCEEDED(element->get_CurrentName(&name)) &&
            SUCCEEDED(element->get_CurrentIsEnabled(&enabled)) && SUCCEEDED(element->get_CurrentControlType(&type)) &&
            SUCCEEDED(element->GetCurrentPatternAs(UIA_InvokePatternId,IID_PPV_ARGS(&invoke)))) {
          value.success=true; value.enabled=enabled!=FALSE; value.button=type==UIA_ButtonControlTypeId;
          if (name) value.name=name; value.invoke=invoke->Invoke();
        }
        if (name) SysFreeString(name);
      }
      invoke.Reset(); element.Reset(); automation.Reset(); CoUninitialize();
    }
    promise->set_value(value);
  });
  const auto end=GetTickCount64()+5000;
  while (result.wait_for(std::chrono::milliseconds(0))!=std::future_status::ready && GetTickCount64()<end) Pump(5);
  if (result.wait_for(std::chrono::milliseconds(0))!=std::future_status::ready) { worker.detach(); return {}; }
  worker.join(); return result.get();
}
int Focused(const std::wstring& font,const std::wstring& output) {
  using namespace taskbar_lyrics;
  const auto resources=GetGuiResources(GetCurrentProcess(),GR_GDIOBJECTS);
  CHECK(ParseColorScheme(L"player") && ParseColorScheme(L"system") && !ParseColorScheme(L"bad"));
  CHECK(ForegroundForScheme(RGB(0,120,160),true,false,0,ColorScheme::kSystem)==RGB(0,0,0));
  CHECK(ForegroundForScheme(RGB(0,120,160),false,false,0,ColorScheme::kSystem)==RGB(255,255,255));
  CHECK(ForegroundForScheme(RGB(0,120,160),true,true,RGB(255,0,0),ColorScheme::kPlayer)==RGB(255,0,0));
  CHECK(ForegroundForScheme(RGB(0,120,160),true,false,0,ColorScheme::kPlayer)!=RGB(0,0,0));
  for (const UINT dpi:{96u,192u,288u}) {
    const int edge=MulDiv(24,dpi,96);
    auto pause=RasterMediaSymbol(MediaSymbol::kPause,edge,edge,dpi,24);
    auto next=RasterMediaSymbol(MediaSymbol::kSkipNext,edge,edge,dpi,24);
    CHECK(pause.pixels[static_cast<size_t>(edge/2)*edge+edge/3]==255);
    CHECK(pause.pixels[static_cast<size_t>(edge/2)*edge+edge/2]==0);
    CHECK(next.pixels[static_cast<size_t>(edge/2)*edge+edge/3]==255);
    CHECK(std::any_of(next.pixels.begin(),next.pixels.end(),[](auto p){return p>0 && p<255;}));
    std::vector<std::uint32_t> pixels(static_cast<size_t>(edge)*edge,0xff202020); std::vector<unsigned char> columns;
    CompositeText(pixels.data(),edge,edge,pause,0,0,1,false,0,RGB(0,190,240),columns);
    CHECK(Save(pixels,edge,edge,output+L"/pause-vector-"+std::to_wstring(dpi)+L".png"));
    pixels.assign(pixels.size(),0xff202020); CompositeText(pixels.data(),edge,edge,next,0,0,1,false,0,RGB(0,190,240),columns);
    CHECK(Save(pixels,edge,edge,output+L"/next-vector-"+std::to_wstring(dpi)+L".png"));
  }
  std::vector<std::uint32_t> old(12,0),target(8,0),composed(8,0);
  old[2]=0xff0080ff; target[0]=0xff0080ff;
  CrossfadeLayout(composed.data(),8,1,old,12,1,0,0,.5,2,0,target.data());
  CHECK(composed[1]==0xff0080ff && composed[0]==0 && composed[2]==0); // actual cached anchor moves, not just a fade
  CrossfadeLayout(composed.data(),8,1,old,12,1,0,0,1,2,0,target.data()); CHECK(composed==target);
  CHECK(LayoutProgress(0)==0 && LayoutProgress(180)==1 && LayoutProgress(90)>.8);
  TaskbarLyrics surface; int actions=0; surface.SetNextTrackCallback([&]{++actions;}); surface.SetNextButtonLabel(L"下一首 · Next track");
  const auto set=[&](bool button,bool enabled,bool stroke=false,std::wstring scheme=L"player",bool layout=false,bool playing=false,
                     std::wstring text=L"当前句 · Current",std::wstring next=L"下一句 · Following",std::wstring line=L"line") {
    return surface.Set(true,std::move(text),0xff008ebd,L"DanPingFangSC",font,playing,playing,{},std::move(next),0,1,L"source",std::move(line),1,0,10000,
        L"center",L"Next: Sample track",true,stroke,0,!playing,std::move(scheme),button,enabled,layout);
  };
  CHECK(set(false,false)); CHECK(WaitVisible()); Pump(350); CHECK(!Button());
  CHECK(GetWindowLongPtrW(Surface(),GWL_EXSTYLE)&WS_EX_TRANSPARENT);
  RECT bounds{}; auto before=Capture(Surface(),bounds); CHECK(Ink(before)>30);
  CHECK(Save(before,bounds.right-bounds.left,bounds.bottom-bounds.top,output+L"/real-vector-stroke-off.png"));
  CHECK(set(true,false)); Pump(100); CHECK(Button() && IsWindowVisible(Button()));
  CHECK(!(GetWindowLongPtrW(Button(),GWL_EXSTYLE)&WS_EX_TRANSPARENT));
  RECT button{}; CHECK(GetWindowRect(Button(),&button));
  CHECK(button.left>=bounds.left && button.right<=bounds.right && button.top>=bounds.top && button.bottom<=bounds.bottom);
  CHECK(button.right-button.left==44 && button.bottom-button.top==44);
  POINT original{}; CHECK(GetCursorPos(&original)); const auto foreground=GetForegroundWindow();
  CHECK(Click({(button.left+button.right)/2,(button.top+button.bottom)/2})); Pump(50); CHECK(actions==0);
  auto accessible=Accessible(Button()); Pump(50);
  CHECK(accessible.success && accessible.button && !accessible.enabled && accessible.name==L"下一首 · Next track");
  CHECK(FAILED(accessible.invoke) && actions==0);
  CHECK(set(true,true)); Pump(30); accessible=Accessible(Button()); Pump(50);
  CHECK(accessible.success && accessible.enabled && SUCCEEDED(accessible.invoke) && actions==1);
  CHECK(Click({(button.left+button.right)/2,(button.top+button.bottom)/2})); Pump(50); CHECK(actions==2);
  CHECK(GetForegroundWindow()==foreground);
  const POINT lyric_point{bounds.left+20,(bounds.top+bounds.bottom)/2};
  CHECK(WindowFromPoint(lyric_point)!=Surface() && WindowFromPoint(lyric_point)!=Button());
  SetCursorPos((button.left+button.right)/2,(button.top+button.bottom)/2); Pump(40);
  auto hovered=Capture(Surface(),bounds); CHECK(Save(hovered,bounds.right-bounds.left,bounds.bottom-bounds.top,output+L"/real-button-hover.png"));
  CHECK(RightClick({(button.left+button.right)/2,(button.top+button.bottom)/2})); Pump(250);
  const bool menu=HasShellMenu(); const bool visible=Surface() && IsWindowVisible(Surface());
  auto menu_pixels=Capture(Surface(),bounds);
  Escape(); SetCursorPos(original.x,original.y); Pump(400);
  CHECK(menu && visible && actions==2); CHECK(Ink(menu_pixels)>30);
  CHECK(Save(menu_pixels,bounds.right-bounds.left,bounds.bottom-bounds.top,output+L"/real-button-context-menu.png"));
  CHECK(Button() && IsWindowVisible(Button()));
  CHECK(set(true,true,true)); Pump(30); auto outlined=Capture(Surface(),bounds);
  CHECK(outlined!=hovered); CHECK(Save(outlined,bounds.right-bounds.left,bounds.bottom-bounds.top,output+L"/real-vector-stroke-on.png"));
  CHECK(set(false,false,false,L"system")); surface.SetSystemLightForTesting(true); SendMessageW(Surface(),WM_THEMECHANGED,0,0);
  Pump(30); const auto black=surface.PixelsForTesting();
  CHECK(std::any_of(black.begin(),black.end(),[](auto p){return (p>>24)>200 && (p&0x00ffffff)==0;}));
  surface.SetSystemLightForTesting(false); SendMessageW(Surface(),WM_SYSCOLORCHANGE,0,0); Pump(30);
  const auto white=surface.PixelsForTesting(); CHECK(white!=black);
  CHECK(std::any_of(white.begin(),white.end(),[](auto p){return (p>>24)>200 && (p&0x00ffffff)!=0;}));
  CHECK(!Button());
  surface.FailNextGeometryForTesting(1); surface.EnvironmentChanged(); CHECK(WaitVisible()); Pump(300); CHECK(IsWindowVisible(Surface()));
  const auto requests=surface.GeometryRequestsForTesting();
  surface.FailNextGeometryForTesting(4); surface.EnvironmentChanged(); Pump(900);
  CHECK(!IsWindowVisible(Surface()) && surface.GetLayout().area_count==0);
  CHECK(surface.GeometryRequestsForTesting()==requests+4); Pump(300); CHECK(surface.GeometryRequestsForTesting()==requests+4);
  surface.EnvironmentChanged(); CHECK(WaitVisible()); Pump(300);
  CHECK(set(false,false,false,L"player",true)); Pump(30); CHECK(GetWindowRect(Surface(),&bounds));
  const auto raster_count=surface.RasterCountForTesting();
  surface.AddOccupiedAreaForTesting({bounds.left,bounds.top,bounds.left+80,bounds.bottom});
  CHECK(surface.LayoutAnimatingForTesting()); const auto first=surface.PixelsForTesting();
  RECT new_bounds{}; CHECK(GetWindowRect(Surface(),&new_bounds)); CHECK(new_bounds.left>bounds.left && new_bounds.right<=bounds.right);
  CHECK(!Button()); CHECK(SaveSurface(Surface(),output+L"/real-layout-000.png"));
  Pump(60); const auto middle=surface.PixelsForTesting(); CHECK(middle!=first && surface.LayoutAnimatingForTesting());
  CHECK(SaveSurface(Surface(),output+L"/real-layout-060.png"));
  CHECK(surface.RasterCountForTesting()==raster_count+1);
  surface.AddOccupiedAreaForTesting({new_bounds.left,new_bounds.top,new_bounds.left+40,new_bounds.bottom}); CHECK(surface.LayoutAnimatingForTesting());
  Pump(220); CHECK(!surface.LayoutAnimatingForTesting());
  CHECK(SaveSurface(Surface(),output+L"/real-layout-220.png"));
  CHECK(set(false,false,false,L"player",false)); CHECK(GetWindowRect(Surface(),&bounds));
  surface.AddOccupiedAreaForTesting({bounds.left,bounds.top,bounds.left+20,bounds.bottom}); CHECK(!surface.LayoutAnimatingForTesting());
  surface.Close(); CHECK(!Surface() && !Button());
  CHECK(GetGuiResources(GetCurrentProcess(),GR_GDIOBJECTS)<=resources+2);
  std::cout << "focused interaction: " << checks << " checks PASS\n";
  return 0;
}
int LayoutFocused(const std::wstring& font,const std::wstring& output) {
  using namespace taskbar_lyrics;
  std::vector<std::uint32_t> old(12,0),target(8,0),composed(8,0);
  old[2]=0xff0080ff; target[0]=0xff0080ff;
  CrossfadeLayout(composed.data(),8,1,old,12,1,0,0,.5,2,0,target.data());
  CHECK(composed[1]==0xff0080ff && composed[0]==0 && composed[2]==0);
  CrossfadeLayout(composed.data(),8,1,old,12,1,0,0,1,2,0,target.data()); CHECK(composed==target);
  old[2]=0xff000000; composed.assign(8,0);
  CrossfadeLayout(composed.data(),8,1,old,12,1,0,0,.5,1,0,target.data());
  CHECK((composed[1]>>24)>0 && (composed[2]>>24)>0); // fractional sampling distributes alpha, not pixel jumps
  TaskbarLyrics surface;
  const auto set=[&](bool layout,bool playing,std::wstring text,std::wstring next,std::wstring line) {
    return surface.Set(true,std::move(text),0xff008ebd,L"DanPingFangSC",font,true,playing,{},std::move(next),0,1,L"layout-source",std::move(line),1,0,10000,
        L"center",L"",false,false,0,!playing,L"player",false,false,layout);
  };
  CHECK(set(true,false,L"当前句 · Current",L"下一句 · Following",L"line")); CHECK(WaitVisible()); Pump(300);
  RECT original{}; CHECK(GetWindowRect(Surface(),&original));
  const auto raster=surface.RasterCountForTesting();
  surface.AddOccupiedAreaForTesting({original.left,original.top,original.left+40,original.bottom});
  RECT safe{}; CHECK(GetWindowRect(Surface(),&safe));
  CHECK(safe.left>original.left && safe.right<=original.right && safe.top==original.top && safe.bottom==original.bottom);
  CHECK(surface.LayoutAnimatingForTesting()); CHECK(surface.LayoutBufferPixelsForTesting()>0);
  CHECK(SaveSurface(Surface(),output+L"/real-layout-final-000.png"));
  const auto first=surface.PixelsForTesting(); Pump(50); const auto middle=surface.PixelsForTesting();
  CHECK(first!=middle && surface.LayoutAnimatingForTesting()); CHECK(surface.RasterCountForTesting()==raster+1);
  CHECK(SaveSurface(Surface(),output+L"/real-layout-final-050.png"));
  surface.AddOccupiedAreaForTesting({safe.left,safe.top,safe.left+20,safe.bottom});
  CHECK(surface.LayoutAnimatingForTesting()); Pump(220);
  CHECK(!surface.LayoutAnimatingForTesting() && surface.LayoutBufferPixelsForTesting()==0);
  CHECK(surface.RasterCountForTesting()==raster+2);
  CHECK(SaveSurface(Surface(),output+L"/real-layout-final-220.png"));
  CHECK(set(true,true,L"当前句 · Current",L"下一句 · Following",L"line")); Pump(30);
  CHECK(set(true,true,L"下一句 · Following",L"再下一句 · Third",L"line-next"));
  const auto line_start=surface.LineAnimationStartForTesting(); CHECK(line_start!=0); Pump(40);
  CHECK(GetWindowRect(Surface(),&safe)); const auto count=surface.RasterCountForTesting();
  surface.AddOccupiedAreaForTesting({safe.left,safe.top,safe.left+10,safe.bottom});
  CHECK(surface.LayoutAnimatingForTesting() && surface.LineAnimationStartForTesting()==line_start);
  Pump(40); CHECK(surface.RasterCountForTesting()==count+1 && surface.LineAnimationStartForTesting()==line_start);
  CHECK(set(false,false,L"下一句 · Following",L"再下一句 · Third",L"line-next"));
  CHECK(!surface.LayoutAnimatingForTesting() && surface.LayoutBufferPixelsForTesting()==0);
  surface.Close(); CHECK(!Surface() && !Button() && surface.LayoutBufferPixelsForTesting()==0);
  std::cout << "layout focused: " << checks << " checks PASS\n";
  return 0;
}
int SingleFocused(const std::wstring& font,const std::wstring& output) {
  using namespace taskbar_lyrics;
  TaskbarLyrics surface;
  const auto set=[&](bool next,bool layout,bool animate,bool playing,std::wstring text=L"当前句 · Current",std::wstring preview=L"下一句 · Following",std::wstring line=L"current") {
    return surface.Set(true,std::move(text),0xff008ebd,L"DanPingFangSC",font,animate,playing,{},std::move(preview),0,1,L"single-source",std::move(line),1,0,10000,
        L"center",L"Next: Sample track",true,false,0,!playing,L"player",true,true,layout,next);
  };
  const auto outside_equal=[](const std::vector<std::uint32_t>& first,const std::vector<std::uint32_t>& second,int width,RECT clip) {
    if (first.size()!=second.size()) return false;
    for (size_t index=0;index<first.size();++index) {
      const int x=static_cast<int>(index%width),y=static_cast<int>(index/width);
      if ((x<clip.left || x>=clip.right || y<clip.top || y>=clip.bottom) && first[index]!=second[index]) return false;
    }
    return true;
  };
  const auto ink_in=[](const std::vector<std::uint32_t>& pixels,int width,RECT clip) {
    int ink=0;
    for (int y=clip.top;y<clip.bottom;++y) for (int x=clip.left;x<clip.right;++x) {
      const auto value=pixels[static_cast<size_t>(y)*width+x];
      if ((value>>24)>10 && static_cast<int>(value&255)>static_cast<int>((value>>16)&255)+15) ++ink;
    }
    return ink;
  };
  CHECK(set(true,false,false,false)); CHECK(WaitVisible()); Pump(300);
  RECT bounds{},button{}; CHECK(GetWindowRect(Surface(),&bounds) && GetWindowRect(Button(),&button));
  const int width=bounds.right-bounds.left,height=bounds.bottom-bounds.top;
  const auto content=LayoutContent(width,height,GetDpiForWindow(Surface()),false,true,true,true);
  const auto original=surface.PixelsForTesting();
  CHECK(ink_in(original,width,{content.lyrics.left,height*3/4,content.lyrics.right,height})>10);
  const auto count=surface.RasterCountForTesting();
  CHECK(set(false,true,false,false)); CHECK(surface.LayoutAnimatingForTesting());
  CHECK(outside_equal(original,surface.PixelsForTesting(),width,content.lyrics));
  CHECK(SaveSurface(Surface(),output+L"/real-single-toggle-000.png"));
  Pump(55); const auto middle=surface.PixelsForTesting();
  CHECK(surface.LayoutAnimatingForTesting() && middle!=original);
  CHECK(outside_equal(original,middle,width,content.lyrics)); CHECK(surface.RasterCountForTesting()==count+1);
  CHECK(SaveSurface(Surface(),output+L"/real-single-toggle-055.png"));
  Pump(150); const auto single=surface.PixelsForTesting();
  CHECK(!surface.LayoutAnimatingForTesting() && surface.LayoutBufferPixelsForTesting()==0);
  CHECK(ink_in(single,width,{content.lyrics.left,height*3/4,content.lyrics.right,height})==0);
  CHECK(ink_in(single,width,{content.lyrics.left,height/3,content.lyrics.right,height*2/3})>30);
  CHECK(outside_equal(original,single,width,content.lyrics));
  RECT after{}; CHECK(GetWindowRect(Button(),&after) && EqualRect(&button,&after));
  CHECK(SaveSurface(Surface(),output+L"/real-single-toggle-220.png"));
  CHECK(set(true,true,false,false)); CHECK(surface.LayoutAnimatingForTesting()); Pump(210);
  CHECK(ink_in(surface.PixelsForTesting(),width,{content.lyrics.left,height*3/4,content.lyrics.right,height})>10);
  CHECK(surface.LayoutBufferPixelsForTesting()==0);
  CHECK(set(false,false,false,false)); CHECK(!surface.LayoutAnimatingForTesting() && surface.LayoutBufferPixelsForTesting()==0);
  CHECK(set(false,false,true,true));
  CHECK(set(false,false,true,true,L"下一句 · Following",L"再下一句 · Third",L"following"));
  CHECK(surface.LineAnimatingForTesting()); const auto entry=surface.PixelsForTesting();
  CHECK(SaveSurface(Surface(),output+L"/real-single-line-000.png")); Pump(70);
  CHECK(surface.LineAnimatingForTesting() && surface.PixelsForTesting()!=entry);
  CHECK(SaveSurface(Surface(),output+L"/real-single-line-070.png")); Pump(150);
  CHECK(!surface.LineAnimatingForTesting()); CHECK(SaveSurface(Surface(),output+L"/real-single-line-220.png"));
  CHECK(set(false,false,false,true,L"直接终态 · No motion",L"下一句",L"off")); CHECK(!surface.LineAnimatingForTesting());
  const std::vector<std::wstring> languages{L"中文单行歌词",L"Single line lyric",L"一行の歌詞表示",L"한 줄 가사 표시"};
  for (size_t index=0;index<languages.size();++index) {
    CHECK(set(false,false,false,false,languages[index],L"预览隐藏",L"lang-"+std::to_wstring(index)));
    CHECK(ink_in(surface.PixelsForTesting(),width,{content.lyrics.left,height/3,content.lyrics.right,height*2/3})>30);
    CHECK(SaveSurface(Surface(),output+L"/real-single-language-"+std::to_wstring(index)+L".png"));
  }
  surface.Close(); CHECK(!Surface() && !Button() && surface.LayoutBufferPixelsForTesting()==0);
  std::cout << "single focused: " << checks << " checks PASS\n";
  return 0;
}
}

// QA owns only its own click-through surface. The explicit real-menu mode opens
// one taskbar context menu in the verified gap, closes it with Escape, and
// restores the pointer. It never invokes a menu action or changes system state.
int wmain(int argc, wchar_t** argv) {
  if (argc==4 && (std::wstring(argv[1])==L"--focused" || std::wstring(argv[1])==L"--layout-only" || std::wstring(argv[1])==L"--single-only")) {
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    ULONG_PTR token=0; Gdiplus::GdiplusStartupInput startup;
    if (Gdiplus::GdiplusStartup(&token,&startup,nullptr)!=Gdiplus::Ok) return 1;
    const int result=std::wstring(argv[1])==L"--focused" ? Focused(argv[2],argv[3]) : std::wstring(argv[1])==L"--single-only" ?
        SingleFocused(argv[2],argv[3]) : LayoutFocused(argv[2],argv[3]);
    Gdiplus::GdiplusShutdown(token); return result;
  }
  CHECK(argc == 3 && std::wstring(argv[1]) == L"--real-menu");
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  TaskbarLyrics surface;
  CHECK(surface.Set(true,L"任务栏菜单恢复 · Menu recovery",0xff008ebd,L"DanPingFangSC",argv[2],false,false,{},
      L"下一句 · Following",0,1,L"menu-source",L"menu-line",1,0,10000));
  CHECK(WaitVisible()); Pump(350);
  CHECK(IsWindowVisible(Surface()));
  RECT area{}; CHECK(GetWindowRect(Surface(),&area));
  POINT original{}; CHECK(GetCursorPos(&original));
  CHECK(RightClick({(area.left+area.right)/2,(area.top+area.bottom)/2}));
  Pump(250);
  std::cout << "while-menu visible=" << IsWindowVisible(Surface()) << " count=" << surface.GetLayout().area_count << '\n';
  const bool menu_visible_surface = IsWindowVisible(Surface()) != FALSE;
  Escape(); SetCursorPos(original.x,original.y); Pump(1200);
  CHECK(menu_visible_surface);
  CHECK(Surface() && IsWindowVisible(Surface()));
  CHECK(surface.GetLayout().area_count > 0);
  surface.Close(); CHECK(!Surface());
  std::cout << "real menu: " << checks << " checks PASS\n";
  return 0;
}
