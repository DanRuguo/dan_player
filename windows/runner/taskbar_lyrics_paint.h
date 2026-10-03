#ifndef RUNNER_TASKBAR_LYRICS_PAINT_H_
#define RUNNER_TASKBAR_LYRICS_PAINT_H_
#include <windows.h>
#include <usp10.h>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>
#include <utility>
#include "desktop_integration_fonts.h"
#include "taskbar_lyrics_policy.h"

struct TaskbarLyricWord {
  std::int64_t start = 0, length = 0;
  std::wstring content;
};
namespace taskbar_lyrics {
struct WordCoverage {
  std::int64_t start, length;
  int leading, trailing;
  int top = -1, bottom = -1;
  double begin = 0, end = 1;
};
struct ShapedText {
  HDC dc = CreateCompatibleDC(nullptr);
  HFONT font = nullptr;
  HGDIOBJ original_font = nullptr;
  SCRIPT_STRING_ANALYSIS analysis = nullptr;
  std::wstring text;
  SIZE measured{};
  ~ShapedText() {
    if (analysis) ScriptStringFree(&analysis);
    if (dc && original_font) SelectObject(dc, original_font);
    if (font) DeleteObject(font);
    if (dc) DeleteDC(dc);
  }
};
struct LongText {
  std::wstring text;
  std::vector<std::pair<int, int>> chunks;
  std::vector<TaskbarLyricWord> words;
};
struct WrappedText {
  std::shared_ptr<LongText> source;
  std::shared_ptr<ShapedText> shaping;
  std::vector<std::pair<int, int>> rows;
  std::vector<int> logical_widths;
  int chunk = -1, first_row = -1, pitch = 24, font_size = 16;
};
struct TextMask {
  int width = 0, height = 0, natural_width = 0, origin = 0, padding = 0, viewport_width = 0;
  UINT dpi = 96;
  std::vector<unsigned char> pixels;
  std::vector<WordCoverage> words;
  std::shared_ptr<ShapedText> shaping;
  std::shared_ptr<LongText> long_text;
  std::shared_ptr<WrappedText> wrapped;
  std::vector<unsigned char> outline;
  double outline_radius = 0;
  int chunk = 0;
  bool overflow = false, paged = false;
};
enum class MediaSymbol { kPlay, kPause, kSkipNext };
// The same 24-unit rounded Material proportions as the player controls, drawn
// from vector primitives instead of depending on a text font's Unicode glyphs.
inline TextMask RasterMediaSymbol(MediaSymbol symbol, int width, int height, UINT dpi, int logical_edge = 16) {
  TextMask result;
  if (width <= 0 || height <= 0) return result;
  result.width = result.viewport_width = result.natural_width = width; result.height = height; result.dpi = dpi;
  result.pixels.assign(static_cast<size_t>(width)*height,0);
  const double edge = std::min<double>(std::min(width,height),MulDiv(logical_edge,dpi,96));
  const double left = (width-edge)/2, top = (height-edge)/2;
  const auto capsule = [](double x,double y,double cx,double begin,double end,double radius) {
    const double dy = y-std::clamp(y,begin+radius,end-radius);
    return (x-cx)*(x-cx)+dy*dy <= radius*radius;
  };
  for (int y=0;y<height;++y) for (int x=0;x<width;++x) {
    unsigned covered = 0;
    for (int sy=0;sy<4;++sy) for (int sx=0;sx<4;++sx) {
      const double px=((x+(sx+.5)/4-left)/edge)*24, py=((y+(sy+.5)/4-top)/edge)*24;
      const bool inside = symbol == MediaSymbol::kPlay ?
          (px>=8 && px<=19 && std::abs(py-12)<=(19-px)*7/11) : symbol == MediaSymbol::kPause ?
          (capsule(px,py,8,5,19,2) || capsule(px,py,16,5,19,2)) :
          (capsule(px,py,17,6,18,1) || (px>=6 && px<=14 && std::abs(py-12)<=(14-px)*.625));
      if (inside) ++covered;
    }
    result.pixels[static_cast<size_t>(y)*width+x] = static_cast<unsigned char>(covered*255/16);
  }
  return result;
}
struct MediaCapsule { TextMask fill, rim; };
// The player's 36 x 30 rounded capsule, fitted to the taskbar's actual height.
// Cached coverage is independent of theme, hover and playback state.
inline MediaCapsule RasterMediaCapsule(int width,int height,UINT dpi) {
  MediaCapsule result;
  if(width<=0 || height<=0) return result;
  for(auto* mask:{&result.fill,&result.rim}) {
    mask->width=mask->viewport_width=mask->natural_width=width; mask->height=height; mask->dpi=dpi;
    mask->pixels.assign(static_cast<size_t>(width)*height,0);
  }
  const double scale=std::min({dpi/96.0,width/36.0,height/30.0});
  const double capsule_width=36*scale,capsule_height=30*scale;
  const double radius=capsule_height/2,half_straight=(capsule_width-capsule_height)/2;
  const double line=std::max(.75,scale);
  for(int y=0;y<height;++y) for(int x=0;x<width;++x) {
    unsigned covered=0,rim=0;
    for(int sy=0;sy<4;++sy) for(int sx=0;sx<4;++sx) {
      const double dx=std::max(0.0,std::abs(x+(sx+.5)/4-width*.5)-half_straight);
      const double dy=y+(sy+.5)/4-height*.5,distance=dx*dx+dy*dy;
      if(distance<=radius*radius) { ++covered; if(distance>(radius-line)*(radius-line)) ++rim; }
    }
    const auto index=static_cast<size_t>(y)*width+x;
    result.fill.pixels[index]=static_cast<unsigned char>(covered*255/16);
    result.rim.pixels[index]=static_cast<unsigned char>(rim*255/16);
  }
  return result;
}
inline int VisibleTextHeight(const TextMask& mask) {
  if (mask.pixels.empty()) return 0;
  if (!mask.wrapped) return mask.height;
  return std::min(mask.height, std::max(0, static_cast<int>(mask.wrapped->rows.size()) - mask.wrapped->first_row) * mask.wrapped->pitch);
}
inline std::vector<TaskbarLyricWord> ChunkWords(const LongText& source, int chunk) {
  const auto range = source.chunks[chunk];
  std::vector<TaskbarLyricWord> words;
  int offset = 0;
  for (const auto& word : source.words) {
    const int end = offset + static_cast<int>(word.content.size());
    if (offset >= range.first && end <= range.second) words.push_back(word);
    else if (end > range.first && offset < range.second) return {};
    offset = end;
  }
  return words;
}
inline bool ValidWords(const std::wstring& text, const std::vector<TaskbarLyricWord>& words);
inline std::shared_ptr<LongText> DivideLongText(const std::wstring& text,
                                              const std::vector<TaskbarLyricWord>& words) {
  auto source = std::make_shared<LongText>(); source->text = text;
  std::vector<int> word_ends;
  if (ValidWords(text, words) && std::none_of(words.begin(), words.end(),
      [](const auto& word) { return word.content.size() > 2048; })) {
    source->words = words;
    int offset = 0;
    for (const auto& word : words) {
      offset += static_cast<int>(word.content.size()); word_ends.push_back(offset);
    }
  }
  // Bound shaping work independently of document size. Never split a UTF-16
  // surrogate pair, nor a normal combining/ZWJ cluster at the chosen boundary.
  int begin = 0;
  const int length = static_cast<int>(text.size());
  while (begin < length) {
    int end = std::min(length, begin + 2048);
    if (!word_ends.empty() && end < length) {
      const auto last = std::upper_bound(word_ends.begin(), word_ends.end(), end);
      if (last != word_ends.begin() && *(last - 1) > begin) end = *(last - 1);
    } else if (end < length) {
      const int earliest = std::max(begin + 1, end - 128);
      for (int space = end - 1; space >= earliest; --space)
        if (text[space] == L' ') { end = space + 1; break; }
      if (text[end] >= 0xdc00 && text[end] <= 0xdfff && end > begin) --end;
      while (end > begin + 1) {
        WORD kind = 0; GetStringTypeW(CT_CTYPE3, text.data() + end, 1, &kind);
        if (!(kind & (C3_NONSPACING | C3_DIACRITIC | C3_VOWELMARK)) &&
            text[end] != 0x200d && text[end - 1] != 0x200d) break;
        --end;
        if (text[end] >= 0xdc00 && text[end] <= 0xdfff && end > begin) --end;
      }
      if (end <= begin) end = std::min(length, begin + 2048);
    }
    source->chunks.emplace_back(begin, end); begin = end;
  }
  return source;
}
inline bool ValidWords(const std::wstring& text, const std::vector<TaskbarLyricWord>& words) {
  if (words.empty() || words.size() > 4096) return false;
  std::wstring joined;
  std::int64_t previous = -(1LL << 53);
  for (const auto& word : words) {
    if (word.start < -(1LL << 53) || word.length < 0 || word.start < previous ||
        word.length > (1LL << 53) || word.start > (1LL << 53) - word.length) return false;
    previous = word.start;
    joined += word.content;
    if (joined.size() > text.size()) return false;
  }
  return joined == text;
}
inline bool WordsRemaining(const TextMask& mask, double position) {
  if (mask.wrapped) return std::any_of(mask.wrapped->source->words.begin(), mask.wrapped->source->words.end(),
      [position](const auto& word) { return position < static_cast<double>(word.start + word.length); });
  return std::any_of(mask.words.begin(), mask.words.end(), [position](const auto& word) {
    return position < static_cast<double>(word.start + word.length);
  });
}
inline double WordFraction(const WordCoverage& word, double position) {
  const double authored = word.length == 0 ? (position >= word.start ? 1 : 0) :
      std::clamp((position - word.start) / word.length, 0.0, 1.0);
  return word.end > word.begin ? std::clamp((authored - word.begin) / (word.end - word.begin), 0.0, 1.0) : 0;
}
inline bool HighlightAt(const TextMask& mask, int x, double position) {
  if (mask.words.empty()) return true;
  for (const auto& word : mask.words) {
    const int left = std::min(word.leading, word.trailing), right = std::max(word.leading, word.trailing);
    if (x < left || x >= right) continue;
    const double fraction = WordFraction(word, position);
    return word.leading <= word.trailing ? x < left + (right - left) * fraction :
                                          x >= right - (right - left) * fraction;
  }
  return false;
}
inline void HighlightColumns(const TextMask& mask, int offset, int width,
                             double position, std::vector<unsigned char>& columns) {
  columns.resize(width);
  std::fill(columns.begin(), columns.end(), static_cast<unsigned char>(mask.words.empty() ? 1 : 0));
  if (mask.words.empty()) return;
  std::vector<std::pair<int, int>> ranges;
  ranges.reserve(mask.words.size());
  for (const auto& word : mask.words) {
    const int left = std::min(word.leading, word.trailing), right = std::max(word.leading, word.trailing);
    if (right <= offset || left >= offset + width) continue;
    const double fraction = WordFraction(word, position);
    const int first = word.leading <= word.trailing ? left :
        static_cast<int>(std::ceil(right - (right - left) * fraction));
    const int last = word.leading <= word.trailing ?
        static_cast<int>(std::ceil(left + (right - left) * fraction)) : right;
    const int clipped_first = std::max(0, first - offset), clipped_last = std::min(width, last - offset);
    if (clipped_first < clipped_last) ranges.emplace_back(clipped_first, clipped_last);
  }
  std::sort(ranges.begin(), ranges.end());
  int painted = 0;
  for (const auto& range : ranges) {
    const int first = std::max(range.first, painted);
    if (first < range.second) std::fill(columns.begin() + first, columns.begin() + range.second, static_cast<unsigned char>(1));
    painted = std::max(painted, range.second);
  }
}
inline void CacheOutline(TextMask& mask, double radius) {
  if (mask.outline_radius == radius && mask.outline.size() == mask.pixels.size()) return;
  mask.outline_radius = radius;
  mask.outline.assign(mask.pixels.size(), 0);
  const int edge = static_cast<int>(std::ceil(radius));
  for (int y = 0; y < mask.height; ++y) for (int x = 0; x < mask.width; ++x) {
    double coverage = 0;
    for (int dy = -edge; dy <= edge; ++dy) for (int dx = -edge; dx <= edge; ++dx) {
      if (x + dx < 0 || x + dx >= mask.width || y + dy < 0 || y + dy >= mask.height) continue;
      const double weight = std::clamp(radius + 1 - std::sqrt(static_cast<double>(dx * dx + dy * dy)), 0.0, 1.0);
      coverage = std::max(coverage, mask.pixels[static_cast<size_t>(y + dy) * mask.width + x + dx] * weight);
    }
    mask.outline[static_cast<size_t>(y) * mask.width + x] = static_cast<unsigned char>(std::round(coverage));
  }
}
inline double WordReadPosition(const TextMask& mask, double position) {
  for (const auto& word : mask.words) {
    if (position < word.start) return word.leading;
    if (word.length && position < word.start + word.length)
      return word.leading + (word.trailing - word.leading) *
          std::clamp((position - word.start) / word.length, 0.0, 1.0);
  }
  return mask.words.empty() ? 0 : mask.words.back().trailing;
}
// A pathological tag gets a bounded page of the same shaped paragraph. Page
// changes do not re-shape or truncate text, and use no ellipsis/substrings.
inline bool PaintPage(TextMask& output, int wanted_origin) {
  if (!output.shaping || !output.shaping->dc || !output.shaping->analysis) return false;
  const int origin = std::clamp(wanted_origin, 0, std::max(0, output.natural_width - output.width));
  if (!output.pixels.empty() && output.origin == origin) return true;
  BITMAPINFO info{}; info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = output.width; info.bmiHeader.biHeight = -output.height;
  info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32; info.bmiHeader.biCompression = BI_RGB;
  void* storage = nullptr;
  const HBITMAP bitmap = CreateDIBSection(nullptr, &info, DIB_RGB_COLORS, &storage, nullptr, 0);
  if (!bitmap || !storage) { if (bitmap) DeleteObject(bitmap); return false; }
  const HDC dc = output.shaping->dc;
  const auto old_bitmap = SelectObject(dc, bitmap);
  memset(storage, 0, static_cast<size_t>(output.width) * output.height * 4);
  const int saved = SaveDC(dc);
  SetTextColor(dc, RGB(255, 255, 255)); SetBkMode(dc, TRANSPARENT);
  IntersectClipRect(dc, 0, 0, output.width, output.height);
  const int top = std::max(0L, (output.height - output.shaping->measured.cy) / 2L);
  const HRESULT result = ScriptStringOut(output.shaping->analysis,
      output.padding - origin, top, 0, nullptr, 0, 0, FALSE);
  RestoreDC(dc, saved); SelectObject(dc, old_bitmap);
  if (SUCCEEDED(result)) {
    output.origin = origin;
    output.pixels.resize(static_cast<size_t>(output.width) * output.height);
    const auto* pixels = static_cast<std::uint32_t*>(storage);
    for (size_t index = 0; index < output.pixels.size(); ++index) {
      const auto pixel = pixels[index];
      output.pixels[index] = static_cast<unsigned char>(std::max({pixel & 255u, (pixel >> 8) & 255u, (pixel >> 16) & 255u}));
    }
    output.outline.clear();
  }
  DeleteObject(bitmap); return SUCCEEDED(result);
}
// Uniscribe provides shaping, font linking, bidi and UTF-16 caret mapping once
// per text/layout. Every highlight frame reuses these exact full glyphs.
inline TextMask RasterText(HDC measuring, desktop_integration::PopupFonts& fonts,
                          const std::wstring& text, int viewport_width, int height,
                          UINT dpi, bool animate, const std::vector<TaskbarLyricWord>& words = {}, int font_size = 16) {
  TextMask output;
  if (!measuring || text.empty() || text.size() > 2 * 1024 * 1024 || viewport_width <= 0 ||
      viewport_width > 7680 || height <= 0 || height > 960) return output;
  if (text.size() > 2048) {
    auto source = DivideLongText(text, words);
    const auto range = source->chunks.front();
    output = RasterText(measuring, fonts, text.substr(range.first, range.second - range.first),
        viewport_width, height, dpi, animate, ChunkWords(*source, 0), font_size);
    output.long_text = std::move(source); output.paged = true;
    return output;
  }
  fonts.Ensure(dpi);
  LOGFONTW description{};
  GetObjectW(fonts.ForText(measuring, text.c_str()), sizeof(description), &description);
  description.lfWeight = FW_MEDIUM; description.lfQuality = ANTIALIASED_QUALITY;
  const int pad = std::max(3, MulDiv(4, dpi, 96));
  auto shaping = std::make_shared<ShapedText>();
  shaping->text = text;
  if (!shaping->dc) return output;
  for (int size = font_size; size >= std::min(12, font_size); --size) {
    if (shaping->analysis) ScriptStringFree(&shaping->analysis);
    if (shaping->font) {
      SelectObject(shaping->dc, shaping->original_font);
      DeleteObject(shaping->font); shaping->font = nullptr;
    }
    description.lfHeight = -MulDiv(size, dpi, 96);
    shaping->font = CreateFontIndirectW(&description);
    if (!shaping->font) return output;
    const auto old = SelectObject(shaping->dc, shaping->font);
    if (!shaping->original_font) shaping->original_font = old;
    const HRESULT status = ScriptStringAnalyse(shaping->dc, shaping->text.data(), static_cast<int>(text.size()),
        static_cast<int>(text.size() * 2 + 16), -1, SSA_GLYPHS | SSA_FALLBACK | SSA_LINK | SSA_BREAK,
        0, nullptr, nullptr, nullptr, nullptr, nullptr, &shaping->analysis);
    if (FAILED(status) || !shaping->analysis || !ScriptString_pSize(shaping->analysis)) return output;
    shaping->measured = *ScriptString_pSize(shaping->analysis);
    if (animate || shaping->measured.cx <= viewport_width - pad * 2) break;
  }
  output.natural_width = shaping->measured.cx + pad * 2;
  output.height = height; output.padding = pad; output.shaping = std::move(shaping);
  output.viewport_width = viewport_width; output.dpi = dpi;
  output.overflow = output.natural_width > viewport_width;
  output.paged = output.natural_width > viewport_width * 2;
  output.width = output.paged ? viewport_width * 2 : std::max(viewport_width, output.natural_width);
  if (ValidWords(text, words)) {
    int offset = 0;
    for (const auto& word : words) {
      int leading = 0, trailing = 0;
      const int end = offset + static_cast<int>(word.content.size());
      const int final_cp = end == static_cast<int>(text.size()) ? std::max(0, end - 1) : end;
      if (SUCCEEDED(ScriptStringCPtoX(output.shaping->analysis, offset, FALSE, &leading)) &&
          SUCCEEDED(ScriptStringCPtoX(output.shaping->analysis, final_cp,
              end == static_cast<int>(text.size()), &trailing)))
        output.words.push_back({word.start, word.length, leading + pad, trailing + pad});
      offset = end;
    }
  }
  if (!PaintPage(output, 0)) return {};
  return output;
}
inline void MapWords(TextMask& output, const std::wstring& text,
                     const std::vector<TaskbarLyricWord>& words) {
  if (output.long_text) {
    auto source = std::exchange(output.long_text, nullptr);
    source->words = ValidWords(text, words) ? words : std::vector<TaskbarLyricWord>{};
    const auto range = source->chunks[output.chunk];
    MapWords(output, text.substr(range.first, range.second - range.first), ChunkWords(*source, output.chunk));
    output.long_text = std::move(source);
    return;
  }
  output.words.clear();
  if (!output.shaping || !ValidWords(text, words)) return;
  int offset = 0;
  for (const auto& word : words) {
    int leading = 0, trailing = 0;
    const int end = offset + static_cast<int>(word.content.size());
    const int final_cp = end == static_cast<int>(text.size()) ? std::max(0, end - 1) : end;
    if (SUCCEEDED(ScriptStringCPtoX(output.shaping->analysis, offset, FALSE, &leading)) &&
        SUCCEEDED(ScriptStringCPtoX(output.shaping->analysis, final_cp,
            end == static_cast<int>(text.size()), &trailing)))
      output.words.push_back({word.start, word.length, leading + output.padding, trailing + output.padding});
    offset = end;
  }
}
inline bool SelectTextChunk(TextMask& output, double position, double line_start,
                            double line_end, HDC measuring, desktop_integration::PopupFonts& fonts,
                            int width, UINT dpi, bool animate) {
  const auto source = output.long_text;
  if (!source || source->chunks.empty()) return false;
  double logical = 0;
  if (!source->words.empty()) {
    for (const auto& word : source->words) {
      if (position < word.start) break;
      if (word.length && position < word.start + word.length) {
        logical += word.content.size() * std::clamp((position - word.start) / word.length, 0.0, 1.0);
        break;
      }
      logical += word.content.size();
    }
  } else if (line_end > line_start) {
    logical=source->text.size()*LineReadProgress(position,line_start,line_end);
  }
  const auto found = std::upper_bound(source->chunks.begin(), source->chunks.end(), logical,
      [](double at, const auto& range) { return at < range.second; });
  const int chunk = found == source->chunks.end() ? static_cast<int>(source->chunks.size()) - 1 :
      static_cast<int>(found - source->chunks.begin());
  if (chunk == output.chunk) return false;
  const auto range = source->chunks[chunk];
  auto next = RasterText(measuring, fonts, source->text.substr(range.first, range.second - range.first),
      width, output.height, dpi, animate, ChunkWords(*source, chunk));
  if (next.pixels.empty()) return false;
  next.long_text = source; next.chunk = chunk; next.paged = true; output = std::move(next);
  return true;
}
inline double LogicalPosition(const LongText& source, double position, double line_start, double line_end) {
  double logical = 0;
  if (!source.words.empty()) {
    for (const auto& word : source.words) {
      if (position < word.start) break;
      if (word.length && position < word.start + word.length) {
        logical += word.content.size() * std::clamp((position - word.start) / word.length, 0.0, 1.0);
        break;
      }
      logical += word.content.size();
    }
  } else if (line_end > line_start)
    logical=source.text.size()*LineReadProgress(position,line_start,line_end);
  return logical;
}
// Narrow side taskbars use real horizontal paragraphs. Only a bounded visible
// page is shaped/rasterized; authoritative timings still refer to the full text.
inline bool SelectWrappedPage(TextMask& output, double position, double line_start, double line_end,
                              HDC dc, desktop_integration::PopupFonts& fonts) {
  const auto state = output.wrapped;
  if (!state || state->source->chunks.empty()) return false;
  const auto& source = *state->source;
  const double logical = LogicalPosition(source, position, line_start, line_end);
  const auto found = std::upper_bound(source.chunks.begin(), source.chunks.end(), logical,
      [](double at, const auto& range) { return at < range.second; });
  const int chunk = found == source.chunks.end() ? static_cast<int>(source.chunks.size()) - 1 :
      static_cast<int>(found - source.chunks.begin());
  const auto range = source.chunks[chunk];
  const auto text = source.text.substr(range.first, range.second - range.first);
  if (state->chunk != chunk) {
    auto measured = RasterText(dc, fonts, text, output.width, MulDiv(state->font_size + 8, output.dpi, 96), output.dpi, true, {}, state->font_size);
    if (!measured.shaping) return false;
    state->shaping = measured.shaping;
    state->logical_widths.assign(text.size() + 1, 0);
    if (FAILED(ScriptStringGetLogicalWidths(state->shaping->analysis, state->logical_widths.data()))) return false;
    const auto attributes = ScriptString_pLogAttr(state->shaping->analysis);
    const int available = std::max(1, output.width - measured.padding * 2);
    state->pitch = std::max(MulDiv(state->font_size + 4, output.dpi, 96), static_cast<int>(state->shaping->measured.cy) + MulDiv(3, output.dpi, 96));
    state->rows.clear();
    int begin = 0;
    while (begin < static_cast<int>(text.size())) {
      int end = begin, consumed = 0, fit = begin, soft = begin;
      while (end < static_cast<int>(text.size())) {
        const int next = consumed + std::max(0, state->logical_widths[end]);
        if (next > available && fit > begin) break;
        consumed = next; ++end;
        if (end == static_cast<int>(text.size()) || !attributes || attributes[end].fCharStop) {
          fit = end;
          if (end < static_cast<int>(text.size()) && attributes && attributes[end].fSoftBreak) soft = end;
          if (consumed > available) break; // one indivisible grapheme
        }
      }
      if (fit <= begin) fit = std::max(begin + 1, end);
      if (fit < static_cast<int>(text.size()) && soft > begin && soft - begin >= (fit - begin) / 2) fit = soft;
      state->rows.emplace_back(begin, fit); begin = fit;
    }
    state->chunk = chunk; state->first_row = -1;
  }
  const double local = std::clamp(logical - range.first, 0.0, static_cast<double>(text.size()));
  const auto row = std::upper_bound(state->rows.begin(), state->rows.end(), local,
      [](double at, const auto& value) { return at < value.second; });
  const int active = row == state->rows.end() ? static_cast<int>(state->rows.size()) - 1 :
      static_cast<int>(row - state->rows.begin());
  const int capacity = std::max(1, output.height / state->pitch);
  const int first = std::clamp(active - capacity / 3, 0, std::max(0, static_cast<int>(state->rows.size()) - capacity));
  if (state->first_row == first) return false;
  std::vector<unsigned char> next_pixels(static_cast<size_t>(output.width) * output.height, 0);
  std::vector<WordCoverage> next_words;
  std::vector<int> prefix(text.size() + 1, 0);
  for (size_t cp = 0; cp < text.size(); ++cp) prefix[cp + 1] = prefix[cp] + std::max(0, state->logical_widths[cp]);
  const auto authored = ChunkWords(source, chunk);
  for (int index = first; index < static_cast<int>(state->rows.size()) && index < first + capacity; ++index) {
    const auto row_range = state->rows[index];
    const auto segment = text.substr(row_range.first, row_range.second - row_range.first);
    auto glyph = RasterText(dc, fonts, segment, output.width, state->pitch, output.dpi, true, {}, state->font_size);
    if (!glyph.shaping) return false;
    if (glyph.natural_width > output.width)
      glyph = RasterText(dc, fonts, segment, output.width, state->pitch, output.dpi, false, {}, state->font_size);
    if (!glyph.shaping || glyph.pixels.empty()) return false;
    const int top = (index - first) * state->pitch;
    for (int y = 0; y < state->pitch && top + y < output.height; ++y)
      std::copy_n(glyph.pixels.data() + static_cast<size_t>(y) * glyph.width, std::min(output.width, glyph.width),
          next_pixels.data() + static_cast<size_t>(top + y) * output.width);
    int word_begin = 0;
    for (const auto& word : authored) {
      const int word_end = word_begin + static_cast<int>(word.content.size());
      const int begin = std::max(row_range.first, word_begin), end = std::min(row_range.second, word_end);
      if (begin < end) {
        int leading = 0, trailing = 0;
        const int final_cp = end - row_range.first;
        const bool final = final_cp == static_cast<int>(segment.size());
        if (SUCCEEDED(ScriptStringCPtoX(glyph.shaping->analysis, begin - row_range.first, FALSE, &leading)) &&
            SUCCEEDED(ScriptStringCPtoX(glyph.shaping->analysis, final ? final_cp - 1 : final_cp, final, &trailing))) {
          const double total = std::max(1, prefix[word_end] - prefix[word_begin]);
          next_words.push_back({word.start, word.length, leading + glyph.padding, trailing + glyph.padding,
              top, top + state->pitch, (prefix[begin] - prefix[word_begin]) / total,
              (prefix[end] - prefix[word_begin]) / total});
        }
      }
      word_begin = word_end;
    }
  }
  output.pixels = std::move(next_pixels); output.words = std::move(next_words); output.outline.clear();
  state->first_row = first;
  return true;
}
inline TextMask RasterWrappedText(HDC dc, desktop_integration::PopupFonts& fonts,
                                  const std::wstring& text, int width, int height, UINT dpi,
                                  const std::vector<TaskbarLyricWord>& words, double position,
                                  double line_start, double line_end, int font_size = 16) {
  TextMask output;
  if (text.empty() || width <= 0 || width > 7680 || height <= 0 || height > 960) return output;
  output.width = output.viewport_width = output.natural_width = width;
  output.height = height; output.dpi = dpi;
  output.wrapped = std::make_shared<WrappedText>();
  output.wrapped->font_size = font_size;
  output.wrapped->source = DivideLongText(text, words);
  if (!SelectWrappedPage(output, position, line_start, line_end, dc, fonts)) return {};
  return output;
}
inline void CompositeText(std::uint32_t* pixels, int width, int height, TextMask& mask,
                           double top, int offset, double opacity, bool highlight,
                           double position, COLORREF foreground,
                           std::vector<unsigned char>& columns, int left = 0, int clip_width = 0,
                           bool stroke = false, COLORREF stroke_color = 0, double stroke_opacity = .9,
                           int clip_top = 0, int clip_height = 0) {
  if (!pixels || mask.pixels.empty() || mask.height <= 0) return;
  const int extent = std::min(clip_width > 0 ? clip_width : width, width - left);
  if (extent <= 0 || left < 0) return;
  if (mask.paged && (offset < mask.origin || offset + extent > mask.origin + mask.width)) {
    if (!PaintPage(mask, std::max(0, offset - extent / 2))) return;
  }
  if (stroke) CacheOutline(mask, .6 * mask.dpi / 96);
  if (highlight) {
    if (!mask.wrapped) HighlightColumns(mask, offset, extent, position, columns);
    else {
      columns.assign(static_cast<size_t>(extent) * mask.height, mask.wrapped->source->words.empty() ? 1 : 0);
      for (const auto& word : mask.words) {
        const double fraction = WordFraction(word, position);
        const int low = std::min(word.leading, word.trailing), high = std::max(word.leading, word.trailing);
        const int begin = word.leading <= word.trailing ? low : static_cast<int>(std::ceil(high - (high - low) * fraction));
        const int end = word.leading <= word.trailing ? static_cast<int>(std::ceil(low + (high - low) * fraction)) : high;
        for (int y = std::max(0, word.top); y < std::min(mask.height, word.bottom); ++y)
          for (int x = std::max(0, begin); x < std::min(extent, end); ++x) columns[static_cast<size_t>(y) * extent + x] = 1;
      }
    }
  }
  const int first = std::max(std::max(0, clip_top), static_cast<int>(std::floor(top)));
  const int last = std::min(std::min(height, clip_height > 0 ? clip_top + clip_height : height),
      static_cast<int>(std::ceil(top + mask.height)));
  for (int y = first; y < last; ++y) {
    const double source_y = y - top;
    const int row = static_cast<int>(std::floor(source_y));
    const double fraction = source_y - row;
    for (int x = 0; x < extent; ++x) {
      const int source_x = x + offset - mask.origin;
      if (source_x < 0 || source_x >= mask.width) continue;
      const auto sample = [&](const std::vector<unsigned char>& glyphs, int at, bool emphasize) -> double {
        if (at < 0 || at >= mask.height) return 0;
        double strength = 1;
        if (emphasize && highlight && !columns[mask.wrapped ? static_cast<size_t>(at) * extent + x : x]) strength = .43;
        return glyphs[static_cast<size_t>(at) * mask.width + source_x] * strength;
      };
      const auto blend = [&](unsigned alpha, COLORREF color) {
        if (!alpha) return;
        const auto index = static_cast<size_t>(y) * width + x + left;
        const auto old = pixels[index];
        const unsigned combined = alpha + (old >> 24) * (255 - alpha) / 255;
        const auto channel = [&](unsigned shift, unsigned value) {
          return value * alpha / 255 + ((old >> shift) & 255) * (255 - alpha) / 255;
        };
        pixels[index] = combined << 24 | channel(16, GetRValue(color)) << 16 |
            channel(8, GetGValue(color)) << 8 | channel(0, GetBValue(color));
      };
      if (stroke) blend(static_cast<unsigned>(std::round(opacity * stroke_opacity *
          (sample(mask.outline, row, false) * (1 - fraction) + sample(mask.outline, row + 1, false) * fraction))), stroke_color);
      blend(static_cast<unsigned>(std::round(opacity * (sample(mask.pixels, row, true) * (1 - fraction) +
          sample(mask.pixels, row + 1, true) * fraction))), foreground);
    }
  }
}
} // namespace taskbar_lyrics
#endif
