#include "../taskbar_lyrics.h"
#include "../taskbar_lyrics_button.h"
#include "taskbar_lyrics_test_windows.h"
#include <dwmapi.h>
#include <gdiplus.h>
#include <future>
#include <iostream>
#include <optional>
#include <thread>
#include <wrl/client.h>

namespace {
int checks=0;
#define CHECK(value) do { ++checks; if (!(value)) { std::cerr<<"Failed line "<<__LINE__<<": " #value "\n"; return 1; } } while(false)
void Pump(DWORD milliseconds) {
  const auto end=GetTickCount64()+milliseconds;
  do { MSG message; while(PeekMessageW(&message,nullptr,0,0,PM_REMOVE)) { TranslateMessage(&message); DispatchMessageW(&message); }
    MsgWaitForMultipleObjects(0,nullptr,FALSE,3,QS_ALLINPUT);
  } while(GetTickCount64()<end);
}
HWND Surface() { return FindOwnedTaskbarWindow(L"DanPlayer.TaskbarLyrics.v1"); }
bool Visible() { return Surface() && IsWindowVisible(Surface()); }
bool WaitVisible() { const auto end=GetTickCount64()+5000; do { Pump(10); if(Visible()) return true; } while(GetTickCount64()<end); return false; }
bool Click(POINT point) {
  INPUT input[2]{}; input[0].type=input[1].type=INPUT_MOUSE;
  input[0].mi.dwFlags=MOUSEEVENTF_LEFTDOWN; input[1].mi.dwFlags=MOUSEEVENTF_LEFTUP;
  return SetCursorPos(point.x,point.y) && SendInput(2,input,sizeof(INPUT))==2;
}
bool RightClick(POINT point) {
  INPUT input[2]{}; input[0].type=input[1].type=INPUT_MOUSE;
  input[0].mi.dwFlags=MOUSEEVENTF_RIGHTDOWN; input[1].mi.dwFlags=MOUSEEVENTF_RIGHTUP;
  if(!SetCursorPos(point.x,point.y) || SendInput(1,input,sizeof(INPUT))!=1)return false;
  Pump(30); return SendInput(1,input+1,sizeof(INPUT))==1;
}
void Escape() { INPUT input[2]{}; input[0].type=input[1].type=INPUT_KEYBOARD;
  input[0].ki.wVk=input[1].ki.wVk=VK_ESCAPE; input[1].ki.dwFlags=KEYEVENTF_KEYUP; SendInput(2,input,sizeof(INPUT)); }
std::wstring ForegroundClass() { wchar_t name[128]{}; GetClassNameW(GetForegroundWindow(),name,128); return name; }
std::vector<std::uint32_t> Capture(RECT bounds) {
  DwmFlush(); GdiFlush(); const int width=bounds.right-bounds.left,height=bounds.bottom-bounds.top;
  BITMAPINFO info{}; info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER); info.bmiHeader.biWidth=width; info.bmiHeader.biHeight=-height;
  info.bmiHeader.biPlanes=1; info.bmiHeader.biBitCount=32;
  void* data=nullptr; const auto bitmap=CreateDIBSection(nullptr,&info,DIB_RGB_COLORS,&data,nullptr,0);
  const auto screen=GetDC(nullptr),memory=CreateCompatibleDC(screen); std::vector<std::uint32_t> result;
  if(bitmap && screen && memory && data) { const auto old=SelectObject(memory,bitmap);
    if(BitBlt(memory,0,0,width,height,screen,bounds.left,bounds.top,SRCCOPY|CAPTUREBLT)) { GdiFlush();
      const auto pixels=static_cast<std::uint32_t*>(data); result.assign(pixels,pixels+static_cast<size_t>(width)*height); for(auto& pixel:result) pixel|=0xff000000; }
    SelectObject(memory,old); }
  if(bitmap) DeleteObject(bitmap); if(memory) DeleteDC(memory); if(screen) ReleaseDC(nullptr,screen); return result;
}
int Ink(const std::vector<std::uint32_t>& pixels) { return static_cast<int>(std::count_if(pixels.begin(),pixels.end(),[](auto pixel) {
  return static_cast<int>(pixel&255)>static_cast<int>((pixel>>16)&255)+15 && static_cast<int>((pixel>>8)&255)>static_cast<int>((pixel>>16)&255)+10;
})); }
bool SampleInk(DWORD duration,RECT bounds,const wchar_t* phase) {
  unsigned samples=0,hidden=0; int minimum=INT_MAX;
  const auto end=GetTickCount64()+duration;
  do { Pump(16); minimum=std::min(minimum,Ink(Capture(bounds))); ++samples; if(!Visible())++hidden; }
  while(GetTickCount64()<end);
  std::wcout<<phase<<L" samples="<<samples<<L" minimumScreenInk="<<minimum<<L" hidden="<<hidden<<L"\n";
  return samples>4 && hidden==0 && minimum>30;
}
bool HasShellMenu() {
  for(const auto* name:{L"Xaml_WindowedPopupClass",L"#32768"}) if(IsWindowVisible(FindWindowW(name,nullptr)))return true;
  bool found=false;
  EnumWindows([](HWND window,LPARAM state)->BOOL {
    wchar_t name[128]{}; GetClassNameW(window,name,128);
    if(IsWindowVisible(window) && (wcscmp(name,L"Xaml_WindowedPopupClass")==0 || wcscmp(name,L"#32768")==0)) *reinterpret_cast<bool*>(state)=true;
    return TRUE;
  },reinterpret_cast<LPARAM>(&found)); return found;
}
bool Save(std::vector<std::uint32_t> pixels,RECT bounds,const std::wstring& path) {
  if(pixels.empty()) return false;
  const int width=bounds.right-bounds.left,height=bounds.bottom-bounds.top;
  Gdiplus::Bitmap image(width,height,width*4,PixelFormat32bppARGB,reinterpret_cast<BYTE*>(pixels.data()));
  const CLSID png{0x557cf406,0x1a04,0x11d3,{0x9a,0x73,0x00,0x00,0xf8,0x1e,0xf3,0x2e}};
  return image.Save(path.c_str(),&png,nullptr)==Gdiplus::Ok;
}
std::optional<RECT> KnownShellControl(const wchar_t* id) {
  auto promise=std::make_shared<std::promise<std::optional<RECT>>>(); auto future=promise->get_future(); const std::wstring identifier=id;
  std::thread worker([promise,identifier] {
    std::optional<RECT> value; const auto init=CoInitializeEx(nullptr,COINIT_MULTITHREADED);
    if(SUCCEEDED(init)) {
      using Microsoft::WRL::ComPtr; ComPtr<IUIAutomation> automation; ComPtr<IUIAutomationElement> root,element; ComPtr<IUIAutomationCondition> condition;
      if(SUCCEEDED(CoCreateInstance(CLSID_CUIAutomation8,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&automation)))) {
        ComPtr<IUIAutomation6> bounded; if(SUCCEEDED(automation.As(&bounded))) { bounded->put_ConnectionTimeout(500); bounded->put_TransactionTimeout(500); }
        VARIANT match; VariantInit(&match); match.vt=VT_BSTR; match.bstrVal=SysAllocString(identifier.c_str()); RECT bounds{};
        if(SUCCEEDED(automation->ElementFromHandle(FindWindowW(L"Shell_TrayWnd",nullptr),&root)) &&
            SUCCEEDED(automation->CreatePropertyCondition(UIA_AutomationIdPropertyId,match,&condition)) &&
            SUCCEEDED(root->FindFirst(TreeScope_Descendants,condition.Get(),&element)) && element && SUCCEEDED(element->get_CurrentBoundingRectangle(&bounds))) value=bounds;
        VariantClear(&match);
      }
      element.Reset(); root.Reset(); condition.Reset(); automation.Reset(); CoUninitialize();
    }
    promise->set_value(value);
  });
  const auto end=GetTickCount64()+5000; while(future.wait_for(std::chrono::milliseconds(0))!=std::future_status::ready && GetTickCount64()<end) Pump(5);
  if(future.wait_for(std::chrono::milliseconds(0))!=std::future_status::ready) { worker.detach(); return {}; }
  worker.join(); return future.get();
}
struct CursorGuard { POINT point{}; CursorGuard(){GetCursorPos(&point);} ~CursorGuard(){SetCursorPos(point.x,point.y);} };
struct FocusGuard {
  HWND previous=GetForegroundWindow(),window=nullptr;
  FocusGuard() {
    WNDCLASSW cls{}; cls.lpszClassName=L"DanPlayer.TaskbarLyrics.QA.Focus"; cls.hInstance=GetModuleHandleW(nullptr); cls.lpfnWndProc=DefWindowProcW; RegisterClassW(&cls);
    window=CreateWindowExW(0,cls.lpszClassName,L"Taskbar lyric QA",WS_OVERLAPPEDWINDOW,100,100,240,120,nullptr,nullptr,cls.hInstance,nullptr);
    ShowWindow(window,SW_SHOWNORMAL);
    // Expose our own fixture even if foreground activation is temporarily
    // denied. A real click then establishes the baseline without changing
    // another application's activation policy.
    SetWindowPos(window,HWND_TOPMOST,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE);
    Pump(80);
  }
  ~FocusGuard(){if(window) DestroyWindow(window); if(previous && IsWindow(previous)) SetForegroundWindow(previous);}
};
struct AccessibleResult {bool success=false,enabled=false; std::wstring name; HRESULT invoke=E_FAIL;};
AccessibleResult Accessible(HWND window) {
  auto promise=std::make_shared<std::promise<AccessibleResult>>(); auto future=promise->get_future();
  std::thread worker([window,promise]{
    AccessibleResult value; const auto init=CoInitializeEx(nullptr,COINIT_MULTITHREADED);
    if(SUCCEEDED(init)) {
      using Microsoft::WRL::ComPtr; ComPtr<IUIAutomation> automation; ComPtr<IUIAutomationElement> element; ComPtr<IUIAutomationInvokePattern> invoke;
      if(SUCCEEDED(CoCreateInstance(CLSID_CUIAutomation8,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&automation)))) {
        // The UIA client defaults to focusing before Invoke. Disable that
        // separate client action to test this non-activating provider itself.
        ComPtr<IUIAutomation2> options; if(SUCCEEDED(automation.As(&options))) options->put_AutoSetFocus(FALSE);
        ComPtr<IUIAutomation6> bounded; if(SUCCEEDED(automation.As(&bounded))){bounded->put_ConnectionTimeout(500);bounded->put_TransactionTimeout(500);}
        BSTR name=nullptr; BOOL enabled=FALSE;
        if(SUCCEEDED(automation->ElementFromHandle(window,&element)) && SUCCEEDED(element->get_CurrentName(&name)) &&
            SUCCEEDED(element->get_CurrentIsEnabled(&enabled)) && SUCCEEDED(element->GetCurrentPatternAs(UIA_InvokePatternId,IID_PPV_ARGS(&invoke)))) {
          value.success=true; value.enabled=enabled!=FALSE; if(name) value.name=name; value.invoke=invoke->Invoke();
        }
        if(name) SysFreeString(name);
      }
      invoke.Reset(); element.Reset(); automation.Reset(); CoUninitialize();
    }
    promise->set_value(value);
  });
  const auto end=GetTickCount64()+5000; while(future.wait_for(std::chrono::milliseconds(0))!=std::future_status::ready && GetTickCount64()<end) Pump(5);
  if(future.wait_for(std::chrono::milliseconds(0))!=std::future_status::ready){worker.detach();return {};}
  worker.join(); return future.get();
}
int Buttons(const std::wstring& font,const std::wstring& output) {
  using namespace taskbar_lyrics;
  CursorGuard cursor; FocusGuard focus; TaskbarLyrics surface; int toggles=0,next=0;
  RECT focus_bounds{}; CHECK(GetWindowRect(focus.window,&focus_bounds));
  CHECK(Click({focus_bounds.left+60,focus_bounds.top+50})); Pump(120); CHECK(GetForegroundWindow()==focus.window);
  CHECK(SetWindowPos(focus.window,HWND_NOTOPMOST,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE));
  surface.SetPlaybackCallback([&]{++toggles;}); surface.SetNextTrackCallback([&]{++next;});
  surface.SetPlaybackButtonLabels(L"播放 · Play",L"暂停 · Pause"); surface.SetNextButtonLabel(L"下一首 · Next");
  const auto set=[&](bool playing,bool enabled){return surface.Set(true,L"Capsule · 播放按钮",0xff008ebd,L"DanPingFangSC",font,true,playing,{},L"第二句 · Second line",1000,1,L"buttons",L"line",1,0,10000,
      L"center",L"Next: sample",true,false,0,!playing,L"player",true,enabled,false,true,enabled);};
  CHECK(set(false,false)); CHECK(WaitVisible()); Pump(250);
  const HWND play=FindOwnedTaskbarWindow(L"DanPlayer.TaskbarLyrics.PlayPause.v1"),skip=FindOwnedTaskbarWindow(L"DanPlayer.TaskbarLyrics.Next.v1");
  CHECK(play && skip && IsWindowVisible(play) && IsWindowVisible(skip));
  CHECK(GetParent(play)==GetParent(Surface()) && GetParent(skip)==GetParent(Surface()));
  CHECK(!(GetWindowLongPtrW(play,GWL_EXSTYLE)&WS_EX_TRANSPARENT));
  RECT play_bounds{},skip_bounds{},bounds{}; CHECK(GetWindowRect(play,&play_bounds) && GetWindowRect(skip,&skip_bounds) && GetWindowRect(Surface(),&bounds));
  CHECK(play_bounds.right<=bounds.left+44 && skip_bounds.left>=bounds.right-44);
  const auto foreground=GetForegroundWindow();
  wchar_t old_class[128]{}; GetClassNameW(foreground,old_class,128);
  std::wcout<<L"initial foreground="<<old_class<<L" handle="<<foreground<<L" QA="<<focus.window<<L"\n";
  CHECK(Click({(play_bounds.left+play_bounds.right)/2,(play_bounds.top+play_bounds.bottom)/2})); Pump(80); CHECK(toggles==0);
  CHECK(GetForegroundWindow()==foreground);
  std::wcout<<L"after disabled click foreground="<<ForegroundClass()<<L" handle="<<GetForegroundWindow()<<L" same="<<(GetForegroundWindow()==foreground)<<L"\n";
  auto accessible=Accessible(play); Pump(30); CHECK(accessible.success && !accessible.enabled && accessible.name==L"播放 · Play" && FAILED(accessible.invoke));
  CHECK(GetForegroundWindow()==foreground);
  surface.SetPlaybackButtonLabels(L"Play · 再生",L"Pause · 一時停止");
  accessible=Accessible(play); CHECK(accessible.success && accessible.name==L"Play · 再生" && FAILED(accessible.invoke));
  surface.SetPlaybackButtonLabels(L"播放 · Play",L"暂停 · Pause");
  CHECK(set(false,true)); Pump(50);
  accessible=Accessible(play); Pump(30); CHECK(accessible.success && accessible.enabled && SUCCEEDED(accessible.invoke) && toggles==1);
  CHECK(GetForegroundWindow()==foreground);
  std::wcout<<L"after UIA foreground="<<ForegroundClass()<<L"\n";
  CHECK(Click({(play_bounds.left+play_bounds.right)/2,(play_bounds.top+play_bounds.bottom)/2})); Pump(60); CHECK(toggles==2);
  CHECK(GetForegroundWindow()==foreground);
  std::wcout<<L"after live click foreground="<<ForegroundClass()<<L"\n";
  CHECK(Click({(skip_bounds.left+skip_bounds.right)/2,(skip_bounds.top+skip_bounds.bottom)/2})); Pump(60); CHECK(next==1);
  CHECK(GetForegroundWindow()==foreground);
  CHECK(Save(Capture(bounds),bounds,output+L"/capsules-paused.png"));
  CHECK(set(true,true)); Pump(200); accessible=Accessible(play); Pump(30);
  CHECK(accessible.success && accessible.name==L"暂停 · Pause" && toggles==3);
  CHECK(Save(Capture(bounds),bounds,output+L"/capsules-playing.png"));
  const auto resources=GetGuiResources(GetCurrentProcess(),GR_GDIOBJECTS);
  TaskbarMediaButton queued{L"DanPlayer.TaskbarLyrics.QA.Queued"}; int actions=0;
  queued.SetCallback([&]{++actions;}); queued.SetSymbol(MediaSymbol::kPlay);
  RECT target{100,140,144,184}; CHECK(queued.Show(focus.window,target,96,RGB(0,142,189),true,false,0,.9));
  Microsoft::WRL::ComPtr<IInvokeProvider> provider; provider.Attach(queued.InvokeProviderForTesting()); CHECK(provider);
  CHECK(SUCCEEDED(provider->Invoke())); CHECK(queued.Show(focus.window,target,96,RGB(0,142,189),false,false,0,.9));
  CHECK(queued.Show(focus.window,target,96,RGB(0,142,189),true,false,0,.9)); Pump(20); CHECK(actions==0);
  CHECK(SUCCEEDED(provider->Invoke())); queued.Hide(); CHECK(queued.Show(focus.window,target,96,RGB(0,142,189),true,false,0,.9)); Pump(20); CHECK(actions==0);
  CHECK(SUCCEEDED(provider->Invoke())); queued.SetSymbol(MediaSymbol::kPause); Pump(20); CHECK(actions==0);
  CHECK(SUCCEEDED(provider->Invoke())); Pump(20); CHECK(actions==1);
  queued.Close(); CHECK(FAILED(provider->Invoke())); provider.Reset();
  CHECK(GetGuiResources(GetCurrentProcess(),GR_GDIOBJECTS)<=resources+2);
  surface.Close(); CHECK(!Surface() && !FindOwnedTaskbarWindow(L"DanPlayer.TaskbarLyrics.Next.v1") && !FindOwnedTaskbarWindow(L"DanPlayer.TaskbarLyrics.PlayPause.v1"));
  std::cout<<"buttons: "<<checks<<" checks PASS\n"; return 0;
}
int Shell(const std::wstring& font,const std::wstring& output) {
  CursorGuard cursor;
  FocusGuard focus;
  const auto bar=FindWindowW(L"Shell_TrayWnd",nullptr); RECT bar_bounds{}; CHECK(GetWindowRect(bar,&bar_bounds));
  CHECK(SetCursorPos((bar_bounds.left+bar_bounds.right)/2,bar_bounds.top-100)); Pump(1200);
  TaskbarLyrics surface;
  const auto set=[&]{return surface.Set(true,L"Paused · 暂停测试 · 下一句",0xff008ebd,L"DanPingFangSC",font,true,false,{},L"Second line · 第二行",0,1,L"source",L"line",1,0,10000,
      L"center",L"",false,false,0,true);};
  const auto thread_context=GetThreadDpiAwarenessContext();
  CHECK(set()); CHECK(WaitVisible()); Pump(400);
  CHECK(AreDpiAwarenessContextsEqual(thread_context,GetThreadDpiAwarenessContext()));
  CHECK(GetParent(Surface())==bar && (GetWindowLongPtrW(Surface(),GWL_STYLE)&WS_CHILD));
  CHECK(GetWindowLongPtrW(Surface(),GWL_EXSTYLE)&WS_EX_TRANSPARENT);
  RECT bounds{}; CHECK(GetWindowRect(Surface(),&bounds));
  const auto band_function=reinterpret_cast<BOOL(WINAPI*)(HWND,DWORD*)>(GetProcAddress(GetModuleHandleW(L"user32.dll"),"GetWindowBand"));
  Pump(100); CHECK(Ink(Capture(bounds))>30);
  const auto raster=surface.RasterCountForTesting();
  for(const auto* id:{L"StartButton",L"TaskViewButton"}) {
    auto control=KnownShellControl(id); CHECK(control.has_value());
    std::wcout<<L"opening "<<id<<L"\n"; CHECK(Click({(control->left+control->right)/2,(control->top+control->bottom)/2}));
    CHECK(SampleInk(1100,bounds,id));
    CHECK(Save(Capture(bounds),bounds,output+L"/"+id+L"-open.png"));
    Escape(); CHECK(SampleInk(900,bounds,L"closing Shell UI"));
    DWORD band=0; if(band_function) band_function(bar,&band);
    std::wcout<<L"after escape foreground="<<ForegroundClass()<<L" barBand="<<band<<L" visible="<<Visible()<<L" ink="<<Ink(Capture(bounds))<<L"\n";
    CHECK(Save(Capture(bounds),bounds,output+L"/"+id+L"-closed.png"));
    CHECK(Visible() && Ink(Capture(bounds))>30);
    CHECK(surface.RasterCountForTesting()==raster);
  }
  const POINT lyric{bounds.left+60,(bounds.top+bounds.bottom)/2};
  CHECK(WindowFromPoint(lyric)!=Surface()); CHECK(Click(lyric)); Pump(160);
  CHECK(Visible() && Ink(Capture(bounds))>30);
  wchar_t hit_class[128]{}; GetClassNameW(WindowFromPoint(lyric),hit_class,128);
  std::wcout<<L"lyric gap hit="<<hit_class<<L" rect="<<bounds.left<<L','<<bounds.top<<L','<<bounds.right<<L','<<bounds.bottom<<L"\n";
  CHECK(RightClick(lyric)); Pump(450); std::wcout<<L"right-menu foreground="<<ForegroundClass()<<L" menu="<<HasShellMenu()<<L"\n";
  const RECT menu_bounds{lyric.x-100,lyric.y-260,lyric.x+270,lyric.y+24};
  CHECK(Save(Capture(menu_bounds),menu_bounds,output+L"/empty-area-right-menu.png")); CHECK(HasShellMenu());
  CHECK(Visible() && Ink(Capture(bounds))>30); Escape(); CHECK(SampleInk(350,bounds,L"closing empty-area context menu"));
  surface.Close(); CHECK(!Surface());
  CHECK(set()); Pump(400); // while the pointer/Shell remains in its elevated band
  if(!Surface()) {
    const auto requests=surface.GeometryRequestsForTesting(); Pump(300); CHECK(surface.GeometryRequestsForTesting()==requests);
    CHECK(Click({160,150})); CHECK(WaitVisible()); Pump(180);
    CHECK(Visible()); CHECK(GetWindowRect(Surface(),&bounds)); CHECK(Ink(Capture(bounds))>30);
    CHECK(Save(Capture(bounds),bounds,output+L"/cold-shell-recovered.png"));
  }
  surface.Close(); CHECK(!Surface());
  std::cout<<"shell: "<<checks<<" checks PASS\n"; return 0;
}
struct FakeBar {
  HWND window=nullptr;
  FakeBar(){Create();}
  void Create(){
    WNDCLASSW cls{};cls.lpszClassName=L"DanPlayer.TaskbarLyrics.QA.Bar";cls.hInstance=GetModuleHandleW(nullptr);
    cls.lpfnWndProc=DefWindowProcW;cls.hbrBackground=static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));RegisterClassW(&cls);
    window=CreateWindowExW(WS_EX_TOPMOST|WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE,cls.lpszClassName,L"",WS_POPUP,
        80,700,960,48,nullptr,nullptr,cls.hInstance,nullptr); ShowWindow(window,SW_SHOWNOACTIVATE);UpdateWindow(window);
  }
  ~FakeBar(){if(IsWindow(window))DestroyWindow(window);}
  std::vector<RECT> Occupied()const {RECT bounds{};GetWindowRect(window,&bounds);return {{bounds.left,bounds.top,bounds.left+20,bounds.bottom}};}
};
std::vector<std::uint32_t> Crop(const std::vector<std::uint32_t>& pixels,int width,RECT bounds) {
  std::vector<std::uint32_t> result;
  for(int y=bounds.top;y<bounds.bottom;++y) for(int x=bounds.left;x<bounds.right;++x) result.push_back(pixels[static_cast<size_t>(y)*width+x]);
  return result;
}
int Reading(const std::wstring& font,const std::wstring& output) {
  using namespace taskbar_lyrics;
  CursorGuard cursor; FocusGuard focus; FakeBar bar; TaskbarLyrics surface;
  const std::wstring lyric(180,L'가'),title(150,L'歌');
  const std::vector<TaskbarLyricWord> words{{0,5000,lyric.substr(0,90)},{5000,5000,lyric.substr(90)}};
  const auto set=[&](const std::wstring& text,std::vector<TaskbarLyricWord> timed,std::wstring metadata,bool playing,double position,double end,std::int64_t revision){
    return surface.Set(true,text,0xff008ebd,L"DanPingFangSC",font,true,playing,std::move(timed),L"",position,1,L"read",text,revision,0,end,
        L"start",std::move(metadata),false,false,0,!playing,L"player",false,false,false,false);};
  CHECK(set(lyric,words,L"Next: short",true,8000,10000,1)); surface.UseBarForTesting(bar.window,bar.Occupied());
  CHECK(Visible()); surface.SetPositionForTesting(8000); Pump(210);
  RECT bounds{}; CHECK(GetWindowRect(Surface(),&bounds)); const int width=bounds.right-bounds.left,height=bounds.bottom-bounds.top;
  const auto content=LayoutContent(width,height,GetDpiForWindow(Surface()),false,false,true,false);
  const auto authoritative=surface.ReadOffsetForTesting(); CHECK(authoritative>0);
  const auto word_pixels=Crop(surface.PixelsForTesting(),width,content.lyrics);
  CHECK(set(lyric,words,title,true,8000,10000,1)); Pump(1950);
  std::cout<<"word viewport before="<<authoritative<<" after="<<surface.ReadOffsetForTesting()<<" pixelEqual="<<(Crop(surface.PixelsForTesting(),width,content.lyrics)==word_pixels)<<'\n';
  CHECK(surface.ReadOffsetForTesting()==authoritative && Crop(surface.PixelsForTesting(),width,content.lyrics)==word_pixels);
  CHECK(surface.MetadataOffsetForTesting()>0);
  CHECK(Save(Capture(bounds),bounds,output+L"/word-reading-metadata.png"));
  CHECK(set(lyric,{},title,true,0,10000,2));
  surface.SetPositionForTesting(0); CHECK(surface.ReadOffsetForTesting()==0);
  surface.SetPositionForTesting(300); CHECK(surface.ReadOffsetForTesting()==0);
  surface.SetPositionForTesting(5000); const auto midpoint=surface.ReadOffsetForTesting(); CHECK(midpoint>0);
  surface.SetPositionForTesting(9700); const auto tail=surface.ReadOffsetForTesting(); CHECK(tail>midpoint);
  surface.SetPositionForTesting(10000); CHECK(surface.ReadOffsetForTesting()==tail);
  CHECK(set(lyric,{},title,false,10000,10000,3)); CHECK(surface.ReadOffsetForTesting()==tail);
  const auto paused_pixels=surface.PixelsForTesting(); const auto paused_frames=surface.MotionFramesForTesting(); Pump(120);
  CHECK(surface.PixelsForTesting()==paused_pixels && surface.MotionFramesForTesting()==paused_frames);
  CHECK(set(lyric,{},title,true,5000,0,4)); surface.SetPositionForTesting(5000); Pump(1950);
  const auto fallback=surface.ReadOffsetForTesting(),metadata=surface.MetadataOffsetForTesting(); CHECK(fallback>0 && metadata>0);
  const auto fallback_pixels=surface.PixelsForTesting();
  CHECK(set(lyric,{},title,false,5000,0,5)); CHECK(surface.ReadOffsetForTesting()==fallback);
  CHECK(surface.MetadataOffsetForTesting()==metadata && surface.PixelsForTesting()==fallback_pixels);
  const auto stopped_frames=surface.MotionFramesForTesting(); Pump(120); CHECK(surface.MotionFramesForTesting()==stopped_frames);
  CHECK(set(lyric,{},title,true,5000,0,6)); CHECK(std::abs(surface.ReadOffsetForTesting()-fallback)<=1);
  CHECK(std::abs(surface.MetadataOffsetForTesting()-metadata)<=1);
  CHECK(set(lyric,{},title,false,5000,0,7));
  CHECK(set(lyric,{},title,false,5000,0,8)); CHECK(surface.ReadOffsetForTesting()==0); // explicit same-position seek revision
  const std::wstring chunked(5000,L'가');
  CHECK(set(chunked,{},L"",false,0,10000,9)); surface.SetPositionForTesting(0); CHECK(surface.CurrentChunkForTesting()==0);
  const auto position_at=[](double cp){return 300+9400*cp/5000;};
  for(int cp:{2048,4096}) {
    surface.SetPositionForTesting(position_at(cp-.01)); CHECK(surface.CurrentChunkForTesting()==cp/2048-1);
    CHECK(surface.ReadOffsetForTesting()>0);
    surface.SetPositionForTesting(position_at(cp+.01)); CHECK(surface.CurrentChunkForTesting()==cp/2048);
    CHECK(surface.ReadOffsetForTesting()<=1);
  }
  CHECK(Save(Capture(bounds),bounds,output+L"/chunk-reading-head.png"));
  surface.Close(); CHECK(!Surface()); std::cout<<"reading: "<<checks<<" checks PASS\n"; return 0;
}
int HiddenReading(const std::wstring& font) {
  CursorGuard cursor; FocusGuard focus; FakeBar bar; TaskbarLyrics surface;
  const std::wstring lyric(120,L'가'),title(200,L'한');
  const auto set=[&](bool playing,std::int64_t revision) {
    return surface.Set(true,lyric,0xff008ebd,L"DanPingFangSC",font,true,playing,{},L"",0,1,L"hidden-reading",L"line",revision,0,0,
        L"center",title,false,false,0,!playing);
  };
  CHECK(set(true,1)); surface.UseBarForTesting(bar.window,bar.Occupied()); CHECK(Visible());
  surface.SetPositionForTesting(0); Pump(2600);
  const int offset=surface.ReadOffsetForTesting(),metadata=surface.MetadataOffsetForTesting();
  std::cout<<"hidden reading before="<<offset<<" metadata="<<metadata<<'\n';
  CHECK(offset>=10 && metadata>=10);
  const auto raster=surface.RasterCountForTesting();
  ShowWindow(bar.window,SW_HIDE); surface.EnvironmentChanged(); CHECK(!Visible());
  const auto frames=surface.MotionFramesForTesting(); Pump(320); CHECK(surface.MotionFramesForTesting()==frames);
  ShowWindow(bar.window,SW_SHOWNOACTIVATE); surface.EnvironmentChanged();
  const auto resumed_frames=surface.MotionFramesForTesting(); Pump(160); CHECK(Visible());
  CHECK(surface.MotionFramesForTesting()>resumed_frames);
  std::cout<<"hidden reading restored="<<surface.ReadOffsetForTesting()<<" metadata="<<surface.MetadataOffsetForTesting()<<'\n';
  CHECK(std::abs(surface.ReadOffsetForTesting()-offset)<=7);
  CHECK(std::abs(surface.MetadataOffsetForTesting()-metadata)<=7);
  CHECK(surface.RasterCountForTesting()==raster);
  CHECK(set(false,2)); const auto paused_pixels=surface.PixelsForTesting();
  ShowWindow(bar.window,SW_HIDE); surface.EnvironmentChanged(); Pump(80);
  ShowWindow(bar.window,SW_SHOWNOACTIVATE); surface.EnvironmentChanged(); CHECK(Visible());
  CHECK(surface.PixelsForTesting()==paused_pixels);
  surface.Close(); CHECK(!Surface());
  std::cout<<"hidden-reading: "<<checks<<" checks PASS\n"; return 0;
}
int Lifecycle(const std::wstring& font,const std::wstring& output) {
  CursorGuard cursor; FocusGuard focus; FakeBar bar; TaskbarLyrics surface;
  struct DpiGuard { DPI_AWARENESS_CONTEXT previous=SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE); ~DpiGuard(){if(previous)SetThreadDpiAwarenessContext(previous);} } dpi_guard;
  CHECK(dpi_guard.previous);
  const auto thread=GetThreadDpiAwarenessContext();
  CHECK(surface.Set(true,L"Recover · 恢复 · 回復 · 복원",0xff008ebd,L"DanPingFangSC",font,false,false,{},L"",0,1,L"lifetime",L"line",1,0,10000));
  surface.UseBarForTesting(bar.window,bar.Occupied()); CHECK(Visible());
  CHECK(AreDpiAwarenessContextsEqual(thread,GetThreadDpiAwarenessContext()));
  CHECK(AreDpiAwarenessContextsEqual(GetWindowDpiAwarenessContext(Surface()),GetWindowDpiAwarenessContext(bar.window)));
  const auto controller=FindWindowExW(HWND_MESSAGE,nullptr,L"DanPlayer.TaskbarLyrics.Control.v1",nullptr);
  CHECK(controller); RECT bounds{}; CHECK(GetWindowRect(Surface(),&bounds)); CHECK(Ink(Capture(bounds))>30);
  ShowWindow(bar.window,SW_HIDE); surface.EnvironmentChanged(); CHECK(!Visible());
  const auto frames=surface.MotionFramesForTesting(); Pump(120); CHECK(surface.MotionFramesForTesting()==frames);
  ShowWindow(bar.window,SW_SHOWNOACTIVATE); surface.EnvironmentChanged(); CHECK(Visible() && Ink(Capture(bounds))>30);
  CHECK(DestroyWindow(bar.window)); bar.window=nullptr; Pump(40); CHECK(!Surface());
  CHECK(IsWindow(controller)); bar.Create(); surface.UseBarForTesting(bar.window,bar.Occupied());
  CHECK(Visible() && GetParent(Surface())==bar.window);
  CHECK(GetWindowRect(Surface(),&bounds)); CHECK(Ink(Capture(bounds))>30);
  CHECK(Save(Capture(bounds),bounds,output+L"/bar-replacement-recovered.png"));
  surface.Close(); CHECK(!IsWindow(controller) && !Surface()); Pump(120);
  CHECK(!Surface()); std::cout<<"lifecycle: "<<checks<<" checks PASS\n"; return 0;
}
}
int wmain(int argc,wchar_t** argv) {
  if(argc!=4) return 2; SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  Gdiplus::GdiplusStartupInput input; ULONG_PTR token=0; if(Gdiplus::GdiplusStartup(&token,&input,nullptr)!=Gdiplus::Ok) return 2;
  const int result=wcscmp(argv[1],L"--shell")==0 ? Shell(argv[2],argv[3]) : wcscmp(argv[1],L"--buttons")==0 ? Buttons(argv[2],argv[3]) :
      wcscmp(argv[1],L"--reading")==0 ? Reading(argv[2],argv[3]) : wcscmp(argv[1],L"--hidden-reading")==0 ? HiddenReading(argv[2]) :
      wcscmp(argv[1],L"--lifecycle")==0 ? Lifecycle(argv[2],argv[3]) : 2;
  Escape(); Pump(100); Gdiplus::GdiplusShutdown(token); return result;
}
