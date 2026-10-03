#ifndef RUNNER_TASKBAR_LYRICS_POLICY_H_
#define RUNNER_TASKBAR_LYRICS_POLICY_H_

#include <windows.h>
#include <algorithm>
#include <optional>
#include <vector>
#include <cmath>
#include <string>
#include "desktop_integration_policy.h"

namespace taskbar_lyrics {
class ScopedParentDpi {
 public:
  explicit ScopedParentDpi(HWND parent) {
    const auto context=GetWindowDpiAwarenessContext(parent);
    if(context) previous_=SetThreadDpiAwarenessContext(context);
  }
  ~ScopedParentDpi(){if(previous_) SetThreadDpiAwarenessContext(previous_);}
  bool valid() const {return previous_!=nullptr;}
 private:
  DPI_AWARENESS_CONTEXT previous_=nullptr;
};
enum class ColorScheme { kPlayer, kSystem };
inline std::optional<ColorScheme> ParseColorScheme(const std::wstring& value) {
  if (value == L"player") return ColorScheme::kPlayer;
  if (value == L"system") return ColorScheme::kSystem;
  return std::nullopt;
}
inline COLORREF ForegroundForScheme(COLORREF accent,bool light,bool high_contrast,COLORREF system_text,ColorScheme scheme) {
  if (high_contrast) return system_text;
  if (scheme==ColorScheme::kSystem) return light ? RGB(0,0,0) : RGB(255,255,255);
  return desktop_integration::TaskbarIconColor(accent,light,false,0);
}
enum class Placement { kAuto, kStart, kCenter, kEnd };
inline std::optional<Placement> ParsePlacement(const std::wstring& value) {
  if (value == L"auto") return Placement::kAuto;
  if (value == L"start") return Placement::kStart;
  if (value == L"center") return Placement::kCenter;
  if (value == L"end") return Placement::kEnd;
  return std::nullopt;
}
struct ContentLayout {
  bool vertical = false;
  RECT lyrics{}, metadata{}, pause{}, button{};
  int row_height = 0;
};
inline POINT ContentOffset(int width, int height, int natural_width, int natural_height,
                           bool vertical, Placement placement) {
  const int spare = vertical ? std::max(0, height - natural_height) : std::max(0, width - natural_width);
  const int distance = placement == Placement::kCenter ? spare / 2 : placement == Placement::kEnd ? spare : 0;
  return vertical ? POINT{0, distance} : POINT{distance, 0};
}
inline ContentLayout LayoutContent(int width, int height, UINT dpi, bool vertical, bool pause, bool next_track, bool next_button = false) {
  ContentLayout result; result.vertical = vertical;
  const int status = pause ? std::min(vertical ? width : height,MulDiv(44,dpi,96)) : 0;
  const int button_size = next_button ? std::min(vertical ? width : height, MulDiv(44,dpi,96)) : 0;
  const int available_width = width - (vertical ? 0 : button_size);
  const int available_height = height - (vertical ? button_size : 0);
  const int next_width = !vertical && next_track && available_width >= MulDiv(480, dpi, 96) ? std::min(available_width / 3, MulDiv(280, dpi, 96)) : 0;
  const int next_height = vertical && next_track && available_height >= MulDiv(320, dpi, 96) ? MulDiv(64, dpi, 96) : 0;
  result.lyrics = RECT{vertical ? 0 : status, vertical ? status : 0, available_width - next_width, available_height - next_height};
  result.metadata = vertical ? RECT{0, available_height - next_height, width, available_height} : RECT{available_width - next_width, 0, available_width, height};
  result.pause = vertical ? RECT{(width-status)/2,0,(width+status)/2,status} : RECT{0,(height-status)/2,status,(height+status)/2};
  result.button = vertical ? RECT{(width-button_size)/2,height-button_size,(width+button_size)/2,height} :
      RECT{width-button_size,(height-button_size)/2,width,(height+button_size)/2};
  const int lyric_height = result.lyrics.bottom - result.lyrics.top;
  result.row_height = lyric_height >= MulDiv(vertical ? 80 : 40, dpi, 96) ? lyric_height / 2 : lyric_height;
  return result;
}
struct Entrance { double opacity; double dy; };
inline Entrance LineEntrance(double milliseconds, bool allowed = true) {
  if (!allowed || milliseconds >= 180) return {1, 0};
  const double time = std::clamp(milliseconds / 180.0, 0.0, 1.0);
  const double value = 1 - std::pow(1 - time, 3);
  return {value, (1 - value) * 4};
}
inline double LayoutProgress(double milliseconds) {
  const double time=std::clamp(milliseconds/180.0,0.0,1.0);
  return 1-std::pow(1-time,3);
}
inline double LineReadProgress(double position,double begin,double end) {
  if(end<=begin) return 0;
  const double dwell=std::min(300.0,(end-begin)/4);
  return std::clamp((position-begin-dwell)/(end-begin-2*dwell),0.0,1.0);
}
inline void CrossfadeLayout(std::uint32_t* pixels,int width,int height,
                            const std::vector<std::uint32_t>& previous,int previous_width,int previous_height,
                            int dx,int dy,double progress,double anchor_dx=0,double anchor_dy=0,
                            const std::uint32_t* current=nullptr,const RECT* clip=nullptr,const RECT* previous_clip=nullptr) {
  if (!pixels || previous.empty() || previous_width<=0 || previous_height<=0) return;
  progress=std::clamp(progress,0.0,1.0);
  struct Sampling { int x,y; std::uint32_t weights[4]; };
  const auto sampling=[](double x,double y,double opacity) {
    const int left=static_cast<int>(std::floor(x)),top=static_cast<int>(std::floor(y));
    const double fx=x-left,fy=y-top;
    Sampling result{left,top,{}};
    result.weights[0]=static_cast<std::uint32_t>(std::round((1-fx)*(1-fy)*opacity*65536));
    result.weights[1]=static_cast<std::uint32_t>(std::round(fx*(1-fy)*opacity*65536));
    result.weights[2]=static_cast<std::uint32_t>(std::round((1-fx)*fy*opacity*65536));
    result.weights[3]=static_cast<std::uint32_t>(std::round(fx*fy*opacity*65536));
    return result;
  };
  const auto old=sampling(-dx+anchor_dx*progress,-dy+anchor_dy*progress,1-progress);
  const auto next=sampling(-anchor_dx*(1-progress),-anchor_dy*(1-progress),progress);
  for (int y=0;y<height;++y) for (int x=0;x<width;++x) {
    if (clip && (x<clip->left || x>=clip->right || y<clip->top || y>=clip->bottom)) continue;
    auto& target=pixels[static_cast<size_t>(y)*width+x];
    std::uint32_t colors[8]{},weights[8]{};
    const auto read=[&](const std::uint32_t* source,int source_width,int source_height,const Sampling& point,int index,const RECT* source_clip) {
      for (int row=0;row<2;++row) for (int column=0;column<2;++column) {
        const int sample_index=row*2+column,px=x+point.x+column,py=y+point.y+row;
        weights[index+sample_index]=point.weights[sample_index];
        if (point.weights[sample_index] && px>=0 && py>=0 && px<source_width && py<source_height &&
            (!source_clip || (px>=source_clip->left && px<source_clip->right && py>=source_clip->top && py<source_clip->bottom)))
          colors[index+sample_index]=source[static_cast<size_t>(py)*source_width+px];
      }
    };
    read(previous.data(),previous_width,previous_height,old,0,previous_clip);
    if (current) read(current,width,height,next,4,clip);
    else { colors[4]=target; weights[4]=static_cast<std::uint32_t>(std::round(progress*65536)); }
    if (!(colors[0]|colors[1]|colors[2]|colors[3]|colors[4]|colors[5]|colors[6]|colors[7])) { target=0; continue; }
    std::uint32_t blended=0;
    for (unsigned shift=0;shift<32;shift+=8) {
      std::uint32_t value=32768;
      for (int sample=0;sample<8;++sample) value+=((colors[sample]>>shift)&255)*weights[sample];
      blended|=std::min(255u,value>>16)<<shift;
    }
    target=blended;
  }
}
// Match the reference double-row handoff without allocating a new layout:
// cubic-bezier(.22,.72,.24,1), 560 ms. First entry/single-row uses LineEntrance.
inline double RowProgress(double milliseconds) {
  const double target = std::clamp(milliseconds / 560.0, 0.0, 1.0);
  const auto cubic = [](double t, double a, double b) {
    const double one = 1 - t;
    return 3 * one * one * t * a + 3 * one * t * t * b + t * t * t;
  };
  double low = 0, high = 1;
  for (int step = 0; step < 24; ++step) {
    const double middle = (low + high) / 2;
    if (cubic(middle, .22, .24) < target) low = middle; else high = middle;
  }
  return cubic((low + high) / 2, .72, 1);
}
// Physical pixels throughout. No Explorer control is moved or resized.
inline std::vector<RECT> EligibleAreas(RECT bar, RECT monitor,
                                     const std::vector<RECT>& occupied, UINT dpi) {
  const LONG width = bar.right - bar.left, height = bar.bottom - bar.top;
  const bool vertical = height > width;
  const LONG thickness = vertical ? width : height;
  const LONG begin = vertical ? bar.top : bar.left;
  const LONG end = vertical ? bar.bottom : bar.right;
  const LONG pad = MulDiv(12, static_cast<int>(dpi), 96);
  const LONG minimum = MulDiv(vertical ? 96 : 160, static_cast<int>(dpi), 96);
  if (dpi < 48 || dpi > 768 || width <= 0 || height <= 0 ||
      thickness < MulDiv(24, dpi, 96) || thickness > MulDiv(240, dpi, 96) || bar.left < monitor.left ||
      bar.right > monitor.right || bar.top < monitor.top || bar.bottom > monitor.bottom)
    return {}; // Includes the thin/off-screen auto-hide strip.
  std::vector<std::pair<LONG, LONG>> ranges;
  for (const auto& item : occupied) {
    if (item.bottom <= bar.top || item.top >= bar.bottom ||
        item.right <= bar.left || item.left >= bar.right) continue;
    ranges.emplace_back(std::max(begin, (vertical ? item.top : item.left) - pad),
                         std::min(end, (vertical ? item.bottom : item.right) + pad));
  }
  // A missing/inaccessible UIA tree is not evidence of an entirely empty bar.
  if (ranges.empty()) return {};
  std::sort(ranges.begin(), ranges.end());
  std::vector<std::pair<LONG, LONG>> gaps;
  LONG cursor = begin + pad;
  for (const auto& range : ranges) {
    if (range.first - cursor >= minimum) gaps.emplace_back(cursor, range.first);
    cursor = std::max(cursor, range.second);
  }
  if (end - pad - cursor >= minimum) gaps.emplace_back(cursor, end - pad);
  std::vector<RECT> result;
  for (const auto& gap : gaps) result.push_back(vertical ? RECT{bar.left, gap.first, bar.right, gap.second} :
      RECT{gap.first, bar.top, gap.second, bar.bottom});
  return result;
}
inline size_t SelectedArea(const std::vector<RECT>& areas, bool vertical, unsigned selection) {
  if (areas.empty()) return 0;
  const auto largest = std::max_element(areas.begin(), areas.end(), [vertical](const auto& a, const auto& b) {
    return (vertical ? a.bottom - a.top : a.right - a.left) <
        (vertical ? b.bottom - b.top : b.right - b.left);
  });
  return (static_cast<size_t>(largest - areas.begin()) + selection % areas.size()) % areas.size();
}
inline RECT PlaceArea(RECT chosen, bool vertical, UINT dpi, Placement placement) {
  const LONG begin = vertical ? chosen.top : chosen.left;
  const LONG end = vertical ? chosen.bottom : chosen.right;
  // Bound the backing bitmap even on very wide screens.
  const LONG extent = std::min(end - begin,
      vertical ? 960L : MulDiv(960, dpi, 96));
  LONG start = begin;
  if (placement == Placement::kEnd) start = end - extent;
  else if (placement == Placement::kCenter) start += (end - begin - extent) / 2;
  if (vertical) { chosen.top = start; chosen.bottom = start + extent; }
  else { chosen.left = start; chosen.right = start + extent; }
  return chosen;
}
inline std::optional<RECT> FreeArea(RECT bar, RECT monitor,
                                   const std::vector<RECT>& occupied, UINT dpi,
                                   Placement placement = Placement::kAuto, unsigned selection = 0) {
  const auto areas = EligibleAreas(bar, monitor, occupied, dpi);
  if (areas.empty()) return std::nullopt;
  const bool vertical = bar.bottom - bar.top > bar.right - bar.left;
  return PlaceArea(areas[SelectedArea(areas, vertical, selection)], vertical, dpi, placement);
}

inline bool CoversMonitor(RECT foreground, RECT monitor, UINT dpi) {
  const LONG tolerance = std::max(1, MulDiv(2, dpi, 96));
  return foreground.left <= monitor.left + tolerance &&
      foreground.top <= monitor.top + tolerance &&
      foreground.right >= monitor.right - tolerance &&
      foreground.bottom >= monitor.bottom - tolerance;
}
} // namespace taskbar_lyrics
#endif
