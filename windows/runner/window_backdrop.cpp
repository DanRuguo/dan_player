#include "window_backdrop.h"

#include <dwmapi.h>
#include <dxgi.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <string>
#include <utility>

#include "window_backdrop_policy.h"
#include "window_backdrop_updates.h"

namespace {

constexpr char kChannelName[] = "dan_player/window_backdrop";
constexpr wchar_t kRefreshMessageName[] =
    L"DanPlayer.WindowBackdrop.Refresh.v1";
constexpr wchar_t kPersonalizationKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";

// Numeric IDs keep the runner buildable with an older SDK. Their availability
// is determined by DWM's HRESULT, never a manifest-dependent version check.
constexpr DWORD kUseImmersiveDarkMode = 20;
constexpr DWORD kBorderColor = 34;
constexpr COLORREF kNoBorderColor = 0xFFFFFFFE;
constexpr DWORD kSystemBackdropType = 38;
constexpr int kNoSystemBackdrop = 1;
constexpr int kDesktopAcrylicBackdrop = 3;  // DWMSBT_TRANSIENTWINDOW, not Mica.

// Windows 10 has no public background-acrylic API. This narrow compatibility
// ABI is dynamically resolved, as in flutter_acrylic/window_manager. Do not
// substitute DwmEnableBlurBehindWindow: it no longer blurs on Windows 8+.
struct AccentPolicy {
  int state;
  DWORD flags;
  DWORD gradient_color;
  DWORD animation_id;
};

struct CompositionAttributeData {
  int attribute;
  void* data;
  SIZE_T size;
};

using SetCompositionAttribute = BOOL(WINAPI*)(HWND, CompositionAttributeData*);
constexpr int kAccentPolicyAttribute = 19;
constexpr int kAccentDisabled = 0;
constexpr int kAccentSolid = 1;
constexpr int kAccentBlur = 3;

uint32_t ToArgb(COLORREF color) {
  return 0xFF000000u | (static_cast<uint32_t>(GetRValue(color)) << 16) |
         (static_cast<uint32_t>(GetGValue(color)) << 8) | GetBValue(color);
}

DWORD ToAbgr(COLORREF color, BYTE alpha) {
  return (static_cast<DWORD>(alpha) << 24) | color;
}

struct Environment {
  window_backdrop::Preferences preferences;
  COLORREF fallback_color = RGB(243, 243, 243);
  bool dark = false;

  bool operator==(const Environment& other) const {
    return preferences == other.preferences &&
           fallback_color == other.fallback_color && dark == other.dark;
  }
};

struct State {
  window_backdrop::Selection selection;
  COLORREF fallback_color = RGB(243, 243, 243);
  bool dark = false;
  bool enabled = true;

  bool operator==(const State& other) const {
    return selection.backend == other.selection.backend &&
           std::string(selection.reason ? selection.reason : "") ==
               std::string(other.selection.reason ? other.selection.reason
                                                  : "") &&
           fallback_color == other.fallback_color && dark == other.dark &&
           enabled == other.enabled;
  }
};

}  // namespace

struct WindowBackdropController::Impl {
  Impl(HWND target_window, flutter::FlutterEngine* target_engine)
      : window(target_window), engine(target_engine) {
    const HMODULE user32 = GetModuleHandleW(L"user32.dll");
    if (user32) {
      set_composition_attribute = reinterpret_cast<SetCompositionAttribute>(
          GetProcAddress(user32, "SetWindowCompositionAttribute"));
    }
    refresh_message = RegisterWindowMessageW(kRefreshMessageName);
    channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        engine->messenger(), kChannelName,
        &flutter::StandardMethodCodec::GetInstance());
    channel->SetMethodCallHandler([this](const auto& call, auto result) {
      if (call.method_name() != "configure") {
        result->NotImplemented();
        return;
      }
      const auto* arguments =
          call.arguments()
              ? std::get_if<flutter::EncodableMap>(call.arguments())
              : nullptr;
      if (!arguments) {
        result->Error("invalid_arguments", "configure requires {dark: bool}.");
        return;
      }
      const auto value = arguments->find(flutter::EncodableValue("dark"));
      const bool* requested_dark = value == arguments->end()
                                       ? nullptr
                                       : std::get_if<bool>(&value->second);
      if (!requested_dark) {
        result->Error("invalid_arguments", "configure requires {dark: bool}.");
        return;
      }
      const auto enabled_value =
          arguments->find(flutter::EncodableValue("enabled"));
      const bool* requested_enabled = enabled_value == arguments->end()
          ? nullptr : std::get_if<bool>(&enabled_value->second);
      if (enabled_value != arguments->end() && !requested_enabled) {
        result->Error("invalid_arguments", "enabled must be a boolean.");
        return;
      }
      dark = *requested_dark;
      enabled = requested_enabled ? *requested_enabled : true;
      configured = true;
      window_backdrop::RefreshRequest request;
      request.Merge(HasNativeFailure()
                        ? window_backdrop::RefreshKind::kComposition
                        : window_backdrop::RefreshKind::kEnvironment);
      Refresh(request);
      result->Success(flutter::EncodableValue(EncodeState()));
    });
  }

  ~Impl() {
    channel->SetMethodCallHandler(nullptr);
    channel.reset();
    if (fallback_brush) {
      DeleteObject(fallback_brush);
    }
  }

  Environment ReadEnvironment() const {
    Environment environment;
    environment.dark = dark;
    environment.fallback_color = dark ? RGB(32, 32, 32) : RGB(243, 243, 243);
    auto& preferences = environment.preferences;
    preferences.effect_enabled = enabled;

    HIGHCONTRASTW contrast{};
    contrast.cbSize = sizeof(contrast);
    if (!SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(contrast), &contrast,
                               0)) {
      preferences.settings_readable = false;
    } else {
      preferences.high_contrast = (contrast.dwFlags & HCF_HIGHCONTRASTON) != 0;
      if (preferences.high_contrast) {
        environment.fallback_color = GetSysColor(COLOR_WINDOW);
      }
    }

    DWORD transparency = 1;
    DWORD transparency_size = sizeof(transparency);
    const LSTATUS preference_result = RegGetValueW(
        HKEY_CURRENT_USER, kPersonalizationKey, L"EnableTransparency",
        RRF_RT_REG_DWORD, nullptr, &transparency, &transparency_size);
    if (preference_result == ERROR_SUCCESS) {
      preferences.transparency_enabled = transparency != 0;
    } else if (preference_result != ERROR_FILE_NOT_FOUND &&
               preference_result != ERROR_PATH_NOT_FOUND) {
      // An absent value uses Windows' default. Unreadable/malformed settings
      // must not accidentally override an accessibility preference.
      preferences.settings_readable = false;
    }

    BOOL disable_overlapping_content = FALSE;
    if (SystemParametersInfoW(SPI_GETDISABLEOVERLAPPEDCONTENT, 0,
                              &disable_overlapping_content, 0)) {
      preferences.overlapping_content_enabled = !disable_overlapping_content;
    }

    BOOL composition_enabled = FALSE;
    preferences.composition_enabled =
        SUCCEEDED(DwmIsCompositionEnabled(&composition_enabled)) &&
        composition_enabled;

    SYSTEM_POWER_STATUS power_status{};
    if (GetSystemPowerStatus(&power_status)) {
      preferences.energy_saver = power_status.SystemStatusFlag == 1;
    }

    // Flutter 3.47's ANGLE window surface requests EGL_ALPHA_SIZE=8 and its
    // child HWND has no background brush. A GDI/software fallback does not
    // provide the same dependable alpha path: report solid instead of claiming
    // a successful DWM attribute alone guarantees a transparent Flutter frame.
    IDXGIAdapter* adapter = nullptr;
    preferences.alpha_surface_available =
        engine->GetGraphicsAdapter(&adapter) && adapter != nullptr;
    if (adapter) {
      adapter->Release();
    }
    return environment;
  }

  bool SetAccent(int accent_state, DWORD color) const {
    if (!set_composition_attribute) {
      return false;
    }
    // Flag 2 enables the tint; do not set accent-border flags that could bring
    // back the Windows 10 left/right/bottom color columns.
    AccentPolicy policy{accent_state, 2, color, 0};
    CompositionAttributeData data{kAccentPolicyAttribute, &policy,
                                  sizeof(policy)};
    return set_composition_attribute(window, &data) != FALSE;
  }

  void SetDarkMode() const {
    const BOOL desired = dark ? TRUE : FALSE;
    BOOL current = FALSE;
    if (FAILED(DwmGetWindowAttribute(window, kUseImmersiveDarkMode, &current,
                                     sizeof(current))) ||
        current != desired) {
      DwmSetWindowAttribute(window, kUseImmersiveDarkMode, &desired,
                            sizeof(desired));
    }
  }

  void DisableSystemBackdrop() {
    if (system_backdrop_owned) {
      const int none = kNoSystemBackdrop;
      DwmSetWindowAttribute(window, kSystemBackdropType, &none, sizeof(none));
      system_backdrop_owned = false;
    }
  }

  bool RestoreFrame(window_backdrop::Backend backend) const {
    // The old one-pixel top glass extension exposed a white DWM line on Win10.
    // AccentPolicy blur covers the HWND without a glass extension. Keep the
    // Flutter client origin unchanged so title-bar spacing remains symmetric.
    const MARGINS margins = backend == window_backdrop::Backend::kSystemAcrylic
                                ? MARGINS{-1, -1, -1, -1}
                                : MARGINS{0, 0, 0, 0};
    const HRESULT result = DwmExtendFrameIntoClientArea(window, &margins);
    // Independent capability probe: this works on early Win11 too, even when
    // the newer Desktop Acrylic attribute is unavailable. Win10 ignores it.
    DwmSetWindowAttribute(window, kBorderColor, &kNoBorderColor,
                          sizeof(kNoBorderColor));
    return SUCCEEDED(result);
  }

  bool TrySystemAcrylic() {
    const int acrylic = kDesktopAcrylicBackdrop;
    if (FAILED(DwmSetWindowAttribute(window, kSystemBackdropType, &acrylic,
                                     sizeof(acrylic)))) {
      return false;
    }
    if (!system_backdrop_owned) {
      // Only a transition to the modern backend needs to remove the legacy
      // policy (including window_manager's initial transparent gradient).
      SetAccent(kAccentDisabled, 0);
    }
    system_backdrop_owned = true;
    if (!RestoreFrame(window_backdrop::Backend::kSystemAcrylic)) {
      DisableSystemBackdrop();
      return false;
    }
    return true;
  }

  bool TryLegacyBlur() {
    const COLORREF tint = dark ? RGB(32, 32, 32) : RGB(243, 243, 243);
    // Replace a tint/blur policy directly, never through an all-black disabled
    // frame. Legacy Acrylic (4) is intentionally never enabled, even at rest.
    if (!SetAccent(kAccentBlur, ToAbgr(tint, 0xBF))) {
      return false;
    }
    DisableSystemBackdrop();
    return RestoreFrame(window_backdrop::Backend::kLegacyBlur);
  }

  void ApplySolid(COLORREF color) {
    SetAccent(kAccentSolid, ToAbgr(color, 0xFF));
    DisableSystemBackdrop();
    RestoreFrame(window_backdrop::Backend::kSolid);
  }

  bool HasNativeFailure() const {
    return state && state->selection.reason &&
           std::string(state->selection.reason) == "native_effect_unavailable";
  }

  void Refresh(const window_backdrop::RefreshRequest& request) {
    const Environment environment = ReadEnvironment();
    const bool environment_changed =
        !last_environment || !(*last_environment == environment);
    const auto plan = window_backdrop::PlanRefresh(
        state.has_value(), environment_changed, request);
    applying = true;
    // The base runner can update DWM's dark flag on a colorization message.
    // Restore the app's explicit preference without resetting the blur policy.
    SetDarkMode();
    if (!plan.apply_effect) {
      if (plan.apply_frame && !RestoreFrame(state->selection.backend) &&
          state->selection.available()) {
        // A failed compositor restore must not leave Dart claiming that its
        // transparent chrome is backed by working glass.
        ApplySolid(environment.fallback_color);
        state = State{{window_backdrop::Backend::kSolid,
                       "native_effect_unavailable"},
                      environment.fallback_color, dark, enabled};
        // The compositor may be temporarily unavailable while restoring a
        // window. Do not cache that failure as a stable material: the next
        // activation/configure must be allowed to probe the effect again.
        last_environment.reset();
      }
      applying = false;
      return;
    }

    const auto selection = window_backdrop::Select(
        environment.preferences, [this]() { return TrySystemAcrylic(); },
        [this]() { return TryLegacyBlur(); });
    if (!selection.available()) {
      ApplySolid(environment.fallback_color);
    }

    HBRUSH replacement = CreateSolidBrush(environment.fallback_color);
    if (replacement) {
      if (fallback_brush) {
        DeleteObject(fallback_brush);
      }
      fallback_brush = replacement;
    }
    state = State{selection, environment.fallback_color, dark, enabled};
    last_environment = environment;
    // DWM presents the changed material; the status event lets Flutter repaint
    // its own alpha/fallback layer when necessary. Never erase/repaint the
    // Flutter child from here: that exposed BLACK_BRUSH after every drag.
    applying = false;
  }

  flutter::EncodableMap EncodeState() const {
    using flutter::EncodableValue;
    flutter::EncodableMap values{
        {EncodableValue("available"),
         EncodableValue(state->selection.available())},
        {EncodableValue("effect"), EncodableValue(state->selection.effect())},
        {EncodableValue("dark"), EncodableValue(state->dark)},
        {EncodableValue("enabled"), EncodableValue(state->enabled)},
        {EncodableValue("fallbackColor"),
         EncodableValue(static_cast<int64_t>(ToArgb(state->fallback_color)))}};
    if (state->selection.reason) {
      values[EncodableValue("reason")] =
          EncodableValue(state->selection.reason);
    }
    return values;
  }

  void ScheduleRefresh(const window_backdrop::RefreshRequest& request) {
    if (!request.pending || !configured || applying || refresh_message == 0) {
      return;
    }
    pending_request.Merge(request);
    if (!refresh_pending) {
      refresh_pending = PostMessageW(window, refresh_message, 0, 0) != FALSE;
    }
  }

  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam,
                                       LPARAM lparam) {
    if (refresh_message != 0 && message == refresh_message) {
      refresh_pending = false;
      const auto request = pending_request;
      pending_request = {};
      if (configured) {
        const auto previous = state;
        Refresh(request);
        if (!previous || !(*previous == *state)) {
          channel->InvokeMethod(
              "stateChanged",
              std::make_unique<flutter::EncodableValue>(EncodeState()));
        }
      }
      return 0;
    }
    if (message == WM_ERASEBKGND && state && wparam != 0) {
      RECT bounds{};
      if (GetClientRect(window, &bounds)) {
        // WS_CLIPCHILDREN excludes the live Flutter surface from this HDC. Only
        // genuinely exposed parent pixels are cleared, including resize gaps.
        // The alpha-zero glass backing is not an intermediate animation frame.
        const HBRUSH brush =
            state->selection.available()
                ? static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH))
                : fallback_brush;
        if (brush) {
          FillRect(reinterpret_cast<HDC>(wparam), &bounds, brush);
          return 1;
        }
      }
    }

    // Pure move/resize events, including WM_EXITSIZEMOVE, request no backdrop
    // work. Fullscreen frame restoration and compositor recreation are separate
    // operations, so a frame change never tears down an unchanged effect.
    ScheduleRefresh(
        message_policy.Observe(message, wparam, lparam, HasNativeFailure()));
    return std::nullopt;
  }

  HWND window;
  flutter::FlutterEngine* engine;
  SetCompositionAttribute set_composition_attribute = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel;
  UINT refresh_message = 0;
  HBRUSH fallback_brush = nullptr;
  std::optional<Environment> last_environment;
  std::optional<State> state;
  window_backdrop::WindowMessagePolicy message_policy;
  window_backdrop::RefreshRequest pending_request;
  bool dark = false;
  bool enabled = true;
  bool configured = false;
  bool applying = false;
  bool refresh_pending = false;
  bool system_backdrop_owned = false;
};

WindowBackdropController::WindowBackdropController(
    HWND window, flutter::FlutterEngine* engine)
    : impl_(std::make_unique<Impl>(window, engine)) {}

WindowBackdropController::~WindowBackdropController() = default;

std::optional<LRESULT> WindowBackdropController::HandleMessage(UINT message,
                                                               WPARAM wparam,
                                                               LPARAM lparam) {
  return impl_->HandleMessage(message, wparam, lparam);
}
