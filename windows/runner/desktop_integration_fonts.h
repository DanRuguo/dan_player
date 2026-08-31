#ifndef RUNNER_DESKTOP_INTEGRATION_FONTS_H_
#define RUNNER_DESKTOP_INTEGRATION_FONTS_H_

#include <windows.h>
#include <gdiplus.h>

#include <algorithm>
#include <array>
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

  bool ConfigureIcons(std::wstring path) {
    if (path == icon_requested_path_) return false;
    ResetHandles();
    if (!icon_registered_path_.empty()) {
      RemoveFontResourceExW(icon_registered_path_.c_str(), FR_PRIVATE, nullptr);
    }
    icon_requested_path_ = std::move(path);
    icon_registered_path_.clear();
    icon_face_.clear();
    if (!icon_requested_path_.empty() &&
        AddFontResourceExW(icon_requested_path_.c_str(), FR_PRIVATE, nullptr) > 0) {
      icon_registered_path_ = icon_requested_path_;
      icon_face_ = PrivateFamily(icon_registered_path_, L"Material Symbols Outlined");
    }
    return true;
  }

  void Ensure(UINT dpi) {
    dpi = std::clamp(dpi, 48u, 768u);
    if (dpi_ == dpi && title_ && row_ && icons_ && legacy_icons_) return;
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
    font.lfHeight = -MulDiv(16, static_cast<int>(dpi), 96);
    font.lfWeight = FW_BOLD;
    title_ = CreateFontIndirectW(&font);
    font.lfHeight = -MulDiv(15, static_cast<int>(dpi), 96);
    row_ = CreateFontIndirectW(&font);
    // Explicit per-label fallback for scripts missing from the main face.
    // Cache every handle at the current DPI: hover paints allocate no fonts.
    constexpr std::array<const wchar_t*, 6> fallback{
        L"Microsoft YaHei UI", L"Microsoft YaHei", L"Yu Gothic UI",
        L"Malgun Gothic", L"Segoe UI Symbol", L"Segoe UI Emoji"};
    for (std::size_t index = 0; index < fallback.size(); ++index) {
      wcsncpy_s(font.lfFaceName, fallback[index], _TRUNCATE);
      fallback_row_[index] = CreateFontIndirectW(&font);
      font.lfHeight = -MulDiv(16, static_cast<int>(dpi), 96);
      fallback_title_[index] = CreateFontIndirectW(&font);
      font.lfHeight = -MulDiv(15, static_cast<int>(dpi), 96);
    }
    font.lfHeight = -MulDiv(20, static_cast<int>(dpi), 96);
    font.lfWeight = FW_NORMAL;
    wcsncpy_s(font.lfFaceName,
               icon_face_.empty() ? L"Segoe MDL2 Assets" : icon_face_.c_str(), _TRUNCATE);
    icons_ = CreateFontIndirectW(&font);
    wcsncpy_s(font.lfFaceName, L"Segoe MDL2 Assets", _TRUNCATE);
    legacy_icons_ = CreateFontIndirectW(&font);
  }

  HFONT ForText(HDC dc, const wchar_t* text, bool title = false) {
    const auto primary = title ? this->title() : row();
    if (!dc || !text || !*text) return primary;
    for (const auto& choice : choices_) {
      if (choice.font && choice.title == title && choice.text == text) return choice.font;
    }
    const std::size_t length = wcsnlen_s(text, 256);
    if (length == 256) return primary;
    const auto supports = [&](HFONT candidate) {
      if (!candidate) return false;
      std::array<WORD, 256> glyphs{};
      const auto old = SelectObject(dc, candidate);
      const DWORD status = GetGlyphIndicesW(dc, text, static_cast<int>(length),
                                             glyphs.data(), GGI_MARK_NONEXISTING_GLYPHS);
      SelectObject(dc, old);
      return status != GDI_ERROR && std::none_of(glyphs.begin(), glyphs.begin() + length,
          [](WORD glyph) { return glyph == 0xffff; });
    };
    HFONT selected = primary;
    if (!supports(primary)) {
      for (HFONT fallback : title ? fallback_title_ : fallback_row_) {
        if (supports(fallback)) { selected = fallback; break; }
      }
    }
    auto& choice = choices_[next_choice_++ % choices_.size()];
    choice = {text, title, selected};
    return selected;
  }

  void ResetHandles() {
    if (title_) DeleteObject(title_);
    if (row_) DeleteObject(row_);
    if (icons_) DeleteObject(icons_);
    if (legacy_icons_) DeleteObject(legacy_icons_);
    title_ = row_ = icons_ = legacy_icons_ = nullptr;
    for (auto& font : fallback_row_) { if (font) DeleteObject(font); font = nullptr; }
    for (auto& font : fallback_title_) { if (font) DeleteObject(font); font = nullptr; }
    for (auto& choice : choices_) choice = {};
    next_choice_ = 0;
    dpi_ = 0;
  }

  void Clear() {
    // Fonts must not remain selected into a DC while resources are retired.
    ResetHandles();
    if (!registered_path_.empty()) {
      RemoveFontResourceExW(registered_path_.c_str(), FR_PRIVATE, nullptr);
    }
    registered_path_.clear();
    if (!icon_registered_path_.empty()) {
      RemoveFontResourceExW(icon_registered_path_.c_str(), FR_PRIVATE, nullptr);
    }
    icon_registered_path_.clear();
    icon_requested_path_.clear();
    icon_face_.clear();
    requested_path_.clear();
    requested_family_.clear();
    face_.clear();
  }

  HFONT title() const { return OrSystem(title_); }
  HFONT row() const { return OrSystem(row_); }
  HFONT icons(bool material = true) const { return OrSystem(material ? icons_ : legacy_icons_); }
  const std::wstring& face() const { return face_; }
  bool private_font_loaded() const { return !registered_path_.empty(); }
  bool material_icons_loaded() const { return !icon_face_.empty(); }
  const std::wstring& icon_face() const { return icon_face_; }

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
  std::wstring icon_requested_path_, icon_registered_path_, icon_face_;
  struct FontChoice { std::wstring text; bool title = false; HFONT font = nullptr; };
  std::array<FontChoice, 16> choices_{};
  std::size_t next_choice_ = 0;
  std::array<HFONT, 6> fallback_row_{}, fallback_title_{};
  UINT dpi_ = 0;
  HFONT title_ = nullptr;
  HFONT row_ = nullptr;
  HFONT icons_ = nullptr;
  HFONT legacy_icons_ = nullptr;
};

}  // namespace desktop_integration
#endif  // RUNNER_DESKTOP_INTEGRATION_FONTS_H_
