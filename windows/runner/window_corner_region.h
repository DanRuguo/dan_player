#ifndef RUNNER_WINDOW_CORNER_REGION_H_
#define RUNNER_WINDOW_CORNER_REGION_H_

#include <windows.h>

#include <algorithm>
#include <cmath>
#include <cstdint>

namespace window_corners {

// Release gate: preserve persisted requests but temporarily use the system
// outer frame. The standalone controller remains testable for a future opt-in.
inline constexpr bool kCustomCornersAvailable = false;
inline bool EffectiveEnabled(bool requested) {
  return kCustomCornersAvailable && requested;
}

struct Shape {
  int width = 0;
  int height = 0;
  int diameter = 0;
  bool operator==(const Shape& other) const {
    return width == other.width && height == other.height && diameter == other.diameter;
  }
};

inline Shape DesiredShape(int width, int height, UINT dpi, double radius,
                            bool enabled, bool iconic, bool maximized, bool fullscreen) {
  if (!enabled || iconic || maximized || fullscreen || width <= 0 || height <= 0 ||
      width > 1048576 || height > 1048576 || !std::isfinite(radius) || radius <= 0 || radius > 64) {
    return {};
  }
  const int diameter = std::max(1, static_cast<int>(std::lround(
      2 * radius * std::clamp(dpi, 48u, 768u) / 96.0)));
  return {width, height, std::min({diameter, width, height})};
}

// Win10/11 share the documented region API. This clips the real window, not
// its Flutter content alone; DWM's preset-radius API cannot promise 16dp.
// No backdrop, frame style, hit-test, owner, focus or visibility is modified.
class Controller {
 public:
  explicit Controller(HWND window, decltype(&SetWindowRgn) set_region = &SetWindowRgn,
                       decltype(&CreateRoundRectRgn) make_region = &CreateRoundRectRgn)
      : window_(window), set_region_(set_region), make_region_(make_region) {}
  ~Controller() { Close(); }
  Controller(const Controller&) = delete;
  Controller& operator=(const Controller&) = delete;
  bool enabled() const { return enabled_; }
  double radius() const { return radius_; }
  bool available() const { return !failed_; }
  unsigned updates() const { return updates_; }

  void Configure(bool enabled, double radius) {
    if (closed_) return;
    if (enabled_ != enabled || radius_ != radius) attempted_ = false;
    enabled_ = enabled;
    radius_ = radius;
    Refresh();
  }

  void Refresh() {
    if (closed_ || applying_ || !IsWindow(window_)) return;
    RECT frame{};
    if (!GetWindowRect(window_, &frame)) return;
    const auto width = static_cast<std::int64_t>(frame.right) - frame.left;
    const auto height = static_cast<std::int64_t>(frame.bottom) - frame.top;
    if (width <= 0 || height <= 0 || width > 1048576 || height > 1048576) {
      Apply({});
      return;
    }
    MONITORINFO monitor{sizeof(monitor)};
    const bool covers_monitor = GetMonitorInfoW(MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST), &monitor) &&
        (GetWindowLongPtrW(window_, GWL_STYLE) & WS_THICKFRAME) == 0 &&
        std::abs(static_cast<std::int64_t>(frame.left) - monitor.rcMonitor.left) <= 1 &&
        std::abs(static_cast<std::int64_t>(frame.top) - monitor.rcMonitor.top) <= 1 &&
        std::abs(static_cast<std::int64_t>(frame.right) - monitor.rcMonitor.right) <= 1 &&
        std::abs(static_cast<std::int64_t>(frame.bottom) - monitor.rcMonitor.bottom) <= 1;
    const auto shape = DesiredShape(static_cast<int>(width), static_cast<int>(height),
        GetDpiForWindow(window_), radius_, enabled_, IsIconic(window_) != FALSE,
        IsZoomed(window_) != FALSE, covers_monitor);
    Apply(shape);
  }

  // Frame/compositor/plugin work can replace the HWND's region without a size
  // change. A geometry cache alone cannot detect that. Reuse two small GDI
  // regions instead of allocating per move/hover, and run this after plugins
  // have handled the triggering message.
  void Revalidate() {
    if (closed_ || applying_ || !IsWindow(window_)) return;
    if (owned_ && !failed_ && expected_region_ && observed_region_) {
      const int kind = GetWindowRgn(window_, observed_region_);
      if (kind == ERROR || !EqualRgn(expected_region_, observed_region_)) {
        attempted_ = false;
        shape_ = {};
      }
    }
    Refresh();
  }

  void Close() {
    if (closed_) return;
    closed_ = true;
    if ((owned_ || applying_) && IsWindow(window_)) set_region_(window_, nullptr, FALSE);
    owned_ = false;
    shape_ = {};
    if (expected_region_) DeleteObject(expected_region_);
    if (observed_region_) DeleteObject(observed_region_);
    expected_region_ = observed_region_ = nullptr;
  }

 private:
  void Apply(Shape shape) {
    // Failed geometry is also memoized: move-only notifications must not
    // allocate/repaint forever on a system that rejects custom regions.
    if (attempted_ && shape == attempted_shape_) return;
    attempted_shape_ = shape;
    attempted_ = true;
    if (shape == shape_ && !failed_) return;
    if (shape.diameter == 0 && !owned_) { shape_ = {}; failed_ = false; return; }
    applying_ = true;
    HRGN region = shape.diameter == 0 ? nullptr : make_region_(
        0, 0, shape.width + 1, shape.height + 1, shape.diameter, shape.diameter);
    if (region) {
      if (!expected_region_) expected_region_ = CreateRectRgn(0, 0, 0, 0);
      if (!observed_region_) observed_region_ = CreateRectRgn(0, 0, 0, 0);
      if (expected_region_ && CombineRgn(expected_region_, region, nullptr, RGN_COPY) == ERROR) {
        DeleteObject(expected_region_);
        expected_region_ = nullptr;
      }
    }
    // A visible window needs its non-client/compositor edge redrawn as well;
    // client-only InvalidateRect does not request that repaint.
    const bool applied = (shape.diameter == 0 || region) &&
                          set_region_(window_, region, IsWindowVisible(window_)) != 0;
    ++updates_;
    // On success Windows owns the region, including if a reentrant teardown
    // already destroyed the HWND. On failure it remains our responsibility.
    if (!applied && region) DeleteObject(region);
    if (closed_) {
      // A callback can close the controller before SetWindowRgn returns.
      // Clear once again after that call, so the last writer is disposal.
      if (IsWindow(window_)) set_region_(window_, nullptr, FALSE);
    } else {
      failed_ = !applied;
      if (applied) {
        owned_ = shape.diameter != 0;
        shape_ = shape;
      } else {
        // Never keep an old smaller clip after allocation/SetWindowRgn failure.
        const bool still_owned = owned_ && IsWindow(window_) &&
                                    set_region_(window_, nullptr, FALSE) == 0;
        owned_ = still_owned;
        if (!still_owned) shape_ = {};
      }
      if (IsWindow(window_)) InvalidateRect(window_, nullptr, FALSE);
    }
    applying_ = false;
  }

  HWND window_;
  decltype(&SetWindowRgn) set_region_;
  decltype(&CreateRoundRectRgn) make_region_;
  Shape shape_;
  Shape attempted_shape_;
  HRGN expected_region_ = nullptr;
  HRGN observed_region_ = nullptr;
  bool attempted_ = false;
  bool enabled_ = false, owned_ = false, applying_ = false, closed_ = false, failed_ = false;
  double radius_ = 16;
  unsigned updates_ = 0;
};

}  // namespace window_corners
#endif  // RUNNER_WINDOW_CORNER_REGION_H_
