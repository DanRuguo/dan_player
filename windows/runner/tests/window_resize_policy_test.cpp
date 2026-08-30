#include "../window_resize_policy.h"

#include <iostream>

namespace {

class Checks {
 public:
  void Check(const char* name, bool passed) {
    ++total_;
    if (!passed) ++failures_;
    std::cout << (passed ? "PASS " : "FAIL ") << name << '\n';
  }

  int Finish() const {
    std::cout << "Window resize policy: " << total_ - failures_ << '/'
              << total_ << " passed\n";
    return failures_ == 0 ? 0 : 1;
  }

 private:
  int total_ = 0;
  int failures_ = 0;
};

bool IsHit(const std::optional<LRESULT>& actual, LRESULT expected) {
  return actual.has_value() && *actual == expected;
}

}  // namespace

int main() {
  Checks checks;
  constexpr LONG_PTR restored_style = WS_OVERLAPPEDWINDOW;
  constexpr LONG_PTR locked_style = restored_style & ~WS_THICKFRAME;

  checks.Check("restored thick-frame window can resize",
               window_resize::CanHitTestResizeBorder(restored_style, false));
  checks.Check("size lock cannot be bypassed",
               !window_resize::CanHitTestResizeBorder(locked_style, false));
  checks.Check("maximized window cannot edge-resize",
               !window_resize::CanHitTestResizeBorder(restored_style, true));
  checks.Check("fullscreen style cannot edge-resize",
               !window_resize::CanHitTestResizeBorder(
                   restored_style & ~WS_THICKFRAME, false));

  checks.Check("locking requires a non-client refresh",
               window_resize::NeedsNonClientFrameRefresh(restored_style,
                                                          locked_style));
  checks.Check("unlocking requires a non-client refresh",
               window_resize::NeedsNonClientFrameRefresh(locked_style,
                                                          restored_style));
  checks.Check("unrelated style changes do not refresh the frame",
               !window_resize::NeedsNonClientFrameRefresh(
                   restored_style, restored_style ^ WS_MINIMIZEBOX));

  const RECT rect{100, 200, 500, 600};
  constexpr int border_x = 12;
  constexpr int border_y = 9;
  checks.Check("top-left corner", IsHit(window_resize::HitTestResizeBorder(
                                             rect, POINT{101, 201}, border_x,
                                             border_y),
                                         HTTOPLEFT));
  checks.Check("top-right corner", IsHit(window_resize::HitTestResizeBorder(
                                              rect, POINT{499, 201}, border_x,
                                              border_y),
                                          HTTOPRIGHT));
  checks.Check("bottom-left corner", IsHit(window_resize::HitTestResizeBorder(
                                                rect, POINT{101, 599}, border_x,
                                                border_y),
                                            HTBOTTOMLEFT));
  checks.Check("bottom-right corner", IsHit(
                                          window_resize::HitTestResizeBorder(
                                              rect, POINT{499, 599}, border_x,
                                              border_y),
                                          HTBOTTOMRIGHT));
  checks.Check("left edge", IsHit(window_resize::HitTestResizeBorder(
                                       rect, POINT{100, 400}, border_x,
                                       border_y),
                                   HTLEFT));
  checks.Check("right edge", IsHit(window_resize::HitTestResizeBorder(
                                        rect, POINT{499, 400}, border_x,
                                        border_y),
                                    HTRIGHT));
  checks.Check("top edge", IsHit(window_resize::HitTestResizeBorder(
                                      rect, POINT{300, 200}, border_x,
                                      border_y),
                                  HTTOP));
  checks.Check("bottom edge", IsHit(window_resize::HitTestResizeBorder(
                                         rect, POINT{300, 599}, border_x,
                                         border_y),
                                     HTBOTTOM));
  checks.Check("client interior has no resize result",
               !window_resize::HitTestResizeBorder(
                    rect, POINT{300, 400}, border_x, border_y)
                    .has_value());
  checks.Check("outside points have no resize result",
               !window_resize::HitTestResizeBorder(
                    rect, POINT{500, 600}, border_x, border_y)
                    .has_value());
  checks.Check("invalid border metrics fail closed",
               !window_resize::HitTestResizeBorder(rect, POINT{100, 200}, 0,
                                                   border_y)
                    .has_value());

  return checks.Finish();
}
