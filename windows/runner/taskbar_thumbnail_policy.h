#ifndef RUNNER_TASKBAR_THUMBNAIL_POLICY_H_
#define RUNNER_TASKBAR_THUMBNAIL_POLICY_H_

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <memory>
#include <new>
#include <vector>

// No HWND, Flutter, image decoder or file access. The source is exactly one
// bounded premultiplied raw-RGBA card; DWM output is a temporary top-down DIB.
namespace taskbar_thumbnail {
constexpr int kMaximumAxis = 512;
constexpr std::size_t kMaximumBytes = 1024 * 1024;
constexpr int kMaximumPeekAxis = 4096;
constexpr std::size_t kMaximumPeekPixels = 4 * 1024 * 1024;

// A transient compositor/resource failure can retry only three times for a
// given source. Success cancels a timer but does not replenish this budget;
// otherwise repeated paint failures could create an invalidate/retry loop.
class RetryBudget {
 public:
  unsigned NextDelayMs() {
    constexpr unsigned delays[] = {100, 500, 1500};
    return used_ < 3 ? delays[used_++] : 0;
  }
  void Reset() { used_ = 0; }
 private:
  unsigned used_ = 0;
};

// KillTimer does not remove an already-queued WM_TIMER. A fresh ID for each
// arm lets such old messages be ignored without cancelling a newer retry.
// Reserve a recognizable high tag in our HWND's timer namespace, distinct
// from plugins' small integer IDs. The serial is never reset on cancellation.
class RetryTimer {
 public:
  static constexpr std::uintptr_t kSerialMask = sizeof(std::uintptr_t) >= 8
      ? static_cast<std::uintptr_t>(0xffffffffULL) : 0x000fffffU;
  static constexpr std::uintptr_t kTag = sizeof(std::uintptr_t) >= 8
      ? static_cast<std::uintptr_t>(0x4450544800000000ULL) : 0x44500000U;
  static bool Owns(std::uintptr_t timer) {
    return (timer & ~kSerialMask) == kTag;
  }
  std::uintptr_t Arm() {
    do { serial_ = (serial_ + 1) & kSerialMask; } while (serial_ == 0);
    current_ = kTag | serial_;
    return current_;
  }
  std::uintptr_t Cancel() {
    const auto previous = current_;
    current_ = 0;
    return previous;
  }
  bool Matches(std::uintptr_t timer) const {
    return current_ != 0 && timer == current_;
  }
  bool pending() const { return current_ != 0; }
 private:
  std::uintptr_t serial_ = 0;
  std::uintptr_t current_ = 0;
};

struct Size {
  int width = 0;
  int height = 0;
  bool valid() const { return width > 0 && height > 0; }
};

// An iconic HWND can report a zero or icon-sized client. Never let that
// transient geometry replace the last actual restored/maximized client.
class PeekClientState {
 public:
  void Observe(Size client, bool minimized) {
    if (!minimized && client.valid()) last_non_iconic_ = client;
  }
  Size Resolve(Size restored_fallback = {}) const {
    return last_non_iconic_.valid() ? last_non_iconic_ : restored_fallback;
  }
 private:
  Size last_non_iconic_;
};

inline Size RestoredClientSize(Size restored_frame, Size iconic_frame,
                               Size iconic_client, Size standard_insets) {
  if (!restored_frame.valid()) return {};
  // Custom WM_NCCALCSIZE (our hidden title bar) also runs on the iconic
  // frame. Its measured insets are more accurate than system caption metrics.
  Size insets = standard_insets;
  if (iconic_frame.valid() && iconic_client.valid() &&
      iconic_client.width <= iconic_frame.width &&
      iconic_client.height <= iconic_frame.height) {
    insets = {iconic_frame.width - iconic_client.width,
              iconic_frame.height - iconic_client.height};
  }
  if (insets.width >= 0 && insets.height >= 0 &&
      insets.width < restored_frame.width &&
      insets.height < restored_frame.height) {
    return {restored_frame.width - insets.width,
             restored_frame.height - insets.height};
  }
  // An invalid metric must not turn the fallback into another tiny icon.
  // FitPeekLayout still applies the independent 4096-axis/16MiB output cap.
  return restored_frame;
}

inline bool ValidPayload(std::int64_t width, std::int64_t height,
                         std::size_t bytes) {
  // Validate before multiplication or narrowing, including int64 channel data.
  return width >= 1 && width <= kMaximumAxis && height >= 1 &&
         height <= kMaximumAxis && bytes <= kMaximumBytes &&
         bytes == static_cast<std::size_t>(width * height * 4);
}

inline Size RequestedSize(std::uintptr_t packed) {
  // WM_DWMSENDICONICTHUMBNAIL: HIWORD is x/width, LOWORD is y/height.
  return {static_cast<int>((packed >> 16) & 0xffff),
          static_cast<int>(packed & 0xffff)};
}

inline Size FitWithin(Size source, Size limit) {
  if (!source.valid() || !limit.valid() || source.width > kMaximumAxis ||
      source.height > kMaximumAxis) return {};
  const double scale = std::min({1.0,
      static_cast<double>(limit.width) / source.width,
      static_cast<double>(limit.height) / source.height});
  return {std::max(1, static_cast<int>(source.width * scale)),
          std::max(1, static_cast<int>(source.height * scale))};
}

struct PeekLayout {
  Size canvas;
  Size content;
  int left = 0;
  int top = 0;
  bool valid() const { return canvas.valid() && content.valid(); }
};

inline bool ValidPeekCanvas(Size canvas, std::size_t bytes) {
  return canvas.valid() && canvas.width <= kMaximumPeekAxis &&
         canvas.height <= kMaximumPeekAxis &&
         static_cast<std::size_t>(canvas.width) * canvas.height <=
             kMaximumPeekPixels &&
         bytes == static_cast<std::size_t>(canvas.width) * canvas.height * 4;
}

inline PeekLayout FitPeekLayout(Size source, Size client) {
  if (!source.valid() || source.width > kMaximumAxis ||
      source.height > kMaximumAxis || !client.valid()) return {};
  // GetClientRect is physical pixels. Keep ordinary windows full scale; only
  // very large windows are uniformly reduced to the temporary DIB budget.
  const double pixels = static_cast<double>(client.width) * client.height;
  const double scale = std::min({1.0,
      static_cast<double>(kMaximumPeekAxis) / client.width,
      static_cast<double>(kMaximumPeekAxis) / client.height,
      std::sqrt(kMaximumPeekPixels / pixels)});
  const Size canvas{std::max(1, static_cast<int>(client.width * scale)),
                    std::max(1, static_cast<int>(client.height * scale))};
  const double content_scale = std::min(
      static_cast<double>(canvas.width) / source.width,
      static_cast<double>(canvas.height) / source.height);
  const Size content{
      std::min(canvas.width, std::max(1, static_cast<int>(source.width * content_scale))),
      std::min(canvas.height, std::max(1, static_cast<int>(source.height * content_scale)))};
  return {canvas, content, (canvas.width - content.width) / 2,
           (canvas.height - content.height) / 2};
}

enum class Update { kChanged, kUnchanged, kInvalid, kOutOfMemory };

class Image {
 public:
  Update Set(std::int64_t width, std::int64_t height,
             const std::vector<std::uint8_t>& pixels) {
    if (!ValidPayload(width, height, pixels.size())) return Update::kInvalid;
    if (size_.width == width && size_.height == height &&
        bytes_ == pixels.size() &&
        std::equal(pixels.begin(), pixels.end(), rgba_.get())) {
      return Update::kUnchanged;
    }
    auto replacement = std::unique_ptr<std::uint8_t[]>(
        new (std::nothrow) std::uint8_t[pixels.size()]);
    if (!replacement) return Update::kOutOfMemory;
    std::memcpy(replacement.get(), pixels.data(), pixels.size());
    rgba_ = std::move(replacement);
    size_ = {static_cast<int>(width), static_cast<int>(height)};
    bytes_ = pixels.size();
    return Update::kChanged;
  }

  bool Clear() {
    const bool had_image = size_.valid();
    rgba_.reset();
    size_ = {};
    bytes_ = 0;
    return had_image;
  }

  Size size() const { return size_; }
  std::size_t bytes() const { return bytes_; }

  bool WriteBgra(Size target, std::uint8_t* output, std::size_t bytes) const {
    if (!rgba_ || !output || !ValidPayload(target.width, target.height, bytes) ||
        target.width > size_.width || target.height > size_.height) return false;
    // Keep the existing small-thumbnail downsampling/rounding byte-for-byte.
    // Only full-window Peek needs the optimized, row-cached upscaler below.
    for (int y = 0; y < target.height; ++y) {
      const double sy = std::clamp((y + .5) * size_.height / target.height - .5,
                                    0.0, static_cast<double>(size_.height - 1));
      const int top = static_cast<int>(sy);
      const int bottom = std::min(top + 1, size_.height - 1);
      const double fy = sy - top;
      for (int x = 0; x < target.width; ++x) {
        const double sx = std::clamp((x + .5) * size_.width / target.width - .5,
                                      0.0, static_cast<double>(size_.width - 1));
        const int left = static_cast<int>(sx);
        const int right = std::min(left + 1, size_.width - 1);
        const double fx = sx - left;
        for (int channel = 0; channel < 4; ++channel) {
          const auto sample = [&](int px, int py) {
            return rgba_[(static_cast<std::size_t>(py) * size_.width + px) * 4 + channel];
          };
          const double upper = sample(left, top) * (1 - fx) + sample(right, top) * fx;
          const double lower = sample(left, bottom) * (1 - fx) + sample(right, bottom) * fx;
          const int bgra_channel = channel == 0 ? 2 : channel == 2 ? 0 : channel;
          output[(static_cast<std::size_t>(y) * target.width + x) * 4 + bgra_channel] =
              static_cast<std::uint8_t>(std::round(upper * (1 - fy) + lower * fy));
        }
      }
    }
    return true;
  }

  bool WritePeekBgra(const PeekLayout& layout, std::uint8_t* output,
                     std::size_t bytes) const {
    if (!rgba_ || !output || !ValidPeekCanvas(layout.canvas, bytes) ||
        !layout.content.valid() || layout.left < 0 || layout.top < 0 ||
        layout.content.width > layout.canvas.width ||
        layout.content.height > layout.canvas.height ||
        layout.left > layout.canvas.width - layout.content.width ||
        layout.top > layout.canvas.height - layout.content.height) return false;
    // The producer renders an opaque card. Its top-left background pixel is
    // also used for letterbox margins, so every source edge/text stays intact.
    for (std::size_t index = 0; index < bytes; index += 4) {
      output[index] = rgba_[2];
      output[index + 1] = rgba_[1];
      output[index + 2] = rgba_[0];
      output[index + 3] = rgba_[3];
    }
    return WriteScaledBgra(layout.content,
        output + (static_cast<std::size_t>(layout.top) * layout.canvas.width +
                  layout.left) * 4,
        layout.canvas.width);
  }

 private:
  bool WriteScaledBgra(Size target, std::uint8_t* output, int stride) const {
    // Fixed-point bilinear interpolation preserves premultiplication. Reuse
    // only the two contributing source rows, not a second large image. The
    // bounded x-taps + two rows cost <=176KiB at the 4096px maximum width.
    struct Tap { int left; int right; std::uint32_t weight; };
    using RowPixel = std::array<std::uint32_t, 4>;
    auto taps = std::unique_ptr<Tap[]>(new (std::nothrow) Tap[target.width]);
    auto rows = std::unique_ptr<RowPixel[]>(
        new (std::nothrow) RowPixel[static_cast<std::size_t>(target.width) * 2]);
    if (!taps || !rows) return false;
    constexpr std::uint32_t unit = 65536;
    for (int x = 0; x < target.width; ++x) {
      const double sx = std::clamp((x + .5) * size_.width / target.width - .5,
                                    0.0, static_cast<double>(size_.width - 1));
      const int left = static_cast<int>(sx);
      taps[x] = {left, std::min(left + 1, size_.width - 1),
                  static_cast<std::uint32_t>(std::round((sx - left) * unit))};
    }
    const auto horizontal = [&](int y, RowPixel* row) {
      const auto* source = rgba_.get() + static_cast<std::size_t>(y) * size_.width * 4;
      for (int x = 0; x < target.width; ++x) {
        const auto tap = taps[x];
        for (int channel = 0; channel < 4; ++channel) {
          const int source_channel = channel == 0 ? 2 : channel == 2 ? 0 : channel;
          row[x][channel] = source[tap.left * 4 + source_channel] * (unit - tap.weight) +
                            source[tap.right * 4 + source_channel] * tap.weight;
        }
      }
    };
    RowPixel* upper = rows.get();
    RowPixel* lower = rows.get() + target.width;
    int upper_y = -1;
    int lower_y = -1;
    for (int y = 0; y < target.height; ++y) {
      const double sy = std::clamp((y + .5) * size_.height / target.height - .5,
                                    0.0, static_cast<double>(size_.height - 1));
      const int top = static_cast<int>(sy);
      const int bottom = std::min(top + 1, size_.height - 1);
      const auto weight = static_cast<std::uint32_t>(std::round((sy - top) * unit));
      if (top == lower_y) {
        std::swap(upper, lower);
        std::swap(upper_y, lower_y);
      }
      if (top != upper_y) { horizontal(top, upper); upper_y = top; }
      if (bottom != lower_y) { horizontal(bottom, lower); lower_y = bottom; }
      for (int x = 0; x < target.width; ++x) {
        for (int channel = 0; channel < 4; ++channel) {
          const auto value = static_cast<std::uint64_t>(upper[x][channel]) * (unit - weight) +
                             static_cast<std::uint64_t>(lower[x][channel]) * weight;
          output[(static_cast<std::size_t>(y) * stride + x) * 4 + channel] =
              static_cast<std::uint8_t>((value + (std::uint64_t{1} << 31)) >> 32);
        }
      }
    }
    return true;
  }

  Size size_;
  std::size_t bytes_ = 0;
  std::unique_ptr<std::uint8_t[]> rgba_;
};
}  // namespace taskbar_thumbnail

#endif  // RUNNER_TASKBAR_THUMBNAIL_POLICY_H_
