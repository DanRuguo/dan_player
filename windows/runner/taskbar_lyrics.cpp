#include "taskbar_lyrics.h"
#include "taskbar_lyrics_policy.h"
#include "taskbar_lyrics_button.h"
#include "desktop_integration_fonts.h"
#include "desktop_integration_policy.h"
#include <dwmapi.h>
#include <shellapi.h>
#include <UIAutomation.h>
#include <wrl/client.h>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <thread>
#include <unordered_map>
#include <utility>
#ifdef DAN_TASKBAR_LYRICS_NATIVE_QA
#include <iostream>
#endif

namespace {
using Microsoft::WRL::ComPtr;
constexpr UINT kRefresh = WM_APP + 0x621, kReady = WM_APP + 0x622;
constexpr UINT kMenuStarted = WM_APP + 0x623, kMenuEnded = WM_APP + 0x624;
constexpr UINT_PTR kSettle = 1, kScroll = 2, kGeometryRetry = 3, kCreateRetry = 4;
constexpr wchar_t kClass[] = L"DanPlayer.TaskbarLyrics.v1";
constexpr wchar_t kControlClass[] = L"DanPlayer.TaskbarLyrics.Control.v1";
std::mutex hook_mutex;
std::atomic<ULONG_PTR> next_epoch{1};
struct HookTarget { HWND surface; HWND bar; ULONG_PTR epoch; };
std::unordered_map<HWINEVENTHOOK, HookTarget> hook_targets;
void CALLBACK ShellEvent(HWINEVENTHOOK hook, DWORD event, HWND target,
                         LONG object, LONG, DWORD, DWORD) {
  std::lock_guard<std::mutex> guard(hook_mutex);
  const auto found = hook_targets.find(hook);
  if (found == hook_targets.end()) return;
  const auto& entry = found->second;
#ifdef DAN_TASKBAR_LYRICS_NATIVE_QA
  if (event==EVENT_SYSTEM_FOREGROUND || (object==OBJID_WINDOW && target==entry.bar)) {
    wchar_t event_class[128]{}; GetClassNameW(target,event_class,128);
    std::wcout<<L"shell event="<<event<<L" class="<<event_class<<L" object="<<object<<L"\n";
  }
#endif
  if (object == OBJID_WINDOW && target != entry.bar && target) {
    wchar_t name[128]{}; GetClassNameW(target, name, 128);
    if (wcscmp(name,L"Xaml_WindowedPopupClass") == 0 || wcscmp(name,L"#32768") == 0) {
      if (event == EVENT_OBJECT_SHOW) PostMessageW(entry.surface,kMenuStarted,reinterpret_cast<WPARAM>(target),entry.epoch);
      else if (event == EVENT_OBJECT_HIDE || event == EVENT_OBJECT_DESTROY)
        PostMessageW(entry.surface,kMenuEnded,reinterpret_cast<WPARAM>(target),entry.epoch);
      return;
    }
  }
  if (event == EVENT_SYSTEM_FOREGROUND) {
    PostMessageW(entry.surface, kRefresh, 0, static_cast<LPARAM>(entry.epoch));
  } else if (event == EVENT_OBJECT_REORDER && object == OBJID_WINDOW && target == entry.bar) {
    PostMessageW(entry.surface, kRefresh, 0, static_cast<LPARAM>(entry.epoch));
  } else if (target == entry.bar || (target && IsChild(entry.bar, target))) {
    // Location changes only trigger a coalesced refresh, never COM or drawing.
    PostMessageW(entry.surface, kRefresh,
        (target != entry.bar || event != EVENT_OBJECT_LOCATIONCHANGE) ? 1 : 0, static_cast<LPARAM>(entry.epoch));
  }
}

struct Geometry {
  HWND bar = nullptr;
  RECT bar_rect{};
  std::vector<RECT> occupied;
  bool valid = false;
};
struct Worker {
  std::mutex mutex;
  std::condition_variable changed;
  bool stopped = false, requested = false, exited = false;
  HWND surface = nullptr, bar = nullptr;
  unsigned revision = 0, completed_revision = 0;
  ULONG_PTR epoch = 0;
  Geometry result;
#ifdef DAN_TASKBAR_LYRICS_NATIVE_QA
  unsigned fail_reads = 0;
#endif
};
Geometry ReadGeometry(IUIAutomation* automation, HWND bar) {
  Geometry result; result.bar = bar;
  if (!automation || !IsWindow(bar) || !GetWindowRect(bar, &result.bar_rect)) return result;
  ComPtr<IUIAutomationElement> root;
  ComPtr<IUIAutomationCondition> button, split, item, pair, filter;
  ComPtr<IUIAutomationCacheRequest> cache;
  VARIANT value; VariantInit(&value); value.vt = VT_I4;
  value.lVal = UIA_ButtonControlTypeId;
  if (FAILED(automation->ElementFromHandle(bar, &root)) ||
      FAILED(automation->CreatePropertyCondition(UIA_ControlTypePropertyId, value, &button))) return result;
  value.lVal = UIA_SplitButtonControlTypeId;
  if (FAILED(automation->CreatePropertyCondition(UIA_ControlTypePropertyId, value, &split))) return result;
  value.lVal = UIA_ListItemControlTypeId;
  if (FAILED(automation->CreatePropertyCondition(UIA_ControlTypePropertyId, value, &item)) ||
      FAILED(automation->CreateOrCondition(button.Get(), split.Get(), &pair)) ||
      FAILED(automation->CreateOrCondition(pair.Get(), item.Get(), &filter)) ||
      FAILED(automation->CreateCacheRequest(&cache))) return result;
  cache->AddProperty(UIA_BoundingRectanglePropertyId);
  cache->AddProperty(UIA_IsOffscreenPropertyId);
  cache->AddProperty(UIA_ProcessIdPropertyId);
  ComPtr<IUIAutomationElementArray> elements;
  if (FAILED(root->FindAllBuildCache(TreeScope_Descendants, filter.Get(), cache.Get(), &elements))) return result;
  int count = 0;
  if (FAILED(elements->get_Length(&count)) || count <= 0 || count > 512) return result;
  for (int index = 0; index < count; ++index) {
    ComPtr<IUIAutomationElement> element;
    BOOL offscreen = TRUE; RECT bounds{}; int process=0;
    if (SUCCEEDED(elements->GetElement(index, &element)) &&
        SUCCEEDED(element->get_CachedIsOffscreen(&offscreen)) && !offscreen &&
        SUCCEEDED(element->get_CachedProcessId(&process)) && process!=static_cast<int>(GetCurrentProcessId()) &&
        SUCCEEDED(element->get_CachedBoundingRectangle(&bounds)) &&
        bounds.right > bounds.left && bounds.bottom > bounds.top) result.occupied.push_back(bounds);
  }
  RECT after{};
  result.valid = !result.occupied.empty() && IsWindow(bar) && GetWindowRect(bar, &after) &&
      EqualRect(&after, &result.bar_rect);
  return result;
}
void RunWorker(std::shared_ptr<Worker> state) {
  const HRESULT init = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  ComPtr<IUIAutomation> automation;
  if (SUCCEEDED(init)) {
    if (FAILED(CoCreateInstance(CLSID_CUIAutomation8, nullptr, CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&automation))))
      CoCreateInstance(CLSID_CUIAutomation, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&automation));
    ComPtr<IUIAutomation6> bounded;
    if (automation && SUCCEEDED(automation.As(&bounded))) {
      bounded->put_ConnectionTimeout(500);
      bounded->put_TransactionTimeout(500);
    }
  }
  for (;;) {
    HWND bar; unsigned revision;
    {
      std::unique_lock<std::mutex> lock(state->mutex);
      state->changed.wait(lock, [&] { return state->stopped || state->requested; });
      if (state->stopped) break;
      state->requested = false; bar = state->bar; revision = state->revision;
    }
    auto result = ReadGeometry(automation.Get(), bar);
    {
      std::lock_guard<std::mutex> lock(state->mutex);
#ifdef DAN_TASKBAR_LYRICS_NATIVE_QA
      if (state->fail_reads) { --state->fail_reads; result.valid = false; result.occupied.clear(); }
#endif
      if (!state->stopped && revision == state->revision && state->surface) {
        state->result = std::move(result); state->completed_revision = revision;
        PostMessageW(state->surface, kReady, state->epoch, 0);
      }
    }
  }
  automation.Reset();
  if (SUCCEEDED(init)) CoUninitialize();
  { std::lock_guard<std::mutex> lock(state->mutex); state->exited = true; }
  state->changed.notify_all();
}
bool ForegroundFullscreen(HWND surface, HWND bar, HMONITOR monitor, RECT bounds, UINT dpi) {
  const HWND foreground = GetForegroundWindow();
  if (!foreground || foreground == surface || foreground == bar || !IsWindowVisible(foreground) ||
      IsIconic(foreground) || MonitorFromWindow(foreground, MONITOR_DEFAULTTONULL) != monitor) return false;
  wchar_t name[80]{}; GetClassNameW(foreground, name, 80);
  if (wcscmp(name, L"Progman") == 0 || wcscmp(name, L"WorkerW") == 0) return false;
  // Task View is Shell navigation, not a fullscreen playback application. Its
  // transient whole-monitor host must not hide lyrics on the visible taskbar.
  DWORD owner=0,shell=0; GetWindowThreadProcessId(foreground,&owner); GetWindowThreadProcessId(bar,&shell);
  if(owner==shell && wcscmp(name,L"XamlExplorerHostIslandWindow")==0) return false;
  DWORD cloaked = 0;
  if (SUCCEEDED(DwmGetWindowAttribute(foreground, DWMWA_CLOAKED, &cloaked, sizeof(cloaked))) && cloaked) return false;
  RECT foreground_rect{};
  if (FAILED(DwmGetWindowAttribute(foreground, DWMWA_EXTENDED_FRAME_BOUNDS,
                                  &foreground_rect, sizeof(foreground_rect))))
    GetWindowRect(foreground, &foreground_rect);
  const bool full=taskbar_lyrics::CoversMonitor(foreground_rect, bounds, dpi);
#ifdef DAN_TASKBAR_LYRICS_NATIVE_QA
  if(full) std::wcout<<L"fullscreen class="<<name<<L" visible="<<IsWindowVisible(foreground)<<L" cloaked="<<cloaked<<L"\n";
#endif
  return full;
}
}

struct TaskbarLyrics::Impl {
  const ULONG_PTR epoch = next_epoch.fetch_add(1);
  HWND controller = nullptr, surface = nullptr, bar = nullptr, shell_menu = nullptr;
  bool enabled = false, animate = false, playing = false, invalid = true;
  bool force_probe = false, scrolling = false, word_sampling = false, entrance_pending = false, entering = false;
  bool roll_from_next = false;
  bool first_frame_pending = false, reuse_next = false;
  unsigned settle_retries = 0;
  unsigned geometry_retries = 0;
  unsigned create_retries=0;
  bool vertical = false, show_pause_indicator = false, paused = false, stroke_enabled = false, metadata_invalid = true;
  bool show_next_button = false, next_button_enabled = false;
  bool playback_button_enabled=false;
  bool show_next_lyric=true;
  bool animate_layout=false,layout_animating=false;
  ULONGLONG layout_start=0;
  RECT previous_layout_area{};
  RECT previous_layout_lyrics{};
  std::vector<std::uint32_t> previous_layout_pixels;
  std::vector<std::uint32_t> layout_target_pixels;
  double previous_layout_anchor_x=0,previous_layout_anchor_y=0,layout_dx=0,layout_dy=0;
  int previous_layout_width=0,previous_layout_height=0;
  taskbar_lyrics::ColorScheme color_scheme = taskbar_lyrics::ColorScheme::kPlayer;
  unsigned area_selection = 0;
  taskbar_lyrics::Placement placement = taskbar_lyrics::Placement::kAuto;
  TaskbarLyricsLayout layout;
  std::function<void(const TaskbarLyricsLayout&)> layout_callback;
  std::function<void()> next_track_callback;
  std::function<void()> playback_callback;
  std::wstring play_label=L"Play",pause_label=L"Pause";
  taskbar_lyrics::NextTrackButton next_button;
  taskbar_lyrics::TaskbarMediaButton playback_button{L"DanPlayer.TaskbarLyrics.PlayPause.v1"};
  RECT button_area{};
  RECT playback_button_area{};
  UINT dpi = 96;
  unsigned accent = 0xff2196f3;
  COLORREF foreground = RGB(0, 120, 170);
  std::wstring text, next_text, next_track_text, source_identity, line_identity;
  std::vector<TaskbarLyricWord> words;
  double anchor_position = 0, playback_rate = 1, line_start = 0, line_end = 0;
  double correction = 0;
  ULONGLONG anchor_tick = 0;
  std::int64_t timeline_revision = 0;
  taskbar_lyrics::TextMask current_mask, next_mask, old_mask;
  taskbar_lyrics::TextMask metadata_mask, next_track_icon;
  taskbar_lyrics::MediaCapsule metadata_capsule;
  std::vector<unsigned char> highlight_columns;
  int row_height = 0;
  int lyric_width = 0, lyric_height = 0, lyric_left = 0, lyric_top = 0;
  int metadata_width = 0, metadata_height = 0, metadata_left = 0, metadata_top = 0;
  COLORREF stroke_color = RGB(0, 0, 0);
  double stroke_opacity = .9;
  Geometry geometry;
  RECT area{};
  RECT available_area{};
  bool area_layout_allowed=false;
  bool layout_reset_pending=false;
  std::vector<HWINEVENTHOOK> hooks;
  std::shared_ptr<Worker> worker;
  std::thread worker_thread;
  desktop_integration::PopupFonts fonts;
  HDC dc = nullptr;
  HBITMAP bitmap = nullptr;
  HGDIOBJ original = nullptr;
  std::uint32_t* pixels = nullptr;
  int width = 0, height = 0, text_width = 0;
  int fallback_read_offset=0,last_read_offset=0,metadata_read_offset=0;
  std::wstring rendered_metadata_text;

  ULONGLONG scroll_start = 0;
  ULONGLONG scroll_elapsed = 0;
  ULONGLONG entrance_start = 0;
  UINT taskbar_created = RegisterWindowMessageW(L"TaskbarCreated");
#ifdef DAN_TASKBAR_LYRICS_NATIVE_QA
  unsigned raster_count=0,motion_frames=0;
  std::optional<bool> system_light_for_testing;
  std::optional<double> position_for_testing;
  std::optional<Geometry> geometry_for_testing;
#endif

  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wp, LPARAM lp) {
    auto* self = reinterpret_cast<Impl*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
      self = static_cast<Impl*>(reinterpret_cast<CREATESTRUCTW*>(lp)->lpCreateParams);
      SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    if (!self) return DefWindowProcW(hwnd, message, wp, lp);
#ifdef DAN_TASKBAR_LYRICS_NATIVE_QA
    if(message==WM_APP+0x626) return reinterpret_cast<LRESULT>(self->surface);
    if(message==WM_APP+0x627) return reinterpret_cast<LRESULT>(self->next_button.window());
    if(message==WM_APP+0x628) return reinterpret_cast<LRESULT>(self->playback_button.window());
#endif
    if(message==WM_NCDESTROY && hwnd==self->surface) {
      self->surface=nullptr; self->next_button.Close(); self->playback_button.Close();
      self->Hide(); self->invalid=self->metadata_invalid=true;
      return DefWindowProcW(hwnd,message,wp,lp);
    }
    if (message == WM_NCHITTEST) return HTTRANSPARENT;
    if (message == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
    if (message == kMenuStarted || message == kMenuEnded) {
      if (static_cast<ULONG_PTR>(lp) != self->epoch) return 0;
      if (message == kMenuStarted) self->shell_menu = reinterpret_cast<HWND>(wp);
      else if (self->shell_menu == reinterpret_cast<HWND>(wp)) {
        self->shell_menu = nullptr; self->force_probe = true;
        if (self->enabled) SetTimer(hwnd,kSettle,80,nullptr);
      }
      if (self->shell_menu) { self->next_button.Hide(); self->playback_button.Hide(); }
      return 0;
    }
    if (message == kRefresh) {
      if (static_cast<ULONG_PTR>(lp) != self->epoch) return 0;
      self->force_probe |= wp != 0;
      if (self->enabled) {
        // A new causal Shell event can recover an exhausted transient UIA read.
        self->force_probe |= !self->geometry.valid;
        self->create_retries=3;
        self->Refresh(false);
        SetTimer(hwnd, kSettle, 80, nullptr);
      }
      return 0;
    }
    if (message == kReady) { if (wp == self->epoch) self->AcceptGeometry(); return 0; }
    if(message==WM_TIMER && wp==kCreateRetry) {
      KillTimer(hwnd,kCreateRetry); self->Refresh(false); return 0;
    }
    if (message == WM_TIMER && wp == kGeometryRetry) {
      KillTimer(hwnd, kGeometryRetry);
      if (self->enabled && self->bar && IsWindowVisible(self->bar)) self->RequestGeometry(true);
      return 0;
    }
    if (message == WM_TIMER && wp == kSettle) {
#ifdef DAN_TASKBAR_LYRICS_NATIVE_QA
      std::cout << "settle timer probe=" << self->force_probe << '\n';
#endif
      KillTimer(hwnd, kSettle);
      const bool probe = std::exchange(self->force_probe, false);
      self->Refresh(probe);
      if (self->settle_retries) {
        --self->settle_retries;
        if (self->settle_retries && self->enabled && IsWindowVisible(self->surface) && self->NeedsRaise())
          SetTimer(hwnd, kSettle, 80, nullptr);
        else self->settle_retries = 0;
      }
      return 0;
    }
    if (message == WM_TIMER && wp == kScroll) {
#ifdef DAN_TASKBAR_LYRICS_NATIVE_QA
      ++self->motion_frames;
#endif
      const unsigned duration = self->roll_from_next && self->row_height < self->lyric_height ? 560 : 180;
      if (self->entering && GetTickCount64() - self->entrance_start >= duration) self->entering = false;
      if (!self->entering) self->old_mask = {};
      self->word_sampling = self->animate && self->playing && taskbar_lyrics::WordsRemaining(self->current_mask, self->Position());
      self->Present();
      if (!self->entering && !self->scrolling && !self->word_sampling && !self->layout_animating) KillTimer(hwnd, kScroll);
      return 0;
    }
    if (message == WM_DISPLAYCHANGE || message == WM_SETTINGCHANGE ||
        message == WM_DPICHANGED || message == WM_THEMECHANGED || message == WM_SYSCOLORCHANGE ||
        (self->taskbar_created && message == self->taskbar_created)) {
      self->UpdateForeground();
      self->Refresh(true); return 0;
    }
    return DefWindowProcW(hwnd, message, wp, lp);
  }
  bool Open() {
    if (controller) return true;
    WNDCLASSW cls{}; cls.lpfnWndProc = WindowProc;
    cls.hInstance = GetModuleHandleW(nullptr); cls.lpszClassName = kControlClass;
    if (!RegisterClassW(&cls) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return false;
    controller=CreateWindowExW(0,kControlClass,L"",0,0,0,0,0,HWND_MESSAGE,nullptr,cls.hInstance,this);
    if (!controller) return false;
    worker = std::make_shared<Worker>(); worker->surface = controller;
    worker->epoch = epoch;
    worker_thread = std::thread(RunWorker, worker);
    return true;
  }
  bool OpenSurface() {
    if(surface) return true;
    if(!bar || !IsWindowVisible(bar)) return false;
    taskbar_lyrics::ScopedParentDpi context(bar);
    if(!context.valid()) return false;
    WNDCLASSW cls{}; cls.lpfnWndProc=WindowProc; cls.hInstance=GetModuleHandleW(nullptr); cls.lpszClassName=kClass;
    if(!RegisterClassW(&cls) && GetLastError()!=ERROR_CLASS_ALREADY_EXISTS) return false;
    surface=CreateWindowExW(WS_EX_LAYERED|WS_EX_NOACTIVATE|WS_EX_TRANSPARENT|WS_EX_NOPARENTNOTIFY,kClass,L"",WS_CHILD,
        0,0,1,1,bar,nullptr,cls.hInstance,this);
    if(!surface) {
#ifdef DAN_TASKBAR_LYRICS_NATIVE_QA
      std::cout<<"child create failure="<<GetLastError()<<'\n';
#endif
      return false; // Shell can temporarily forbid children in its higher band.
    }
    invalid=metadata_invalid=true;
    KillTimer(controller,kCreateRetry); create_retries=0; return true;
  }
  void Unhook() {
    for (auto hook : hooks) {
      { std::lock_guard<std::mutex> guard(hook_mutex); hook_targets.erase(hook); }
      UnhookWinEvent(hook);
    }
    hooks.clear();
  }
  void Observe() {
    Unhook();
    const auto add = [&](DWORD first, DWORD last, DWORD process,bool skip_own=true) {
      const auto hook = SetWinEventHook(first, last, nullptr, ShellEvent,
          process, 0, WINEVENT_OUTOFCONTEXT | (skip_own ? WINEVENT_SKIPOWNPROCESS : 0));
      if (hook) {
        hooks.push_back(hook);
        std::lock_guard<std::mutex> guard(hook_mutex);
        hook_targets.emplace(hook, HookTarget{controller, bar, epoch});
      }
    };
    // Returning to the player's own window is also a causal Shell recovery
    // event. Our no-activate surfaces never generate foreground events.
    add(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, 0,false);
    DWORD process = 0; if (bar) GetWindowThreadProcessId(bar, &process);
    if (process) {
      add(EVENT_OBJECT_CREATE, EVENT_OBJECT_HIDE, process);
      add(EVENT_OBJECT_LOCATIONCHANGE, EVENT_OBJECT_LOCATIONCHANGE, process);
      add(EVENT_OBJECT_REORDER, EVENT_OBJECT_REORDER, process);
    }
  }
  void Hide(bool preserve_geometry_retry = false) {
    if (scrolling && scroll_start) scroll_elapsed+=GetTickCount64()-scroll_start;
    next_button.Hide(); playback_button.Hide();
    if (controller) {
      KillTimer(controller, kScroll);
      KillTimer(controller, kSettle);
      if (!preserve_geometry_retry) KillTimer(controller, kGeometryRetry);
    }
    if(surface) ShowWindow(surface,SW_HIDE);
    scrolling = entering = entrance_pending = word_sampling = false;
    FinishLayout();
    old_mask = {};
    scroll_start = entrance_start = 0;
  }
  void FinishLayout() {
    layout_animating=false;
    std::vector<std::uint32_t>().swap(previous_layout_pixels);
    std::vector<std::uint32_t>().swap(layout_target_pixels);
    previous_layout_width=previous_layout_height=0;
  }
  void BeginLayout() {
    const auto alignment=taskbar_lyrics::ContentOffset(lyric_width,row_height,current_mask.natural_width,
        taskbar_lyrics::VisibleTextHeight(current_mask),vertical,placement);
    const double remaining=layout_animating ? 1-taskbar_lyrics::LayoutProgress(static_cast<double>(GetTickCount64()-layout_start)) : 0;
    previous_layout_anchor_x=area.left+lyric_left+alignment.x+layout_dx*remaining;
    previous_layout_anchor_y=area.top+lyric_top+alignment.y+(vertical ? 0 : row_height*.5)+layout_dy*remaining;
    previous_layout_pixels.assign(pixels,pixels+static_cast<size_t>(width)*height);
    previous_layout_area=area; previous_layout_width=width; previous_layout_height=height;
    previous_layout_lyrics=RECT{lyric_left,lyric_top,lyric_left+lyric_width,lyric_top+lyric_height};
    layout_start=GetTickCount64(); layout_animating=true;
  }
  void RequestGeometry(bool retry = false) {
    if (!worker) return;
    if (!retry) { geometry_retries = 3; if (controller) KillTimer(controller, kGeometryRetry); }
    std::lock_guard<std::mutex> lock(worker->mutex);
    worker->bar = bar; ++worker->revision; worker->requested = true;
    worker->changed.notify_one();
  }
  void AcceptGeometry() {
    if (!enabled || !worker) return;
#ifdef DAN_TASKBAR_LYRICS_NATIVE_QA
    if(geometry_for_testing) return; // injected fixture owns geometry/epochs
#endif
    Geometry result;
    {
      std::lock_guard<std::mutex> lock(worker->mutex);
      if (worker->stopped || worker->completed_revision != worker->revision) return;
      result = worker->result;
    }
    // XAML temporarily substitutes a menu-only UIA tree for the taskbar tree.
    // Keep its already verified surface only while that menu is actually open
    // and the physical bar is unchanged; recheck once after the menu closes.
    RECT current{};
    if (!result.valid && shell_menu && IsWindowVisible(shell_menu) && geometry.valid &&
        geometry.bar == bar && GetWindowRect(bar,&current) && EqualRect(&current,&geometry.bar_rect)) {
      force_probe = true; return;
    }
    geometry = std::move(result);
#ifdef DAN_TASKBAR_LYRICS_NATIVE_QA
    std::cout << "geometry accepted valid=" << geometry.valid << " controls=" << geometry.occupied.size() << '\n';
#endif
    if (geometry.bar != bar || !geometry.valid) {
      UpdateLayout({vertical, 0, 0}); Hide();
      if (geometry.bar == bar && geometry_retries && bar && IsWindowVisible(bar)) {
        --geometry_retries;
        SetTimer(controller, kGeometryRetry, 80, nullptr);
      }
      return;
    }
    geometry_retries = 0; KillTimer(controller, kGeometryRetry);
    Refresh(false);
  }
  void UpdateLayout(TaskbarLyricsLayout value) {
    if (layout.vertical == value.vertical && layout.area_count == value.area_count && layout.area_index == value.area_index) return;
    layout = value;
    if (layout_callback) layout_callback(layout);
  }
  bool NeedsRaise() const {
    if(!surface) return false;
    for (HWND above = GetWindow(surface, GW_HWNDPREV); above; above = GetWindow(above, GW_HWNDPREV))
      if (IsWindowVisible(above) && above!=next_button.window() && above!=playback_button.window()) return true;
    return false;
  }
  void Refresh(bool probe) {
    if (!enabled || !controller || text.empty()) { Hide(); return; }
    auto current = FindWindowW(L"Shell_TrayWnd", nullptr);
#ifdef DAN_TASKBAR_LYRICS_NATIVE_QA
    if(geometry_for_testing) current=geometry_for_testing->bar;
#endif
    if (current != bar) {
      next_button.Close(); playback_button.Close();
      if(surface) DestroyWindow(surface);
      bar = current; geometry = {}; Observe(); probe = true;
      create_retries=3;
    }
#ifdef DAN_TASKBAR_LYRICS_NATIVE_QA
    if(geometry_for_testing) { geometry=*geometry_for_testing; probe=false; }
#endif
    if (!bar || !IsWindowVisible(bar)) { Hide(); return; }
    if(!OpenSurface()) {
      Hide();
      if(create_retries) { --create_retries; SetTimer(controller,kCreateRetry,80,nullptr); }
      return;
    }
    RECT bounds{}; MONITORINFO monitor{sizeof(monitor)};
    const auto display = MonitorFromWindow(bar, MONITOR_DEFAULTTONEAREST);
    if (!GetWindowRect(bar, &bounds) || !GetMonitorInfoW(display, &monitor)) { Hide(); return; }
    const UINT next_dpi = GetDpiForWindow(bar);
    const bool orientation_changed=vertical!=(bounds.bottom-bounds.top>bounds.right-bounds.left);
    vertical = bounds.bottom - bounds.top > bounds.right - bounds.left;
    const bool dpi_changed=next_dpi!=dpi;
    if (next_dpi != dpi) {
      dpi = next_dpi; invalid = true; reuse_next = false;
      entering = entrance_pending = false; old_mask = {}; probe = true;
    }
    if (probe) {
      // Shell descendants are often created without moving an occupied slot.
      // Recheck on the MTA worker while keeping the last verified glyph buffer;
      // a real bar move/resize, missing geometry or fullscreen remains hidden.
      const bool keep_menu_cache = shell_menu && IsWindowVisible(shell_menu) && geometry.valid &&
          EqualRect(&bounds,&geometry.bar_rect);
      if (keep_menu_cache) force_probe = true;
      else RequestGeometry();
      if (!geometry.valid || !EqualRect(&bounds, &geometry.bar_rect)) {
        geometry.valid = false; UpdateLayout({vertical, 0, 0});
        Hide(); return;
      }
    }
    if (ForegroundFullscreen(surface, bar, display, monitor.rcMonitor, dpi)) { Hide(); return; }
    if (!geometry.valid) { Hide(true); return; }
    const LONG dx = bounds.left - geometry.bar_rect.left;
    const LONG dy = bounds.top - geometry.bar_rect.top;
    if (bounds.right - bounds.left != geometry.bar_rect.right - geometry.bar_rect.left ||
        bounds.bottom - bounds.top != geometry.bar_rect.bottom - geometry.bar_rect.top) {
      geometry.valid = false; Hide(); RequestGeometry(); return;
    }
    auto occupied = geometry.occupied;
    for (auto& rect : occupied) OffsetRect(&rect, dx, dy);
    const auto areas = taskbar_lyrics::EligibleAreas(bounds, monitor.rcMonitor, occupied, dpi);
    if (areas.empty()) { UpdateLayout({vertical, 0, 0}); Hide(); return; }
    const auto selected = taskbar_lyrics::SelectedArea(areas, vertical, area_selection);
    const int previous_area_index=layout.area_index;
    UpdateLayout({vertical, static_cast<int>(areas.size()), static_cast<int>(selected)});
    const auto free = taskbar_lyrics::PlaceArea(areas[selected], vertical, dpi, placement);
    area_layout_allowed=!orientation_changed && !dpi_changed && previous_area_index==static_cast<int>(selected);
    const bool budget_changed=available_area.right-available_area.left!=free.right-free.left ||
        available_area.bottom-available_area.top!=free.bottom-free.top;
    available_area=free;
    if (budget_changed) { invalid=metadata_invalid=true; reuse_next=false; }
    if (invalid && !Raster()) { Hide(); return; }
    if (!invalid) SetArea(vertical ? free : taskbar_lyrics::FitHorizontalArea(free,width,placement));
    if (layout_animating) {
      const auto alignment=taskbar_lyrics::ContentOffset(lyric_width,row_height,current_mask.natural_width,
          taskbar_lyrics::VisibleTextHeight(current_mask),vertical,placement);
      layout_dx=previous_layout_anchor_x-(area.left+lyric_left+alignment.x);
      layout_dy=previous_layout_anchor_y-(area.top+lyric_top+alignment.y+(vertical ? 0 : row_height*.5));
    }
    if (metadata_invalid) RasterMetadata();
    const bool motion_allowed = animate && playing;
    if ((entrance_pending || first_frame_pending) && motion_allowed) {
      entering = true; entrance_start = GetTickCount64();
    }
    entrance_pending = false;
    first_frame_pending = false;
    if (!motion_allowed) entering = false;
    Present();
    const bool showing = !IsWindowVisible(surface);
    // Keep our child above taskbar siblings. Avoid redundant reordering when
    // it is already at the front; this surface never changes Shell's band.
    const BOOL raised = !(showing || NeedsRaise()) || SetWindowPos(surface, HWND_TOP, 0, 0, 0, 0,
        SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE | (showing ? SWP_SHOWWINDOW : 0));
    if (!raised) { Hide(); return; }
    if (show_next_button && !(shell_menu && IsWindowVisible(shell_menu))) {
      RECT destination=button_area; OffsetRect(&destination,area.left,area.top);
      next_button.SetCallback([this] { if (enabled && show_next_button && next_button_enabled && next_track_callback) next_track_callback(); });
      next_button.SetRestoreCallback([this] { if (enabled && surface) SetTimer(controller,kSettle,80,nullptr); });
      next_button.Show(bar,destination,dpi,foreground,next_button_enabled,stroke_enabled,stroke_color,stroke_opacity);
    } else next_button.Hide();
    if(show_pause_indicator && !(shell_menu && IsWindowVisible(shell_menu))) {
      RECT destination=playback_button_area; OffsetRect(&destination,area.left,area.top);
      playback_button.SetSymbol(playing ? taskbar_lyrics::MediaSymbol::kPause : taskbar_lyrics::MediaSymbol::kPlay);
      playback_button.SetLabel(playing ? pause_label : play_label);
      playback_button.SetCallback([this] { if(enabled && show_pause_indicator && playback_button_enabled && playback_callback) playback_callback(); });
      playback_button.SetRestoreCallback([this] { if(enabled && controller) SetTimer(controller,kSettle,80,nullptr); });
      playback_button.Show(bar,destination,dpi,foreground,playback_button_enabled,stroke_enabled,stroke_color,stroke_opacity);
    } else playback_button.Hide();
#ifdef DAN_TASKBAR_LYRICS_NATIVE_QA
    bool tray_above = false;
    for (HWND above = GetWindow(surface, GW_HWNDPREV); above; above = GetWindow(above, GW_HWNDPREV))
      if (above == bar) tray_above = true;
    std::cout << "raise=" << raised << " showing=" << showing << " trayabove=" << tray_above << " exstyle=" << GetWindowLongPtrW(surface, GWL_EXSTYLE) << '\n';
#endif
    // Shell can insert a sibling during first show. Recheck our own child
    // ordering at most three times, with no idle polling.
    if (showing) { settle_retries = 3; SetTimer(controller, kSettle, 80, nullptr); }
    const bool motion = motion_allowed && ((current_mask.overflow && !current_mask.long_text && current_mask.words.empty()) ||
        (metadata_mask.overflow && !metadata_mask.long_text));
    word_sampling = motion_allowed && taskbar_lyrics::WordsRemaining(current_mask, Position());
    if (motion && !scrolling) {
      scroll_start = GetTickCount64();
      scrolling = true;
    } else if (!motion && scrolling) {
      if(scroll_start) scroll_elapsed+=GetTickCount64()-scroll_start;
      scrolling = false; scroll_start = 0; Present();
    }
    if (scrolling || entering || word_sampling || layout_animating) {
      if (!SetTimer(controller, kScroll, 16, nullptr)) {
        scrolling = entering = false; FinishLayout(); Present();
      }
    } else KillTimer(controller, kScroll);
  }
  void ClearBitmap() {
    if (dc && original) SelectObject(dc, original);
    if (dc) DeleteDC(dc);
    if (bitmap) DeleteObject(bitmap);
    dc = nullptr; bitmap = nullptr; original = nullptr; pixels = nullptr;
    width = height = text_width = 0;
  }
  double Position() const {
#ifdef DAN_TASKBAR_LYRICS_NATIVE_QA
    if(position_for_testing) return *position_for_testing;
#endif
    const double elapsed = static_cast<double>(GetTickCount64() - anchor_tick);
    return anchor_position + (playing ? elapsed * playback_rate : 0) +
        correction * (1 - std::clamp(elapsed / 90.0, 0.0, 1.0));
  }
  void SetArea(RECT target) {
    if (EqualRect(&area,&target)) return;
    RECT intersection{};
    if (animate_layout && area_layout_allowed && !layout_reset_pending && IsWindowVisible(surface) && pixels &&
        static_cast<size_t>(width)*height<=1024*1024 &&
        static_cast<size_t>(target.right-target.left)*(target.bottom-target.top)<=1024*1024 &&
        IntersectRect(&intersection,&area,&target)) BeginLayout();
    else FinishLayout();
    area=target;
  }
  bool Raster() {
#ifdef DAN_TASKBAR_LYRICS_NATIVE_QA
    ++raster_count;
#endif
    const int previous_lyric_height = lyric_height;
    const int available_width=available_area.right-available_area.left;
    const int available_height=available_area.bottom-available_area.top;
    if (available_width <= 0 || available_height <= 0 || available_width > 7680 || available_height > 960) return false;
    const auto maximum=taskbar_lyrics::LayoutContent(available_width,available_height,dpi,vertical,
        show_pause_indicator,!next_track_text.empty(),show_next_button);
    const int measuring_width=maximum.lyrics.right-maximum.lyrics.left;
    const int measuring_height=maximum.lyrics.bottom-maximum.lyrics.top;
    const int target_row_height=show_next_lyric ? maximum.row_height : measuring_height;
    const HDC measuring=CreateCompatibleDC(nullptr);
    if (!measuring) return false;
    taskbar_lyrics::TextMask current;
    if (reuse_next && next_mask.height==target_row_height && next_mask.shaping && !vertical && next_mask.dpi==dpi) {
      current=next_mask;
      taskbar_lyrics::MapWords(current,text,words);
    } else current=vertical ? taskbar_lyrics::RasterWrappedText(measuring,fonts,text,measuring_width,target_row_height,
        dpi,words,Position(),line_start,line_end) : taskbar_lyrics::RasterText(measuring,fonts,text,measuring_width,target_row_height,
        dpi,target_row_height<measuring_height || animate,words,16,false);
    auto next=target_row_height<measuring_height ? (vertical ?
        taskbar_lyrics::RasterWrappedText(measuring,fonts,next_text,measuring_width,target_row_height,dpi,{},0,0,0) :
        taskbar_lyrics::RasterText(measuring,fonts,next_text,measuring_width,target_row_height,dpi,true,{},16,false)) : taskbar_lyrics::TextMask{};
    DeleteDC(measuring);
    if (!current.shaping && current.pixels.empty()) return false;
    const int natural_width=current.long_text || next.long_text ? measuring_width :
        std::min(measuring_width,std::max(current.natural_width,next.natural_width));
    const int fitted_width=vertical ? available_width : available_width-measuring_width+natural_width;
    SetArea(vertical ? available_area : taskbar_lyrics::FitHorizontalArea(available_area,fitted_width,placement));
    const auto content=taskbar_lyrics::LayoutContent(fitted_width,available_height,dpi,vertical,
        show_pause_indicator,!next_track_text.empty(),show_next_button,
        maximum.metadata.right-maximum.metadata.left);
    if (!vertical && (!taskbar_lyrics::SetTextViewport(current,content.lyrics.right-content.lyrics.left) ||
        !taskbar_lyrics::SetTextViewport(next,content.lyrics.right-content.lyrics.left))) return false;
    ClearBitmap();
    width=fitted_width; height=available_height;
    BITMAPINFO info{}; info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = width; info.bmiHeader.biHeight = -height;
    info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    void* storage = nullptr;
    bitmap = CreateDIBSection(nullptr, &info, DIB_RGB_COLORS, &storage, nullptr, 0);
    dc = CreateCompatibleDC(nullptr);
    if (!bitmap || !dc || !storage) { ClearBitmap(); return false; }
    original = SelectObject(dc, bitmap); pixels = static_cast<std::uint32_t*>(storage);
    button_area=content.button;
    playback_button_area=content.pause;
    lyric_left = content.lyrics.left; lyric_top = content.lyrics.top;
    lyric_width = content.lyrics.right - content.lyrics.left; lyric_height = content.lyrics.bottom - content.lyrics.top;
    metadata_left = content.metadata.left; metadata_top = content.metadata.top;
    metadata_width = content.metadata.right - content.metadata.left; metadata_height = content.metadata.bottom - content.metadata.top;
    row_height = show_next_lyric ? content.row_height : lyric_height;
    // A natural-width change keeps the existing line/word clocks. Only a
    // different row height needs to interrupt that old vertical presentation.
    if (previous_lyric_height && previous_lyric_height != lyric_height) {
      if (!layout_animating) { entering = entrance_pending = false; old_mask = {}; }
      reuse_next = false;
    }
    current_mask=std::move(current);
    reuse_next = false;
    next_mask=std::move(next);
    if (current_mask.pixels.empty()) return false;
    text_width = current_mask.natural_width;
    UpdateForeground();
    // Reflow changes glyph budgets, not the media/read identity. Freeze the
    // existing fallback clock here and resume it after presenting the new
    // viewport; Set owns the reset for a seek, source or line replacement.
    if (scrolling && scroll_start) scroll_elapsed += GetTickCount64() - scroll_start;
    invalid = false; metadata_invalid = true; scrolling = false; scroll_start = 0; return true;
  }
  void RasterMetadata() {
    const int icon=MulDiv(20,dpi,96);
    const int viewport=vertical ? metadata_width : std::max(0,metadata_width-icon);
    if(rendered_metadata_text!=next_track_text || metadata_mask.viewport_width!=viewport || metadata_mask.dpi!=dpi) metadata_read_offset=0;
    rendered_metadata_text=next_track_text;
    metadata_mask = metadata_width && metadata_height ? (vertical ?
        taskbar_lyrics::RasterWrappedText(dc, fonts, next_track_text, metadata_width, std::max(0,metadata_height-icon), dpi, {}, 0, 0, 0, 12) :
        taskbar_lyrics::RasterText(dc, fonts, next_track_text, std::max(0,metadata_width-icon), metadata_height, dpi, true, {}, 12)) : taskbar_lyrics::TextMask{};
    next_track_icon=metadata_width && metadata_height ? taskbar_lyrics::RasterMediaSymbol(taskbar_lyrics::MediaSymbol::kSkipNext,
        vertical ? metadata_width : icon,vertical ? icon : metadata_height,dpi) : taskbar_lyrics::TextMask{};
    metadata_capsule=taskbar_lyrics::RasterMediaCapsule(next_track_icon.width,next_track_icon.height,dpi);
    metadata_invalid = false;
  }
  void UpdateForeground() {
    DWORD light = 0, bytes = sizeof(light);
    RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
        L"SystemUsesLightTheme", RRF_RT_REG_DWORD, nullptr, &light, &bytes);
#ifdef DAN_TASKBAR_LYRICS_NATIVE_QA
    if (system_light_for_testing) light=*system_light_for_testing ? 1 : 0;
#endif
    HIGHCONTRASTW contrast{sizeof(contrast), 0, nullptr};
    const bool high_contrast = SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(contrast), &contrast, 0) &&
        (contrast.dwFlags & HCF_HIGHCONTRASTON) != 0;
    const COLORREF source = RGB((accent >> 16) & 255, (accent >> 8) & 255, accent & 255);
    foreground=taskbar_lyrics::ForegroundForScheme(source,light!=0,high_contrast,GetSysColor(COLOR_BTNTEXT),color_scheme);
    const auto linear = [](BYTE value) { const double channel = value / 255.0; return channel <= .04045 ? channel / 12.92 : std::pow((channel + .055) / 1.055, 2.4); };
    const double luminance = .2126 * linear(GetRValue(foreground)) + .7152 * linear(GetGValue(foreground)) + .0722 * linear(GetBValue(foreground));
    stroke_color = luminance > .45 ? RGB(0, 0, 0) : RGB(255, 255, 255);
    stroke_opacity = high_contrast ? 1 : .9;
  }
  int ReadOffset(const taskbar_lyrics::TextMask& mask, double position) const {
    const int viewport = mask.viewport_width;
    if (mask.natural_width <= viewport) return 0;
    if (!mask.words.empty()) {
      return static_cast<int>(std::clamp(taskbar_lyrics::WordReadPosition(mask, position) - viewport * .45,
          0.0, static_cast<double>(mask.natural_width - viewport)));
    }
    double fraction=taskbar_lyrics::LineReadProgress(position,line_start,line_end);
    if (mask.long_text) {
      const auto range = mask.long_text->chunks[mask.chunk];
      fraction = std::clamp((fraction * mask.long_text->text.size() - range.first) /
          (range.second - range.first), 0.0, 1.0);
    }
    return static_cast<int>(std::round((mask.natural_width - viewport) * fraction));
  }
  void BlendMask(taskbar_lyrics::TextMask& mask, double top, int offset,
                 double opacity, bool highlight, double position) {
    const auto aligned = taskbar_lyrics::ContentOffset(lyric_width, row_height, mask.natural_width,
        taskbar_lyrics::VisibleTextHeight(mask), vertical, placement);
    taskbar_lyrics::CompositeText(pixels, width, height, mask, top + aligned.y, offset,
        opacity, highlight, position, foreground, highlight_columns, lyric_left + aligned.x, lyric_width - aligned.x, stroke_enabled, stroke_color, stroke_opacity,
        lyric_top, lyric_height);
  }
  void Present() {
#ifdef DAN_TASKBAR_LYRICS_NATIVE_QA
    LARGE_INTEGER cpu_start{},cpu_frequency{}; const bool measuring_layout=layout_animating;
    if (measuring_layout) { QueryPerformanceCounter(&cpu_start); QueryPerformanceFrequency(&cpu_frequency); }
#endif
    if (!surface || !pixels || width <= 0 || current_mask.pixels.empty()) return;
    const double position = Position();
    if (current_mask.wrapped) taskbar_lyrics::SelectWrappedPage(current_mask, position, line_start, line_end, dc, fonts);
    else taskbar_lyrics::SelectTextChunk(current_mask, position, line_start, line_end, dc, fonts,
        lyric_width, dpi, row_height < lyric_height || animate);
    int offset = ReadOffset(current_mask, position);
    const auto scroll_offset = [&](const taskbar_lyrics::TextMask& mask) {
      const double seconds = (scroll_elapsed + GetTickCount64() - scroll_start) / 1000.0;
      const double travel = (mask.natural_width - mask.viewport_width) / (30.0 * dpi / 96);
      const double period = travel * 2 + 3;
      const double phase = std::fmod(seconds, period);
      return static_cast<int>(std::clamp(phase < 1.5 + travel ?
          (phase - 1.5) * 30.0 * dpi / 96 :
          (period - phase) * 30.0 * dpi / 96, 0.0, static_cast<double>(mask.natural_width - mask.viewport_width)));
    };
    if(current_mask.words.empty() && !current_mask.long_text && line_end<=line_start && current_mask.overflow) {
      offset=scrolling && scroll_start ? scroll_offset(current_mask) : std::clamp(fallback_read_offset,0,std::max(0,current_mask.natural_width-current_mask.viewport_width));
      fallback_read_offset=offset;
    }
    last_read_offset=offset;
    const double elapsed = entering ? static_cast<double>(GetTickCount64() - entrance_start) : 560;
    const bool rolling = entering && roll_from_next && row_height < lyric_height;
    const auto entrance = taskbar_lyrics::LineEntrance(entering ? elapsed : 180.0);
    const double progress = rolling ? taskbar_lyrics::RowProgress(elapsed) : entrance.opacity;
    memset(pixels, 0, static_cast<size_t>(width) * height * 4);
    const double shift = (1 - progress) * row_height;
    if (entering && !old_mask.pixels.empty())
      BlendMask(old_mask, rolling ? lyric_top + shift - row_height : lyric_top-entrance.opacity*4*dpi/96, 0, rolling ? .98 - .82 * progress :
          1 - entrance.opacity, false, position);
    const double current_top = lyric_top + (rolling ? shift : entrance.dy * dpi / 96);
    BlendMask(current_mask, current_top, offset, rolling ? .46 + .54 * progress : entrance.opacity, true, position);
    BlendMask(next_mask, lyric_top + row_height + shift, 0, .46 * (rolling ? 1 : entrance.opacity), false, position);
    if (metadata_width) {
      const int icon=MulDiv(20,dpi,96);
      if (metadata_mask.wrapped) taskbar_lyrics::SelectWrappedPage(metadata_mask, position, line_start, line_end, dc, fonts);
      else taskbar_lyrics::SelectTextChunk(metadata_mask, position, line_start, line_end, dc, fonts, std::max(0,metadata_width-icon), dpi, true);
      const int metadata_offset=scrolling && scroll_start && metadata_mask.overflow ? scroll_offset(metadata_mask) :
          std::clamp(metadata_read_offset,0,std::max(0,metadata_mask.natural_width-metadata_mask.viewport_width));
      metadata_read_offset=metadata_offset;
      taskbar_lyrics::CompositeText(pixels,width,height,metadata_capsule.fill,metadata_top,0,.12,false,position,foreground,highlight_columns,metadata_left,metadata_capsule.fill.width);
      taskbar_lyrics::CompositeText(pixels,width,height,metadata_capsule.rim,metadata_top,0,.3,false,position,foreground,highlight_columns,metadata_left,metadata_capsule.rim.width);
      taskbar_lyrics::CompositeText(pixels,width,height,next_track_icon,metadata_top,0,.72,false,position,foreground,highlight_columns,
          metadata_left,next_track_icon.width,stroke_enabled,stroke_color,stroke_opacity);
      taskbar_lyrics::CompositeText(pixels, width, height, metadata_mask, metadata_top+(vertical ? icon : 0), metadata_offset, .72, false,
          position, foreground, highlight_columns, metadata_left+(vertical ? 0 : icon), metadata_mask.viewport_width, stroke_enabled, stroke_color, stroke_opacity);
    }
    if (layout_animating) {
      const auto layout_elapsed=GetTickCount64()-layout_start;
      if (!animate_layout || layout_elapsed>=180) FinishLayout();
      else {
        layout_target_pixels.assign(pixels,pixels+static_cast<size_t>(width)*height);
        const RECT clip{lyric_left,lyric_top,lyric_left+lyric_width,lyric_top+lyric_height};
        taskbar_lyrics::CrossfadeLayout(pixels,width,height,previous_layout_pixels,previous_layout_width,previous_layout_height,
            previous_layout_area.left-area.left,previous_layout_area.top-area.top,taskbar_lyrics::LayoutProgress(static_cast<double>(layout_elapsed)),
            layout_dx,layout_dy,layout_target_pixels.data(),&clip,&previous_layout_lyrics);
      }
    }
    POINT destination{area.left, area.top}, origin{}; ScreenToClient(bar,&destination); SIZE size{width, height};
    BLENDFUNCTION blend{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
    const BOOL updated = UpdateLayeredWindow(surface, nullptr, &destination, &size, dc, &origin, 0, &blend, ULW_ALPHA);
#ifdef DAN_TASKBAR_LYRICS_NATIVE_QA
    if (measuring_layout) {
      LARGE_INTEGER cpu_end{}; QueryPerformanceCounter(&cpu_end);
      std::cout << "layout Present CPU microseconds=" << (cpu_end.QuadPart-cpu_start.QuadPart)*1000000.0/cpu_frequency.QuadPart << '\n';
    }
    static int frames = 0;
    if (frames++ < 24 || !updated) {
      std::cout << "ULW=" << updated << " error=" << (updated ? 0 : GetLastError())
          << " currentInk=" << std::count_if(current_mask.pixels.begin(), current_mask.pixels.end(), [](auto x) { return x != 0; })
          << " frameInk=" << std::count_if(pixels, pixels + static_cast<size_t>(width) * height, [](auto x) { return (x >> 24) != 0; })
          << " size=" << width << ',' << height << " xy=" << area.left << ',' << area.top
          << " visible=" << IsWindowVisible(surface) << '\n';
    }
#endif
    if (!updated) Hide();
  }
  void Stop() {
    enabled = false; Hide(); next_button.Close(); playback_button.Close(); Unhook();
    if (controller) KillTimer(controller, kSettle);
    if(controller) KillTimer(controller,kCreateRetry);
    if (worker) {
      std::unique_lock<std::mutex> lock(worker->mutex);
      worker->stopped = true; worker->surface = nullptr; worker->changed.notify_all();
      const bool exited = worker->changed.wait_for(lock, std::chrono::milliseconds(25), [&] { return worker->exited; });
      lock.unlock();
      // UIA can be stalled by a Shell provider. Its bounded COM work has no HWND
      // or Impl access after stop, so shutdown never waits indefinitely.
      if (worker_thread.joinable()) { if (exited) worker_thread.join(); else worker_thread.detach(); }
      worker.reset();
    }
    if (surface) { DestroyWindow(surface); surface = nullptr; }
    if(controller) { DestroyWindow(controller); controller=nullptr; }
    bar = shell_menu = nullptr; geometry = {}; ClearBitmap();
    current_mask = {}; next_mask = {}; old_mask = {}; metadata_mask = {}; metadata_capsule={}; next_track_icon={}; fonts.Clear();
    text.clear(); next_text.clear(); source_identity.clear(); line_identity.clear(); words.clear();
    invalid = true; force_probe = first_frame_pending = reuse_next = false;
  }
};

TaskbarLyrics::TaskbarLyrics() = default;
TaskbarLyrics::~TaskbarLyrics() { Close(); }
bool TaskbarLyrics::Set(bool enabled, std::wstring text, unsigned accent,
                       std::wstring family, std::wstring path, bool animate, bool playing,
                       std::vector<TaskbarLyricWord> words, std::wstring next_text,
                       double position, double rate, std::wstring source, std::wstring line,
                       std::int64_t timeline_revision, double line_start, double line_end,
                       std::wstring placement, std::wstring next_track_text,
                       bool show_pause_indicator, bool stroke_enabled, unsigned area_selection, bool paused,
                       std::wstring color_scheme,bool show_next_button,bool next_button_enabled,bool animate_layout,bool show_next_lyric,bool playback_button_enabled) {
  if (!enabled || text.empty()) { Close(); return true; }
  const auto parsed_placement = taskbar_lyrics::ParsePlacement(placement);
  const auto parsed_color=taskbar_lyrics::ParseColorScheme(color_scheme);
  if (!parsed_placement || !parsed_color || area_selection > 65535) return false;
  if (!impl_) {
    impl_=std::make_unique<Impl>(); impl_->layout_callback=layout_callback_; impl_->next_track_callback=next_track_callback_;
    impl_->playback_callback=playback_callback_; impl_->play_label=play_label_; impl_->pause_label=pause_label_;
    impl_->next_button.SetLabel(next_button_label_);
  }
  auto& self = *impl_;
  if (!std::isfinite(position) || position < 0 || !std::isfinite(rate) || rate <= 0 || rate > 8 ||
      !std::isfinite(line_start) || !std::isfinite(line_end)) return false;
  const bool starting = !self.enabled;
  const bool source_changed = source != self.source_identity;
  const bool line_changed = line != self.line_identity || text != self.text;
  const bool discontinuity = source_changed || timeline_revision != self.timeline_revision ||
      std::abs(position - self.Position()) > 750;
  const double previous_position = self.Position();
  // Transport intents revise the timeline too. Pausing/resuming this exact
  // line freezes its fallback reading clock; a seek or new line resets it.
  const bool transport_switch=!source_changed && !line_changed && self.playing!=playing &&
      std::abs(position-previous_position)<=100;
  const bool family_changed = self.fonts.Configure(std::move(family), std::move(path));
  if(family_changed) self.metadata_read_offset=0;
  const bool row_mode_changed=self.show_next_lyric!=show_next_lyric;
  if((discontinuity && !transport_switch) || line_changed) {
    self.fallback_read_offset=0; self.scroll_elapsed=0;
    self.scrolling=false; self.scroll_start=0;
  }
  if (row_mode_changed && animate_layout && !discontinuity && !family_changed && self.enabled && self.pixels &&
      IsWindowVisible(self.surface) && static_cast<size_t>(self.width)*self.height<=1024*1024) self.BeginLayout();
  self.reuse_next = line_changed && !family_changed && self.next_text == text &&
      !self.next_mask.pixels.empty() && text.size() <= 2048;
  if (line_changed && !discontinuity && !family_changed && self.animate && animate && playing && self.row_height) {
    self.old_mask = self.current_mask;
    self.roll_from_next = self.next_text == text;
    self.entrance_pending = true;
  } else if (discontinuity || family_changed || !animate || !playing) {
    self.entering = self.entrance_pending = false; self.old_mask = {}; self.roll_from_next = false;
    if(transport_switch && self.scroll_start) self.scroll_elapsed+=GetTickCount64()-self.scroll_start;
    self.scrolling = false; self.scroll_start = 0;
  }
  const bool words_changed = words.size() != self.words.size() ||
      !std::equal(words.begin(), words.end(), self.words.begin(), self.words.end(), [](const auto& a, const auto& b) {
        return a.start == b.start && a.length == b.length && a.content == b.content;
      });
  self.invalid |= line_changed || self.animate != animate || family_changed || next_text != self.next_text ||
      (words_changed && (text.size() > 2048 || self.vertical)) ||
      show_pause_indicator != self.show_pause_indicator || next_track_text.empty() != self.next_track_text.empty() || show_next_button!=self.show_next_button || row_mode_changed;
  self.metadata_invalid |= next_track_text != self.next_track_text || family_changed || show_pause_indicator != self.show_pause_indicator;
  if (words_changed && !self.invalid) taskbar_lyrics::MapWords(self.current_mask, text, words);
  self.enabled = true;
  if (!self.Open()) { self.Stop(); return false; }
  for (auto& character : text) if (character < L' ' || character == 0x7f) character = L' ';
  for (auto& character : next_text) if (character < L' ' || character == 0x7f) character = L' ';
  for (auto& character : next_track_text) if (character < L' ' || character == 0x7f) character = L' ';
  self.text = std::move(text); self.next_text = std::move(next_text); self.words = std::move(words);
  self.source_identity = std::move(source); self.line_identity = std::move(line);
  self.placement = *parsed_placement; self.area_selection = area_selection;
  self.next_track_text = std::move(next_track_text); self.show_pause_indicator = show_pause_indicator;
  self.stroke_enabled = stroke_enabled; self.paused = paused;
  self.color_scheme=*parsed_color; self.show_next_button=show_next_button; self.next_button_enabled=next_button_enabled;
  self.playback_button_enabled=playback_button_enabled;
  self.animate_layout=animate_layout;
  self.show_next_lyric=show_next_lyric;
  if (!animate_layout || discontinuity || family_changed) self.FinishLayout();
  if (!show_next_button) self.next_button.Close();
  if(!show_pause_indicator) self.playback_button.Close();
  self.accent = accent; self.animate = animate; self.playing = playing;
  self.UpdateForeground();
  self.first_frame_pending |= starting && animate && playing;
  self.correction = !discontinuity && !line_changed && animate && playing ?
      std::clamp(previous_position - position, -100.0, 100.0) : 0;
  self.anchor_position = position; self.playback_rate = rate; self.anchor_tick = GetTickCount64();
  self.timeline_revision = timeline_revision; self.line_start = line_start; self.line_end = line_end;
  self.layout_reset_pending=starting || discontinuity || family_changed;
  self.Refresh(starting);
  self.layout_reset_pending=false;
  return true;
}
void TaskbarLyrics::EnvironmentChanged() {
  if (!impl_) return;
  impl_->UpdateForeground(); impl_->Refresh(true);
}
bool TaskbarLyrics::IsVerticalLayout() {
  RECT bounds{};
  const HWND bar = FindWindowW(L"Shell_TrayWnd", nullptr);
  return bar && GetWindowRect(bar, &bounds) && bounds.bottom - bounds.top > bounds.right - bounds.left;
}
TaskbarLyricsLayout TaskbarLyrics::GetLayout() const {
  auto value = impl_ ? impl_->layout : TaskbarLyricsLayout{};
  value.vertical = IsVerticalLayout();
  return value;
}
void TaskbarLyrics::SetLayoutCallback(std::function<void(const TaskbarLyricsLayout&)> callback) {
  layout_callback_ = std::move(callback);
  if (impl_) impl_->layout_callback = layout_callback_;
}
void TaskbarLyrics::SetNextTrackCallback(std::function<void()> callback) {
  next_track_callback_=std::move(callback);
  if (impl_) impl_->next_track_callback=next_track_callback_;
}
void TaskbarLyrics::SetNextButtonLabel(std::wstring label) {
  next_button_label_=std::move(label);
  if (impl_) impl_->next_button.SetLabel(next_button_label_);
}
void TaskbarLyrics::SetPlaybackCallback(std::function<void()> callback) {
  playback_callback_=std::move(callback); if(impl_) impl_->playback_callback=playback_callback_;
}
void TaskbarLyrics::SetPlaybackButtonLabels(std::wstring play,std::wstring pause) {
  play_label_=std::move(play); pause_label_=std::move(pause);
  if(impl_) {
    impl_->play_label=play_label_; impl_->pause_label=pause_label_;
    impl_->playback_button.SetLabel(impl_->playing ? pause_label_ : play_label_);
  }
}
#ifdef DAN_TASKBAR_LYRICS_NATIVE_QA
void TaskbarLyrics::FailNextGeometryForTesting(unsigned count) {
  if (impl_ && impl_->worker) { std::lock_guard<std::mutex> guard(impl_->worker->mutex); impl_->worker->fail_reads=count; }
}
void TaskbarLyrics::AddOccupiedAreaForTesting(RECT occupied) {
  if (impl_ && impl_->geometry.valid) { impl_->geometry.occupied.push_back(occupied); impl_->Refresh(false); }
}
bool TaskbarLyrics::LayoutAnimatingForTesting() const { return impl_ && impl_->layout_animating; }
unsigned TaskbarLyrics::GeometryRequestsForTesting() const {
  if (!impl_ || !impl_->worker) return 0;
  std::lock_guard<std::mutex> guard(impl_->worker->mutex); return impl_->worker->revision;
}
unsigned TaskbarLyrics::RasterCountForTesting() const { return impl_ ? impl_->raster_count : 0; }
ULONGLONG TaskbarLyrics::LineAnimationStartForTesting() const { return impl_ ? impl_->entrance_start : 0; }
void TaskbarLyrics::SetSystemLightForTesting(bool light) { if (impl_) impl_->system_light_for_testing=light; }
std::vector<std::uint32_t> TaskbarLyrics::PixelsForTesting() const {
  if (!impl_ || !impl_->pixels) return {};
  return std::vector<std::uint32_t>(impl_->pixels,impl_->pixels+static_cast<size_t>(impl_->width)*impl_->height);
}
size_t TaskbarLyrics::LayoutBufferPixelsForTesting() const {
  return impl_ ? impl_->previous_layout_pixels.capacity()+impl_->layout_target_pixels.capacity() : 0;
}
bool TaskbarLyrics::LineAnimatingForTesting() const { return impl_ && impl_->entering; }
int TaskbarLyrics::ReadOffsetForTesting() const { return impl_ ? impl_->last_read_offset : 0; }
int TaskbarLyrics::MetadataOffsetForTesting() const { return impl_ ? impl_->metadata_read_offset : 0; }
unsigned TaskbarLyrics::MotionFramesForTesting() const { return impl_ ? impl_->motion_frames : 0; }
int TaskbarLyrics::CurrentChunkForTesting() const { return impl_ ? impl_->current_mask.chunk : 0; }
taskbar_lyrics::ContentLayout TaskbarLyrics::ContentForTesting() const {
  taskbar_lyrics::ContentLayout result;
  if(impl_) {
    result.vertical=impl_->vertical;
    result.lyrics=RECT{impl_->lyric_left,impl_->lyric_top,impl_->lyric_left+impl_->lyric_width,impl_->lyric_top+impl_->lyric_height};
    result.metadata=RECT{impl_->metadata_left,impl_->metadata_top,impl_->metadata_left+impl_->metadata_width,impl_->metadata_top+impl_->metadata_height};
    result.pause=impl_->playback_button_area; result.button=impl_->button_area; result.row_height=impl_->row_height;
  }
  return result;
}
int TaskbarLyrics::NaturalWidthForTesting(bool next) const {
  return impl_ ? (next ? impl_->next_mask : impl_->current_mask).natural_width : 0;
}
const void* TaskbarLyrics::ShapingForTesting(bool next) const {
  return impl_ ? (next ? impl_->next_mask : impl_->current_mask).shaping.get() : nullptr;
}
void TaskbarLyrics::SetPositionForTesting(double position){if(impl_){impl_->position_for_testing=position;impl_->Present();}}
void TaskbarLyrics::UseBarForTesting(HWND bar,std::vector<RECT> occupied) {
  if(!impl_) return;
  Geometry geometry; geometry.bar=bar; geometry.valid=IsWindow(bar) && GetWindowRect(bar,&geometry.bar_rect) && !occupied.empty();
  geometry.occupied=std::move(occupied); impl_->geometry_for_testing=std::move(geometry); impl_->Refresh(false);
}
#endif
void TaskbarLyrics::Close() {
  if (impl_) {
    impl_->layout_callback = nullptr;
    impl_->Stop(); impl_.reset();
    if (layout_callback_) layout_callback_(GetLayout());
  }
}
