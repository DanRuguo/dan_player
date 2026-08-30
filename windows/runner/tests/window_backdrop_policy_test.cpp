#include "../window_backdrop_policy.h"

#include <cstring>
#include <iostream>
#include <vector>

namespace {

using window_backdrop::Backend;
using window_backdrop::Preferences;

bool Check(const char* name, const Preferences& preferences, bool modern,
           bool blur, Backend expected_backend,
           const char* expected_reason,
           const std::vector<int>& expected_calls) {
  std::vector<int> calls;
  const auto selection = window_backdrop::Select(
      preferences,
      [&]() {
        calls.push_back(1);
        return modern;
      },
      [&]() {
        calls.push_back(2);
        return blur;
      });
  const bool reason_matches =
      (selection.reason == nullptr && expected_reason == nullptr) ||
      (selection.reason != nullptr && expected_reason != nullptr &&
       std::strcmp(selection.reason, expected_reason) == 0);
  const bool passed =
      selection.backend == expected_backend && reason_matches &&
      calls == expected_calls &&
      selection.available() == (expected_backend != Backend::kSolid);
  std::cout << (passed ? "PASS " : "FAIL ") << name << '\n';
  return passed;
}

}  // namespace

int main() {
  int failures = 0;
  const Preferences defaults;
  failures += !Check("modern DWM succeeds without legacy calls", defaults, true,
                     true, Backend::kSystemAcrylic, nullptr, {1});
  failures +=
      !Check("older Windows uses blur directly, never legacy Acrylic", defaults,
             false, true, Backend::kLegacyBlur, nullptr, {1, 2});
  failures +=
      !Check("all APIs unavailable use solid", defaults, false, false,
             Backend::kSolid, "native_effect_unavailable", {1, 2});

  auto preferences = defaults;
  preferences.effect_enabled = false;
  failures += !Check("app can turn glass off without probing blur APIs", preferences,
                     true, true, Backend::kSolid, "disabled", {});
  preferences.high_contrast = true;
  failures += !Check("high contrast keeps its system color even with glass off", preferences,
                     true, true, Backend::kSolid, "high_contrast", {});
  preferences = defaults;
  failures += !Check("app reenables legacy blur without acrylic", preferences,
                     false, true, Backend::kLegacyBlur, nullptr, {1, 2});
  preferences = defaults;
  preferences.high_contrast = true;
  failures += !Check("high contrast never invokes a blur API", preferences,
                     true, true, Backend::kSolid, "high_contrast", {});
  preferences.settings_readable = false;
  failures += !Check("known high contrast takes precedence", preferences, true,
                     true, Backend::kSolid, "high_contrast", {});
  preferences = defaults;
  preferences.settings_readable = false;
  failures += !Check("unreadable preferences fail safely", preferences, true,
                     true, Backend::kSolid, "settings_unavailable", {});
  preferences = defaults;
  preferences.transparency_enabled = false;
  failures +=
      !Check("system transparency disabled never invokes blur", preferences,
             true, true, Backend::kSolid, "transparency_disabled", {});
  preferences.transparency_enabled = true;
  failures += !Check("reenabling transparency restores blur without Acrylic",
                     preferences, false, true, Backend::kLegacyBlur, nullptr,
                     {1, 2});
  preferences = defaults;
  preferences.overlapping_content_enabled = false;
  failures +=
      !Check("accessibility overlap preference is respected", preferences, true,
             true, Backend::kSolid, "overlapping_content_disabled", {});
  preferences = defaults;
  preferences.composition_enabled = false;
  failures += !Check("no DWM composition uses solid", preferences, true, true,
                     Backend::kSolid, "composition_unavailable", {});
  preferences = defaults;
  preferences.alpha_surface_available = false;
  failures += !Check("GDI rendering is not falsely reported transparent",
                     preferences, true, true, Backend::kSolid,
                     "alpha_surface_unavailable", {});
  preferences = defaults;
  preferences.energy_saver = true;
  failures += !Check("energy saver uses solid", preferences, true, true,
                     Backend::kSolid, "energy_saver", {});
  std::cout << "Backdrop policy: " << (15 - failures) << "/15 passed\n";
  return failures == 0 ? 0 : 1;
}
