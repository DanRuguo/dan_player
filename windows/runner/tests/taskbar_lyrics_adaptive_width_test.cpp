#include "../taskbar_lyrics.h"
#include "taskbar_lyrics_test_windows.h"
#include <dwmapi.h>
#include <gdiplus.h>
#include <iostream>

namespace {
int checks=0;
#define CHECK(value) do { ++checks; if(!(value)) { std::cerr<<"Failed line "<<__LINE__<<": " #value "\n"; return 1; } } while(false)
void Pump(DWORD milliseconds) {
  const auto end=GetTickCount64()+milliseconds;
  do { MSG message; while(PeekMessageW(&message,nullptr,0,0,PM_REMOVE)) { TranslateMessage(&message); DispatchMessageW(&message); }
    MsgWaitForMultipleObjects(0,nullptr,FALSE,2,QS_ALLINPUT);
  } while(GetTickCount64()<end);
}
HWND Surface(){return FindOwnedTaskbarWindow(L"DanPlayer.TaskbarLyrics.v1");}
RECT Bounds(){RECT result{}; if(Surface()) GetWindowRect(Surface(),&result); return result;}
int Width(RECT area){return area.right-area.left;}
bool Inside(RECT inner,RECT outer){return inner.left>=outer.left && inner.top>=outer.top && inner.right<=outer.right && inner.bottom<=outer.bottom;}
int Ink(const std::vector<std::uint32_t>& pixels){return static_cast<int>(std::count_if(pixels.begin(),pixels.end(),[](auto pixel){return (pixel>>24)!=0;}));}
bool Save(const std::vector<std::uint32_t>& pixels,int width,int height,const std::wstring& path) {
  if(pixels.empty()) return false;
  Gdiplus::Bitmap image(width,height,width*4,PixelFormat32bppARGB,reinterpret_cast<BYTE*>(const_cast<std::uint32_t*>(pixels.data())));
  const CLSID png{0x557cf406,0x1a04,0x11d3,{0x9a,0x73,0x00,0x00,0xf8,0x1e,0xf3,0x2e}};
  return image.Save(path.c_str(),&png,nullptr)==Gdiplus::Ok;
}
std::vector<std::uint32_t> Capture(RECT bounds) {
  DwmFlush(); GdiFlush(); const int width=Width(bounds),height=bounds.bottom-bounds.top;
  BITMAPINFO info{}; info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER); info.bmiHeader.biWidth=width; info.bmiHeader.biHeight=-height;
  info.bmiHeader.biPlanes=1; info.bmiHeader.biBitCount=32;
  void* data=nullptr; const auto bitmap=CreateDIBSection(nullptr,&info,DIB_RGB_COLORS,&data,nullptr,0);
  const auto screen=GetDC(nullptr),memory=CreateCompatibleDC(screen); std::vector<std::uint32_t> result;
  if(bitmap && screen && memory && data) {
    const auto old=SelectObject(memory,bitmap);
    if(BitBlt(memory,0,0,width,height,screen,bounds.left,bounds.top,SRCCOPY|CAPTUREBLT)) {
      GdiFlush(); const auto pixels=static_cast<std::uint32_t*>(data); result.assign(pixels,pixels+static_cast<size_t>(width)*height);
      for(auto& pixel:result)pixel|=0xff000000;
    }
    SelectObject(memory,old);
  }
  if(bitmap)DeleteObject(bitmap); if(memory)DeleteDC(memory); if(screen)ReleaseDC(nullptr,screen); return result;
}
int ScreenInk(const std::vector<std::uint32_t>& pixels){return static_cast<int>(std::count_if(pixels.begin(),pixels.end(),[](auto pixel){
  return static_cast<int>(pixel&255)>static_cast<int>((pixel>>16)&255)+15 && static_cast<int>((pixel>>8)&255)>static_cast<int>((pixel>>16)&255)+10;
}));}
struct FakeBar {
  HWND window=nullptr;
  FakeBar() {
    WNDCLASSW cls{}; cls.lpszClassName=L"DanPlayer.TaskbarLyrics.QA.AdaptiveBar"; cls.hInstance=GetModuleHandleW(nullptr);
    cls.lpfnWndProc=DefWindowProcW; cls.hbrBackground=static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)); RegisterClassW(&cls);
    window=CreateWindowExW(WS_EX_TOPMOST|WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE,cls.lpszClassName,L"",WS_POPUP,
        80,400,940,48,nullptr,nullptr,cls.hInstance,nullptr); ShowWindow(window,SW_SHOWNOACTIVATE); UpdateWindow(window);
  }
  ~FakeBar(){if(window)DestroyWindow(window);}
  RECT Bounds()const{RECT result{};GetWindowRect(window,&result);return result;}
  std::vector<RECT> Occupied()const {auto area=Bounds();return {{area.left,area.top,area.left+20,area.bottom},{area.right-20,area.top,area.right,area.bottom}};}
  RECT Safe()const {const auto bounds=Bounds();MONITORINFO monitor{sizeof(monitor)};GetMonitorInfoW(MonitorFromWindow(window,MONITOR_DEFAULTTONEAREST),&monitor);
    return *taskbar_lyrics::FreeArea(bounds,monitor.rcMonitor,Occupied(),GetDpiForWindow(window));}
};
struct Frame {
  std::wstring text=L"歌 · Song · 노래",next=L"",placement=L"start",metadata=L"",line=L"line";
  bool show_next=true,layout=false,animate=false,playing=false,buttons=false;
  std::vector<TaskbarLyricWord> words;
  double position=0;
  std::int64_t revision=1;
  bool Send(TaskbarLyrics& surface,const std::wstring& font)const {
    return surface.Set(true,text,0xff008ebd,L"DanPingFangSC",font,animate,playing,words,next,
        position,1,L"adaptive",line,revision,0,12000,placement,metadata,buttons,false,0,!playing,
        L"player",buttons,buttons,layout,show_next,buttons);
  }
};
int Compact(const std::wstring& font,const std::wstring& output) {
  FakeBar bar; TaskbarLyrics surface; Frame frame;
  CHECK(frame.Send(surface,font)); surface.UseBarForTesting(bar.window,bar.Occupied()); Pump(220);
  const auto safe=bar.Safe(); const auto short_width=Width(Bounds());
  CHECK(IsWindowVisible(Surface())); CHECK(short_width==surface.NaturalWidthForTesting()); CHECK(short_width<Width(safe)/2);
  CHECK(ScreenInk(Capture(Bounds()))>30); CHECK(Ink(surface.PixelsForTesting())>30);
  CHECK(Save(Capture(bar.Bounds()),Width(bar.Bounds()),48,output+L"/short-start-screen.png"));
  const auto cached_shape=surface.ShapingForTesting(); const auto raster=surface.RasterCountForTesting();
  for(const auto* placement:{L"auto",L"start",L"center",L"end"}) {
    frame.placement=placement; CHECK(frame.Send(surface,font));
    const auto area=Bounds(); CHECK(Width(area)==short_width); CHECK(Inside(area,safe));
    CHECK(area.left==(frame.placement==L"end" ? safe.right-short_width : frame.placement==L"center" ? safe.left+(Width(safe)-short_width)/2 : safe.left));
    CHECK(surface.ShapingForTesting()==cached_shape); CHECK(surface.RasterCountForTesting()==raster);
    CHECK(Save(Capture(bar.Bounds()),Width(bar.Bounds()),48,output+L"/short-"+placement+L"-screen.png"));
  }
  frame.next=L"下一句 · The next visible lyric · 다음 가사"; CHECK(frame.Send(surface,font));
  CHECK(Width(Bounds())==std::max(surface.NaturalWidthForTesting(),surface.NaturalWidthForTesting(true)));
  const auto next_width=Width(Bounds()); CHECK(next_width>short_width);
  CHECK(Save(surface.PixelsForTesting(),next_width,48,output+L"/max-next-glyph.png"));
  frame.show_next=false; CHECK(frame.Send(surface,font)); CHECK(Width(Bounds())==short_width);
  frame.text=L"歌"; frame.buttons=true; frame.metadata=L"下一首 · Next track · 次の曲 · 다음 곡"; CHECK(frame.Send(surface,font));
  const auto content=surface.ContentForTesting();
  CHECK(Width(content.lyrics)==surface.NaturalWidthForTesting()); CHECK(Width(content.metadata)>0);
  CHECK(content.lyrics.left==content.pause.right && content.lyrics.right==content.metadata.left && content.metadata.right==content.button.left);
  CHECK(Width(Bounds())==Width(content.pause)+Width(content.lyrics)+Width(content.metadata)+Width(content.button));
  CHECK(Width(Bounds())<480); // Metadata survives the compact width crossing its old eligibility threshold.
  const auto next=FindOwnedTaskbarWindow(L"DanPlayer.TaskbarLyrics.Next.v1"),play=FindOwnedTaskbarWindow(L"DanPlayer.TaskbarLyrics.PlayPause.v1");
  CHECK(next && play); RECT next_bounds{},play_bounds{};CHECK(GetWindowRect(next,&next_bounds) && GetWindowRect(play,&play_bounds));
  CHECK(Inside(next_bounds,Bounds()) && Inside(play_bounds,Bounds())); CHECK(play_bounds.right<=Bounds().left+content.lyrics.left);
  CHECK(SendMessageW(Surface(),WM_NCHITTEST,0,0)==HTTRANSPARENT);
  CHECK(Save(surface.PixelsForTesting(),Width(Bounds()),48,output+L"/compact-controls-metadata.png"));
  frame.text=std::wstring(160,L'歌'); frame.words={{0,6000,frame.text.substr(0,80)},{6000,6000,frame.text.substr(80)}};
  frame.show_next=true; frame.next=L"短い · Short"; frame.buttons=false; frame.metadata=L""; CHECK(frame.Send(surface,font));
  CHECK(Width(Bounds())==Width(safe)); CHECK(Inside(Bounds(),safe));
  surface.SetPositionForTesting(0); const auto head=surface.ReadOffsetForTesting(); surface.SetPositionForTesting(9000); CHECK(surface.ReadOffsetForTesting()>head+100);
  CHECK(Save(surface.PixelsForTesting(),Width(Bounds()),48,output+L"/long-words-glyph.png"));
  frame.words.clear(); frame.text=std::wstring(2400,L'가'); CHECK(frame.Send(surface,font)); CHECK(Width(Bounds())==Width(safe));
  surface.SetPositionForTesting(11500); CHECK(surface.CurrentChunkForTesting()>0); CHECK(Ink(surface.PixelsForTesting())>30);
  surface.Close(); CHECK(!Surface()); std::cout<<"compact: "<<checks<<" checks PASS\n"; return 0;
}
int Handoff(const std::wstring& font,const std::wstring& output) {
  FakeBar bar; TaskbarLyrics surface; Frame frame; frame.animate=frame.playing=true;
  const auto media_start=GetTickCount64();
  frame.text=L"旧句 · Previous"; frame.next=L"下一句的宽度更长 · The longer next line · 긴 다음 가사";
  CHECK(frame.Send(surface,font)); surface.UseBarForTesting(bar.window,bar.Occupied()); Pump(220);
  const auto shape=surface.ShapingForTesting(true); CHECK(shape); const auto old_width=Width(Bounds());
  frame.text=frame.next; frame.next=L"小 · Small"; frame.line=L"line2";
  frame.words={{0,12000,frame.text}}; frame.position=static_cast<double>(GetTickCount64()-media_start); CHECK(frame.Send(surface,font));
  CHECK(surface.ShapingForTesting()==shape); CHECK(Width(Bounds())==old_width); CHECK(surface.LineAnimatingForTesting());
  const auto entrance=surface.LineAnimationStartForTesting(); const auto raster=surface.RasterCountForTesting();
  CHECK(Save(surface.PixelsForTesting(),Width(Bounds()),48,output+L"/handoff-first.png"));
  Pump(240); CHECK(surface.LineAnimatingForTesting()); CHECK(surface.LineAnimationStartForTesting()==entrance);
  CHECK(Save(surface.PixelsForTesting(),Width(Bounds()),48,output+L"/handoff-middle.png"));
  Pump(350); CHECK(!surface.LineAnimatingForTesting()); CHECK(surface.RasterCountForTesting()==raster);
  CHECK(Save(surface.PixelsForTesting(),Width(Bounds()),48,output+L"/handoff-end.png"));
  frame.layout=true; frame.text=frame.next; frame.next=L""; frame.words.clear(); frame.line=L"line3";
  frame.position=static_cast<double>(GetTickCount64()-media_start); CHECK(frame.Send(surface,font));
  CHECK(Width(Bounds())<old_width); CHECK(surface.LayoutAnimatingForTesting() && surface.LineAnimatingForTesting());
  // Sample between the independent 180 ms layout and 560 ms line clocks,
  // leaving more than one native timer quantum after the layout endpoint.
  const auto shrinking_entrance=surface.LineAnimationStartForTesting(); Pump(240);
  std::cout<<"shrink elapsed="<<GetTickCount64()-shrinking_entrance<<" layout="<<surface.LayoutAnimatingForTesting()<<" line="<<surface.LineAnimatingForTesting()<<'\n';
  CHECK(!surface.LayoutAnimatingForTesting() && surface.LineAnimatingForTesting()); CHECK(surface.LineAnimationStartForTesting()==shrinking_entrance);
  CHECK(surface.LayoutBufferPixelsForTesting()==0); Pump(390); CHECK(!surface.LineAnimatingForTesting());
  surface.Close(); CHECK(!Surface()); std::cout<<"handoff: "<<checks<<" checks PASS\n"; return 0;
}
int Layout(const std::wstring& font,const std::wstring& output) {
  FakeBar bar; TaskbarLyrics surface; Frame frame; frame.layout=true; frame.placement=L"center";
  CHECK(frame.Send(surface,font)); surface.UseBarForTesting(bar.window,bar.Occupied()); Pump(220);
  frame.text=L"当前句变宽 · Width adapts smoothly · 넓어지는 가사";
  CHECK(frame.Send(surface,font)); CHECK(surface.LayoutAnimatingForTesting()); CHECK(Inside(Bounds(),bar.Safe()));
  const auto raster=surface.RasterCountForTesting(); const auto start=surface.PixelsForTesting();
  CHECK(Save(Capture(bar.Bounds()),Width(bar.Bounds()),48,output+L"/layout-first-screen.png"));
  Pump(75); const auto middle=surface.PixelsForTesting(); CHECK(middle!=start); CHECK(surface.RasterCountForTesting()==raster);
  CHECK(Save(Capture(bar.Bounds()),Width(bar.Bounds()),48,output+L"/layout-middle-screen.png"));
  frame.text=L"回缩 · Short"; CHECK(frame.Send(surface,font)); CHECK(surface.LayoutAnimatingForTesting()); CHECK(Inside(Bounds(),bar.Safe()));
  Pump(200); CHECK(!surface.LayoutAnimatingForTesting()); CHECK(surface.LayoutBufferPixelsForTesting()==0);
  CHECK(Save(Capture(bar.Bounds()),Width(bar.Bounds()),48,output+L"/layout-end-screen.png"));
  const auto idle=surface.MotionFramesForTesting(); Pump(160); CHECK(surface.MotionFramesForTesting()==idle);
  frame.layout=false; frame.text=L"关闭布局动画 · Layout off · 동작 없음"; CHECK(frame.Send(surface,font));
  CHECK(!surface.LayoutAnimatingForTesting() && surface.LayoutBufferPixelsForTesting()==0);
  frame.layout=true; frame.text=L"定位后的新句 · After seek · 이동 후"; ++frame.revision; CHECK(frame.Send(surface,font));
  CHECK(!surface.LayoutAnimatingForTesting() && surface.LayoutBufferPixelsForTesting()==0);
  frame.layout=true; frame.text=L"隐藏前变宽 · Before hiding · 숨기기 전"; CHECK(frame.Send(surface,font));
  ShowWindow(bar.window,SW_HIDE); surface.EnvironmentChanged(); CHECK(!IsWindowVisible(Surface())); CHECK(!surface.LayoutAnimatingForTesting());
  const auto hidden_frames=surface.MotionFramesForTesting(); Pump(160); CHECK(surface.MotionFramesForTesting()==hidden_frames);
  ShowWindow(bar.window,SW_SHOWNOACTIVATE); surface.EnvironmentChanged(); CHECK(IsWindowVisible(Surface())); CHECK(Inside(Bounds(),bar.Safe()));
  CHECK(!surface.LayoutAnimatingForTesting()); CHECK(ScreenInk(Capture(Bounds()))>30);
  surface.Close(); CHECK(!Surface()); std::cout<<"layout: "<<checks<<" checks PASS\n"; return 0;
}
}
int wmain(int argc,wchar_t** argv) {
  if(argc!=4)return 2; SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  Gdiplus::GdiplusStartupInput input; ULONG_PTR token=0; if(Gdiplus::GdiplusStartup(&token,&input,nullptr)!=Gdiplus::Ok)return 2;
  const int result=wcscmp(argv[1],L"--compact")==0 ? Compact(argv[2],argv[3]) : wcscmp(argv[1],L"--handoff")==0 ? Handoff(argv[2],argv[3]) :
      wcscmp(argv[1],L"--layout")==0 ? Layout(argv[2],argv[3]) : 2;
  Gdiplus::GdiplusShutdown(token); return result;
}
