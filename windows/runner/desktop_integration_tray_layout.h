#ifndef RUNNER_DESKTOP_INTEGRATION_TRAY_LAYOUT_H_
#define RUNNER_DESKTOP_INTEGRATION_TRAY_LAYOUT_H_

#include "desktop_integration_text.h"

namespace desktop_integration {

inline FontLanguage TrayPopupLanguage(const std::optional<NativeFontPolicy>& policy,
    const std::array<std::wstring, 8>& labels) {
  if (policy) return policy->language;
  bool han = false;
  for (const auto& label : labels) {
    for (size_t at = 0; at < label.size();) {
      size_t count = 0;
      const auto cp = FontCodePoint(label, at, &count);
      if (FontKana(cp)) return FontLanguage::kJa;
      if (FontHangul(cp)) return FontLanguage::kKo;
      han |= FontHan(cp);
      at += count;
    }
  }
  return han ? FontLanguage::kZh : FontLanguage::kEn;
}

inline const wchar_t* TrayPopupFontFamily(FontLanguage language) {
  switch (language) {
    case FontLanguage::kEn: return L"Segoe UI";
    case FontLanguage::kJa: return L"Yu Gothic UI";
    case FontLanguage::kKo: return L"Malgun Gothic";
    default: return L"Microsoft YaHei UI";
  }
}

// Measure with the same face, script fallback, weight and shaping used to
// paint. Font point sizes alone do not bound a custom font's line metrics.
struct TrayPopupLayout {
  int width = 0, height = 0;
  int title_top = 0, title_height = 0;
  int caption_top = 0, caption_height = 0;
  int header_height = 0, row_height = 0, separator_height = 0;

  bool Measure(PopupFonts& fonts, UINT dpi, const std::wstring& title,
               const std::wstring& caption,
               const std::array<std::wstring, 8>& labels, int available_width) {
    const auto px = [dpi](int value) {
      return MulDiv(value, static_cast<int>(dpi), 96);
    };
    fonts.Ensure(dpi);
    const auto measure = [&](const std::wstring& text, bool heading, SIZE* size) {
      const HDC dc = CreateCompatibleDC(nullptr);
      if (!dc) return false;
      const auto previous = SelectObject(dc, fonts.ForText(dc, text.c_str(), heading));
      RECT rect{};
      const bool measured = DrawTextW(dc, text.c_str(), -1, &rect,
          DT_SINGLELINE | DT_CALCRECT | DT_NOPREFIX) != 0;
      SelectObject(dc, previous);
      DeleteDC(dc);
      *size = {rect.right - rect.left, rect.bottom - rect.top};
      return measured;
    };
    SIZE title_size{}, caption_size{};
    if (!measure(title, true, &title_size) ||
        !measure(caption, false, &caption_size)) return false;
    int label_width = 0, label_height = 0;
    // Include both play and pause so a playback update cannot clip a new label.
    for (const auto& label : labels) {
      SIZE size{};
      if (!measure(label, false, &size)) return false;
      label_width = std::max(label_width, static_cast<int>(size.cx));
      label_height = std::max(label_height, static_cast<int>(size.cy));
    }
    const int required_width = std::max({px(240),
        label_width + 2 * px(8) + px(48) + px(34) + px(4),
        static_cast<int>(caption_size.cx) + 2 * px(18) + px(4)});
    if (required_width > available_width) return false;
    // Track metadata does not set command-menu width. Keep its existing
    // single-line ellipsis; only full command labels can expand the menu.
    width = required_width;
    title_top = px(11);
    title_height = std::max(px(27), static_cast<int>(title_size.cy) + px(4));
    caption_top = title_top + title_height + px(1);
    caption_height = std::max(px(20), static_cast<int>(caption_size.cy) + px(4));
    header_height = caption_top + caption_height + px(6);
    row_height = std::max(px(44), label_height + px(12));
    separator_height = px(10);
    height = header_height + 7 * row_height + 2 * separator_height + px(16);
    return true;
  }
};

}  // namespace desktop_integration
#endif  // RUNNER_DESKTOP_INTEGRATION_TRAY_LAYOUT_H_
