#ifndef RUNNER_WINDOW_BACKDROP_UPDATES_H_
#define RUNNER_WINDOW_BACKDROP_UPDATES_H_

#include <windows.h>

namespace window_backdrop {

inline bool UsesSquareSystemCorners(DWORD style, bool maximized,
                                    const RECT& bounds, const RECT& monitor) {
  // window_manager fullscreen removes these resize capabilities but leaves
  // WS_CAPTION set, so DWM does not infer square corners for it. A fixed-size
  // mini window must retain rounding unless it actually covers the monitor.
  return maximized ||
      ((style & (WS_THICKFRAME | WS_MAXIMIZEBOX)) == 0 &&
       bounds.left == monitor.left && bounds.top == monitor.top &&
       bounds.right == monitor.right && bounds.bottom == monitor.bottom);
}

enum class RefreshKind { kEnvironment, kFrame, kComposition };

// Requests coalesce monotonically while the controller waits for its posted
// message. A later environment check must not discard an earlier frame repair
// or compositor reset.
struct RefreshRequest {
  bool pending = false;
  bool frame = false;
  bool effect = false;

  void Merge(RefreshKind kind) {
    pending = true;
    switch (kind) {
      case RefreshKind::kEnvironment:
        break;
      case RefreshKind::kFrame:
        frame = true;
        break;
      case RefreshKind::kComposition:
        frame = true;
        effect = true;
        break;
    }
  }

  void Merge(const RefreshRequest& other) {
    pending = pending || other.pending;
    frame = frame || other.frame;
    effect = effect || other.effect;
  }
};

struct RefreshPlan {
  bool apply_effect = false;
  bool apply_frame = false;
};

inline RefreshPlan PlanRefresh(bool has_state, bool environment_changed,
                               const RefreshRequest& request) {
  const bool apply_effect =
      !has_state || environment_changed || request.effect;
  return {apply_effect, apply_effect || request.frame};
}

// Observes messages without handling or consuming them. Pure move/resize loops
// leave the current backdrop intact; only a size-state transition (as opposed
// to a change of dimensions) can request a frame repair.
class WindowMessagePolicy {
 public:
  RefreshRequest Observe(UINT message, WPARAM wparam, LPARAM lparam,
                         bool retry_native_failure = false) {
    RefreshRequest request;
    switch (message) {
      case WM_SETTINGCHANGE:
      case WM_SYSCOLORCHANGE:
      case WM_DWMCOLORIZATIONCOLORCHANGED:
      case WM_POWERBROADCAST:
        request.Merge(RefreshKind::kEnvironment);
        break;
      case WM_ACTIVATE:
        // Only a genuine activation retries a transient native failure. DWM
        // can emit style/theme messages after ApplySolid; those must not form
        // a retry feedback loop. Policy-disabled transparency is not a failure.
        request.Merge(retry_native_failure && LOWORD(wparam) != WA_INACTIVE
                          ? RefreshKind::kComposition
                          : RefreshKind::kEnvironment);
        break;
      case WM_THEMECHANGED:
      case WM_STYLECHANGED:
        request.Merge(RefreshKind::kFrame);
        break;
      case WM_DWMCOMPOSITIONCHANGED:
      case WM_DISPLAYCHANGE:
        request.Merge(RefreshKind::kComposition);
        break;
      case WM_WINDOWPOSCHANGED:
        if (lparam != 0 &&
            (reinterpret_cast<const WINDOWPOS*>(lparam)->flags &
             SWP_FRAMECHANGED) != 0) {
          request.Merge(RefreshKind::kFrame);
        }
        break;
      case WM_SIZE:
        if (wparam != last_size_state_) {
          last_size_state_ = wparam;
          request.Merge(RefreshKind::kFrame);
        }
        break;
      default:
        break;
    }
    return request;
  }

 private:
  WPARAM last_size_state_ = SIZE_RESTORED;
};

}  // namespace window_backdrop

#endif  // RUNNER_WINDOW_BACKDROP_UPDATES_H_
