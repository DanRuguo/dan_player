#ifndef RUNNER_WINDOW_BACKDROP_POLICY_H_
#define RUNNER_WINDOW_BACKDROP_POLICY_H_

// Kept free of Win32/Flutter dependencies so capability ordering and user
// preferences can be regression-tested without a compositor or visible window.
namespace window_backdrop {

struct Preferences {
  bool effect_enabled = true;
  bool settings_readable = true;
  bool high_contrast = false;
  bool transparency_enabled = true;
  bool overlapping_content_enabled = true;
  bool composition_enabled = true;
  bool alpha_surface_available = true;
  bool energy_saver = false;

  bool operator==(const Preferences& other) const {
    return effect_enabled == other.effect_enabled &&
           settings_readable == other.settings_readable &&
           high_contrast == other.high_contrast &&
           transparency_enabled == other.transparency_enabled &&
           overlapping_content_enabled == other.overlapping_content_enabled &&
           composition_enabled == other.composition_enabled &&
           alpha_surface_available == other.alpha_surface_available &&
           energy_saver == other.energy_saver;
  }
};

enum class Backend { kSolid, kSystemAcrylic, kLegacyBlur };

struct Selection {
  Backend backend = Backend::kSolid;
  const char* reason = nullptr;

  bool available() const { return backend != Backend::kSolid; }

  const char* effect() const {
    switch (backend) {
      case Backend::kSystemAcrylic:
        return "acrylic";
      case Backend::kLegacyBlur:
        return "blur";
      case Backend::kSolid:
        return "solid";
    }
    return "solid";
  }
};

inline const char* BlockingReason(const Preferences& preferences) {
  if (preferences.high_contrast) {
    return "high_contrast";
  }
  if (!preferences.effect_enabled) {
    return "disabled";
  }
  if (!preferences.settings_readable) {
    return "settings_unavailable";
  }
  if (!preferences.transparency_enabled) {
    return "transparency_disabled";
  }
  if (!preferences.overlapping_content_enabled) {
    return "overlapping_content_disabled";
  }
  if (preferences.energy_saver) {
    return "energy_saver";
  }
  if (!preferences.composition_enabled) {
    return "composition_unavailable";
  }
  if (!preferences.alpha_surface_available) {
    return "alpha_surface_unavailable";
  }
  return nullptr;
}

// Legacy Acrylic (AccentPolicy 4) causes input lag during window dragging on
// Windows 10. Keep background blur (3) enabled continuously instead: switching
// effects at drag boundaries adds flashes and does not fix every move gesture.
// Modern Windows 11 Desktop Acrylic does not use that legacy path.
template <typename TrySystemAcrylic, typename TryLegacyBlur>
Selection Select(const Preferences& preferences,
                 TrySystemAcrylic try_system_acrylic,
                 TryLegacyBlur try_legacy_blur) {
  if (const char* reason = BlockingReason(preferences)) {
    return {Backend::kSolid, reason};
  }
  if (try_system_acrylic()) {
    return {Backend::kSystemAcrylic, nullptr};
  }
  if (try_legacy_blur()) {
    return {Backend::kLegacyBlur, nullptr};
  }
  return {Backend::kSolid, "native_effect_unavailable"};
}

}  // namespace window_backdrop

#endif  // RUNNER_WINDOW_BACKDROP_POLICY_H_
