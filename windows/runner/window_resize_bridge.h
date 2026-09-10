#ifndef RUNNER_WINDOW_RESIZE_BRIDGE_H_
#define RUNNER_WINDOW_RESIZE_BRIDGE_H_

#include <windows.h>
#include <commctrl.h>

#include "window_resize_policy.h"

namespace window_resize {

// The Flutter child fills the client area, including our custom resize edges.
// Pass only those native hit tests through to the parent. Keep all interior
// input and cursor handling in Flutter; never turn the child itself into a
// sizing window or alter its geometry to expose a border.
class ChildResizeBridge final {
 public:
  ChildResizeBridge(HWND parent, HWND child) : parent_(parent) {
    if (!IsWindow(parent) || !IsWindow(child) || GetParent(child) != parent ||
        GetWindowThreadProcessId(parent, nullptr) != GetCurrentThreadId() ||
        GetWindowThreadProcessId(child, nullptr) != GetCurrentThreadId()) {
      return;
    }
    DWORD_PTR existing = 0;
    if (GetWindowSubclass(child, SubclassProc, SubclassId(), &existing)) return;
    if (SetWindowSubclass(child, SubclassProc, SubclassId(),
                          reinterpret_cast<DWORD_PTR>(this))) {
      child_ = child;
    }
  }

  ~ChildResizeBridge() {
    if (child_) RemoveWindowSubclass(child_, SubclassProc, SubclassId());
  }

  ChildResizeBridge(const ChildResizeBridge&) = delete;
  ChildResizeBridge& operator=(const ChildResizeBridge&) = delete;

  bool attached() const { return child_ != nullptr; }

 private:
  static constexpr UINT_PTR SubclassId() { return 1; }

  static bool IsResizeHit(LRESULT hit) {
    switch (hit) {
      case HTLEFT:
      case HTRIGHT:
      case HTTOP:
      case HTBOTTOM:
      case HTTOPLEFT:
      case HTTOPRIGHT:
      case HTBOTTOMLEFT:
      case HTBOTTOMRIGHT:
        return true;
      default:
        return false;
    }
  }

  static LRESULT CALLBACK SubclassProc(HWND child, UINT message, WPARAM wparam,
                                       LPARAM lparam, UINT_PTR id,
                                       DWORD_PTR reference) {
    auto* bridge = reinterpret_cast<ChildResizeBridge*>(reference);
    if (message == WM_NCDESTROY) {
      RemoveWindowSubclass(child, SubclassProc, id);
      bridge->child_ = nullptr;
    } else if (message == WM_NCHITTEST && GetCapture() != child &&
               GetParent(child) == bridge->parent_ &&
               CanHitTestResizeBorder(
                   GetWindowLongPtrW(bridge->parent_, GWL_STYLE),
                   IsZoomed(bridge->parent_) != FALSE)) {
      // Ask the real parent handler so plugin size locks and native window
      // state remain authoritative. Its hit test never queries this child.
      const auto hit = SendMessageW(bridge->parent_, message, wparam, lparam);
      if (IsResizeHit(hit)) return HTTRANSPARENT;
    }
    return DefSubclassProc(child, message, wparam, lparam);
  }

  HWND parent_;
  HWND child_ = nullptr;
};

}  // namespace window_resize

#endif  // RUNNER_WINDOW_RESIZE_BRIDGE_H_
