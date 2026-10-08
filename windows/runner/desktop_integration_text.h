#ifndef RUNNER_DESKTOP_INTEGRATION_TEXT_H_
#define RUNNER_DESKTOP_INTEGRATION_TEXT_H_

#include <windows.h>
#include <usp10.h>
#include <algorithm>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>
#include "desktop_integration_fonts.h"

#pragma comment(lib, "usp10.lib")

namespace desktop_integration {
struct FontTextRun { int begin = 0, end = 0; FontLanguage language = FontLanguage::kZh; bool fallback = false; };
inline std::uint32_t FontCodePoint(const std::wstring& text, size_t at, size_t* count) {
  const auto first = static_cast<std::uint32_t>(text[at]);
  *count = 1;
  if (first >= 0xd800 && first <= 0xdbff && at + 1 < text.size()) {
    const auto last = static_cast<std::uint32_t>(text[at + 1]);
    if (last >= 0xdc00 && last <= 0xdfff) { *count = 2; return 0x10000 + ((first - 0xd800) << 10) + last - 0xdc00; }
  }
  return first;
}
inline bool FontKana(std::uint32_t cp) {
  return (cp >= 0x3040 && cp <= 0x30ff) || (cp >= 0xff66 && cp <= 0xff9d);
}
inline bool FontHangul(std::uint32_t cp) {
  return (cp >= 0xac00 && cp <= 0xd7af) || (cp >= 0x1100 && cp <= 0x11ff) ||
      (cp >= 0x3130 && cp <= 0x318f) || (cp >= 0xa960 && cp <= 0xa97f) || (cp >= 0xd7b0 && cp <= 0xd7ff);
}
inline bool FontHan(std::uint32_t cp) {
  return (cp >= 0x3400 && cp <= 0x9fff) || (cp >= 0xf900 && cp <= 0xfaff) || (cp >= 0x20000 && cp <= 0x323af);
}
inline bool FontLatin(std::uint32_t cp) {
  return (cp >= 0x41 && cp <= 0x5a) || (cp >= 0x61 && cp <= 0x7a) ||
      (cp >= 0xc0 && cp <= 0x24f) || (cp >= 0x1e00 && cp <= 0x1eff);
}
inline bool FontAttached(std::uint32_t cp) {
  if (cp == 0x200d || (cp >= 0xfe00 && cp <= 0xfe0f) || (cp >= 0xe0100 && cp <= 0xe01ef) ||
      (cp >= 0x1f3fb && cp <= 0x1f3ff) || (cp >= 0xe0020 && cp <= 0xe007f)) return true;
  if (cp > 0xffff) return false;
  const auto unit = static_cast<wchar_t>(cp);
  WORD kind = 0;
  return GetStringTypeW(CT_CTYPE3, &unit, 1, &kind) && (kind & (C3_NONSPACING | C3_DIACRITIC | C3_VOWELMARK));
}
enum class FontHangulPart { kOther, kL, kV, kT, kLV, kLVT };
inline FontHangulPart HangulPart(std::uint32_t cp) {
  if ((cp >= 0x1100 && cp <= 0x115f) || (cp >= 0xa960 && cp <= 0xa97c)) return FontHangulPart::kL;
  if ((cp >= 0x1160 && cp <= 0x11a7) || (cp >= 0xd7b0 && cp <= 0xd7c6)) return FontHangulPart::kV;
  if ((cp >= 0x11a8 && cp <= 0x11ff) || (cp >= 0xd7cb && cp <= 0xd7fb)) return FontHangulPart::kT;
  if (cp >= 0xac00 && cp <= 0xd7a3) return (cp - 0xac00) % 28 ? FontHangulPart::kLVT : FontHangulPart::kLV;
  return FontHangulPart::kOther;
}
inline bool HangulJoined(std::uint32_t previous, std::uint32_t next) {
  const auto from = HangulPart(previous), to = HangulPart(next);
  return (from == FontHangulPart::kL && (to == FontHangulPart::kL || to == FontHangulPart::kV || to == FontHangulPart::kLV || to == FontHangulPart::kLVT)) ||
      ((from == FontHangulPart::kLV || from == FontHangulPart::kV) && (to == FontHangulPart::kV || to == FontHangulPart::kT)) ||
      ((from == FontHangulPart::kLVT || from == FontHangulPart::kT) && to == FontHangulPart::kT);
}
inline bool FontPrepend(std::uint32_t cp) {
  return (cp >= 0x0600 && cp <= 0x0605) || cp == 0x06dd || cp == 0x070f ||
      (cp >= 0x0890 && cp <= 0x0891) || cp == 0x08e2 || cp == 0x0d4e ||
      cp == 0x110bd || cp == 0x110cd || (cp >= 0x111c2 && cp <= 0x111c3) ||
      cp == 0x1193f || cp == 0x11941 || cp == 0x11a3a || (cp >= 0x11a84 && cp <= 0x11a89) || cp == 0x11d46 || cp == 0x11f02;
}
inline size_t FontClusterEnd(const std::wstring& text, size_t at) {
  bool joined = false;
  size_t first_count = 0;
  const auto first = FontCodePoint(text, at, &first_count);
  bool regional_pair = first >= 0x1f1e6 && first <= 0x1f1ff;
  do {
    size_t count = 0; const auto cp = FontCodePoint(text, at, &count);
    joined = cp == 0x200d || FontPrepend(cp); at += count;
    if (at == text.size()) break;
    size_t next_count = 0; const auto next = FontCodePoint(text, at, &next_count);
    const bool paired = regional_pair && next >= 0x1f1e6 && next <= 0x1f1ff;
    regional_pair = false;
    if (!joined && !paired && !FontAttached(next) && !HangulJoined(cp, next)) break;
  } while (at < text.size());
  return at;
}
// Font selection is cached with shaping, never queried on a highlight frame.
// Shared Han follows the sentence's Kana/Hangul context and then the UI locale.
inline FontLanguage HanFontLanguage(const std::wstring& text, const NativeFontPolicy& policy) {
  bool kana = false, hangul = false;
  for (size_t at = 0; at < text.size();) {
    size_t count = 0; const auto cp = FontCodePoint(text, at, &count);
    kana |= FontKana(cp); hangul |= FontHangul(cp); at += count;
  }
  return kana ? FontLanguage::kJa : hangul ? FontLanguage::kKo :
      policy.language == FontLanguage::kEn ? FontLanguage::kZh : policy.language;
}
inline std::vector<FontTextRun> FontTextRuns(const std::wstring& text, const NativeFontPolicy& policy,
    std::optional<FontLanguage> han_context = std::nullopt) {
  std::vector<FontTextRun> result;
  if (text.empty()) return result;
  if (!policy.mixed_scripts) return {{0, static_cast<int>(text.size()), policy.language}};
  const auto han = han_context ? *han_context : HanFontLanguage(text, policy);
  auto language = policy.language;
  int begin = 0;
  for (size_t at = 0; at < text.size();) {
    const size_t cluster_begin = at;
    bool has_kana = false, has_hangul = false, has_han = false, has_latin = false;
    const auto cluster_end = FontClusterEnd(text, at);
    while (at < cluster_end) {
      size_t count = 0; const auto cp = FontCodePoint(text, at, &count);
      has_kana |= FontKana(cp); has_hangul |= FontHangul(cp); has_han |= FontHan(cp); has_latin |= FontLatin(cp);
      at += count;
    }
    const auto next = has_kana ? FontLanguage::kJa : has_hangul ? FontLanguage::kKo :
        has_han ? han : has_latin ? FontLanguage::kEn : language;
    if (next != language && cluster_begin > static_cast<size_t>(begin))
      result.push_back({begin, static_cast<int>(cluster_begin), language});
    if (next != language) begin = static_cast<int>(cluster_begin);
    language = next;
  }
  result.push_back({begin, static_cast<int>(text.size()), language});
  return result;
}
inline std::vector<FontTextRun> SelectFontRanges(HDC dc, PopupFonts& fonts,
    const std::wstring& text, std::vector<FontTextRun> ranges, bool title) {
  if (!fonts.policy() || fonts.policy()->base_fallback.family.empty()) return ranges;
  const auto old = SelectObject(dc, fonts.BaseFallback(title));
  std::vector<WORD> base(text.size(), 0xffff);
  const bool base_available = GetGlyphIndicesW(dc, text.data(), static_cast<int>(text.size()),
      base.data(), GGI_MARK_NONEXISTING_GLYPHS) != GDI_ERROR;
  SelectObject(dc, old);
  if (!base_available) return ranges;
  std::vector<FontTextRun> result;
  for (const auto& range : ranges) {
    SelectObject(dc, fonts.ForLanguage(range.language, title));
    std::vector<WORD> glyphs(range.end - range.begin, 0xffff);
    GetGlyphIndicesW(dc, text.data() + range.begin, range.end - range.begin, glyphs.data(), GGI_MARK_NONEXISTING_GLYPHS);
    SelectObject(dc, old);
    for (int begin = range.begin; begin < range.end;) {
      const int end = std::min(range.end, static_cast<int>(FontClusterEnd(text, begin)));
      bool missing = false, covered = true;
      for (int cp = begin; cp < end; ++cp) { missing |= glyphs[cp - range.begin] == 0xffff; covered &= base[cp] != 0xffff; }
      const bool fallback = missing && covered;
      if (!result.empty() && result.back().end == begin && result.back().language == range.language && result.back().fallback == fallback)
        result.back().end = end;
      else result.push_back({begin, end, range.language, fallback});
      begin = end;
    }
  }
  return result;
}

// Each run retains Uniscribe's glyphs, logical widths and UTF-16 caret map.
// A single bounded paragraph owns its DC/fonts and releases them before the
// PopupFonts snapshot retires its private resources.
class NativeTextLayout {
 public:
  HDC dc = CreateCompatibleDC(nullptr);
  std::wstring text;
  SIZE measured{};
  struct Run {
    int begin = 0, end = 0, x = 0, ascent = 0;
    BYTE level = 0;
    FontLanguage language = FontLanguage::kZh;
    bool fallback = false;
    HFONT font = nullptr;
    SCRIPT_STRING_ANALYSIS analysis = nullptr;
    SIZE size{};
  };
  std::vector<Run> runs;
  std::vector<SCRIPT_LOGATTR> attributes;
  std::vector<int> logical_widths;
  NativeTextLayout() { if (dc) original_font_ = GetCurrentObject(dc, OBJ_FONT); }
  NativeTextLayout(const NativeTextLayout&) = delete;
  NativeTextLayout& operator=(const NativeTextLayout&) = delete;
  ~NativeTextLayout() { Clear(); if (dc) DeleteDC(dc); }
  void Clear() {
    if (dc && original_font_) SelectObject(dc, original_font_);
    for (auto& run : runs) {
      if (run.analysis) ScriptStringFree(&run.analysis);
    }
    for (auto& font : sized_fonts_) { if (font) DeleteObject(font); font = nullptr; }
    runs.clear(); attributes.clear(); logical_widths.clear(); measured = {};
    baseline_ = 0;
  }
  bool valid() const { return dc && !runs.empty(); }
  bool Shape(PopupFonts& fonts, const std::wstring& source, UINT dpi, int size,
             int weight = FW_MEDIUM, BYTE quality = ANTIALIASED_QUALITY, bool title = false,
             std::optional<FontLanguage> han_context = std::nullopt) {
    Clear(); text = source;
    if (!dc || text.empty() || text.size() > 2048) return false;
    fonts.Ensure(dpi);
    auto font_ranges = fonts.policy() ? FontTextRuns(text, *fonts.policy(), han_context) :
        std::vector<FontTextRun>{{0, static_cast<int>(text.size()), FontLanguage::kZh}};
    font_ranges = SelectFontRanges(dc, fonts, text, std::move(font_ranges), title);
    std::vector<SCRIPT_ITEM> items(text.size() + 1);
    SCRIPT_CONTROL control{}; SCRIPT_STATE state{};
    int item_count = 0;
    if (FAILED(ScriptItemize(text.data(), static_cast<int>(text.size()),
        static_cast<int>(items.size()), &control, &state, items.data(), &item_count))) return false;
    // Bidi levels are sampled at complete cluster starts. An item boundary
    // inside a combining/Jamo/emoji sequence cannot split its font or shaping.
    std::vector<Run> specifications;
    int item = 0;
    for (const auto& range : font_ranges) {
      int begin = range.begin;
      while (begin < range.end) {
        while (item + 1 < item_count && items[item + 1].iCharPos <= begin) ++item;
        Run run;
        run.begin = begin; run.end = fonts.policy() ? std::min(range.end, static_cast<int>(FontClusterEnd(text, begin))) : range.end;
        run.language = range.language;
        run.fallback = range.fallback;
        run.level = static_cast<BYTE>(fonts.policy() ? items[item].a.s.uBidiLevel : 0);
        if (!specifications.empty() && specifications.back().end == run.begin &&
            specifications.back().language == run.language && specifications.back().level == run.level &&
            specifications.back().fallback == run.fallback) specifications.back().end = run.end;
        else specifications.push_back(run);
        begin = run.end;
      }
    }
    for (auto run : specifications) {
        const size_t font_index = fonts.policy() ? (run.fallback ? 4 : static_cast<size_t>(run.language)) : 0;
        if (!sized_fonts_[font_index]) {
          LOGFONTW description{};
          const HFONT selected = fonts.policy() ? (run.fallback ? fonts.BaseFallback(title) : fonts.ForLanguage(run.language, title)) : fonts.ForText(dc, text.c_str(), title);
          if (!GetObjectW(selected, sizeof(description), &description)) { Clear(); return false; }
          description.lfHeight = -MulDiv(size, dpi, 96);
          description.lfWeight = weight; description.lfQuality = quality;
          sized_fonts_[font_index] = CreateFontIndirectW(&description);
        }
        run.font = sized_fonts_[font_index];
        if (!run.font) { Clear(); return false; }
        SelectObject(dc, run.font);
        TEXTMETRICW metrics{}; GetTextMetricsW(dc, &metrics); run.ascent = metrics.tmAscent;
        SCRIPT_STATE run_state{}; run_state.uBidiLevel = run.level;
        const int count = run.end - run.begin;
        const auto status = ScriptStringAnalyse(dc, text.data() + run.begin, count, count * 2 + 16,
            -1, SSA_GLYPHS | SSA_FALLBACK | SSA_LINK | SSA_BREAK, 0, nullptr,
            fonts.policy() ? &run_state : nullptr, nullptr, nullptr, nullptr, &run.analysis);
        if (FAILED(status) || !run.analysis || !ScriptString_pSize(run.analysis)) {
          if (run.analysis) ScriptStringFree(&run.analysis);
          Clear(); return false;
        }
        run.size = *ScriptString_pSize(run.analysis);
        baseline_ = std::max(baseline_, run.ascent);
        runs.push_back(run);
    }
    std::vector<BYTE> levels; for (const auto& run : runs) levels.push_back(run.level);
    std::vector<int> visual(runs.size());
    if (FAILED(ScriptLayout(static_cast<int>(runs.size()), levels.data(), visual.data(), nullptr))) { Clear(); return false; }
    for (const int logical : visual) { runs[logical].x = measured.cx; measured.cx += runs[logical].size.cx; }
    for (const auto& run : runs) measured.cy = std::max(measured.cy, baseline_ - run.ascent + run.size.cy);
    attributes.resize(text.size() + 1); logical_widths.resize(text.size() + 1);
    for (const auto& run : runs) {
      const auto attrs = ScriptString_pLogAttr(run.analysis);
      if (attrs) std::copy_n(attrs, run.end - run.begin, attributes.begin() + run.begin);
      if (FAILED(ScriptStringGetLogicalWidths(run.analysis, logical_widths.data() + run.begin))) { Clear(); return false; }
    }
    // A font boundary must never become a new break inside a surrogate or
    // combining/ZWJ sequence when narrow side taskbars wrap this paragraph.
    for (size_t begin = 0; begin < text.size();) {
      const auto end = FontClusterEnd(text, begin);
      for (size_t at = begin + 1; at < end; ++at)
        attributes[at].fCharStop = attributes[at].fSoftBreak = 0;
      begin = end;
    }
    return true;
  }
  HRESULT CpToX(int cp, BOOL trailing, int* x) const {
    if (!x || runs.empty() || cp < 0 || cp >= static_cast<int>(text.size())) return E_INVALIDARG;
    const auto run = std::upper_bound(runs.begin(), runs.end(), cp,
        [](int value, const Run& item) { return value < item.end; });
    if (run == runs.end()) return E_INVALIDARG;
    const auto status = ScriptStringCPtoX(run->analysis, cp - run->begin, trailing, x);
    if (SUCCEEDED(status)) *x += run->x;
    return status;
  }
  HRESULT Paint(int x, int y) {
    if (!valid()) return E_FAIL;
    for (const auto& run : runs) {
      SelectObject(dc, run.font);
      const auto status = ScriptStringOut(run.analysis, x + run.x, y + baseline_ - run.ascent,
          0, nullptr, 0, 0, FALSE);
      if (FAILED(status)) return status;
    }
    return S_OK;
  }
 private:
  HGDIOBJ original_font_ = nullptr;
  std::array<HFONT, 5> sized_fonts_{};
  int baseline_ = 0;
};

// Tray hover paints reuse bounded glyph coverage and a reusable backing DIB.
// Theme/highlight colors only composite that coverage; no font lookup, shaping,
// font handle creation or per-paint bitmap allocation is needed.
class NativeTextCache {
 public:
  void Clear() { for (auto& entry : entries_) entry.reset(); next_ = 0; }
  bool Draw(HDC target, PopupFonts& fonts, const std::wstring& text, RECT rect,
            UINT dpi, bool title = false) {
    const int width = rect.right - rect.left, height = rect.bottom - rect.top;
    if (!target || text.empty() || width <= 0 || height <= 0 || width > 4096 || height > 512) return false;
    Entry* cached = nullptr;
    for (const auto& entry : entries_) if (entry && entry->text == text && entry->width == width &&
        entry->height == height && entry->dpi == dpi && entry->title == title) { cached = entry.get(); break; }
    if (!cached) {
      auto entry = std::make_unique<Entry>();
      entry->text = text; entry->width = width; entry->height = height; entry->dpi = dpi; entry->title = title;
      entry->layout = std::make_unique<NativeTextLayout>();
      const int size = title ? 16 : 15;
      const std::optional<FontLanguage> han_context = fonts.policy() ?
          std::optional<FontLanguage>(HanFontLanguage(text, *fonts.policy())) : std::nullopt;
      if (!entry->layout->Shape(fonts, text, dpi, size, FW_BOLD, ANTIALIASED_QUALITY, title)) return false;
      if (entry->layout->measured.cx > width) {
        std::vector<int> ends{0};
        for (int cp = 1; cp < static_cast<int>(text.size()); ++cp)
          if (entry->layout->attributes[cp].fCharStop) ends.push_back(cp);
        int low = 0, high = static_cast<int>(ends.size()) - 1;
        std::unique_ptr<NativeTextLayout> best;
        while (low <= high) {
          const int middle = (low + high) / 2;
          auto layout = std::make_unique<NativeTextLayout>();
          if (!layout->Shape(fonts, text.substr(0, ends[middle]) + L"\u2026", dpi, size, FW_BOLD, ANTIALIASED_QUALITY, title, han_context)) return false;
          if (layout->measured.cx <= width) { best = std::move(layout); low = middle + 1; }
          else high = middle - 1;
        }
        if (best) entry->layout = std::move(best);
      }
      BITMAPINFO info{}; info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
      info.bmiHeader.biWidth = width; info.bmiHeader.biHeight = -height;
      info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32; info.bmiHeader.biCompression = BI_RGB;
      void* pixels = nullptr;
      entry->bitmap = CreateDIBSection(nullptr, &info, DIB_RGB_COLORS, &pixels, nullptr, 0);
      if (!entry->bitmap || !pixels) return false;
      entry->pixels = static_cast<std::uint32_t*>(pixels);
      entry->original_bitmap = SelectObject(entry->layout->dc, entry->bitmap);
      memset(pixels, 0, static_cast<size_t>(width) * height * 4);
      SetTextColor(entry->layout->dc, RGB(255, 255, 255)); SetBkMode(entry->layout->dc, TRANSPARENT);
      const int saved = SaveDC(entry->layout->dc);
      IntersectClipRect(entry->layout->dc, 0, 0, width, height);
      const auto painted = entry->layout->Paint(0, std::max(0L, (height - entry->layout->measured.cy) / 2));
      RestoreDC(entry->layout->dc, saved);
      if (FAILED(painted)) return false;
      GdiFlush();
      entry->coverage.resize(static_cast<size_t>(width) * height);
      for (size_t pixel = 0; pixel < entry->coverage.size(); ++pixel) {
        const auto color = entry->pixels[pixel];
        entry->coverage[pixel] = static_cast<unsigned char>(std::max({color & 255u, (color >> 8) & 255u, (color >> 16) & 255u}));
      }
      auto& slot = entries_[next_++ % entries_.size()]; slot = std::move(entry); cached = slot.get();
    }
    if (!BitBlt(cached->layout->dc, 0, 0, width, height, target, rect.left, rect.top, SRCCOPY)) return false;
    GdiFlush();
    const auto foreground = GetTextColor(target);
    const unsigned blue = GetBValue(foreground), green = GetGValue(foreground), red = GetRValue(foreground);
    for (size_t pixel = 0; pixel < cached->coverage.size(); ++pixel) {
      const unsigned alpha = cached->coverage[pixel];
      if (!alpha) continue;
      const auto background = cached->pixels[pixel];
      const auto blend = [alpha](unsigned from, unsigned to) { return (from * (255 - alpha) + to * alpha + 127) / 255; };
      cached->pixels[pixel] = blend(background & 255, blue) | (blend((background >> 8) & 255, green) << 8) |
          (blend((background >> 16) & 255, red) << 16);
    }
    return BitBlt(target, rect.left, rect.top, width, height, cached->layout->dc, 0, 0, SRCCOPY) != FALSE;
  }
 private:
  struct Entry {
    std::wstring text;
    int width = 0, height = 0; UINT dpi = 0; bool title = false;
    std::unique_ptr<NativeTextLayout> layout;
    HBITMAP bitmap = nullptr; HGDIOBJ original_bitmap = nullptr;
    std::uint32_t* pixels = nullptr;
    std::vector<unsigned char> coverage;
    ~Entry() {
      if (layout && original_bitmap) SelectObject(layout->dc, original_bitmap);
      if (bitmap) DeleteObject(bitmap);
    }
  };
  std::array<std::unique_ptr<Entry>, 16> entries_{};
  size_t next_ = 0;
};
}  // namespace desktop_integration
#endif  // RUNNER_DESKTOP_INTEGRATION_TEXT_H_
