#include "../taskbar_progress_policy.h"

#include <cstdlib>
#include <iostream>
#include <limits>

namespace p = taskbar_progress;

int main() {
  int count = 0;
  const auto check = [&](bool condition, const char* label) {
    ++count;
    if (!condition) {
      std::cerr << "FAIL: " << label << '\n';
      std::exit(1);
    }
  };
  for (const auto name : {"none", "indeterminate", "normal", "paused", "error"}) {
    check(p::ParseState(name).has_value(), "known state parsed");
  }
  for (const auto name : {"", "NORMAL", "unknown", "normal\0extra"}) {
    // The explicit embedded-NUL check below includes the bytes after NUL.
    if (std::string_view(name) != "normal") {
      check(!p::ParseState(name), "unknown state rejected");
    }
  }
  check(!p::ParseState(std::string_view("normal\0extra", 12)), "embedded NUL rejected");
  for (const auto state : {p::State::kNormal, p::State::kPaused, p::State::kError}) {
    check(p::Valid({state, 0, 100}), "determinate zero valid");
    check(p::Valid({state, 100, 100}), "determinate full valid");
    check(p::Valid({state, p::kMaximumValue, p::kMaximumValue}), "safe upper bound valid");
    for (const auto invalid : {p::Snapshot{state, -1, 100},
                              p::Snapshot{state, 101, 100},
                              p::Snapshot{state, 0, 0},
                              p::Snapshot{state, 0, -1},
                              p::Snapshot{state, 1, p::kMaximumValue + 1},
                              p::Snapshot{state, 1, std::numeric_limits<std::int64_t>::max()}}) {
      check(!p::Valid(invalid), "invalid numeric bounds rejected before cast");
    }
  }
  check(p::Valid({}), "clear state canonical");
  check(p::Valid({p::State::kIndeterminate}), "indeterminate no percentage");
  check(!p::Valid({p::State::kNone, 1, 100}), "non-determinate fields canonical");

  // Exercise every directed state transition, including Win32's blocking
  // paused/error flags; this is the precise plan used by the COM controller.
  for (const auto from : {p::State::kNone, p::State::kIndeterminate,
                         p::State::kNormal, p::State::kPaused, p::State::kError}) {
    for (const auto to : {p::State::kNone, p::State::kIndeterminate,
                         p::State::kNormal, p::State::kPaused, p::State::kError}) {
      const p::Snapshot before = p::Determinate(from) ? p::Snapshot{from, 25, 100} : p::Snapshot{from};
      const p::Snapshot after = p::Determinate(to) ? p::Snapshot{to, 75, 100} : p::Snapshot{to};
      const auto plan = p::MakePlan(after, before);
      auto effective = before;
      for (unsigned index = 0; index < plan.size; ++index) {
        if (plan.operations[index] == p::Operation::kValue) {
          if (effective.state != p::State::kPaused && effective.state != p::State::kError) {
            effective.state = p::State::kNormal;
          }
          effective.completed = after.completed;
          effective.total = after.total;
        } else {
          effective.state = after.state;
          if (!p::Determinate(after.state)) { effective.completed = 0; effective.total = 0; }
        }
      }
      check(effective == after, "all directed transitions reflect actual Win32 semantics");
      check(plan.size <= 2, "bounded native calls per change");
      check(p::MakePlan(after, after).size == 0, "identical payload no native calls");
    }
  }

  p::Reconciler controller;
  controller.SetDesired({p::State::kNormal, 25, 100});
  check(!controller.sent(), "state cached before Shell exists");
  auto attempt = *controller.Begin();
  controller.Complete(attempt, true);
  check(controller.sent() && !controller.pending(), "success remembered");
  check(!controller.Begin(), "repeated playback event deduplicated");
  controller.InvalidateShell();
  check(controller.pending() && !controller.sent(), "Explorer restart invalidates sent state");
  attempt = *controller.Begin();
  check(attempt.desired == p::Snapshot{p::State::kNormal, 25, 100}, "restart retains desired progress");
  controller.Complete(attempt, false);
  check(!controller.sent() && !controller.pending(), "failure is not success or polling retry");
  check(!controller.SetDesired({p::State::kNormal, 25, 100}) && !controller.Begin(), "duplicate failed event does not retry");
  controller.SetDesired({p::State::kPaused, 25, 100});
  attempt = *controller.Begin();
  controller.Complete(attempt, true);
  check(controller.sent()->state == p::State::kPaused, "changed state can recover after failure");

  controller.SetDesired({p::State::kNormal, 50, 100});
  attempt = *controller.Begin();
  controller.SetDesired({p::State::kError, 50, 100});
  controller.SetDesired({p::State::kNormal, 50, 100});
  controller.Complete(attempt, true);
  check(!controller.sent() && controller.pending(), "nested away-and-back cannot accept stale COM completion");
  attempt = *controller.Begin();
  check(attempt.plan.size == 2, "reentrant state is fully established after stale call");
  controller.InvalidateShell();
  controller.Complete(attempt, true);
  check(!controller.sent() && controller.pending(), "old Explorer completion cannot populate new epoch");
  controller.SetDesired({});
  attempt = *controller.Begin();
  check(attempt.desired.state == p::State::kNone && attempt.plan.size == 1,
        "cancel/close clears instead of claiming completed 100 percent");
  controller.Complete(attempt, true);
  check(controller.sent()->state == p::State::kNone, "clear acknowledged");
  std::cout << count << " taskbar progress policy checks passed\n";
}
