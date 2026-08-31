#include "../taskbar_thumbnail_policy.h"

#include <array>
#include <cstdlib>
#include <iostream>
#include <limits>

namespace p = taskbar_thumbnail;

int main() {
  int count = 0;
  const auto check = [&](bool condition, const char* label) {
    ++count;
    if (!condition) {
      std::cerr << "FAIL: " << label << '\n';
      std::exit(1);
    }
  };
  check(p::ValidPayload(1, 1, 4), "smallest RGBA pixel");
  check(p::ValidPayload(512, 512, 1048576), "exact 1 MiB upper bound");
  for (const auto dimension : {std::int64_t(-1), std::int64_t(0),
                               std::int64_t(513), std::int64_t(1) << 32,
                               std::numeric_limits<std::int64_t>::max()}) {
    check(!p::ValidPayload(dimension, 1, 4), "width validated before narrowing");
    check(!p::ValidPayload(1, dimension, 4), "height validated before product");
  }
  for (const std::size_t bytes : {0U, 3U, 5U, 1048577U}) {
    check(!p::ValidPayload(1, 1, bytes), "exact byte count, no partial pixels");
  }
  const auto wide = p::RequestedSize((320U << 16) | 180U);
  check(wide.width == 320 && wide.height == 180, "HIWORD width LOWORD height");
  const auto landscape = p::FitWithin({400, 225}, wide);
  check(landscape.width == 320 && landscape.height == 180, "landscape bounds");
  const auto portrait = p::FitWithin({225, 400}, {180, 320});
  check(portrait.width == 180 && portrait.height == 320, "portrait bounds");
  const auto square = p::FitWithin({400, 225}, {100, 100});
  check(square.width == 100 && square.height == 56, "letterbox not crop");
  const auto no_upscale = p::FitWithin({20, 10}, {65535, 65535});
  check(no_upscale.width == 20 && no_upscale.height == 10, "no large allocation from DWM dimensions");
  check(!p::FitWithin({512, 512}, {0, 20}).valid(), "zero-width requests ignored");
  check(!p::FitWithin({0, 512}, {20, 20}).valid(), "missing source ignored");
  for (const auto client : {p::Size{1280, 800}, p::Size{1920, 1080}}) {
    const auto peek = p::FitPeekLayout({1440, 720}, client);
    check(peek.canvas.width == client.width && peek.canvas.height == client.height,
          "ordinary Peek canvas matches the full client, not thumbnail size");
    check(peek.content.width == 640 && peek.content.height == 320,
          "high-resolution Peek is a readable 640x320 logical card, not desktop-stretched text");
    check(peek.left == (client.width - peek.content.width) / 2 &&
              peek.top == (client.height - peek.content.height) / 2,
          "whole card is centered, never cropped to the client aspect ratio");
  }
  for (const auto source : {p::Size{1440, 720}, p::Size{720, 1440}, p::Size{1024, 1024}}) {
    for (const auto client : {p::Size{320, 200}, p::Size{507, 320},
                              p::Size{1280, 800}, p::Size{1920, 1080},
                              p::Size{3840, 2160}, p::Size{7680, 4320},
                              p::Size{65535, 65535},
                              p::Size{std::numeric_limits<int>::max(), 1},
                              p::Size{1, std::numeric_limits<int>::max()}}) {
      const auto peek = p::FitPeekLayout(source, client);
      const auto bytes = static_cast<std::size_t>(peek.canvas.width) * peek.canvas.height * 4;
      check(peek.valid() && p::ValidPeekCanvas(peek.canvas, bytes),
            "every Peek canvas fits the 4096-axis/16MiB allocation budget");
      check(peek.canvas.width <= client.width && peek.canvas.height <= client.height &&
                peek.content.width <= peek.canvas.width && peek.content.height <= peek.canvas.height,
            "canvas and complete card stay inside the physical client bounds");
      check(peek.left >= 0 && peek.top >= 0 &&
                std::abs((peek.canvas.width - peek.content.width) - 2 * peek.left) <= 1 &&
                std::abs((peek.canvas.height - peek.content.height) - 2 * peek.top) <= 1,
            "letterbox margins differ by at most one rounding pixel");
      check(std::abs(static_cast<double>(peek.content.width) * source.height -
                       static_cast<double>(peek.content.height) * source.width) <=
                std::max(source.width, source.height),
            "Peek preserves source aspect ratio within one output pixel");
      check(peek.content.width <= source.width && peek.content.height <= source.height,
            "Peek never invents glyph pixels beyond the high-resolution source");
    }
  }
  check(!p::FitPeekLayout({480, 240}, {0, 800}).valid(), "zero-width Peek ignored");
  check(!p::FitPeekLayout({480, 240}, {1280, -1}).valid(), "negative Peek ignored");
  check(!p::FitPeekLayout({2049, 240}, {1280, 800}).valid(), "unbounded Peek source rejected");
  check(!p::FitPeekLayout({2048, 1024}, {1280, 800}).valid(), "oversized source pixel budget rejected");
  for (const auto dpi : {96u, 120u, 144u, 192u, 216u, 288u, 768u}) {
    const auto large = p::FitPeekLayout({1440, 720}, {3840, 2160}, dpi);
    const int expected_width = std::min(1440, static_cast<int>(640 * dpi / 96));
    check(large.content.width == expected_width && large.content.height == expected_width / 2,
          "DPI-based readability grows only up to the genuinely rasterized source density");
    const auto narrow = p::FitPeekLayout({1440, 720}, {507, 320}, dpi);
    check(narrow.content.width == 507 && narrow.content.height == 253,
          "small high-DPI clients remain contained and preserve whole-card aspect");
  }
  const auto legacy_peek = p::FitPeekLayout({480, 240}, {1280, 800}, 192);
  check(legacy_peek.content.width == 480 && legacy_peek.content.height == 240,
        "older thumbnail-only callers remain compatible without blurry bitmap enlargement");
  check(p::ValidPeekPayload(1440, 720, 1440U * 720 * 4), "3x Peek payload accepted");
  check(p::ValidPeekPayload(2048, 512, 4U * 1024 * 1024), "exact Peek source budget accepted");
  for (const auto dimension : {std::int64_t(0), std::int64_t(-1), std::int64_t(2049),
                               std::numeric_limits<std::int64_t>::max()}) {
    check(!p::ValidPeekPayload(dimension, 1, 4), "Peek width rejected before multiplication");
    check(!p::ValidPeekPayload(1, dimension, 4), "Peek height rejected before multiplication");
  }
  check(!p::ValidPeekPayload(2048, 513, 2048U * 513 * 4), "Peek payload bounded to 4MiB");
  check(!p::ValidPeekPayload(1440, 720, 1440U * 720 * 4 - 1), "Peek exact byte count enforced");
  check(!p::ValidPeekCanvas({4096, 4096}, 4096U * 4096 * 4), "Peek pixel budget enforced");
  check(!p::ValidPeekCanvas({1280, 800}, 1), "Peek exact output byte count enforced");

  p::PeekClientState client_state;
  check(!client_state.Resolve().valid(), "no fabricated client before observation");
  client_state.Observe({199, 34}, true);
  check(!client_state.Resolve().valid(), "initial iconic geometry never enters the cache");
  const auto initial_fallback = client_state.Resolve({1264, 792});
  check(initial_fallback.width == 1264 && initial_fallback.height == 792,
        "initially minimized HWND can use normal-placement fallback");
  check(!client_state.Resolve().valid(), "estimated normal client is not cached as observed geometry");
  for (const auto actual : {p::Size{1280, 800}, p::Size{1920, 1080}, p::Size{320, 200}}) {
    client_state.Observe(actual, false);
    for (const auto iconic : {p::Size{}, p::Size{199, 34}, p::Size{183, 26},
                                p::Size{actual.width, actual.height}}) {
      client_state.Observe(iconic, true);
      client_state.Observe({0, 0}, false);
      const auto retained = client_state.Resolve({507, 320});
      check(retained.width == actual.width && retained.height == actual.height,
            "minimize/failed reads preserve restored, maximized and real mini-player sizes");
    }
  }
  for (const int dpi : {96, 144, 192, 288}) {
    const p::Size normal{1280 * dpi / 96, 800 * dpi / 96};
    const p::Size inset{16 * dpi / 96, 8 * dpi / 96};
    const p::Size frame{199 * dpi / 96, 34 * dpi / 96};
    const p::Size client{frame.width - inset.width, frame.height - inset.height};
    const auto custom = p::RestoredClientSize(normal, frame, client, {20, 45});
    check(custom.width == normal.width - inset.width &&
              custom.height == normal.height - inset.height,
          "actual custom NCCALCSIZE insets override system caption assumptions at each DPI");
    const auto legacy = p::RestoredClientSize(normal, frame, frame, {20, 45});
    check(legacy.width == normal.width && legacy.height == normal.height,
          "legacy all-client frame preserves its full normal rectangle");
    const auto standard = p::RestoredClientSize(normal, frame, {}, inset);
    check(standard.width == normal.width - inset.width &&
              standard.height == normal.height - inset.height,
          "empty system iconic client falls back to DPI-aware non-client metrics");
    const auto layout = p::FitPeekLayout({1440, 720}, custom, dpi);
    const auto bytes = static_cast<std::size_t>(layout.canvas.width) * layout.canvas.height * 4;
    check(p::ValidPeekCanvas(layout.canvas, bytes) && layout.content.width > 480 &&
              layout.content.height > 240,
          "restored fallback is readable and still obeys the Peek allocation budget");
  }
  for (const auto insets : {p::Size{-1, -1}, p::Size{1280, 8}, p::Size{16, 800},
                             p::Size{std::numeric_limits<int>::max(), 0}}) {
    const auto safe = p::RestoredClientSize({1280, 800}, {}, {}, insets);
    check(safe.width == 1280 && safe.height == 800,
          "invalid/non-fitting metrics cannot return zero or icon-sized fallback");
  }
  check(!p::RestoredClientSize({}, {199, 34}, {183, 26}, {}).valid(),
        "missing normal placement does not reuse tiny iconic geometry");
  const auto invalid_measurement = p::RestoredClientSize({1280, 800}, {199, 34}, {200, 35}, {16, 39});
  check(invalid_measurement.width == 1264 && invalid_measurement.height == 761,
        "out-of-frame iconic client measurement uses safe system metrics");

  p::RetryBudget retries;
  p::RetryTimer timer;
  check(!timer.pending() && !timer.Matches(0), "no retry timer before a failure");
  check(!p::RetryTimer::Owns(1) && !p::RetryTimer::Owns(0x5105),
        "ordinary plugin timer IDs do not enter thumbnail recovery");
  std::uintptr_t previous_timer = 0;
  for (int source = 0; source < 1000; ++source) {
    const auto retired = timer.Arm();
    check(p::RetryTimer::Owns(retired) && timer.Matches(retired), "new timer owns a tagged token");
    check(retired != previous_timer, "repeated retry arms do not reuse old message IDs");
    check(timer.Cancel() == retired && !timer.pending(), "cancel retires the exact timer ID");
    const auto current = timer.Arm();
    check(current != retired && !timer.Matches(retired) && timer.Matches(current),
          "late queued WM_TIMER cannot match or cancel the next source timer");
    check(timer.pending(), "rejecting a late token leaves the current backoff pending");
    check(timer.Cancel() == current && timer.Cancel() == 0, "timer cleanup remains idempotent");
    previous_timer = current;
  }
  for (int generation = 0; generation < 8; ++generation) {
    check(retries.NextDelayMs() == 100, "first compositor recovery is delayed 100ms");
    check(retries.NextDelayMs() == 500, "second compositor recovery backs off");
    check(retries.NextDelayMs() == 1500, "last compositor recovery stays bounded");
    for (int repeat = 0; repeat < 100; ++repeat) {
      check(retries.NextDelayMs() == 0, "failures never replenish the retry budget");
    }
    retries.Reset();  // Only new source, explicit clear or Shell/DWM rebuild.
  }
  for (int width = 1; width <= 512; width += 17) {
    for (int height = 1; height <= 512; height += 17) {
      const auto fit = p::FitWithin({width, height}, {117, 63});
      check(fit.valid() && fit.width <= 117 && fit.height <= 63 &&
                fit.width <= width && fit.height <= height,
            "every fitted size stays inside source and requested rectangle");
    }
  }

  p::Image image;
  p::Image paired_small, paired_large;
  const std::vector<std::uint8_t> first_pair{20, 30, 40, 255};
  const std::vector<std::uint8_t> second_pair{80, 90, 100, 255};
  const p::RawImage valid_pair{1, 1, &first_pair};
  const p::RawImage invalid_pair{2049, 1, &second_pair};
  check(p::ReplacePreviewImages(paired_small, paired_large, valid_pair, &valid_pair) == p::Update::kChanged,
        "thumbnail and high-resolution Peek commit as one generation");
  check(p::ReplacePreviewImages(paired_small, paired_large, valid_pair, &valid_pair) == p::Update::kUnchanged,
        "identical image pairs avoid duplicate allocations and invalidations");
  check(p::ReplacePreviewImages(paired_small, paired_large, {1, 1, &second_pair}, &invalid_pair) == p::Update::kInvalid &&
            paired_small.Matches(1, 1, first_pair) && paired_large.Matches(1, 1, first_pair),
        "invalid Peek cannot partly replace the matching thumbnail");
  check(p::ReplacePreviewImages(paired_small, paired_large, valid_pair, nullptr) == p::Update::kChanged &&
            !paired_large.size().valid() && paired_small.Matches(1, 1, first_pair),
        "older payload intentionally clears obsolete high-resolution source, never mixing tracks");
  check(p::ReplacePreviewImages(paired_small, paired_large, valid_pair, nullptr) == p::Update::kUnchanged,
        "old payload deduplication retained");
  const std::vector<std::uint8_t> red_blue{255, 0, 0, 255, 0, 0, 255, 255};
  check(image.Set(2, 1, red_blue) == p::Update::kChanged, "first image invalidates");
  check(image.Set(2, 1, red_blue) == p::Update::kUnchanged, "equal pixels do not invalidate");
  check(image.bytes() == 8, "one bounded source cache");
  std::array<std::uint8_t, 8> output{};
  check(image.WriteBgra({2, 1}, output.data(), output.size()), "identity DIB conversion");
  check(output == std::array<std::uint8_t, 8>{0, 0, 255, 255, 255, 0, 0, 255},
        "RGBA to BGRA keeps row order and alpha");
  std::array<std::uint8_t, 4> small{};
  check(image.WriteBgra({1, 1}, small.data(), small.size()), "bounded resampling");
  check(small == std::array<std::uint8_t, 4>{128, 0, 128, 255}, "bilinear midpoint is opaque purple");
  check(!image.WriteBgra({2, 1}, small.data(), small.size()), "undersized output rejected");
  check(!image.WriteBgra({1, 1}, nullptr, 4), "null output rejected");
  check(!image.WriteBgra({1, 2}, output.data(), output.size()), "upscale forbidden");
  check(image.Set(1, 2, red_blue) == p::Update::kChanged, "different dimensions invalidate even equal bytes");
  check(image.Set(1, 1, {32, 16, 8, 64}) == p::Update::kChanged, "premultiplied input accepted");
  check(image.WriteBgra({1, 1}, small.data(), small.size()) &&
            small == std::array<std::uint8_t, 4>{8, 16, 32, 64},
        "premultiplied channels are not multiplied twice");
  check(image.Set(513, 1, {0, 0, 0, 0}) == p::Update::kInvalid, "invalid replacement explicit result");
  check(image.WriteBgra({1, 1}, small.data(), small.size()) &&
            small == std::array<std::uint8_t, 4>{8, 16, 32, 64},
        "invalid replacement does not erase the previously accepted image");
  check(image.Clear(), "disable releases cached source");
  check(image.bytes() == 0 && !image.size().valid(), "clear removes dimensions and pixels");
  check(!image.Clear(), "repeated clear idempotent");
  check(!image.WriteBgra({1, 1}, small.data(), small.size()), "cleared cache cannot serve stale image");
  check(image.Set(2, 1, red_blue) == p::Update::kChanged, "re-enable needs a new invalidation");
  const auto peek = p::FitPeekLayout(image.size(), {1280, 800});
  std::vector<std::uint8_t> peek_output(
      static_cast<std::size_t>(peek.canvas.width) * peek.canvas.height * 4);
  check(image.WritePeekBgra(peek, peek_output.data(), peek_output.size()),
        "full-window Peek uses the same bounded RGBA source, not a screenshot");
  const auto pixel = [&](int x, int y) {
    const auto start = (static_cast<std::size_t>(y) * peek.canvas.width + x) * 4;
    return std::array<std::uint8_t, 4>{peek_output[start], peek_output[start + 1],
                                      peek_output[start + 2], peek_output[start + 3]};
  };
  check(pixel(0, 0) == std::array<std::uint8_t, 4>{0, 0, 255, 255},
        "Peek letterbox margins use the opaque card background");
  check(pixel(peek.left, peek.top) == std::array<std::uint8_t, 4>{0, 0, 255, 255} &&
            pixel(peek.left + peek.content.width - 1, peek.top) ==
                std::array<std::uint8_t, 4>{255, 0, 0, 255},
        "upscaling retains both extreme source edges, no crop or distortion");
  check(!image.WritePeekBgra(peek, nullptr, peek_output.size()), "null Peek output rejected");
  check(!image.WritePeekBgra(peek, peek_output.data(), peek_output.size() - 1),
        "short Peek output rejected before writing");
  auto outside = peek;
  outside.left = std::numeric_limits<int>::max();
  check(!image.WritePeekBgra(outside, peek_output.data(), peek_output.size()),
        "overflowing content offset rejected without arithmetic overflow");
  image.Clear();
  check(!image.WritePeekBgra(peek, peek_output.data(), peek_output.size()),
        "disable retires Peek source as well as thumbnail source");
  std::cout << "PASS: " << count << " thumbnail policy checks (no HWND/Shell).\n";
}
