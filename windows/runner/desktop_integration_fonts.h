#ifndef RUNNER_DESKTOP_INTEGRATION_FONTS_H_
#define RUNNER_DESKTOP_INTEGRATION_FONTS_H_

#include <windows.h>
#include <gdiplus.h>

#include <algorithm>
#include <memory>
#include <string>

#pragma comment(lib, "gdiplus.lib")

namespace desktop_integration {

// GDI does not know Flutter's FontLoader aliases. Register the same local font
// privately, resolve its native family, and reuse DPI-specific HFONTs between
// paints. Nothing is installed into Windows or shared with other processes.
class PopupFonts {
 public:
  PopupFonts() {
    Gdiplus::GdiplusStartupInput input;
    if (Gdiplus::GdiplusStartup(&gdiplus_, &input, nullptr) != Gdiplus::Ok) {
      gdiplus_ = 0;
    }
  }
  ~PopupFonts() {
    Clear();
    if (gdiplus_) Gdiplus::GdiplusShutdown(gdiplus_);
  }
  PopupFonts(const PopupFonts&) = delete;
  PopupFonts& operator=(const PopupFonts&) = delete;

  bool Configure(std::wstring family, std::wstring path) {
    if (family == requested_family_ && path == requested_path_) return false;
    Clear();
    requested_family_ = std::move(family);
    requested_path_ = std::move(path);
    if (!requested_path_.empty() &&
        AddFontResourceExW(requested_path_.c_str(), FR_PRIVATE, nullptr) > 0) {
      registered_path_ = requested_path_;
      face_ = PrivateFamily(registered_path_, requested_family_);
    }
    if (face_.empty() && requested_family_ != L"DanPingFangSC" &&
        requested_family_.size() < LF_FACESIZE) {
      face_ = requested_family_;
    }
    return true;
  }

  void Ensure(UINT dpi) {
    dpi = std::clamp(dpi, 48u, 768u);
    if (dpi_ == dpi && title_ && row_ && icons_) return;
    ResetHandles();
    dpi_ = dpi;
    NONCLIENTMETRICSW metrics{};
    metrics.cbSize = sizeof(metrics);
    if (!SystemParametersInfoForDpi(SPI_GETNONCLIENTMETRICS, sizeof(metrics),
                                    &metrics, 0, dpi)) {
      SystemParametersInfoW(SPI_GETNONCLIENTMETRICS, sizeof(metrics), &metrics, 0);
    }
    LOGFONTW font = metrics.lfMenuFont;
    font.lfCharSet = DEFAULT_CHARSET;
    font.lfQuality = CLEARTYPE_QUALITY;
    if (!face_.empty()) wcsncpy_s(font.lfFaceName, face_.c_str(), _TRUNCATE);
    font.lfHeight = -MulDiv(15, static_cast<int>(dpi), 96);
    font.lfWeight = FW_SEMIBOLD;
    title_ = CreateFontIndirectW(&font);
    font.lfHeight = -MulDiv(14, static_cast<int>(dpi), 96);
    font.lfWeight = FW_NORMAL;
    row_ = CreateFontIndirectW(&font);
    font.lfHeight = -MulDiv(19, static_cast<int>(dpi), 96);
    wcsncpy_s(font.lfFaceName, L"Segoe MDL2 Assets", _TRUNCATE);
    icons_ = CreateFontIndirectW(&font);
  }

  void ResetHandles() {
    if (title_) DeleteObject(title_);
    if (row_) DeleteObject(row_);
    if (icons_) DeleteObject(icons_);
    title_ = row_ = icons_ = nullptr;
    dpi_ = 0;
  }

  void Clear() {
    // Fonts must not remain selected into a DC while resources are retired.
    ResetHandles();
    if (!registered_path_.empty()) {
      RemoveFontResourceExW(registered_path_.c_str(), FR_PRIVATE, nullptr);
    }
    registered_path_.clear();
    requested_path_.clear();
    requested_family_.clear();
    face_.clear();
  }

  HFONT title() const { return OrSystem(title_); }
  HFONT row() const { return OrSystem(row_); }
  HFONT icons() const { return OrSystem(icons_); }
  const std::wstring& face() const { return face_; }
  bool private_font_loaded() const { return !registered_path_.empty(); }

 private:
  static HFONT OrSystem(HFONT font) {
    return font ? font : static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
  }

  std::wstring PrivateFamily(const std::wstring& path,
                             const std::wstring& requested) const {
    if (!gdiplus_) return {};
    Gdiplus::PrivateFontCollection collection;
    if (collection.AddFontFile(path.c_str()) != Gdiplus::Ok) return {};
    const int count = collection.GetFamilyCount();
    if (count <= 0 || count > 64) return {};
    auto families = std::make_unique<Gdiplus::FontFamily[]>(count);
    int found = 0;
    if (collection.GetFamilies(count, families.get(), &found) != Gdiplus::Ok) {
      return {};
    }
    std::wstring first;
    for (int index = 0; index < found; ++index) {
      WCHAR name[LF_FACESIZE]{};
      if (families[index].GetFamilyName(name) != Gdiplus::Ok) continue;
      if (first.empty()) first = name;
      const std::wstring family(name);
      if (_wcsnicmp(requested.c_str(), family.c_str(), family.size()) == 0) {
        return family;
      }
    }
    // A FontLoader alias has no GDI identity. A single-face TTF is unambiguous;
    // TTC collections otherwise retain the requested system family fallback.
    return count == 1 || requested == L"DanPingFangSC" ? first : std::wstring{};
  }

  ULONG_PTR gdiplus_ = 0;
  std::wstring requested_family_;
  std::wstring requested_path_;
  std::wstring registered_path_;
  std::wstring face_;
  UINT dpi_ = 0;
  HFONT title_ = nullptr;
  HFONT row_ = nullptr;
  HFONT icons_ = nullptr;
};

}  // namespace desktop_integration
#endif  // RUNNER_DESKTOP_INTEGRATION_FONTS_H_
