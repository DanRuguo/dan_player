#ifndef RUNNER_DESKTOP_INTEGRATION_EFFECTS_H_
#define RUNNER_DESKTOP_INTEGRATION_EFFECTS_H_

#include <windows.h>
#include <roapi.h>
#include <powersetting.h>
#include <windows.ui.viewmanagement.h>
#include <wrl.h>
#include <wrl/wrappers/corewrappers.h>

#include <atomic>
#include <cstdint>
#include <memory>

#pragma comment(lib, "runtimeobject.lib")

namespace desktop_integration {

// Public Windows transparency preference. Subscription exists only while our
// menu is open. Unknown/unsupported/error is solid, never an assumed opt-in.
class PopupEffectsPreference {
 public:
  ~PopupEffectsPreference() { Close(); }

  bool Open(HWND target, UINT message) {
    Close();
    const auto generation = generation_;
    // Keep activation resources local until complete. A COM-pumped Close()
    // cannot release an interface underneath an in-flight subscribe call or
    // publish that late subscription back into a closed menu.
    auto next = std::make_shared<Session>();
    if (!next->Open(target, message) || generation != generation_) return false;
    session_ = std::move(next);
    return true;
  }

  bool enabled() const {
    if (!session_) return false;
    // A property getter can also pump. Hold a local COM reference, never a raw
    // pointer into the session that a nested Close() could retire.
    const auto session = session_;
    const auto generation = generation_;
    boolean value = false;
    return session->settings && SUCCEEDED(session->settings->get_AdvancedEffectsEnabled(&value)) &&
           generation == generation_ && value;
  }

  void Close() {
    ++generation_;
    if (session_ && session_->destination) session_->destination->store(nullptr);
    // Retire member ownership before unsubscribe invokes COM.
    auto previous = std::move(session_);
  }

 private:
  struct Session {
    bool Open(HWND target, UINT message) {
      initialized = SUCCEEDED(RoInitialize(RO_INIT_SINGLETHREADED));
      if (!initialized) return false;
      Microsoft::WRL::ComPtr<IInspectable> instance;
      const auto name = Microsoft::WRL::Wrappers::HStringReference(
          RuntimeClass_Windows_UI_ViewManagement_UISettings);
      if (FAILED(RoActivateInstance(name.Get(), &instance)) ||
          FAILED(instance.As(&settings))) return false;
      destination = std::make_shared<std::atomic<HWND>>(target);
      const auto receiver = destination;
      auto handler = Microsoft::WRL::Callback<
          __FITypedEventHandler_2_Windows__CUI__CViewManagement__CUISettings_IInspectable>(
          [receiver, message](auto*, auto*) -> HRESULT {
            const HWND current = receiver->load();
            if (current) PostMessageW(current, message, 0, 0);
            return S_OK;
          });
      subscribed = handler && SUCCEEDED(
          settings->add_AdvancedEffectsEnabledChanged(handler.Get(), &token));
      if (!subscribed) return false;
      power = RegisterPowerSettingNotification(
          target, &GUID_POWER_SAVING_STATUS, DEVICE_NOTIFY_WINDOW_HANDLE);
      boolean value = false;
      return power && SUCCEEDED(settings->get_AdvancedEffectsEnabled(&value)) && value;
    }

    ~Session() {
      if (destination) destination->store(nullptr);
      if (power) UnregisterPowerSettingNotification(power);
      if (settings && subscribed) settings->remove_AdvancedEffectsEnabledChanged(token);
      settings.Reset();
      if (initialized) RoUninitialize();
    }

    Microsoft::WRL::ComPtr<ABI::Windows::UI::ViewManagement::IUISettings4> settings;
    std::shared_ptr<std::atomic<HWND>> destination;
    EventRegistrationToken token{};
    bool initialized = false;
    bool subscribed = false;
    HPOWERNOTIFY power = nullptr;
  };

  std::shared_ptr<Session> session_;
  std::uint64_t generation_ = 0;
};

inline bool TrayEnergySaver() {
  SYSTEM_POWER_STATUS power{};
  return !GetSystemPowerStatus(&power) || power.SystemStatusFlag != 0;
}

}  // namespace desktop_integration
#endif  // RUNNER_DESKTOP_INTEGRATION_EFFECTS_H_
