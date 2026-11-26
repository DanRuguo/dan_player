#ifndef RUNNER_DESKTOP_INTEGRATION_TRAY_LAYOUT_H_
#define RUNNER_DESKTOP_INTEGRATION_TRAY_LAYOUT_H_

#include "desktop_integration_text.h"

namespace desktop_integration {

inline FontLanguage TrayPopupLanguage(
    const std::optional<NativeFontPolicy>& policy,
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
    case FontLanguage::kEn:
      return L"Segoe UI";
    case FontLanguage::kJa:
      return L"Yu Gothic UI";
    case FontLanguage::kKo:
      return L"Malgun Gothic";
    default:
      return L"Microsoft YaHei UI";
  }
}

// Measure with the same face, script fallback, weight and shaping used to
// paint. Top hero card houses artwork + track/brand metadata + 3-button
// horizontal media transport deck, followed by 4 clean menu command rows.
struct TrayPopupLayout {
  int width = 0, height = 0;
  RECT card_rect{};
  RECT cover_rect{};
  RECT info_hit_rect{};
  RECT title_rect{};
  RECT caption_rect{};
  RECT prev_rect{};
  RECT toggle_rect{};
  RECT next_rect{};
  int list_top = 0;
  int row_height = 0;
  int separator_height = 0;

  bool Measure(PopupFonts& fonts, UINT dpi, const std::wstring& title,
               const std::wstring& caption,
               const std::wstring& idle_caption,
               const std::array<std::wstring, 8>& labels, int available_width) {
    const auto px = [dpi](int value) {
      return MulDiv(value, static_cast<int>(dpi), 96);
    };
    fonts.Ensure(dpi);
    const auto measure = [&](const std::wstring& text, PopupFonts::TextRole role,
                             SIZE* size) {
      if (text.empty()) {
        *size = {0, 0};
        return true;
      }
      const HDC dc = CreateCompatibleDC(nullptr);
      if (!dc) return false;
      const auto previous =
          SelectObject(dc, fonts.ForRole(dc, text.c_str(), role));
      RECT rect{};
      const bool measured =
          DrawTextW(dc, text.c_str(), -1, &rect,
                    DT_SINGLELINE | DT_CALCRECT | DT_NOPREFIX) != 0;
      SelectObject(dc, previous);
      DeleteDC(dc);
      *size = {rect.right - rect.left, rect.bottom - rect.top};
      return measured;
    };

    SIZE title_size{}, caption_size{}, idle_caption_size{};
    if (!measure(title, PopupFonts::TextRole::kTitle, &title_size) ||
        !measure(caption, PopupFonts::TextRole::kCaption, &caption_size) ||
        !measure(idle_caption, PopupFonts::TextRole::kCaption,
                 &idle_caption_size)) {
      return false;
    }

    // Measure row labels (0=showMain, 1=showMini, 6=lyrics, 7=exit) and
    // transport toggle labels (3=play, 4=pause) so play/pause never clips.
    int row_label_width = 0, row_label_height = 0;
    for (const size_t idx : {size_t{0}, size_t{1}, size_t{6}, size_t{7}}) {
      SIZE size{};
      if (!measure(labels[idx], PopupFonts::TextRole::kRow, &size)) return false;
      row_label_width = std::max(row_label_width, static_cast<int>(size.cx));
      row_label_height = std::max(row_label_height, static_cast<int>(size.cy));
    }
    int toggle_label_width = 0, toggle_label_height = 0;
    for (const size_t idx : {size_t{3}, size_t{4}}) {
      SIZE size{};
      if (!measure(labels[idx], PopupFonts::TextRole::kPill, &size)) {
        return false;
      }
      toggle_label_width =
          std::max(toggle_label_width, static_cast<int>(size.cx));
      toggle_label_height =
          std::max(toggle_label_height, static_cast<int>(size.cy));
    }

    const int outer_pad = px(8);
    const int card_pad = px(10);
    const int cover_edge = px(44);
    const int side_btn_w = px(38);
    const int btn_gap = px(8);

    const int min_for_rows =
        2 * px(6) + px(38) + row_label_width + px(34) + px(8);
    const int min_for_transport =
        2 * (outer_pad + card_pad) + 2 * side_btn_w + 2 * btn_gap +
        (px(38) + toggle_label_width);
    const int min_for_brand =
        2 * (outer_pad + card_pad) + cover_edge + px(11) +
        static_cast<int>(idle_caption_size.cx) + px(4);

    // Track metadata uses single-line ellipsis so long titles never bloat width.
    const int required_width =
        std::max({px(258), min_for_rows, min_for_transport, min_for_brand});
    if (required_width > available_width) return false;
    width = required_width;

    const int title_h = std::max(px(21), static_cast<int>(title_size.cy) + px(2));
    const int caption_h =
        std::max(px(16), static_cast<int>(caption_size.cy) + px(2));
    const int text_block_h = title_h + px(2) + caption_h;
    const int info_h = std::max(cover_edge, text_block_h);

    const int card_left = outer_pad;
    const int card_top = outer_pad;
    const int card_right = width - outer_pad;
    const int cover_top = card_top + card_pad + (info_h - cover_edge) / 2;
    cover_rect = {card_left + card_pad, cover_top,
                  card_left + card_pad + cover_edge, cover_top + cover_edge};

    const int text_left = cover_rect.right + px(11);
    const int text_right = card_right - card_pad;
    const int text_top = card_top + card_pad + (info_h - text_block_h) / 2;
    title_rect = {text_left, text_top, text_right, text_top + title_h};
    caption_rect = {text_left, title_rect.bottom + px(2), text_right,
                    title_rect.bottom + px(2) + caption_h};
    info_hit_rect = {card_left + px(4), card_top + px(4), card_right - px(4),
                     card_top + card_pad + info_h + px(3)};

    const int transport_top = card_top + card_pad + info_h + px(9);
    const int transport_h = std::max(px(32), toggle_label_height + px(12));
    const int inner_left = card_left + card_pad;
    const int inner_right = card_right - card_pad;
    prev_rect = {inner_left, transport_top, inner_left + side_btn_w,
                 transport_top + transport_h};
    next_rect = {inner_right - side_btn_w, transport_top, inner_right,
                 transport_top + transport_h};
    toggle_rect = {prev_rect.right + btn_gap, transport_top,
                   next_rect.left - btn_gap, transport_top + transport_h};

    card_rect = {card_left, card_top, card_right,
                 transport_top + transport_h + card_pad};

    list_top = card_rect.bottom + px(6);
    row_height = std::max(px(38), row_label_height + px(12));
    separator_height = px(9);
    height = list_top + 4 * row_height + separator_height + outer_pad;
    return true;
  }
};

}  // namespace desktop_integration
#endif  // RUNNER_DESKTOP_INTEGRATION_TRAY_LAYOUT_H_
