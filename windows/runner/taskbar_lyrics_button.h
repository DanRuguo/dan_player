#ifndef RUNNER_TASKBAR_LYRICS_BUTTON_H_
#define RUNNER_TASKBAR_LYRICS_BUTTON_H_
#include "taskbar_lyrics_paint.h"
#include "taskbar_lyrics_policy.h"
#include <UIAutomation.h>
#include <atomic>
#include <functional>
#include <mutex>
#ifdef DAN_TASKBAR_LYRICS_NATIVE_QA
#include <iostream>
#endif

namespace taskbar_lyrics {
struct ButtonAccessibilityState {
  std::atomic<HWND> window{nullptr};
  std::atomic<bool> enabled{false};
  std::mutex mutex;
  std::wstring label;
  std::atomic<ULONG_PTR> epoch{0};
};
inline ULONG_PTR NextButtonToken(){static std::atomic<ULONG_PTR> next{1}; return next.fetch_add(1);}
constexpr UINT kInvokeNextButton = WM_APP + 0x625;
class NextButtonProvider final : public IRawElementProviderSimple, public IInvokeProvider {
 public:
  explicit NextButtonProvider(std::shared_ptr<ButtonAccessibilityState> state) : state_(std::move(state)) {}
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid,void** result) override {
    if (!result) return E_POINTER;
    *result = nullptr;
    if (iid==__uuidof(IUnknown) || iid==__uuidof(IRawElementProviderSimple)) *result=static_cast<IRawElementProviderSimple*>(this);
    else if (iid==__uuidof(IInvokeProvider)) *result=static_cast<IInvokeProvider*>(this);
    else return E_NOINTERFACE;
    AddRef(); return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++references_; }
  ULONG STDMETHODCALLTYPE Release() override { const auto value=--references_; if (!value) delete this; return value; }
  HRESULT STDMETHODCALLTYPE get_ProviderOptions(ProviderOptions* result) override {
    if (!result) return E_POINTER;
    *result=ProviderOptions_ServerSideProvider;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetPatternProvider(PATTERNID id,IUnknown** result) override {
    if (!result) return E_POINTER; *result=nullptr;
    if (id==UIA_InvokePatternId) { *result=static_cast<IInvokeProvider*>(this); AddRef(); }
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetPropertyValue(PROPERTYID id,VARIANT* result) override {
    if (!result) return E_POINTER; VariantInit(result);
    if (!state_->window.load()) return UIA_E_ELEMENTNOTAVAILABLE;
    if (id==UIA_ControlTypePropertyId) { result->vt=VT_I4; result->lVal=UIA_ButtonControlTypeId; }
    else if (id==UIA_NamePropertyId) {
      std::lock_guard<std::mutex> guard(state_->mutex);
      result->vt=VT_BSTR; result->bstrVal=SysAllocString(state_->label.c_str());
      if (!result->bstrVal) return E_OUTOFMEMORY;
    } else if (id==UIA_IsEnabledPropertyId || id==UIA_IsControlElementPropertyId || id==UIA_IsContentElementPropertyId || id==UIA_IsKeyboardFocusablePropertyId) {
      result->vt=VT_BOOL;
      result->boolVal=(id==UIA_IsEnabledPropertyId ? state_->enabled.load() : id!=UIA_IsKeyboardFocusablePropertyId) ? VARIANT_TRUE : VARIANT_FALSE;
    }
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE get_HostRawElementProvider(IRawElementProviderSimple** result) override {
    if (!result) return E_POINTER; *result=nullptr;
    const auto window=state_->window.load();
    return window ? UiaHostProviderFromHwnd(window,result) : UIA_E_ELEMENTNOTAVAILABLE;
  }
  HRESULT STDMETHODCALLTYPE Invoke() override {
    const auto epoch=state_->epoch.load();
    const auto window=state_->window.load();
    if (!window) return UIA_E_ELEMENTNOTAVAILABLE;
    if (!state_->enabled.load()) return UIA_E_ELEMENTNOTENABLED;
    return PostMessageW(window,kInvokeNextButton,epoch,0) ? S_OK : UIA_E_ELEMENTNOTAVAILABLE;
  }
 private:
  std::atomic<ULONG> references_{1};
  std::shared_ptr<ButtonAccessibilityState> state_;
};

// Only this small taskbar child accepts input. The entire lyric surface keeps
// WS_EX_TRANSPARENT, including its metadata. No global hooks or animation clock.
class TaskbarMediaButton {
 public:
  explicit TaskbarMediaButton(const wchar_t* class_name=L"DanPlayer.TaskbarLyrics.Next.v1") : class_name_(class_name) {}
  ~TaskbarMediaButton() { Close(); }
  void SetLabel(const std::wstring& label) {
    label_=label;
    if (accessibility_) { std::lock_guard<std::mutex> guard(accessibility_->mutex); accessibility_->label=label; }
  }
  void SetCallback(std::function<void()> callback) { callback_=std::move(callback); }
  void SetRestoreCallback(std::function<void()> callback) { restore_callback_=std::move(callback); }
  void SetSymbol(MediaSymbol symbol) {
    if(symbol_kind_!=symbol) {
      if(accessibility_) accessibility_->epoch=NextButtonToken();
      symbol_kind_=symbol; symbol_={}; if(window_ && IsWindowVisible(window_)) Paint();
    }
  }
#ifdef DAN_TASKBAR_LYRICS_NATIVE_QA
  IInvokeProvider* InvokeProviderForTesting(){if(provider_) provider_->AddRef(); return provider_;}
#endif
  HWND window() const { return window_; }
  void Hide() {
    if (window_) { if (GetCapture()==window_) ReleaseCapture(); ShowWindow(window_,SW_HIDE); }
    hovered_=pressed_=false;
    if (accessibility_) { accessibility_->epoch=NextButtonToken(); accessibility_->enabled=false; }
  }
  void Close() {
    Hide();
    if (accessibility_) { accessibility_->window=nullptr; accessibility_->enabled=false; }
    if (window_) { DestroyWindow(window_); window_=nullptr; }
    if (provider_) { provider_->Release(); provider_=nullptr; }
    accessibility_.reset(); ClearBitmap(); symbol_={};
  }
  bool Show(HWND owner,RECT area,UINT dpi,COLORREF foreground,bool enabled,bool stroke,COLORREF stroke_color,double stroke_opacity) {
    if (area.right<=area.left || area.bottom<=area.top) { Hide(); return true; }
    if (!window_) {
      ScopedParentDpi context(owner); if(!context.valid()) return false;
      WNDCLASSW cls{}; cls.hInstance=GetModuleHandleW(nullptr); cls.lpszClassName=class_name_;
      cls.lpfnWndProc=WindowProc; cls.hCursor=LoadCursorW(nullptr,IDC_ARROW);
      if (!RegisterClassW(&cls) && GetLastError()!=ERROR_CLASS_ALREADY_EXISTS) return false;
      POINT location{area.left,area.top}; ScreenToClient(owner,&location);
      window_=CreateWindowExW(WS_EX_LAYERED|WS_EX_NOACTIVATE|WS_EX_NOPARENTNOTIFY,
          cls.lpszClassName,L"",WS_CHILD,location.x,location.y,area.right-area.left,area.bottom-area.top,owner,nullptr,cls.hInstance,this);
      if (!window_) return false;
      accessibility_=std::make_shared<ButtonAccessibilityState>();
      accessibility_->epoch=NextButtonToken(); accessibility_->window=window_; accessibility_->label=label_;
      provider_=new NextButtonProvider(accessibility_);
    }
    const bool changed=!EqualRect(&area_,&area) || dpi_!=dpi || foreground_!=foreground || enabled_!=enabled ||
        stroke_!=stroke || stroke_color_!=stroke_color || stroke_opacity_!=stroke_opacity;
    area_=area; dpi_=dpi; foreground_=foreground; enabled_=enabled; stroke_=stroke; stroke_color_=stroke_color; stroke_opacity_=stroke_opacity;
    if(!enabled && accessibility_->enabled.load()) accessibility_->epoch=NextButtonToken();
    accessibility_->enabled=enabled;
    if (!enabled && GetCapture()==window_) { ReleaseCapture(); pressed_=false; }
    if ((changed || !IsWindowVisible(window_)) && !Paint()) { Close(); return false; }
    if (!IsWindowVisible(window_) || GetWindow(window_,GW_HWNDPREV)) return SetWindowPos(window_,HWND_TOP,0,0,0,0,SWP_NOACTIVATE|SWP_NOMOVE|SWP_NOSIZE|SWP_SHOWWINDOW)!=FALSE;
    return true;
  }
 private:
  const wchar_t* class_name_;
  MediaSymbol symbol_kind_=MediaSymbol::kSkipNext;
  MediaCapsule capsule_;
  HWND window_=nullptr;
  RECT area_{};
  UINT dpi_=96;
  bool enabled_=false,hovered_=false,pressed_=false,focused_=false,stroke_=false;
  COLORREF foreground_=RGB(0,0,0),stroke_color_=RGB(0,0,0);
  double stroke_opacity_=.9;
  std::wstring label_=L"Next track";
  std::function<void()> callback_;
  std::function<void()> restore_callback_;
  std::shared_ptr<ButtonAccessibilityState> accessibility_;
  NextButtonProvider* provider_=nullptr;
  HDC dc_=nullptr;
  HBITMAP bitmap_=nullptr;
  HGDIOBJ original_=nullptr;
  std::uint32_t* pixels_=nullptr;
  int width_=0,height_=0;
  TextMask symbol_;
  std::vector<unsigned char> highlights_;
  void ClearBitmap() {
    if (dc_ && original_) SelectObject(dc_,original_);
    if (dc_) DeleteDC(dc_);
    if (bitmap_) DeleteObject(bitmap_);
    dc_=nullptr; bitmap_=nullptr; original_=nullptr; pixels_=nullptr; width_=height_=0;
  }
  bool Paint() {
    const int width=area_.right-area_.left,height=area_.bottom-area_.top;
    if (width!=width_ || height!=height_ || capsule_.fill.dpi!=dpi_ || !pixels_) {
      ClearBitmap(); width_=width; height_=height;
      BITMAPINFO info{}; info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);
      info.bmiHeader.biWidth=width; info.bmiHeader.biHeight=-height; info.bmiHeader.biPlanes=1; info.bmiHeader.biBitCount=32;
      void* data=nullptr; bitmap_=CreateDIBSection(nullptr,&info,DIB_RGB_COLORS,&data,nullptr,0); dc_=CreateCompatibleDC(nullptr);
      if (!bitmap_ || !dc_ || !data) { ClearBitmap(); return false; }
      original_=SelectObject(dc_,bitmap_); pixels_=static_cast<std::uint32_t*>(data);
      capsule_=RasterMediaCapsule(width,height,dpi_);
      symbol_={};
    }
    if(symbol_.pixels.empty()) symbol_=RasterMediaSymbol(symbol_kind_,width,height,dpi_,24);
    std::fill(pixels_,pixels_+static_cast<size_t>(width)*height,0x01000000);
    const double background=enabled_ ? (pressed_ ? .25 : hovered_ || focused_ ? .18 : .12) : .06;
    CompositeText(pixels_,width,height,capsule_.fill,0,0,background,false,0,foreground_,highlights_);
    CompositeText(pixels_,width,height,capsule_.rim,0,0,enabled_ ? .3 : .12,false,0,foreground_,highlights_);
    CompositeText(pixels_,width,height,symbol_,0,0,enabled_ ? 1 : .38,false,0,foreground_,highlights_,0,width,stroke_,stroke_color_,stroke_opacity_);
    POINT destination{area_.left,area_.top},origin{}; ScreenToClient(GetParent(window_),&destination);
    SIZE size{width,height}; BLENDFUNCTION blend{AC_SRC_OVER,0,255,AC_SRC_ALPHA};
    return UpdateLayeredWindow(window_,nullptr,&destination,&size,dc_,&origin,0,&blend,ULW_ALPHA)!=FALSE;
  }
  void Invoke() { if (enabled_ && window_ && IsWindowVisible(window_) && callback_) callback_(); }
  static LRESULT CALLBACK WindowProc(HWND hwnd,UINT message,WPARAM wp,LPARAM lp) {
    auto* self=reinterpret_cast<TaskbarMediaButton*>(GetWindowLongPtrW(hwnd,GWLP_USERDATA));
    if (message==WM_NCCREATE) { self=static_cast<TaskbarMediaButton*>(reinterpret_cast<CREATESTRUCTW*>(lp)->lpCreateParams); SetWindowLongPtrW(hwnd,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(self)); }
    if (!self) return DefWindowProcW(hwnd,message,wp,lp);
#ifdef DAN_TASKBAR_LYRICS_NATIVE_QA
    if(message==WM_MOUSEACTIVATE || message==WM_LBUTTONDOWN || (message==WM_MOUSEMOVE && !self->hovered_)) {
      wchar_t name[128]{}; GetClassNameW(GetForegroundWindow(),name,128);
      std::wcout<<L"button message="<<message<<L" foreground="<<name<<L"\n";
    }
#endif
    if(message==WM_NCDESTROY) {
      if(self->accessibility_) { self->accessibility_->window=nullptr; self->accessibility_->enabled=false; }
      self->window_=nullptr; return DefWindowProcW(hwnd,message,wp,lp);
    }
    if (message==WM_MOUSEACTIVATE) return MA_NOACTIVATE;
    if (message==WM_NCHITTEST) return HTCLIENT;
    if (message==WM_GETOBJECT && static_cast<LONG>(lp)==UiaRootObjectId && self->provider_)
      return UiaReturnRawElementProvider(hwnd,wp,lp,self->provider_);
    if (message==kInvokeNextButton) {
      if (self->accessibility_ && wp==self->accessibility_->epoch) self->Invoke(); return 0;
    }
    if (message==WM_MOUSEMOVE) {
      if (!self->hovered_) { self->hovered_=true; TRACKMOUSEEVENT track{sizeof(track),TME_LEAVE,hwnd,0}; TrackMouseEvent(&track); self->Paint(); }
      return 0;
    }
    if (message==WM_MOUSELEAVE) { self->hovered_=false; self->Paint(); return 0; }
    if (message==WM_LBUTTONDOWN) {
      if (self->enabled_) { self->pressed_=true; SetCapture(hwnd); self->Paint(); }
      return 0;
    }
    if (message==WM_LBUTTONUP) {
      const bool pressed=self->pressed_; self->pressed_=false;
      if (GetCapture()==hwnd) ReleaseCapture();
      POINT point{static_cast<short>(LOWORD(lp)),static_cast<short>(HIWORD(lp))}; RECT bounds{}; GetClientRect(hwnd,&bounds);
      self->Paint(); if (pressed && PtInRect(&bounds,point)) self->Invoke(); return 0;
    }
    if (message==WM_CAPTURECHANGED || message==WM_CANCELMODE) { self->pressed_=false; self->Paint(); return 0; }
    if (message==WM_SETFOCUS || message==WM_KILLFOCUS) { self->focused_=message==WM_SETFOCUS; self->pressed_=false; self->Paint(); return 0; }
    if (message==WM_KEYDOWN && (wp==VK_SPACE || wp==VK_RETURN)) { self->pressed_=self->enabled_; self->Paint(); return 0; }
    if (message==WM_KEYUP && (wp==VK_SPACE || wp==VK_RETURN)) { const bool pressed=self->pressed_; self->pressed_=false; self->Paint(); if (pressed) self->Invoke(); return 0; }
    if (message==WM_RBUTTONUP) {
      POINT point{static_cast<short>(LOWORD(lp)),static_cast<short>(HIWORD(lp))}; ClientToScreen(hwnd,&point);
      const HWND bar=FindWindowW(L"Shell_TrayWnd",nullptr);
      self->Hide();
      const HWND underneath=WindowFromPoint(point);
      POINT cursor{};
      if (bar && (underneath==bar || IsChild(bar,underneath)) && GetCursorPos(&cursor) && cursor.x==point.x && cursor.y==point.y) {
        // XAML taskbars do not handle synthetic WM_CONTEXTMENU/WM_RBUTTONUP.
        // Restore this exact physical right-click to the now exposed taskbar,
        // without moving the cursor or routing any left-click to Explorer.
        INPUT input[2]{}; input[0].type=input[1].type=INPUT_MOUSE;
        input[0].mi.dwFlags=MOUSEEVENTF_RIGHTDOWN; input[1].mi.dwFlags=MOUSEEVENTF_RIGHTUP;
        const auto sent=SendInput(2,input,sizeof(INPUT));
        if (sent==1) SendInput(1,&input[1],sizeof(INPUT)); // release a partially accepted right-down; never retry its action
      }
      if (self->restore_callback_) self->restore_callback_();
      return 0;
    }
    return DefWindowProcW(hwnd,message,wp,lp);
  }
};
using NextTrackButton = TaskbarMediaButton;
} // namespace taskbar_lyrics
#endif
