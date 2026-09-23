#ifndef RUNNER_TASKBAR_PROGRESS_POLICY_H_
#define RUNNER_TASKBAR_PROGRESS_POLICY_H_

#include <array>
#include <cstdint>
#include <optional>
#include <string_view>

// Bounded, allocation-free desired/Shell-state reconciliation. The Shell owns
// indeterminate animation; this policy never creates a timer or frame callback.
namespace taskbar_progress {
enum class State { kNone, kIndeterminate, kNormal, kPaused, kError };
constexpr std::int64_t kMaximumValue = 9007199254740991LL;

inline std::optional<State> ParseState(std::string_view name) {
  if (name == "none") return State::kNone;
  if (name == "indeterminate") return State::kIndeterminate;
  if (name == "normal") return State::kNormal;
  if (name == "paused") return State::kPaused;
  if (name == "error") return State::kError;
  return std::nullopt;
}

constexpr bool Determinate(State state) {
  return state == State::kNormal || state == State::kPaused ||
         state == State::kError;
}

struct Snapshot {
  State state = State::kNone;
  std::int64_t completed = 0;
  std::int64_t total = 0;
  bool operator==(const Snapshot& other) const {
    return state == other.state && completed == other.completed &&
           total == other.total;
  }
  bool operator!=(const Snapshot& other) const { return !(*this == other); }
};

inline bool Valid(const Snapshot& value) {
  if (!Determinate(value.state)) {
    return (value.state == State::kNone || value.state == State::kIndeterminate) &&
           value.completed == 0 && value.total == 0;
  }
  return value.total > 0 && value.total <= kMaximumValue &&
         value.completed >= 0 && value.completed <= value.total;
}

enum class Operation { kValue, kState };
struct Plan {
  std::array<Operation, 2> operations{};
  unsigned size = 0;
};

inline Plan MakePlan(const Snapshot& desired,
                     const std::optional<Snapshot>& sent) {
  Plan plan;
  if (Determinate(desired.state) &&
      (!sent || !Determinate(sent->state) ||
       sent->completed != desired.completed || sent->total != desired.total)) {
    plan.operations[plan.size++] = Operation::kValue;
  }
  // Value first, then state: SetProgressValue clears indeterminate but retains
  // paused/error. Explicit state is therefore essential when resuming, and
  // prevents a stale/generic percentage when entering paused/error.
  if (!sent || sent->state != desired.state) {
    plan.operations[plan.size++] = Operation::kState;
  }
  return plan;
}

class Reconciler {
 public:
  struct Attempt {
    std::uint64_t generation = 0;
    Snapshot desired;
    Plan plan;
  };
  bool SetDesired(Snapshot next) {
    if (!Valid(next) || desired_ == next) return false;
    desired_ = next;
    ++generation_;
    return true;
  }
  void InvalidateShell() {
    ++generation_;
    attempted_.reset();
    sent_.reset();
  }
  bool pending() const { return !attempted_ || *attempted_ != desired_; }
  std::optional<Attempt> Begin() {
    if (!pending()) return std::nullopt;
    attempted_ = desired_;
    return Attempt{generation_, desired_, MakePlan(desired_, sent_)};
  }
  void Complete(const Attempt& attempt, bool success) {
    if (attempt.generation != generation_) {
      // An old COM call may pump messages and apply a now-obsolete state. Its
      // actual Shell result is unknown, so the latest request must fully set
      // both fields instead of trusting an earlier successful state.
      sent_.reset();
      attempted_.reset();
      return;
    }
    if (success) sent_ = attempt.desired;
    else sent_.reset();
    // Keep attempted_ even on failure. Identical input cannot spin retries;
    // a new desired value or Shell lifecycle event provides the next attempt.
  }
  const Snapshot& desired() const { return desired_; }
  const std::optional<Snapshot>& sent() const { return sent_; }

 private:
  Snapshot desired_;
  std::optional<Snapshot> attempted_;
  std::optional<Snapshot> sent_;
  std::uint64_t generation_ = 0;
};
}  // namespace taskbar_progress

#endif  // RUNNER_TASKBAR_PROGRESS_POLICY_H_
