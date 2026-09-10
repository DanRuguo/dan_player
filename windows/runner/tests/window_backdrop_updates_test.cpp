#include "../window_backdrop_updates.h"

#include <array>
#include <iostream>

namespace {

using window_backdrop::PlanRefresh;
using window_backdrop::RefreshKind;
using window_backdrop::RefreshPlan;
using window_backdrop::RefreshRequest;
using window_backdrop::WindowMessagePolicy;

class Checks {
 public:
  void Check(const char* name, bool passed) {
    ++total_;
    if (!passed) {
      ++failures_;
    }
    std::cout << (passed ? "PASS " : "FAIL ") << name << '\n';
  }

  int Finish() const {
    std::cout << "Backdrop updates: " << total_ - failures_ << '/' << total_
              << " passed\n";
    return failures_ == 0 ? 0 : 1;
  }

 private:
  int total_ = 0;
  int failures_ = 0;
};

bool IsRequest(const RefreshRequest& request, bool pending, bool frame,
               bool effect) {
  return request.pending == pending && request.frame == frame &&
         request.effect == effect;
}

bool IsEmpty(const RefreshRequest& request) {
  return IsRequest(request, false, false, false);
}

bool IsPlan(const RefreshPlan& plan, bool effect, bool frame) {
  return plan.apply_effect == effect && plan.apply_frame == frame;
}

RefreshRequest MakeRequest(RefreshKind kind) {
  RefreshRequest request;
  request.Merge(kind);
  return request;
}

void CheckRequestMerging(Checks& checks) {
  const auto environment = MakeRequest(RefreshKind::kEnvironment);
  const auto frame = MakeRequest(RefreshKind::kFrame);
  const auto composition = MakeRequest(RefreshKind::kComposition);
  checks.Check("default request is empty", IsEmpty(RefreshRequest{}));
  checks.Check("environment request does not force frame or effect",
               IsRequest(environment, true, false, false));
  checks.Check("frame request does not force effect",
               IsRequest(frame, true, true, false));
  checks.Check("composition request repairs frame and effect",
               IsRequest(composition, true, true, true));

  RefreshRequest request;
  request.Merge(RefreshRequest{});
  checks.Check("merging an empty request does not schedule work",
               IsEmpty(request));
  request.Merge(environment);
  request.Merge(frame);
  request.Merge(environment);
  checks.Check("later environment request cannot downgrade a frame repair",
               IsRequest(request, true, true, false));
  request.Merge(composition);
  request.Merge(frame);
  request.Merge(environment);
  request.Merge(RefreshRequest{});
  checks.Check("later weak or empty requests cannot downgrade composition",
               IsRequest(request, true, true, true));

  constexpr std::array<std::array<RefreshKind, 3>, 6> orders = {{
      {RefreshKind::kEnvironment, RefreshKind::kFrame,
       RefreshKind::kComposition},
      {RefreshKind::kEnvironment, RefreshKind::kComposition,
       RefreshKind::kFrame},
      {RefreshKind::kFrame, RefreshKind::kEnvironment,
       RefreshKind::kComposition},
      {RefreshKind::kFrame, RefreshKind::kComposition,
       RefreshKind::kEnvironment},
      {RefreshKind::kComposition, RefreshKind::kEnvironment,
       RefreshKind::kFrame},
      {RefreshKind::kComposition, RefreshKind::kFrame,
       RefreshKind::kEnvironment},
  }};
  bool all_orders_preserve_strongest_request = true;
  for (const auto& order : orders) {
    RefreshRequest merged_kinds;
    RefreshRequest merged_requests;
    for (const auto kind : order) {
      merged_kinds.Merge(kind);
      merged_requests.Merge(MakeRequest(kind));
    }
    all_orders_preserve_strongest_request &=
        IsRequest(merged_kinds, true, true, true) &&
        IsRequest(merged_requests, true, true, true);
  }
  checks.Check("both merge overloads preserve upgrades in every order",
               all_orders_preserve_strongest_request);

  request.Merge(request);
  checks.Check("merging a request into itself is idempotent",
               IsRequest(request, true, true, true));
}

void CheckRefreshPlans(Checks& checks) {
  const RefreshRequest empty;
  const auto environment = MakeRequest(RefreshKind::kEnvironment);
  const auto frame = MakeRequest(RefreshKind::kFrame);
  const auto composition = MakeRequest(RefreshKind::kComposition);
  checks.Check("first configuration applies effect and frame",
               IsPlan(PlanRefresh(false, false, empty), true, true));
  checks.Check("unchanged state without a request does no work",
               IsPlan(PlanRefresh(true, false, empty), false, false));
  checks.Check("unchanged preferences do not reset the backdrop",
               IsPlan(PlanRefresh(true, false, environment), false, false));
  checks.Check("a frame repair preserves the existing effect",
               IsPlan(PlanRefresh(true, false, frame), false, true));
  checks.Check("composition recovery reapplies an unchanged effect",
               IsPlan(PlanRefresh(true, false, composition), true, true));
  checks.Check("changed environment applies effect and frame",
               IsPlan(PlanRefresh(true, true, environment), true, true));
  checks.Check("changed environment upgrades a pending frame repair",
               IsPlan(PlanRefresh(true, true, frame), true, true));

  // Exhaust the inputs, including an explicit effect-only request: applying an
  // effect must always imply applying its required frame configuration.
  bool all_plans_match_contract = true;
  for (int mask = 0; mask < 32; ++mask) {
    const bool has_state = (mask & 1) != 0;
    const bool changed = (mask & 2) != 0;
    const RefreshRequest request{(mask & 4) != 0, (mask & 8) != 0,
                                 (mask & 16) != 0};
    const bool effect = !has_state || changed || request.effect;
    all_plans_match_contract &=
        IsPlan(PlanRefresh(has_state, changed, request), effect,
               effect || request.frame);
  }
  checks.Check("all 32 refresh-plan inputs preserve the exact contract",
               all_plans_match_contract);
}

void CheckMoveAndResize(Checks& checks) {
  WindowMessagePolicy policy;
  RECT moving_rect{20, 30, 1044, 750};
  WINDOWPOS position{};
  position.cx = 1024;
  position.cy = 720;
  position.flags = SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE;
  bool all_drag_messages_are_empty = true;
  for (int drag = 0; drag < 500; ++drag) {
    all_drag_messages_are_empty &=
        IsEmpty(policy.Observe(WM_ENTERSIZEMOVE, 0, 0));
    for (int movement = 0; movement < 5; ++movement) {
      ++position.x;
      all_drag_messages_are_empty &=
          IsEmpty(policy.Observe(WM_MOVING, 0,
                                 reinterpret_cast<LPARAM>(&moving_rect))) &&
          IsEmpty(policy.Observe(WM_WINDOWPOSCHANGED, 0,
                                 reinterpret_cast<LPARAM>(&position)));
    }
    all_drag_messages_are_empty &=
        IsEmpty(policy.Observe(WM_EXITSIZEMOVE, 0, 0));
  }
  checks.Check("500 complete drag loops never request backdrop work",
               all_drag_messages_are_empty);

  bool all_resize_messages_are_empty = true;
  position.flags = SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE;
  for (int resize = 0; resize < 500; ++resize) {
    all_resize_messages_are_empty &=
        IsEmpty(policy.Observe(WM_ENTERSIZEMOVE, 0, 0));
    ++position.cx;
    all_resize_messages_are_empty &=
        IsEmpty(policy.Observe(WM_SIZING, WMSZ_RIGHT,
                               reinterpret_cast<LPARAM>(&moving_rect))) &&
        IsEmpty(policy.Observe(WM_WINDOWPOSCHANGED, 0,
                               reinterpret_cast<LPARAM>(&position))) &&
        IsEmpty(policy.Observe(WM_SIZE, SIZE_RESTORED,
                               MAKELPARAM(position.cx, position.cy))) &&
        IsEmpty(policy.Observe(WM_EXITSIZEMOVE, 0, 0));
  }
  checks.Check("500 restored-window resize loops leave the effect intact",
               all_resize_messages_are_empty);
  checks.Check("null WINDOWPOS is safely ignored",
               IsEmpty(policy.Observe(WM_WINDOWPOSCHANGED, 0, 0)));

  constexpr std::array<UINT, 7> ignored_messages = {
      WM_MOUSEMOVE, WM_NCMOUSEMOVE, WM_PAINT, WM_ERASEBKGND,
      WM_CANCELMODE, WM_CAPTURECHANGED, WM_NCHITTEST};
  bool unrelated_messages_are_empty = true;
  for (const auto message : ignored_messages) {
    unrelated_messages_are_empty &= IsEmpty(policy.Observe(message, 0, 0));
  }
  checks.Check("paint, input and cancelled drags are not consumed or refreshed",
               unrelated_messages_are_empty);
  checks.Check("observing WINDOWPOS does not mutate caller-owned geometry",
               position.x == 2500 && position.cx == 1524 &&
                   position.cy == 720 &&
                   position.flags ==
                       (SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE));
}

void CheckFrameChanges(Checks& checks) {
  WindowMessagePolicy policy;
  constexpr std::array<WPARAM, 5> states = {
      SIZE_MAXIMIZED, SIZE_MINIMIZED, SIZE_RESTORED, SIZE_MINIMIZED,
      SIZE_RESTORED};
  bool transitions_only_repair_frame = true;
  bool duplicate_sizes_do_nothing = true;
  for (const auto state : states) {
    const auto request = policy.Observe(WM_SIZE, state, MAKELPARAM(900, 700));
    transitions_only_repair_frame &=
        IsRequest(request, true, true, false) &&
        IsPlan(PlanRefresh(true, false, request), false, true);
    duplicate_sizes_do_nothing &=
        IsEmpty(policy.Observe(WM_SIZE, state, MAKELPARAM(1000, 750)));
  }
  checks.Check("maximize, minimize and restore transitions repair only frame",
               transitions_only_repair_frame);
  checks.Check("repeated dimensions in a size state do not request work",
               duplicate_sizes_do_nothing);

  bool theme_and_style_only_repair_frame = true;
  for (const auto message : {WM_THEMECHANGED, WM_STYLECHANGED}) {
    const auto request = policy.Observe(message, 0, 0);
    theme_and_style_only_repair_frame &=
        IsRequest(request, true, true, false) &&
        IsPlan(PlanRefresh(true, false, request), false, true);
  }
  checks.Check("theme and style messages repair frame without clearing effect",
               theme_and_style_only_repair_frame);

  WINDOWPOS position{};
  position.flags = SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER;
  const auto frame_change = policy.Observe(
      WM_WINDOWPOSCHANGED, 0, reinterpret_cast<LPARAM>(&position));
  checks.Check("SWP_FRAMECHANGED repairs frame even without a geometry change",
               IsRequest(frame_change, true, true, false) &&
                   IsPlan(PlanRefresh(true, false, frame_change), false, true));

  RefreshRequest fullscreen;
  fullscreen.Merge(policy.Observe(WM_STYLECHANGED, 0, 0));
  fullscreen.Merge(policy.Observe(WM_WINDOWPOSCHANGED, 0,
                                  reinterpret_cast<LPARAM>(&position)));
  fullscreen.Merge(policy.Observe(WM_SIZE, SIZE_RESTORED,
                                  MAKELPARAM(1920, 1080)));
  fullscreen.Merge(policy.Observe(WM_EXITSIZEMOVE, 0, 0));
  checks.Check("fullscreen style/frame sequence never forces an effect reset",
               IsRequest(fullscreen, true, true, false) &&
                   IsPlan(PlanRefresh(true, false, fullscreen), false, true));

  WindowMessagePolicy independent_policy;
  policy.Observe(WM_SIZE, SIZE_MAXIMIZED, 0);
  checks.Check("each window owns its own remembered size state",
               IsEmpty(independent_policy.Observe(WM_SIZE, SIZE_RESTORED, 0)) &&
                   IsRequest(policy.Observe(WM_SIZE, SIZE_RESTORED, 0), true,
                             true, false));
}

void CheckEnvironmentChanges(Checks& checks) {
  WindowMessagePolicy policy;
  constexpr std::array<UINT, 5> environment_messages = {
      WM_SETTINGCHANGE, WM_SYSCOLORCHANGE, WM_DWMCOLORIZATIONCOLORCHANGED,
      WM_POWERBROADCAST, WM_ACTIVATE};
  bool environment_messages_only_check_preferences = true;
  for (const auto message : environment_messages) {
    const auto request = policy.Observe(message, 0, 0);
    environment_messages_only_check_preferences &=
        IsRequest(request, true, false, false) &&
        IsPlan(PlanRefresh(true, false, request), false, false);
  }
  checks.Check("environment signals do not reset unchanged native state",
               environment_messages_only_check_preferences);

  for (const auto activation : {WA_ACTIVE, WA_CLICKACTIVE}) {
    const auto retry = policy.Observe(WM_ACTIVATE, activation, 0, true);
    checks.Check("activation retries a transient native failure",
                 IsRequest(retry, true, true, true) &&
                     IsPlan(PlanRefresh(true, false, retry), true, true));
  }
  checks.Check(
      "deactivation after a native failure does not force a retry",
      IsRequest(policy.Observe(WM_ACTIVATE, WA_INACTIVE, 0, true), true,
                false, false));
  bool failure_does_not_create_a_feedback_loop = true;
  for (const auto message : {WM_STYLECHANGED, WM_THEMECHANGED}) {
    failure_does_not_create_a_feedback_loop &=
        IsRequest(policy.Observe(message, 0, 0, true), true, true, false);
  }
  checks.Check("native failure does not upgrade self-generated frame signals",
               failure_does_not_create_a_feedback_loop);

  const auto high_contrast =
      policy.Observe(WM_SETTINGCHANGE, SPI_SETHIGHCONTRAST, 0);
  checks.Check("a detected high-contrast change reapplies effect and frame",
               IsRequest(high_contrast, true, false, false) &&
                   IsPlan(PlanRefresh(true, true, high_contrast), true, true));
  const auto system_colors = policy.Observe(WM_SYSCOLORCHANGE, 0, 0);
  checks.Check("changed system fallback colors reapply while HC stays enabled",
               IsPlan(PlanRefresh(true, true, system_colors), true, true));
  const auto power =
      policy.Observe(WM_POWERBROADCAST, PBT_APMPOWERSTATUSCHANGE, 0);
  checks.Check(
      "a detected energy-saver change is not deferred until drag end",
      IsPlan(PlanRefresh(true, true, power), true, true));

  bool composition_messages_repair_everything = true;
  for (const auto message : {WM_DWMCOMPOSITIONCHANGED, WM_DISPLAYCHANGE}) {
    const auto request = policy.Observe(message, 0, 0);
    composition_messages_repair_everything &=
        IsRequest(request, true, true, true) &&
        IsPlan(PlanRefresh(true, false, request), true, true);
  }
  checks.Check("DWM and display changes repair effect even with equal settings",
               composition_messages_repair_everything);

  RefreshRequest pending;
  pending.Merge(policy.Observe(WM_DWMCOMPOSITIONCHANGED, 0, 0));
  pending.Merge(policy.Observe(WM_THEMECHANGED, 0, 0));
  pending.Merge(policy.Observe(WM_SETTINGCHANGE, 0, 0));
  pending.Merge(policy.Observe(WM_ACTIVATE, WA_ACTIVE, 0));
  pending.Merge(policy.Observe(WM_EXITSIZEMOVE, 0, 0));
  checks.Check(
      "queued composition repair survives frame, settings and drag end",
      IsRequest(pending, true, true, true) &&
          IsPlan(PlanRefresh(true, false, pending), true, true));
}

}  // namespace

int main() {
  Checks checks;
  const RECT screen{0, 0, 2560, 1440};
  const RECT ordinary{100, 100, 1380, 856};
  const RECT work_area{0, 0, 2560, 1392};
  const DWORD normal = WS_OVERLAPPEDWINDOW;
  const DWORD fullscreen = normal & ~(WS_THICKFRAME | WS_MAXIMIZEBOX);
  using window_backdrop::UsesSquareSystemCorners;
  checks.Check("normal window requests system rounding",
      !UsesSquareSystemCorners(normal, false, ordinary, screen));
  checks.Check("maximized work area has square corners",
      UsesSquareSystemCorners(normal, true, work_area, screen));
  checks.Check("caption-bearing plugin fullscreen has square corners",
      UsesSquareSystemCorners(fullscreen, false, screen, screen));
  checks.Check("restored ordinary window requests rounding again",
      !UsesSquareSystemCorners(normal, false, ordinary, screen));
  checks.Check("fixed-size mini retains system rounding",
      !UsesSquareSystemCorners(fullscreen, false, ordinary, screen));
  checks.Check("a resizable screen-sized window is not plugin fullscreen",
      !UsesSquareSystemCorners(normal, false, screen, screen));
  checks.Check("fixed-size work area is not full monitor",
      !UsesSquareSystemCorners(fullscreen, false, work_area, screen));
  const RECT second_screen{-1920, -120, 0, 960};
  checks.Check("fullscreen works on a negative-origin secondary display",
      UsesSquareSystemCorners(fullscreen, false, second_screen, second_screen));
  CheckRequestMerging(checks);
  CheckRefreshPlans(checks);
  CheckMoveAndResize(checks);
  CheckFrameChanges(checks);
  CheckEnvironmentChanges(checks);
  return checks.Finish();
}
