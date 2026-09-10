#include "../window_resize_bridge.h"
#include "../window_resize_policy.h"

#include <array>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>

namespace {

constexpr wchar_t kParentClass[] = L"DanResizeBridgeTestParent";
constexpr wchar_t kChildClass[] = L"DanResizeBridgeTestChild";
constexpr UINT kForwardedMessage = WM_APP + 17;
constexpr LRESULT kForwardedResult = 0x5721;

class Checks {
 public:
  void Check(const std::string& name, bool passed) {
    ++total_;
    if (!passed) ++failures_;
    std::cout << (passed ? "PASS " : "FAIL ") << name << '\n';
  }

  int Finish() const {
    std::cout << "Window resize bridge: " << total_ - failures_ << '/'
              << total_ << " passed\n";
    return failures_ == 0 ? 0 : 1;
  }

 private:
  int total_ = 0;
  int failures_ = 0;
};

struct WindowState {
  int border_x = 8;
  int border_y = 8;
  int hit_calls = 0;
  int click_calls = 0;
  int forwarded_calls = 0;
  int child_destroy_calls = 0;
  bool override_parent_hit = false;
  LRESULT parent_hit = HTCLIENT;
};

WindowState* GetState(HWND window, UINT message, LPARAM lparam) {
  auto* state = reinterpret_cast<WindowState*>(
      GetWindowLongPtrW(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    state = static_cast<WindowState*>(
        reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams);
    SetWindowLongPtrW(window, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(state));
  }
  return state;
}

LRESULT CALLBACK ParentProc(HWND window, UINT message, WPARAM wparam,
                            LPARAM lparam) {
  auto* state = GetState(window, message, lparam);
  if (message == WM_NCCALCSIZE && wparam) return 0;
  if (state && message == WM_NCHITTEST) {
    ++state->hit_calls;
    if (state->override_parent_hit) return state->parent_hit;
    RECT bounds{};
    GetWindowRect(window, &bounds);
    const POINT point{static_cast<SHORT>(LOWORD(lparam)),
                      static_cast<SHORT>(HIWORD(lparam))};
    return window_resize::HitTestResizeBorder(
               bounds, point, state->border_x, state->border_y)
        .value_or(HTCLIENT);
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

LRESULT CALLBACK ChildProc(HWND window, UINT message, WPARAM wparam,
                           LPARAM lparam) {
  auto* state = GetState(window, message, lparam);
  if (state) {
    if (message == WM_NCHITTEST) return HTCLIENT;
    if (message == WM_LBUTTONDOWN) {
      ++state->click_calls;
      return 37;
    }
    if (message == kForwardedMessage) {
      ++state->forwarded_calls;
      return wparam == 123 && lparam == 456 ? kForwardedResult : 0;
    }
    if (message == WM_NCDESTROY) ++state->child_destroy_calls;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

void RegisterTestClasses() {
  WNDCLASSW parent{};
  parent.lpfnWndProc = ParentProc;
  parent.hInstance = GetModuleHandleW(nullptr);
  parent.lpszClassName = kParentClass;
  WNDCLASSW child = parent;
  child.lpfnWndProc = ChildProc;
  child.lpszClassName = kChildClass;
  if (!RegisterClassW(&parent) || !RegisterClassW(&child)) {
    throw std::runtime_error("test window classes could not be registered");
  }
}

struct HitPoint {
  POINT point;
  LRESULT expected;
};

class Fixture {
 public:
  Fixture() {
    parent = CreateWindowExW(0, kParentClass, L"Hidden resize bridge parent",
                             WS_OVERLAPPEDWINDOW, 100, 120, 480, 320, nullptr,
                             nullptr, GetModuleHandleW(nullptr), &state);
    if (!parent) throw std::runtime_error("hidden parent creation failed");
    SetWindowPos(parent, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                     SWP_FRAMECHANGED);
    RECT client{};
    GetClientRect(parent, &client);
    child = CreateWindowExW(0, kChildClass, L"Hidden resize bridge child",
                            WS_CHILD | WS_VISIBLE, 0, 0, client.right,
                            client.bottom, parent, nullptr,
                            GetModuleHandleW(nullptr), &state);
    if (!child) {
      DestroyWindow(parent);
      throw std::runtime_error("hidden child creation failed");
    }
  }

  ~Fixture() {
    if (IsWindow(parent)) DestroyWindow(parent);
  }

  Fixture(const Fixture&) = delete;
  Fixture& operator=(const Fixture&) = delete;

  RECT Bounds() const {
    RECT result{};
    GetWindowRect(parent, &result);
    return result;
  }

  std::array<HitPoint, 8> Edges(int inset) const {
    const auto r = Bounds();
    const LONG middle_x = (r.left + r.right) / 2;
    const LONG middle_y = (r.top + r.bottom) / 2;
    const LONG left = r.left + inset;
    const LONG right = r.right - 1 - inset;
    const LONG top = r.top + inset;
    const LONG bottom = r.bottom - 1 - inset;
    return {{{{left, middle_y}, HTLEFT},
             {{right, middle_y}, HTRIGHT},
             {{middle_x, top}, HTTOP},
             {{middle_x, bottom}, HTBOTTOM},
             {{left, top}, HTTOPLEFT},
             {{right, top}, HTTOPRIGHT},
             {{left, bottom}, HTBOTTOMLEFT},
             {{right, bottom}, HTBOTTOMRIGHT}}};
  }

  POINT Center() const {
    const auto r = Bounds();
    return {(r.left + r.right) / 2, (r.top + r.bottom) / 2};
  }

  WindowState state;
  HWND parent = nullptr;
  HWND child = nullptr;
};

LRESULT Hit(HWND window, POINT point) {
  return SendMessageW(window, WM_NCHITTEST, 0,
                       MAKELPARAM(static_cast<SHORT>(point.x),
                                  static_cast<SHORT>(point.y)));
}

void CheckHitRouting(Checks& checks) {
  Fixture fixture;
  RECT child_bounds{};
  GetWindowRect(fixture.child, &child_bounds);
  const RECT parent_bounds = fixture.Bounds();
  checks.Check("fixture child covers every parent border",
               EqualRect(&child_bounds, &parent_bounds) != FALSE);
  checks.Check("fixture does not display any window",
               !IsWindowVisible(fixture.parent) &&
                   !IsWindowVisible(fixture.child));
  bool reproduces = true;
  for (const auto& sample : fixture.Edges(2)) {
    reproduces = reproduces &&
        Hit(fixture.parent, sample.point) == sample.expected &&
        Hit(fixture.child, sample.point) == HTCLIENT;
  }
  checks.Check("unbridged child swallows all eight parent resize hits",
               reproduces);

  window_resize::ChildResizeBridge bridge(fixture.parent, fixture.child);
  checks.Check("same-thread direct child attaches", bridge.attached());
  for (int dpi : {96, 144, 192}) {
    fixture.state.border_x = MulDiv(8, dpi, 96);
    fixture.state.border_y = MulDiv(8, dpi, 96);
    for (int inset : {2, fixture.state.border_x - 1}) {
      bool all_routed = true;
      for (const auto& sample : fixture.Edges(inset)) {
        all_routed = all_routed &&
            Hit(fixture.parent, sample.point) == sample.expected &&
            Hit(fixture.child, sample.point) == HTTRANSPARENT;
      }
      checks.Check("all eight child edges route to parent at " +
                       std::to_string(dpi) + " DPI, inset " +
                       std::to_string(inset),
                   all_routed);
    }
  }
  checks.Check("client interior remains ordinary child hit",
               Hit(fixture.child, fixture.Center()) == HTCLIENT);
  checks.Check("client clicks still reach original child procedure",
               SendMessageW(fixture.child, WM_LBUTTONDOWN, MK_LBUTTON,
                              MAKELPARAM(40, 40)) == 37 &&
                   fixture.state.click_calls == 1);
  checks.Check("unrelated message and parameters forward unchanged",
               SendMessageW(fixture.child, kForwardedMessage, 123, 456) ==
                       kForwardedResult &&
                   fixture.state.forwarded_calls == 1);

  // No input or message pump occurs while this hidden test child owns capture.
  SetCapture(fixture.child);
  const bool captured = GetCapture() == fixture.child;
  const LRESULT captured_hit = Hit(fixture.child, fixture.Edges(2)[0].point);
  ReleaseCapture();
  checks.Check("Flutter drag capture retains ordinary child edge handling",
               captured && captured_hit == HTCLIENT);
  checks.Check("releasing Flutter capture restores native edge routing",
               GetCapture() != fixture.child &&
                   Hit(fixture.child, fixture.Edges(2)[0].point) == HTTRANSPARENT);

  fixture.state.override_parent_hit = true;
  const POINT edge = fixture.Edges(2)[0].point;
  for (LRESULT hit : {HTNOWHERE, HTCLIENT, HTCAPTION, HTCLOSE, HTTRANSPARENT}) {
    fixture.state.parent_hit = hit;
    checks.Check("parent non-resize hit " + std::to_string(hit) +
                     " cannot make child transparent",
                 Hit(fixture.child, edge) == HTCLIENT);
  }
  fixture.state.parent_hit = HTNOWHERE;
  checks.Check("plugin size lock blocks resize even with thick-frame style",
               (GetWindowLongPtrW(fixture.parent, GWL_STYLE) & WS_THICKFRAME) &&
                   Hit(fixture.child, edge) == HTCLIENT);

  fixture.state.parent_hit = HTLEFT;
  const LONG_PTR normal_style = GetWindowLongPtrW(fixture.parent, GWL_STYLE);
  SetWindowLongPtrW(fixture.parent, GWL_STYLE,
                    normal_style & ~WS_THICKFRAME);
  checks.Check("native size lock blocks even a parent resize result",
               Hit(fixture.child, edge) == HTCLIENT);
  SetWindowLongPtrW(fixture.parent, GWL_STYLE,
                    normal_style & ~(WS_THICKFRAME | WS_MAXIMIZEBOX));
  checks.Check("fullscreen style cannot leak resize through child",
               Hit(fixture.child, edge) == HTCLIENT);
  SetWindowLongPtrW(fixture.parent, GWL_STYLE, normal_style | WS_MAXIMIZE);
  checks.Check("maximized hidden fixture is recognized without showing it",
               IsZoomed(fixture.parent) != FALSE);
  checks.Check("maximized window cannot leak resize through child",
               Hit(fixture.child, edge) == HTCLIENT);
  SetWindowLongPtrW(fixture.parent, GWL_STYLE, normal_style);
  checks.Check("restoring ordinary style re-enables child edge routing",
               Hit(fixture.child, edge) == HTTRANSPARENT);
}

void CheckLifetime(Checks& checks) {
  {
    Fixture fixture;
    const POINT edge = fixture.Edges(2)[0].point;
    {
      window_resize::ChildResizeBridge bridge(fixture.parent, fixture.child);
      checks.Check("bridge begins attached before explicit scope destruction",
                   bridge.attached() &&
                       Hit(fixture.child, edge) == HTTRANSPARENT);
    }
    checks.Check("destroying bridge restores original child procedure",
                 Hit(fixture.child, edge) == HTCLIENT &&
                     SendMessageW(fixture.child, kForwardedMessage, 123, 456) ==
                         kForwardedResult);
    window_resize::ChildResizeBridge reattached(fixture.parent, fixture.child);
    checks.Check("child may attach again after previous bridge destruction",
                 reattached.attached() &&
                     Hit(fixture.child, edge) == HTTRANSPARENT);
  }
  {
    Fixture fixture;
    auto bridge = std::make_unique<window_resize::ChildResizeBridge>(
        fixture.parent, fixture.child);
    DestroyWindow(fixture.child);
    checks.Check("child destruction clears attached state",
                 !bridge->attached() && fixture.state.child_destroy_calls == 1);
    bridge.reset();
    checks.Check("destroying bridge after child is safe",
                 IsWindow(fixture.parent) != FALSE);
  }
  {
    Fixture fixture;
    auto bridge = std::make_unique<window_resize::ChildResizeBridge>(
        fixture.parent, fixture.child);
    DestroyWindow(fixture.parent);
    checks.Check("parent destruction cleans the child bridge first",
                 !bridge->attached() && !IsWindow(fixture.child) &&
                     fixture.state.child_destroy_calls == 1);
    bridge.reset();
  }
  {
    Fixture fixture;
    const POINT edge = fixture.Edges(2)[0].point;
    window_resize::ChildResizeBridge first(fixture.parent, fixture.child);
    {
      window_resize::ChildResizeBridge duplicate(fixture.parent, fixture.child);
      checks.Check("duplicate attach is rejected without replacing first",
                   first.attached() && !duplicate.attached() &&
                       Hit(fixture.child, edge) == HTTRANSPARENT);
    }
    checks.Check("duplicate destruction does not detach the first bridge",
                 first.attached() &&
                     Hit(fixture.child, edge) == HTTRANSPARENT);
  }
}

void CheckInvalidParents(Checks& checks) {
  Fixture fixture;
  Fixture unrelated;
  window_resize::ChildResizeBridge wrong(unrelated.parent, fixture.child);
  checks.Check("unrelated parent cannot attach to another window's child",
               !wrong.attached() &&
                   Hit(fixture.child, fixture.Edges(2)[0].point) == HTCLIENT);
  window_resize::ChildResizeBridge null_parent(nullptr, fixture.child);
  window_resize::ChildResizeBridge null_child(fixture.parent, nullptr);
  window_resize::ChildResizeBridge self(fixture.child, fixture.child);
  checks.Check("null and self-parent handles fail closed",
               !null_parent.attached() && !null_child.attached() &&
                   !self.attached());

  window_resize::ChildResizeBridge moved(fixture.parent, fixture.child);
  SetParent(fixture.child, unrelated.parent);
  fixture.state.override_parent_hit = true;
  fixture.state.parent_hit = HTLEFT;
  checks.Check("reparented child cannot consult the stale parent",
               Hit(fixture.child, fixture.Edges(2)[0].point) == HTCLIENT);
  SetParent(fixture.child, fixture.parent);
}

void CheckWrongThread(Checks& checks) {
  HANDLE ready = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  HANDLE finish = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (!ready || !finish) throw std::runtime_error("thread events unavailable");
  HWND foreign_parent = nullptr;
  HWND foreign_child = nullptr;
  std::thread worker([&] {
    try {
      Fixture fixture;
      foreign_parent = fixture.parent;
      foreign_child = fixture.child;
      SetEvent(ready);
      WaitForSingleObject(finish, 5000);
    } catch (...) {
      SetEvent(ready);
    }
  });
  const bool created = WaitForSingleObject(ready, 2000) == WAIT_OBJECT_0 &&
      foreign_parent != nullptr && foreign_child != nullptr;
  checks.Check("foreign hidden windows were created on another thread", created);
  if (created) {
    window_resize::ChildResizeBridge foreign(foreign_parent, foreign_child);
    checks.Check("bridge cannot subclass another thread's windows",
                 !foreign.attached());
  }
  SetEvent(finish);
  worker.join();
  CloseHandle(ready);
  CloseHandle(finish);
}

}  // namespace

int main() {
  Checks checks;
  try {
    RegisterTestClasses();
    CheckHitRouting(checks);
    CheckLifetime(checks);
    CheckInvalidParents(checks);
    CheckWrongThread(checks);
  } catch (const std::exception& error) {
    checks.Check(error.what(), false);
  }
  return checks.Finish();
}
