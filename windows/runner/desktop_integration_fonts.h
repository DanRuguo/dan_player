#ifndef RUNNER_DESKTOP_INTEGRATION_FONTS_H_
#define RUNNER_DESKTOP_INTEGRATION_FONTS_H_

#include <windows.h>
#include <gdiplus.h>

#include <algorithm>
#include <array>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#pragma comment(lib, "gdiplus.lib")

namespace desktop_integration {

enum class FontLanguage { kZh = 0, kEn = 1, kJa = 2, kKo = 3 };
struct NativeFontFace {
  std::wstring family, path;
  bool operator==(const NativeFontFace& other) const {
    return family == other.family && path == other.path;
  }
};
struct NativeFontPolicy {
  FontLanguage language = FontLanguage::kZh;
  bool mixed_scripts = true;
  std::array<NativeFontFace, 4> faces{};
  NativeFontFace base_fallback;
  bool operator==(const NativeFontPolicy& other) const {
    return language == other.language && mixed_scripts == other.mixed_scripts && faces == other.faces && base_fallback == other.base_fallback;
  }
};

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
    if (Matches(family, path)) return false;
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

  bool Matches(const std::wstring& family, const std::wstring& path) const {
    return !policy_ && family == requested_family_ && path == requested_path_;
  }
  bool Matches(const NativeFontPolicy& policy) const {
    return policy_ && *policy_ == policy;
  }
  bool Configure(const NativeFontPolicy& policy) {
    if (Matches(policy)) return false;
    Clear();
    policy_ = policy;
    for (size_t index = 0; index < policy_faces_.size(); ++index) {
      const auto& requested = index < policy.faces.size() ? policy.faces[index] : policy.base_fallback;
      if (!requested.path.empty() &&
          std::find(policy_paths_.begin(), policy_paths_.end(), requested.path) == policy_paths_.end() &&
          AddFontResourceExW(requested.path.c_str(), FR_PRIVATE, nullptr) > 0) {
        policy_paths_.push_back(requested.path);
      }
      // Builtin snapshots contain the font's real name, rather than a Flutter
      // alias. Custom single-face files can resolve an arbitrary loader alias.
      auto& face = policy_faces_[index];
      if (std::find(policy_paths_.begin(), policy_paths_.end(), requested.path) != policy_paths_.end())
        face = PrivateFamily(requested.path, requested.family, MAKELANGID(LANG_ENGLISH, SUBLANG_ENGLISH_US));
      if (face.empty() && requested.family.size() < LF_FACESIZE &&
          requested.family.find(L"packages/") != 0) face = requested.family;
    }
    face_ = policy_faces_[static_cast<size_t>(policy.language)];
    return true;
  }
  const std::optional<NativeFontPolicy>& policy() const { return policy_; }

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
    if (policy_) for (size_t index = 0; index < policy_faces_.size(); ++index) {
      auto script_font = font;
      if (!policy_faces_[index].empty())
        wcsncpy_s(script_font.lfFaceName, policy_faces_[index].c_str(), _TRUNCATE);
      policy_row_[index] = CreateFontIndirectW(&script_font);
      script_font.lfHeight = -MulDiv(16, static_cast<int>(dpi), 96);
      policy_title_[index] = CreateFontIndirectW(&script_font);
    }
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
    if (policy_) return primary;  // Explicit runs are selected by NativeTextLayout.
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
    for (auto& font : policy_row_) { if (font) DeleteObject(font); font = nullptr; }
    for (auto& font : policy_title_) { if (font) DeleteObject(font); font = nullptr; }
    for (auto& choice : choices_) choice = {};
    next_choice_ = 0;
    dpi_ = 0;
  }

  void Clear() {
    // Fonts must not remain selected into a DC while resources are retired.
    ResetHandles();
    for (const auto& path : policy_paths_)
      RemoveFontResourceExW(path.c_str(), FR_PRIVATE, nullptr);
    policy_paths_.clear();
    policy_faces_ = {};
    policy_.reset();
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
  HFONT ForLanguage(FontLanguage language, bool title = false) const {
    if (!policy_) return title ? this->title() : row();
    const auto index = static_cast<size_t>(language);
    return OrSystem(title ? policy_title_[index] : policy_row_[index]);
  }
  HFONT BaseFallback(bool title = false) const { return OrSystem(title ? policy_title_[4] : policy_row_[4]); }
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
                             const std::wstring& requested, LANGID language = LANG_NEUTRAL) const {
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
      if (families[index].GetFamilyName(name, language) != Gdiplus::Ok) continue;
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
  std::optional<NativeFontPolicy> policy_;
  std::vector<std::wstring> policy_paths_;
  std::array<std::wstring, 5> policy_faces_{};
  std::array<HFONT, 5> policy_row_{}, policy_title_{};
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
