#include "desktop_integration.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <dwmapi.h>
#include <shellapi.h>
#include <shobjidl.h>
#include <windowsx.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#include "desktop_integration_blur.h"
#include "desktop_integration_effects.h"
#include "desktop_integration_policy.h"
#include "desktop_integration_paint.h"
#include "desktop_integration_fonts.h"
#include "desktop_integration_tray_style.h"
#include "resource.h"
#include "taskbar_peek_geometry.h"
#include "taskbar_thumbnail_policy.h"

namespace {
using flutter::EncodableMap;
using flutter::EncodableValue;
namespace policy = desktop_integration;
namespace thumbnail = taskbar_thumbnail;

constexpr UINT kTrayId = 1;
constexpr UINT kTrayCallback = WM_APP + 0x541;
constexpr UINT kTrayEffectsChanged = WM_APP + 0x542;

// Use the runner's generated version, never a second manually updated release
// string. Standalone native checks do not define FLUTTER_VERSION.
#ifdef FLUTTER_VERSION
#define DAN_WIDE_LITERAL_IMPL(value) L##value
#define DAN_WIDE_LITERAL(value) DAN_WIDE_LITERAL_IMPL(value)
constexpr wchar_t kPublisherCaption[] = L"RCEIT.Inc \u00b7 " DAN_WIDE_LITERAL(FLUTTER_VERSION);
#undef DAN_WIDE_LITERAL
#undef DAN_WIDE_LITERAL_IMPL
#else
constexpr wchar_t kPublisherCaption[] = L"RCEIT.Inc";
#endif

bool ReadTrayBlurRadius(const EncodableMap& map, double* output) {
  const auto found = map.find(EncodableValue("trayMenuBlurRadius"));
  if (found == map.end()) return true;  // Backward-compatible older Dart peer.
  double radius = -1;
  if (const auto* value = std::get_if<double>(&found->second)) radius = *value;
  if (const auto* value = std::get_if<int32_t>(&found->second)) radius = *value;
  if (const auto* value = std::get_if<int64_t>(&found->second)) {
    radius = static_cast<double>(*value);
  }
  if (!policy::ValidTrayBlurRadius(radius)) return false;
  *output = radius;
  return true;
}

bool ReadBool(const EncodableMap& map, const char* key, bool* output) {
  const auto found = map.find(EncodableValue(key));
  if (found == map.end()) return false;
  const auto* value = std::get_if<bool>(&found->second);
  if (!value) return false;
  *output = *value;
  return true;
}

bool ReadInt(const EncodableMap& map, const char* key, int* output) {
  const auto found = map.find(EncodableValue(key));
  if (found == map.end()) return false;
  if (const auto* value = std::get_if<int32_t>(&found->second)) {
    *output = *value;
    return true;
  }
  if (const auto* value = std::get_if<int64_t>(&found->second)) {
    *output = static_cast<int>(*value);
    return true;
  }
  return false;
}

bool ReadWideString(const EncodableMap& map, const char* key,
                    std::size_t limit, std::wstring* output) {
  const auto found = map.find(EncodableValue(key));
  if (found == map.end()) return false;
  const auto* value = std::get_if<std::string>(&found->second);
  if (!value || value->size() > limit || value->find('\0') != std::string::npos) {
    return false;
  }
  if (value->empty()) { output->clear(); return true; }
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
      value->data(), static_cast<int>(value->size()), nullptr, 0);
  if (length <= 0) return false;
  output->resize(length);
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value->data(),
      static_cast<int>(value->size()), output->data(), length);
  return true;
}

bool ReadThumbnailDimension(const EncodableMap& map, const char* key,
                            std::int64_t* output) {
  const auto found = map.find(EncodableValue(key));
  if (found == map.end()) return false;
  if (const auto* value = std::get_if<int32_t>(&found->second)) {
    *output = *value;
    return true;
  }
  if (const auto* value = std::get_if<int64_t>(&found->second)) {
    *output = *value;
    return true;
  }
  return false;
}

std::wstring Tooltip(const std::string& title) {
  std::wstring result = L"Dan Player";
  // Bound malformed/untrusted tags before allocating or handing text to Shell.
  if (!title.empty() && title.size() <= 4096) {
    const int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                         title.data(),
                                         static_cast<int>(title.size()),
                                         nullptr, 0);
    if (count > 0) {
      std::wstring decoded(static_cast<size_t>(count), L' ');
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, title.data(),
                          static_cast<int>(title.size()), decoded.data(), count);
      for (auto& character : decoded) {
        if (character < L' ' || character == 0x7f) character = L' ';
      }
      result += L" - " + decoded;
    }
  }
  if (result.size() > 127) result.resize(127);
  if (!result.empty() && result.back() >= 0xd800 && result.back() <= 0xdbff) {
    result.pop_back();
  }
  return result;
}

bool SystemHighContrast() {
  HIGHCONTRASTW contrast{sizeof(contrast), 0, nullptr};
  return SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(contrast),
                                &contrast, 0) &&
         (contrast.dwFlags & HCF_HIGHCONTRASTON) != 0;
}

COLORREF TaskbarForeground(COLORREF accent, bool fallback_dark) {
  if (SystemHighContrast()) {
    return policy::TaskbarIconColor(accent, false, true,
                                     GetSysColor(COLOR_BTNTEXT));
  }
  DWORD light = fallback_dark ? 0 : 1;
  DWORD bytes = sizeof(light);
  RegGetValueW(HKEY_CURRENT_USER,
               L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
               L"SystemUsesLightTheme", RRF_RT_REG_DWORD, nullptr, &light, &bytes);
  return policy::TaskbarIconColor(accent, light != 0, false, 0);
}

bool InsideMediaShape(int kind, double x, double y) {
  if (kind == 2) {  // pause
    return y >= .20 && y <= .80 &&
           ((x >= .25 && x <= .42) || (x >= .58 && x <= .75));
  }
  if (kind == 1) {  // play
    return x >= .28 && x <= .80 &&
           std::abs(y - .5) <= (.80 - x) * .62;
  }
  if (kind == 3) x = 1.0 - x;  // next mirrors previous
  return (x >= .17 && x <= .27 && y >= .20 && y <= .80) ||
         (x >= .30 && x <= .78 && std::abs(y - .5) <= (x - .30) * .63);
}

HICON MakeMediaIcon(int kind, int edge, COLORREF foreground) {
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = edge;
  info.bmiHeader.biHeight = -edge;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void* storage = nullptr;
  HBITMAP color = CreateDIBSection(nullptr, &info, DIB_RGB_COLORS, &storage,
                                   nullptr, 0);
  if (!color || !storage) {
    if (color) DeleteObject(color);
    return nullptr;
  }
  auto* pixels = static_cast<std::uint32_t*>(storage);
  // Small, bounded supersampling makes the native buttons legible at 100–300%
  // DPI without depending on a Flutter/private icon font or screen capture.
  for (int y = 0; y < edge; ++y) {
    for (int x = 0; x < edge; ++x) {
      unsigned covered = 0;
      for (int sy = 0; sy < 4; ++sy) {
        for (int sx = 0; sx < 4; ++sx) {
          if (InsideMediaShape(kind, (x + (sx + .5) / 4) / edge,
                               (y + (sy + .5) / 4) / edge)) ++covered;
        }
      }
      const unsigned alpha = covered * 255 / 16;
      const unsigned r = GetRValue(foreground) * alpha / 255;
      const unsigned g = GetGValue(foreground) * alpha / 255;
      const unsigned b = GetBValue(foreground) * alpha / 255;
      pixels[y * edge + x] = (alpha << 24) | (r << 16) | (g << 8) | b;
    }
  }
  const size_t mask_bytes = static_cast<size_t>(((edge + 15) / 16) * 2 * edge);
  const std::vector<unsigned char> mask_data(mask_bytes, 0);
  HBITMAP mask = CreateBitmap(edge, edge, 1, 1, mask_data.data());
  ICONINFO icon_info{};
  icon_info.fIcon = TRUE;
  icon_info.hbmMask = mask;
  icon_info.hbmColor = color;
  HICON icon = mask ? CreateIconIndirect(&icon_info) : nullptr;
  if (mask) DeleteObject(mask);
  DeleteObject(color);
  return icon;
}

COLORREF BlendColor(COLORREF foreground, COLORREF background, int alpha) {
  const auto blend = [alpha](BYTE front, BYTE back) {
    return static_cast<BYTE>((front * alpha + back * (255 - alpha)) / 255);
  };
  return RGB(blend(GetRValue(foreground), GetRValue(background)),
             blend(GetGValue(foreground), GetGValue(background)),
             blend(GetBValue(foreground), GetBValue(background)));
}

}  // namespace

struct DesktopIntegrationController::Impl
    : std::enable_shared_from_this<DesktopIntegrationController::Impl> {
  explicit Impl(HWND target) : window(target) {
    peek_client_geometry.Observe(window);
    taskbar_created = RegisterWindowMessageW(L"TaskbarCreated");
    taskbar_button_created = RegisterWindowMessageW(L"TaskbarButtonCreated");
    state_message =
        RegisterWindowMessageW(L"DanPlayer.DesktopIntegration.State.v1");
  }

  HWND window;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;
  ITaskbarList3* taskbar = nullptr;
  std::array<HICON, 4> icons{};
  HICON tray_icon = nullptr;
  UINT taskbar_created = 0;
  UINT taskbar_button_created = 0;
  UINT state_message = 0;
  policy::ShellState shell;
  policy::Playback playback;
  std::wstring tooltip = L"Dan Player";
  std::array<std::wstring, 8> labels{
      L"\u663e\u793a\u4e3b\u7a97\u53e3", L"\u8ff7\u4f60\u64ad\u653e\u5668",
      L"\u4e0a\u4e00\u9996", L"\u64ad\u653e", L"\u6682\u505c",
      L"\u4e0b\u4e00\u9996", L"\u684c\u9762\u6b4c\u8bcd", L"\u9000\u51fa Dan Player"};
  bool active = false;
  bool disposed = false;
  bool tray_available = false;
  bool tray_v4 = false;
  bool taskbar_controls = true;
  bool taskbar_available = false;
  bool taskbar_connecting = false;
  thumbnail::Image thumbnail_image;
  thumbnail::Image peek_image;
  thumbnail::PeekClientGeometry peek_client_geometry;
  bool thumbnail_attributes = false;
  bool thumbnail_reset_pending = false;
  bool thumbnail_available = false;
  std::uint64_t thumbnail_generation = 0;
  bool thumbnail_dirty = false;
  thumbnail::RetryTimer thumbnail_retry_timer;
  std::uint64_t thumbnail_retry_generation = 0;
  thumbnail::RetryBudget thumbnail_retry_budget;
  bool state_pending = false;
  bool menu_open = false;
  bool menu_opening = false;
  HWND menu_window = nullptr;
  int menu_hovered = -1;
  int menu_focused = 0;
  bool menu_tracking = false;
  bool custom_menu_paint_failed = false;
  policy::PopupPaintBuffer popup_paint;
  UINT menu_dpi = 96;
  policy::PopupFonts popup_fonts;
  std::array<wchar_t, 9> material_glyphs{};
  policy::PopupBlurImage popup_blur;
  policy::PopupEffectsPreference popup_effects;
  double tray_blur_radius = 0;
  bool dark_mode = false;
  COLORREF accent = RGB(0, 120, 170);
  std::int64_t revision = 0;
  std::string reason;

  ~Impl() { Dispose(); }

  void Connect(flutter::FlutterEngine* engine, std::weak_ptr<Impl> weak) {
    channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
        engine->messenger(), "dan_player/desktop_integration",
        &flutter::StandardMethodCodec::GetInstance());
    channel->SetMethodCallHandler(
        [weak](const auto& call, auto result) {
          auto self = weak.lock();
          if (!self) {
            result->Error("CLOSED", "Desktop integration is closed");
            return;
          }
          self->HandleMethod(call, std::move(result));
        });
  }

  void HandleMethod(const flutter::MethodCall<EncodableValue>& call,
                    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    const auto& method = call.method_name();
    if (method == "dispose") {
      Dispose();
      result->Success();
      return;
    }
    if (disposed) {
      result->Error("CLOSED", "Desktop integration is closed");
      return;
    }
    const auto* args = call.arguments()
                           ? std::get_if<EncodableMap>(call.arguments())
                           : nullptr;
    if (method == "configure") {
      bool controls = true;
      if (!args || !ReadBool(*args, "taskbarControls", &controls)) {
        result->Error("INVALID_ARGUMENT", "taskbarControls must be bool");
        return;
      }
      double next_blur_radius = tray_blur_radius;
      if (!ReadTrayBlurRadius(*args, &next_blur_radius)) {
        result->Error("INVALID_ARGUMENT", "trayMenuBlurRadius must be finite, 0..24 logical pixels");
        return;
      }
      const bool blur_changed = next_blur_radius != tray_blur_radius;
      tray_blur_radius = next_blur_radius;
      if (blur_changed) ClearPopupBlur();  // New radius takes effect next open.
      bool next_dark = dark_mode;
      int next_accent = static_cast<int>(accent);
      ReadBool(*args, "dark", &next_dark);
      ReadInt(*args, "accent", &next_accent);
      std::wstring font_family;
      std::wstring font_path;
      const bool font_changed =
          ReadWideString(*args, "fontFamily", 1024, &font_family) &&
          ReadWideString(*args, "fontPath", 32768, &font_path) &&
          popup_fonts.Configure(std::move(font_family), std::move(font_path));
      std::wstring icon_font_path;
      bool icons_changed = ReadWideString(*args, "trayIconFontPath", 32768, &icon_font_path) &&
                            popup_fonts.ConfigureIcons(std::move(icon_font_path));
      const auto icon_values = args->find(EncodableValue("trayIconCodepoints"));
      if (icon_values != args->end()) {
        const auto* values = std::get_if<flutter::EncodableList>(&icon_values->second);
        std::array<wchar_t, 9> next{};
        bool valid = values && values->size() == next.size();
        for (std::size_t index = 0; valid && index < next.size(); ++index) {
          std::int64_t point = 0;
          if (const auto* integer = std::get_if<std::int32_t>(&(*values)[index])) point = *integer;
          if (const auto* large = std::get_if<std::int64_t>(&(*values)[index])) point = *large;
          valid = point >= 0xe000 && point <= 0xf8ff;
          if (valid) next[index] = static_cast<wchar_t>(point);
        }
        if (valid && next != material_glyphs) { material_glyphs = next; icons_changed = true; }
      }
      bool labels_changed = false;
      const auto labels_arg = args->find(EncodableValue("labels"));
      if (labels_arg != args->end()) {
        if (const auto* map = std::get_if<EncodableMap>(&labels_arg->second)) {
          constexpr std::array<const char*, 8> keys{
              "showMain", "showMini", "previous", "play", "pause", "next", "lyrics", "exit"};
          for (size_t i = 0; i < keys.size(); ++i) {
            std::wstring label;
            if (ReadWideString(*map, keys[i], 96, &label) && !label.empty() && label != labels[i]) {
              labels[i] = std::move(label);
              labels_changed = true;
            }
          }
        }
      }
      const auto next_color = static_cast<COLORREF>(next_accent & 0x00ffffff);
      const bool theme_changed = policy::NativeThemeChanged(
          accent, dark_mode, next_color, next_dark);
      dark_mode = next_dark;
      accent = next_color;
      active = true;
      // Use the 26.0.3 external-frame path: no custom region controller is
      // created/configured/removed. Legacy preference fields are ignored.
      taskbar_controls = controls;
      EnsureIcons(theme_changed);
      EnsureTray();
      EnsureTaskbar();
      UpdateButtons();
      if (theme_changed || font_changed || icons_changed || labels_changed || blur_changed) RefreshMenuAppearance();
      result->Success(Status());
    } else if (method == "setThumbnail") {
      std::int64_t width = 0;
      std::int64_t height = 0;
      const std::vector<std::uint8_t>* pixels = nullptr;
      if (args) {
        const auto found = args->find(EncodableValue("pixels"));
        if (found != args->end()) {
          pixels = std::get_if<std::vector<std::uint8_t>>(&found->second);
        }
      }
      if (!args || !ReadThumbnailDimension(*args, "width", &width) ||
          !ReadThumbnailDimension(*args, "height", &height) || !pixels ||
          !thumbnail::ValidPayload(width, height, pixels->size())) {
        result->Error("INVALID_ARGUMENT", "Thumbnail must be exact raw RGBA, 1..512 per axis");
        return;
      }
      if (!active) {
        result->Error("NOT_READY", "Configure desktop integration before a thumbnail");
        return;
      }
      thumbnail::RawImage large{};
      const thumbnail::RawImage* large_pointer = nullptr;
      const auto large_entry = args->find(EncodableValue("peek"));
      if (large_entry != args->end()) {
        const auto* map = std::get_if<EncodableMap>(&large_entry->second);
        if (map) {
          const auto entry = map->find(EncodableValue("pixels"));
          if (entry != map->end()) large.pixels = std::get_if<std::vector<std::uint8_t>>(&entry->second);
        }
        if (!map || !ReadThumbnailDimension(*map, "width", &large.width) ||
            !ReadThumbnailDimension(*map, "height", &large.height) || !large.pixels ||
            !thumbnail::ValidPeekPayload(large.width, large.height, large.pixels->size())) {
          result->Error("INVALID_ARGUMENT", "Peek must be exact raw RGBA, 1..2048 per axis and <=4MiB");
          return;
        }
        large_pointer = &large;
      }
      const auto update = thumbnail::ReplacePreviewImages(thumbnail_image, peek_image,
          {width, height, pixels}, large_pointer);
      if (update == thumbnail::Update::kOutOfMemory ||
          update == thumbnail::Update::kInvalid) {
        result->Error("THUMBNAIL_UNAVAILABLE", "Unable to cache thumbnail pixels");
        return;
      }
      const bool changed = update == thumbnail::Update::kChanged;
      ++thumbnail_generation;
      CancelThumbnailRetry();
      if (changed) thumbnail_retry_budget.Reset();
      thumbnail_dirty = thumbnail_dirty || changed;
      ApplyThumbnail(thumbnail_dirty);
      // This reply acknowledges ownership of the validated source, not a
      // promise that DWM is currently displaying it. A transient DWM failure
      // retains that source and reports availability separately; returning an
      // RPC error here would make Dart clear the very source being recovered.
      result->Success();
    } else if (method == "clearThumbnail") {
      const HRESULT cleared = ClearThumbnail();
      if (FAILED(cleared)) {
        result->Error("THUMBNAIL_UNAVAILABLE", "Windows could not restore its default preview");
      } else {
        result->Success();
      }
    } else if (method == "updatePlayback") {
      policy::Playback next;
      if (!args || !ReadBool(*args, "ready", &next.ready) ||
          !ReadBool(*args, "hasTrack", &next.has_track) ||
          !ReadBool(*args, "hasQueue", &next.has_queue) ||
          !ReadBool(*args, "playing", &next.playing) ||
          !ReadBool(*args, "buffering", &next.buffering) ||
          !ReadBool(*args, "desktopLyrics", &next.desktop_lyrics)) {
        result->Error("INVALID_ARGUMENT", "Invalid playback state");
        return;
      }
      const bool playback_changed = policy::PopupPlaybackChanged(playback, next);
      playback = next;
      const auto item = args->find(EncodableValue("title"));
      const auto* title = item == args->end()
                              ? nullptr
                              : std::get_if<std::string>(&item->second);
      const auto next_tooltip = Tooltip(title ? *title : "");
      const bool title_changed = next_tooltip != tooltip;
      if (title_changed) {
        tooltip = next_tooltip;
        EnsureTray();
      }
      UpdateButtons();
      // State updates are infrequent and may change every row (enabled state,
      // toggle glyph, check mark) plus the title. Hover remains row-local.
      if (!disposed && menu_window && (playback_changed || title_changed)) {
        InvalidateRect(menu_window, nullptr, FALSE);
      }
      result->Success();
    } else if (method == "prepareHide") {
      EnsureIcons();
      EnsureTray();
      result->Success(Status());
    } else if (method == "getState") {
      result->Success(Status());
    } else if (method == "showMenu") {
      // TrackPopupMenu runs a nested message loop which can destroy the runner.
      // Complete the channel reply while its engine is still known to exist.
      result->Success();
      ShowMenu();
    } else {
      result->NotImplemented();
    }
  }

  EncodableValue Status() {
    return EncodableValue(EncodableMap{
        {EncodableValue("revision"), EncodableValue(++revision)},
        {EncodableValue("trayAvailable"), EncodableValue(tray_available)},
        {EncodableValue("taskbarAvailable"), EncodableValue(taskbar_available)},
        {EncodableValue("thumbnailAvailable"), EncodableValue(thumbnail_available)},
        {EncodableValue("roundedWindowCornersAvailable"), EncodableValue(false)},
        {EncodableValue("windowVisible"),
         EncodableValue(IsWindowVisible(window) != FALSE)},
        {EncodableValue("minimized"), EncodableValue(IsIconic(window) != FALSE)},
        {EncodableValue("reason"),
         reason.empty() ? EncodableValue() : EncodableValue(reason)},
    });
  }

  void QueueState() {
    if (!active || disposed || state_pending || state_message == 0) return;
    state_pending = PostMessageW(window, state_message, 0, 0) != FALSE;
  }

  void CancelThumbnailRetry() {
    const auto timer = thumbnail_retry_timer.Cancel();
    if (timer != 0) KillTimer(window, timer);
  }

  void ScheduleThumbnailRetry() {
    if (disposed || !active || thumbnail_retry_timer.pending() || !IsWindow(window) ||
        (!thumbnail_image.size().valid() && !thumbnail_reset_pending)) return;
    const unsigned delay = thumbnail_retry_budget.NextDelayMs();
    if (delay == 0) return;
    thumbnail_retry_generation = thumbnail_generation;
    const auto timer = thumbnail_retry_timer.Arm();
    if (SetTimer(window, timer, delay, nullptr) == 0) thumbnail_retry_timer.Cancel();
  }

  // A completed old DWM call may have raced a nested replace/clear. Repair only
  // the current desired state on a bounded timer, never delete its new pixels.
  bool ThumbnailCallCurrent(std::uint64_t generation) {
    if (disposed) return false;
    if (generation == thumbnail_generation) return true;
    thumbnail_attributes = false;
    thumbnail_reset_pending = true;
    thumbnail_available = false;
    thumbnail_dirty = thumbnail_image.size().valid();
    ScheduleThumbnailRetry();
    QueueState();
    return false;
  }

  HRESULT ResetThumbnailAttributes(std::uint64_t generation) {
    const bool owned = thumbnail_attributes || thumbnail_reset_pending;
    thumbnail_attributes = false;
    thumbnail_reset_pending = owned;
    if (!owned || !IsWindow(window)) {
      thumbnail_reset_pending = false;
      return S_OK;
    }
    const BOOL disabled = FALSE;
    const HRESULT force = DwmSetWindowAttribute(window,
        DWMWA_FORCE_ICONIC_REPRESENTATION, &disabled, sizeof(disabled));
    // Dispose also uses this cleanup while disposed=true; only a newer
    // desired generation supersedes it, not the terminal flag itself.
    if (generation != thumbnail_generation) {
      ThumbnailCallCurrent(generation);
      return E_ABORT;
    }
    const HRESULT bitmap = DwmSetWindowAttribute(window,
        DWMWA_HAS_ICONIC_BITMAP, &disabled, sizeof(disabled));
    if (generation != thumbnail_generation) {
      ThumbnailCallCurrent(generation);
      return E_ABORT;
    }
    thumbnail_reset_pending = FAILED(force) || FAILED(bitmap);
    return FAILED(force) ? force : bitmap;
  }

  HRESULT ClearThumbnail() {
    // Retire desired pixels and cancel retries before any message-pumping API.
    ++thumbnail_generation;
    const auto generation = thumbnail_generation;
    CancelThumbnailRetry();
    thumbnail_retry_budget.Reset();
    thumbnail_available = false;
    thumbnail_dirty = false;
    thumbnail_image.Clear();
    peek_image.Clear();
    QueueState();
    const HRESULT status = ResetThumbnailAttributes(generation);
    if (generation == thumbnail_generation && FAILED(status)) ScheduleThumbnailRetry();
    return status;
  }

  void RecoverThumbnail(std::uint64_t generation) {
    if (!ThumbnailCallCurrent(generation) || !thumbnail_image.size().valid()) return;
    // Invalidate older in-flight operations without discarding the latest
    // accepted source or replenishing this source's finite retry budget.
    const auto recovery = ++thumbnail_generation;
    CancelThumbnailRetry();
    thumbnail_available = false;
    thumbnail_dirty = true;
    ResetThumbnailAttributes(recovery);
    if (disposed || recovery != thumbnail_generation) return;
    ScheduleThumbnailRetry();
    QueueState();
  }

  HRESULT ApplyThumbnail(bool invalidate, bool rebuild = false) {
    if (disposed || !active || !thumbnail_image.size().valid()) return E_ABORT;
    const auto generation = thumbnail_generation;
    if (!thumbnail_attributes || thumbnail_reset_pending || rebuild) {
      const BOOL enabled = TRUE;
      // Mark ownership before enabling, so partial failures undo both flags.
      thumbnail_attributes = true;
      thumbnail_reset_pending = false;
      HRESULT status = DwmSetWindowAttribute(window,
          DWMWA_FORCE_ICONIC_REPRESENTATION, &enabled, sizeof(enabled));
      if (!ThumbnailCallCurrent(generation)) return E_ABORT;
      if (SUCCEEDED(status)) {
        status = DwmSetWindowAttribute(window, DWMWA_HAS_ICONIC_BITMAP,
                                       &enabled, sizeof(enabled));
      }
      if (!ThumbnailCallCurrent(generation)) return E_ABORT;
      if (FAILED(status)) { RecoverThumbnail(generation); return status; }
      invalidate = true;
    }
    if (invalidate || thumbnail_dirty) {
      const HRESULT status = DwmInvalidateIconicBitmaps(window);
      if (!ThumbnailCallCurrent(generation)) return E_ABORT;
      if (FAILED(status)) { RecoverThumbnail(generation); return status; }
    }
    thumbnail_dirty = false;
    CancelThumbnailRetry();
    if (!thumbnail_available) {
      thumbnail_available = true;
      QueueState();
    }
    return S_OK;
  }

  void RebuildThumbnail() {
    CancelThumbnailRetry();
    thumbnail_retry_budget.Reset();
    ++thumbnail_generation;
    if (thumbnail_image.size().valid()) {
      ApplyThumbnail(true, true);
    } else if (thumbnail_reset_pending) {
      ClearThumbnail();
    }
  }

  bool DrawThumbnail(thumbnail::Size requested, bool live_preview) {
    if (!thumbnail_attributes || !thumbnail_image.size().valid()) return false;
    const auto& source = live_preview && peek_image.size().valid() ? peek_image : thumbnail_image;
    const auto peek = live_preview
        ? thumbnail::FitPeekLayout(source.size(), requested, GetDpiForWindow(window))
        : thumbnail::PeekLayout{};
    const auto target = live_preview ? peek.canvas
        : thumbnail::FitWithin(thumbnail_image.size(), requested);
    if (!target.valid()) return false;
    const auto generation = thumbnail_generation;
    BITMAPINFO info{};
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = target.width;
    info.bmiHeader.biHeight = -target.height;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    void* pixels = nullptr;
    HBITMAP bitmap = CreateDIBSection(nullptr, &info, DIB_RGB_COLORS, &pixels,
                                      nullptr, 0);
    const std::size_t bytes = static_cast<std::size_t>(target.width) * target.height * 4;
    HRESULT status = E_OUTOFMEMORY;
    const bool written = bitmap && pixels && (live_preview
        ? source.WritePeekBgra(peek, static_cast<std::uint8_t*>(pixels), bytes)
        : thumbnail_image.WriteBgra(target, static_cast<std::uint8_t*>(pixels), bytes));
    if (written) {
      status = live_preview
                   ? DwmSetIconicLivePreviewBitmap(window, bitmap, nullptr, 0)
                   : DwmSetIconicThumbnail(window, bitmap, 0);
    }
    // DWM copies it. Never retain an HBITMAP/HDC; only the two bounded raw
    // sources survive this request.
    if (bitmap) DeleteObject(bitmap);
    if (!ThumbnailCallCurrent(generation)) return false;
    if (FAILED(status)) RecoverThumbnail(generation);
    return SUCCEEDED(status);
  }

  NOTIFYICONDATAW TrayData() const {
    NOTIFYICONDATAW data{};
    data.cbSize = sizeof(data);
    // HWND + ID intentionally isolates simultaneous portable/QA instances;
    // a fixed global GUID would let one process replace another one's icon.
    data.hWnd = window;
    data.uID = kTrayId;
    data.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP | NIF_SHOWTIP;
    data.uCallbackMessage = kTrayCallback;
    data.hIcon = tray_icon;
    wcsncpy_s(data.szTip, tooltip.c_str(), _TRUNCATE);
    return data;
  }

  void EnsureIcons(bool refresh = false) {
    if (disposed || (tray_icon && !refresh)) return;
    UINT dpi = GetDpiForWindow(window);
    if (dpi == 0) dpi = 96;
    const int edge = std::clamp(GetSystemMetricsForDpi(SM_CXSMICON, dpi), 16, 64);
    std::array<HICON, 4> replacement{};
    const COLORREF foreground = TaskbarForeground(accent, dark_mode);
    for (size_t i = 0; i < replacement.size(); ++i) {
      replacement[i] = MakeMediaIcon(static_cast<int>(i), edge, foreground);
    }
    HICON replacement_tray = static_cast<HICON>(LoadImageW(
        GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
        edge, edge, LR_DEFAULTCOLOR));
    if (!replacement_tray) {
      replacement_tray = CopyIcon(LoadIconW(nullptr, IDI_APPLICATION));
    }
    for (size_t i = 0; i < icons.size(); ++i) {
      if (replacement[i]) {
        if (icons[i]) DestroyIcon(icons[i]);
        icons[i] = replacement[i];
      }
    }
    if (replacement_tray) {
      if (tray_icon) DestroyIcon(tray_icon);
      tray_icon = replacement_tray;
    }
  }

  void EnsureTray() {
    if (!active || disposed) return;
    auto data = TrayData();
    if (tray_icon && tray_available && Shell_NotifyIconW(NIM_MODIFY, &data)) {
      if (!disposed) reason.clear();
      return;
    }
    if (disposed) return;
    const bool added = tray_icon && Shell_NotifyIconW(NIM_ADD, &data) != FALSE;
    if (disposed) {
      // A Shell call may pump a final window-destruction message. Do not leave
      // behind an icon registered after that cleanup already ran.
      if (added) Shell_NotifyIconW(NIM_DELETE, &data);
      return;
    }
    tray_available = added;
    tray_v4 = false;
    if (tray_available) {
      data.uVersion = NOTIFYICON_VERSION_4;
      const bool version4 = Shell_NotifyIconW(NIM_SETVERSION, &data) != FALSE;
      if (disposed) return;
      tray_v4 = version4;
      reason.clear();
    } else {
      reason = "tray_unavailable";
    }
    QueueState();
  }

  void EnsureTaskbar() {
    if (disposed || taskbar || taskbar_connecting) return;
    // main.cpp owns the UI thread's COM apartment. Do not add an unmatched
    // CoInitialize call or attempt to change that thread's apartment here.
    taskbar_connecting = true;
    ITaskbarList3* replacement = nullptr;
    HRESULT result = CoCreateInstance(CLSID_TaskbarList, nullptr,
        CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&replacement));
    if (SUCCEEDED(result) && replacement && !disposed) {
      result = replacement->HrInit();
    }
    taskbar_connecting = false;
    // COM can pump messages. Only publish a fully initialized interface if a
    // nested cleanup has not already made this controller permanently closed.
    if (disposed || FAILED(result) || !replacement) {
      if (replacement) replacement->Release();
      taskbar_available = false;
      return;
    }
    taskbar = replacement;
    taskbar_available = true;
  }

  void UpdateButtons() {
    if (!active || disposed || !taskbar || !shell.taskbar_ready) return;
    if (!shell.ShouldAdd(taskbar_controls) && !shell.ShouldUpdate()) return;
    const std::array<unsigned, 3> ids{policy::kPrevious, policy::kToggle,
                                      policy::kNext};
    const std::array<HICON, 3> images{icons[0],
                                      playback.playing ? icons[2] : icons[1],
                                      icons[3]};
    const std::array<const wchar_t*, 3> tips{
        labels[2].c_str(), labels[playback.playing ? 4 : 3].c_str(), labels[5].c_str()};
    THUMBBUTTON buttons[3]{};
    for (size_t i = 0; i < ids.size(); ++i) {
      buttons[i].dwMask = THB_ICON | THB_TOOLTIP | THB_FLAGS;
      buttons[i].iId = ids[i];
      buttons[i].hIcon = images[i];
      wcsncpy_s(buttons[i].szTip, tips[i], _TRUNCATE);
      buttons[i].dwFlags = !taskbar_controls
                              ? THBF_HIDDEN
                              : policy::Allows(policy::MenuAction(ids[i]), playback)
                                    ? THBF_ENABLED : THBF_DISABLED;
    }
    auto* current = taskbar;
    current->AddRef();
    const HRESULT result = shell.buttons_added
                               ? current->ThumbBarUpdateButtons(window, 3, buttons)
                               : current->ThumbBarAddButtons(window, 3, buttons);
    current->Release();
    if (disposed || taskbar != current) return;
    if (SUCCEEDED(result)) {
      shell.buttons_added = true;
      taskbar_available = true;
    } else {
      taskbar_available = false;
    }
    QueueState();
  }

  void Emit(policy::Action action) {
    if (disposed || !active || !channel || !policy::Allows(action, playback)) {
      return;
    }
    channel->InvokeMethod("action", std::make_unique<EncodableValue>(
                                         policy::ActionName(action)));
  }

  struct PopupItem {
    unsigned id;
    const wchar_t* label;
    policy::PopupIcon icon;
    bool separator;
  };

  std::array<PopupItem, 9> PopupItems() const {
    return {{{policy::kShowMain, labels[0].c_str(),
              policy::PopupIconForAction(policy::Action::kShowMain), false},
             {policy::kShowMini, labels[1].c_str(),
              policy::PopupIconForAction(policy::Action::kShowMini), false},
             {0, L"", policy::PopupIcon::kNone, true},
             {policy::kPrevious, labels[2].c_str(),
              policy::PopupIconForAction(policy::Action::kPrevious), false},
             {policy::kToggle,
              labels[playback.playing ? 4 : 3].c_str(),
              policy::PopupIconForAction(policy::Action::kToggle), false},
             {policy::kNext, labels[5].c_str(),
              policy::PopupIconForAction(policy::Action::kNext), false},
             {policy::kDesktopLyrics, labels[6].c_str(),
              policy::PopupIconForAction(policy::Action::kDesktopLyrics),
              false},
             {0, L"", policy::PopupIcon::kNone, true},
             {policy::kExit, labels[7].c_str(),
              policy::PopupIconForAction(policy::Action::kExit), false}}};
  }

  int Scale(int value) const {
    return MulDiv(value, static_cast<int>(menu_dpi), 96);
  }

  int PopupHeight() const {
    int result = Scale(62 + 16);
    for (const auto& item : PopupItems()) {
      result += Scale(item.separator ? 10 : 44);
    }
    return result;
  }

  RECT PopupItemRect(int target, int width) const {
    int top = Scale(62);
    const auto items = PopupItems();
    for (int index = 0; index < static_cast<int>(items.size()); ++index) {
      const int height = Scale(items[index].separator ? 10 : 44);
      if (index == target) {
        return RECT{Scale(8), top, width - Scale(8), top + height};
      }
      top += height;
    }
    return RECT{};
  }

  int PopupItemAt(POINT point) const {
    if (!menu_window) return -1;
    RECT client{};
    GetClientRect(menu_window, &client);
    const auto items = PopupItems();
    for (int index = 0; index < static_cast<int>(items.size()); ++index) {
      const RECT row = PopupItemRect(index, client.right);
      if (!items[index].separator && PtInRect(&row, point)) return index;
    }
    return -1;
  }

  bool PopupAllows(int index) const {
    const auto items = PopupItems();
    return index >= 0 && index < static_cast<int>(items.size()) &&
           !items[index].separator &&
           policy::Allows(policy::MenuAction(items[index].id), playback);
  }

  int NextPopupItem(int from, int direction) const {
    const auto items = PopupItems();
    int current = from;
    for (size_t attempt = 0; attempt < items.size(); ++attempt) {
      current = (current + direction + static_cast<int>(items.size())) %
                static_cast<int>(items.size());
      if (!items[current].separator && PopupAllows(current)) return current;
    }
    return from;
  }

  void DrawMaterialMenu(HDC dc) {
    RECT client{};
    GetClientRect(menu_window, &client);
    const COLORREF background = BlendColor(accent,
        dark_mode ? RGB(38, 38, 42) : RGB(250, 249, 252), dark_mode ? 16 : 10);
    const COLORREF foreground = policy::ContrastAdjustedAccent(BlendColor(accent,
        dark_mode ? RGB(245, 243, 247) : RGB(35, 32, 37), 48), background);
    const COLORREF secondary = policy::ContrastAdjustedAccent(BlendColor(accent,
        dark_mode ? RGB(198, 194, 201) : RGB(91, 86, 94), 40), background);
    const COLORREF disabled =
        dark_mode ? RGB(112, 109, 114) : RGB(160, 156, 162);
    SetDCBrushColor(dc, background);
    FillRect(dc, &client, static_cast<HBRUSH>(GetStockObject(DC_BRUSH)));
    popup_blur.Draw(dc, client, background);
    SetBkMode(dc, TRANSPARENT);
    popup_fonts.Ensure(menu_dpi);
    const auto old_font = SelectObject(dc, popup_fonts.ForText(dc, tooltip.c_str(), true));
    SetTextColor(dc, foreground);
    RECT title{Scale(18), Scale(11), client.right - Scale(18), Scale(38)};
    DrawTextW(dc, tooltip.c_str(), -1, &title,
              DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS | DT_NOPREFIX);
    SelectObject(dc, popup_fonts.ForText(dc, kPublisherCaption));
    SetTextColor(dc, secondary);
    RECT caption{Scale(18), Scale(36), client.right - Scale(18), Scale(56)};
    DrawTextW(dc, kPublisherCaption, -1, &caption,
              DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS | DT_NOPREFIX);

    const auto items = PopupItems();
    for (int index = 0; index < static_cast<int>(items.size()); ++index) {
      RECT row = PopupItemRect(index, client.right);
      if (items[index].separator) {
        const auto old_pen = SelectObject(dc, GetStockObject(DC_PEN));
        SetDCPenColor(dc, BlendColor(foreground, background, 30));
        const int y = (row.top + row.bottom) / 2;
        MoveToEx(dc, Scale(16), y, nullptr);
        LineTo(dc, client.right - Scale(16), y);
        SelectObject(dc, old_pen);
        continue;
      }
      const bool enabled = PopupAllows(index);
      const bool highlighted = enabled &&
                               (index == menu_hovered || index == menu_focused);
      const COLORREF row_background = highlighted
          ? BlendColor(accent, background, dark_mode ? 58 : 38) : background;
      if (highlighted) {
        const auto old_pen = SelectObject(dc, GetStockObject(NULL_PEN));
        const auto old_brush = SelectObject(dc, GetStockObject(DC_BRUSH));
        SetDCBrushColor(dc, row_background);
        RoundRect(dc, row.left, row.top + Scale(2), row.right,
                  row.bottom - Scale(2), Scale(12), Scale(12));
        SelectObject(dc, old_brush);
        SelectObject(dc, old_pen);
      }
      const COLORREF item_color = enabled
          ? policy::ContrastAdjustedAccent(foreground, row_background) : disabled;
      const COLORREF capsule_color = policy::TrayIconCapsuleColor(accent, row_background, dark_mode, enabled);
      const COLORREF icon_color = !enabled ? disabled
          : items[index].id == policy::kExit ? policy::ContrastAdjustedAccent(item_color, capsule_color)
          : policy::ContrastAdjustedAccent(accent, capsule_color);
      const int material_index = policy::PopupMaterialIndex(items[index].icon, playback.playing);
      const bool material = popup_fonts.material_icons_loaded() && material_index >= 0 &&
                               material_glyphs[material_index] != 0;
      const wchar_t glyph = material
          ? material_glyphs[material_index] : policy::PopupGlyph(items[index].icon, playback.playing);
      const auto capsule = policy::TrayIconCapsuleRect(row, menu_dpi);
      policy::PaintTrayIconCapsule(dc, capsule, popup_fonts.icons(material), glyph,
                                    capsule_color, icon_color);
      SelectObject(dc, popup_fonts.ForText(dc, items[index].label));
      SetTextColor(dc, item_color);
      RECT label{row.left + Scale(48), row.top,
                 row.right - Scale(34), row.bottom};
      DrawTextW(dc, items[index].label, -1, &label,
                DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS | DT_NOPREFIX);
      if (items[index].id == policy::kDesktopLyrics &&
          playback.desktop_lyrics) {
        if (popup_fonts.material_icons_loaded() && material_glyphs[8]) {
          SelectObject(dc, popup_fonts.icons());
          RECT checked{row.right - Scale(30), row.top, row.right - Scale(8), row.bottom};
          SetTextColor(dc, icon_color);
          DrawTextW(dc, &material_glyphs[8], 1, &checked,
                      DT_SINGLELINE | DT_CENTER | DT_VCENTER | DT_NOPREFIX);
        } else {
        const auto old_pen = SelectObject(dc, GetStockObject(DC_PEN));
        SetDCPenColor(dc, icon_color);
        MoveToEx(dc, row.right - Scale(25), row.top + Scale(22), nullptr);
        LineTo(dc, row.right - Scale(20), row.top + Scale(27));
        LineTo(dc, row.right - Scale(12), row.top + Scale(17));
        SelectObject(dc, old_pen);
        }
      }
      if (index == menu_focused && GetFocus() == menu_window) {
        RECT focus = row;
        InflateRect(&focus, -Scale(5), -Scale(5));
        DrawFocusRect(dc, &focus);
      }
    }
    SelectObject(dc, old_font);
  }

  void InvalidatePopupSelection(int old_hovered, int old_focused) {
    if (!menu_window) return;
    RECT client{};
    GetClientRect(menu_window, &client);
    const std::array<int, 4> changed{
        old_hovered, old_focused, menu_hovered, menu_focused};
    for (size_t i = 0; i < changed.size(); ++i) {
      if (changed[i] < 0) continue;
      bool duplicate = false;
      for (size_t j = 0; j < i; ++j) duplicate |= changed[j] == changed[i];
      if (duplicate) continue;
      const RECT row = PopupItemRect(changed[i], client.right);
      InvalidateRect(menu_window, &row, FALSE);
    }
  }

  void ActivatePopupItem(int index) {
    if (!PopupAllows(index)) return;
    const auto action = policy::MenuAction(PopupItems()[index].id);
    if (menu_window) DestroyWindow(menu_window);
    if (!disposed) Emit(action);
  }

  static LRESULT CALLBACK PopupWindowProc(HWND hwnd, UINT message,
                                           WPARAM wparam, LPARAM lparam) {
    auto* self = reinterpret_cast<Impl*>(
        GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
      const auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
      self = static_cast<Impl*>(create->lpCreateParams);
      SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                        reinterpret_cast<LONG_PTR>(self));
    }
    if (!self) return DefWindowProcW(hwnd, message, wparam, lparam);
    // Releasing WinRT subscriptions on close may pump STA messages that
    // destroy the owner/controller. Keep this callback's state alive until it
    // returns; disposed still prevents actions or resources from resurfacing.
    const auto keep_alive = self->weak_from_this().lock();
    if (!keep_alive) return DefWindowProcW(hwnd, message, wparam, lparam);
    switch (message) {
      case WM_ERASEBKGND:
        return 1;
      case WM_NCHITTEST:
        return HTCLIENT;
      case WM_GETDLGCODE:
        return DLGC_WANTARROWS | DLGC_WANTCHARS;
      case WM_PAINT: {
        PAINTSTRUCT paint{};
        HDC dc = BeginPaint(hwnd, &paint);
        const bool painted = self->popup_paint.Paint(dc, paint.rcPaint,
            [self](HDC buffer) { self->DrawMaterialMenu(buffer); });
        EndPaint(hwnd, &paint);
        if (!painted) {
          // Do not leave an erased/stale popup validated forever, nor reopen
          // an unexpected menu after focus moved. Next invocation uses HMENU.
          self->custom_menu_paint_failed = true;
          DestroyWindow(hwnd);
        }
        return 0;
      }
      case WM_MOUSEMOVE: {
        if (!self->menu_tracking) {
          TRACKMOUSEEVENT tracking{sizeof(tracking), TME_LEAVE, hwnd, 0};
          self->menu_tracking = TrackMouseEvent(&tracking) != FALSE;
        }
        POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        const int next = self->PopupItemAt(point);
        if (next != self->menu_hovered) {
          const int old_hovered = self->menu_hovered;
          const int old_focused = self->menu_focused;
          self->menu_hovered = next;
          if (self->PopupAllows(next)) self->menu_focused = next;
          self->InvalidatePopupSelection(old_hovered, old_focused);
        }
        return 0;
      }
      case WM_MOUSELEAVE: {
        const int old_hovered = self->menu_hovered;
        self->menu_tracking = false;
        self->menu_hovered = -1;
        self->InvalidatePopupSelection(old_hovered, self->menu_focused);
        return 0;
      }
      case WM_LBUTTONUP: {
        POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        self->ActivatePopupItem(self->PopupItemAt(point));
        return 0;
      }
      case WM_KEYDOWN:
        if (wparam == VK_ESCAPE) {
          DestroyWindow(hwnd);
        } else if (wparam == VK_DOWN || wparam == VK_UP) {
          const int old_hovered = self->menu_hovered;
          const int old_focused = self->menu_focused;
          self->menu_hovered = -1;
          self->menu_focused = self->NextPopupItem(
              self->menu_focused, wparam == VK_DOWN ? 1 : -1);
          self->InvalidatePopupSelection(old_hovered, old_focused);
        } else if (wparam == VK_RETURN || wparam == VK_SPACE) {
          self->ActivatePopupItem(self->menu_focused);
        }
        return 0;
      case WM_ACTIVATE:
        if (LOWORD(wparam) == WA_INACTIVE) DestroyWindow(hwnd);
        return 0;
      case WM_CLOSE:
        DestroyWindow(hwnd);
        return 0;
      case WM_NCDESTROY:
        if (self->menu_window == hwnd) self->menu_window = nullptr;
        self->menu_open = false;
        self->menu_tracking = false;
        self->popup_paint.Clear();
        self->ClearPopupBlur();
        if (!self->disposed && self->tray_available) {
          auto data = self->TrayData();
          Shell_NotifyIconW(NIM_SETFOCUS, &data);
        }
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
        return DefWindowProcW(hwnd, message, wparam, lparam);
      default:
        return DefWindowProcW(hwnd, message, wparam, lparam);
    }
  }

  bool ShowMaterialMenu(POINT anchor) {
    if (custom_menu_paint_failed || SystemHighContrast()) return false;
    static std::once_flag registration;
    static bool registered = false;
    std::call_once(registration, [&]() {
      WNDCLASSEXW klass{};
      klass.cbSize = sizeof(klass);
      klass.style = CS_DROPSHADOW;
      klass.lpfnWndProc = PopupWindowProc;
      klass.hInstance = GetModuleHandleW(nullptr);
      klass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
      klass.lpszClassName = L"DanPlayer.MaterialTrayPopup.26";
      registered = RegisterClassExW(&klass) != 0 ||
                   GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
    });
    if (!registered) return false;
    menu_dpi = GetDpiForWindow(window);
    if (menu_dpi == 0) menu_dpi = 96;
    const int width = Scale(292);
    const int height = PopupHeight();
    MONITORINFO monitor{sizeof(monitor)};
    const HMONITOR target = MonitorFromPoint(anchor, MONITOR_DEFAULTTONEAREST);
    if (!GetMonitorInfoW(target, &monitor)) return false;
    RECT bounds{};
    if (!policy::PlaceTrayPopup(anchor, width, height, monitor.rcWork, &bounds)) return false;
    // Allocate before showing anything; use the accessible native menu if a
    // complete atomic frame cannot be buffered (including very high DPI).
    if (!popup_paint.Open(width, height)) return false;
    ClearPopupBlur();
    if (tray_blur_radius > 0) {
      const double requested_radius = tray_blur_radius;
      const bool effects = popup_effects.Open(window, kTrayEffectsChanged);
      // WinRT activation/subscription can pump messages, including shutdown
      // or a new configuration. Never start a capture after that generation.
      if (disposed || !active || requested_radius != tray_blur_radius) {
        popup_paint.Clear();
        ClearPopupBlur();
        return false;
      }
      // A display/contrast change could have arrived while WinRT activated.
      // Re-resolve the final rectangle before any pixels are read.
      if (SystemHighContrast() || !GetMonitorInfoW(target, &monitor) ||
          !policy::PlaceTrayPopup(anchor, width, height, monitor.rcWork, &bounds)) {
        popup_paint.Clear();
        ClearPopupBlur();
        return false;
      }
      // The HWND has not been created yet. Read ONLY its final rectangle once,
      // without kernel padding or any full-screen staging image.
      popup_blur.Open(bounds, monitor.rcWork, tray_blur_radius, menu_dpi,
          policy::TrayBlurAllowed(SystemHighContrast(), effects, policy::TrayEnergySaver()),
          [](HDC destination, const RECT& rect) {
            const HDC screen = GetDC(nullptr);
            if (!screen) return false;
            const bool copied = BitBlt(destination, 0, 0,
                rect.right - rect.left, rect.bottom - rect.top, screen,
                rect.left, rect.top, SRCCOPY | CAPTUREBLT) != FALSE;
            ReleaseDC(nullptr, screen);
            return copied;
          });
      if (!popup_blur.ready()) ClearPopupBlur();
    }
    if (disposed || !active) {
      popup_paint.Clear(); ClearPopupBlur(); return false;
    }
    HWND popup = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_TOPMOST, L"DanPlayer.MaterialTrayPopup.26",
        L"Dan Player", WS_POPUP, bounds.left, bounds.top, width, height, window, nullptr,
        GetModuleHandleW(nullptr), this);
    if (!popup || disposed || !active || !IsWindow(popup)) {
      if (popup && IsWindow(popup)) DestroyWindow(popup);
      popup_paint.Clear();
      ClearPopupBlur();
      return false;
    }
    const int radius = Scale(16);
    HRGN region = CreateRoundRectRgn(0, 0, width + 1, height + 1,
                                     radius, radius);
    if (region && !SetWindowRgn(popup, region, TRUE)) DeleteObject(region);
    menu_window = popup;
    menu_open = true;
    menu_hovered = -1;
    menu_tracking = false;
    menu_focused = NextPopupItem(-1, 1);
    ShowWindow(popup, SW_SHOWNORMAL);
    if (disposed || menu_window != popup) return true;
    SetForegroundWindow(popup);
    if (disposed || menu_window != popup) return true;
    SetFocus(popup);
    return true;
  }

  void ShowNativeMenu(POINT location) {
    if (disposed || !active) return;
    HMENU menu = CreatePopupMenu();
    if (!menu) return;
    const auto append = [&](unsigned id, const wchar_t* label,
                            bool checked = false) {
      UINT flags = MF_STRING;
      if (!policy::Allows(policy::MenuAction(id), playback)) flags |= MF_GRAYED;
      if (checked) flags |= MF_CHECKED;
      AppendMenuW(menu, flags, id, label);
    };
    append(policy::kShowMain, labels[0].c_str());
    append(policy::kShowMini, labels[1].c_str());
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    append(policy::kPrevious, labels[2].c_str());
    append(policy::kToggle, labels[playback.playing ? 4 : 3].c_str());
    append(policy::kNext, labels[5].c_str());
    append(policy::kDesktopLyrics, labels[6].c_str(),
           playback.desktop_lyrics);
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    append(policy::kExit, labels[7].c_str());
    menu_open = true;
    SetForegroundWindow(window);
    const UINT command = static_cast<UINT>(TrackPopupMenu(
        menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
        location.x, location.y, 0, window, nullptr));
    DestroyMenu(menu);
    menu_open = false;
    if (disposed) return;
    PostMessageW(window, WM_NULL, 0, 0);
    auto data = TrayData();
    Shell_NotifyIconW(NIM_SETFOCUS, &data);
    Emit(policy::MenuAction(command));
  }

  void ShowMenu() {
    if (disposed || !active || !tray_available || menu_open || menu_opening) return;
    menu_opening = true;
    POINT location{};
    GetCursorPos(&location);
    NOTIFYICONIDENTIFIER identifier{};
    identifier.cbSize = sizeof(identifier);
    identifier.hWnd = window;
    identifier.uID = kTrayId;
    RECT icon_rect{};
    if (SUCCEEDED(Shell_NotifyIconGetRect(&identifier, &icon_rect))) {
      location.x = icon_rect.left;
      location.y = icon_rect.top;
    }
    if (!ShowMaterialMenu(location)) ShowNativeMenu(location);
    menu_opening = false;
  }

  void ClearPopupBlur() {
    popup_blur.Clear();
    popup_effects.Close();
  }

  void RefreshMenuAppearance() {
    if (!menu_window) return;
    const HWND current = menu_window;
    // A contrast-theme toggle can arrive while a custom popup is already open.
    // Retire it; the next invocation uses the system-colored native HMENU.
    if (SystemHighContrast()) {
      DestroyWindow(current);
    } else {
      // Never capture again over our own popup. A disabled effect retires the
      // static image immediately; re-enabling waits for the next menu opening.
      const bool allowed = policy::TrayBlurAllowed(false, popup_effects.enabled(),
                                                   policy::TrayEnergySaver());
      if (disposed || menu_window != current) return;
      if (!allowed) ClearPopupBlur();
      if (disposed || menu_window != current) return;
      InvalidateRect(current, nullptr, FALSE);
    }
  }

  std::optional<LRESULT> Handle(UINT message, WPARAM wparam, LPARAM lparam) {
    if (disposed) return std::nullopt;
    if (message == WM_TIMER && thumbnail::RetryTimer::Owns(wparam)) {
      if (!thumbnail_retry_timer.Matches(wparam)) return 0;
      const bool current = thumbnail_retry_generation == thumbnail_generation;
      CancelThumbnailRetry();
      if (current) {
        if (thumbnail_image.size().valid()) {
          ApplyThumbnail(true, true);
        } else if (thumbnail_reset_pending) {
          const auto generation = thumbnail_generation;
          const HRESULT status = ResetThumbnailAttributes(generation);
          if (generation == thumbnail_generation && FAILED(status)) ScheduleThumbnailRetry();
        }
      }
      return 0;
    }
    if (message == kTrayEffectsChanged) {
      RefreshMenuAppearance();
      return 0;
    }
    if (message == state_message && state_message != 0) {
      state_pending = false;
      if (active && channel) {
        channel->InvokeMethod("stateChanged",
                               std::make_unique<EncodableValue>(Status()));
      }
      return 0;
    }
    if (message == taskbar_created && taskbar_created != 0) {
      shell.ExplorerRestarted();
      tray_available = false;
      if (taskbar) { taskbar->Release(); taskbar = nullptr; }
      EnsureTray();
      EnsureTaskbar();
      RebuildThumbnail();
      QueueState();
      // Other plugins may also need Shell restart notifications.
      return std::nullopt;
    }
    if (message == taskbar_button_created && taskbar_button_created != 0) {
      shell.TaskbarButtonCreated();
      EnsureTaskbar();
      UpdateButtons();
      RebuildThumbnail();
      QueueState();
      return std::nullopt;
    }
    if (message == WM_DWMSENDICONICTHUMBNAIL) {
      if (DrawThumbnail(thumbnail::RequestedSize(static_cast<std::uintptr_t>(lparam)), false)) return 0;
      return std::nullopt;
    }
    if (message == WM_DWMSENDICONICLIVEPREVIEWBITMAP) {
      if (DrawThumbnail(peek_client_geometry.Resolve(window), true)) return 0;
      return std::nullopt;
    }
    if (message == WM_DWMCOMPOSITIONCHANGED) {
      RebuildThumbnail();
      // Backdrop and other plugins must still receive the compositor event.
      return std::nullopt;
    }
    if (message == kTrayCallback) {
      const UINT icon_id = tray_v4 ? HIWORD(lparam) : static_cast<UINT>(wparam);
      const UINT event = tray_v4 ? LOWORD(lparam) : static_cast<UINT>(lparam);
      if (icon_id != kTrayId || !tray_available) return std::nullopt;
      if ((tray_v4 && (event == NIN_SELECT || event == NIN_KEYSELECT)) ||
          (!tray_v4 && event == WM_LBUTTONUP)) {
        Emit(policy::Action::kRestore);
      } else if ((tray_v4 && event == WM_CONTEXTMENU) ||
                 (!tray_v4 && event == WM_RBUTTONUP)) {
        ShowMenu();
      }
      return 0;
    }
    if (message == WM_COMMAND) {
      const auto action = policy::TaskbarAction(wparam);
      if (action != policy::Action::kNone) {
        if (taskbar_controls && shell.buttons_added) Emit(action);
        return 0;
      }
    }
    if (message == WM_SHOWWINDOW || message == WM_SIZE || message == WM_ACTIVATE) {
      peek_client_geometry.Observe(window, message == WM_SIZE && wparam == SIZE_MINIMIZED);
      QueueState();
    }
    if (message == WM_DPICHANGED || message == WM_THEMECHANGED ||
        message == WM_SETTINGCHANGE || message == WM_POWERBROADCAST) {
      popup_fonts.ResetHandles();
      EnsureIcons(true);
      EnsureTray();
      UpdateButtons();
      RefreshMenuAppearance();
    }
    if (message == WM_ENDSESSION && wparam != FALSE) {
      Emit(policy::Action::kExit);
      Dispose();
    }
    // Only owned iconic-bitmap requests are consumed. Lifecycle, frame,
    // compositor-change, resize and system-shutdown messages keep propagating.
    return std::nullopt;
  }

  void Dispose() {
    if (disposed) return;
    // Make the terminal state visible before any API which can pump messages.
    // Reentrant destroy/Explorer callbacks must not resurrect Shell resources.
    disposed = true;
    active = false;
    ClearThumbnail();
    const bool had_tray = std::exchange(tray_available, false);
    auto* old_taskbar = std::exchange(taskbar, nullptr);
    const bool had_buttons = shell.buttons_added;
    shell.ExplorerRestarted();
    taskbar_available = false;
    taskbar_controls = false;
    if (menu_window) DestroyWindow(menu_window);
    if (menu_open) EndMenu();
    popup_paint.Clear();
    ClearPopupBlur();
    popup_fonts.Clear();
    if (old_taskbar && had_buttons) {
      THUMBBUTTON buttons[3]{};
      const std::array<unsigned, 3> ids{policy::kPrevious, policy::kToggle,
                                       policy::kNext};
      for (size_t i = 0; i < ids.size(); ++i) {
        buttons[i].dwMask = THB_FLAGS;
        buttons[i].iId = ids[i];
        buttons[i].dwFlags = THBF_HIDDEN;
      }
      old_taskbar->ThumbBarUpdateButtons(window, 3, buttons);
    }
    auto data = TrayData();
    if (had_tray) Shell_NotifyIconW(NIM_DELETE, &data);
    if (old_taskbar) old_taskbar->Release();
    for (auto& icon : icons) {
      if (icon) DestroyIcon(icon);
      icon = nullptr;
    }
    if (tray_icon) DestroyIcon(tray_icon);
    tray_icon = nullptr;
  }
};

DesktopIntegrationController::DesktopIntegrationController(
    HWND window, flutter::FlutterEngine* engine)
    : impl_(std::make_shared<Impl>(window)) {
  impl_->Connect(engine, impl_);
}

DesktopIntegrationController::~DesktopIntegrationController() {
  impl_->Dispose();
  if (impl_->channel) impl_->channel->SetMethodCallHandler(nullptr);
  impl_->channel.reset();
}

std::optional<LRESULT> DesktopIntegrationController::HandleMessage(
    UINT message, WPARAM wparam, LPARAM lparam) {
  auto state = impl_;
  return state->Handle(message, wparam, lparam);
}
