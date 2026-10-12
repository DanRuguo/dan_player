// Reuse the private-desktop fixture; do not execute its existing glyph cases.
#define wmain LetterSpacingGlyphCases
#include "taskbar_lyric_spacing_test.cpp"
#undef wmain

int wmain(int argc, wchar_t** argv) {
  using namespace desktop_integration;
  CHECK(argc == 5);
  PrivateDesktop desktop;
  CHECK(desktop.owned);
  NativeFontPolicy policy;
  const std::array<const wchar_t*, 4> families{
      L"Source Han Sans SC", L"Google Sans", L"Source Han Sans JP", L"Pretendard"};
  for (size_t index = 0; index < families.size(); ++index) {
    policy.faces[index] = {families[index], argv[index + 1]};
  }
  policy.base_fallback = policy.faces[0];
  FakeBar bar;
  CHECK(bar.window);
  TaskbarLyrics surface;
  const std::wstring text = L"\u6668\u5149 Moonlight e\u0301 \U0001f469\U0001f3fd\u200d\U0001f680 \ud55c\uae00 \u05e9\u05dc\u05d5\u05dd \u7d42\u70b9";
  double spacing = 0;
  bool motion = true;
  const auto send = [&]() {
    return surface.Set(true, text, 0xff008ebd, L"", L"", false, false,
        {{0, 4000, text}}, text, 1250, 1, L"source", L"line", 5, 0, 4000,
        L"start", L"", false, false, 0, true, L"player", false, false,
        motion, true, false, policy, spacing);
  };
  CHECK(send());
  surface.UseBarForTesting(bar.window, bar.Occupied());
  Pump(250);
  CHECK(surface.ShapingForTesting() && !surface.PixelsForTesting().empty());
  const auto initial = surface.PixelsForTesting();
  const auto initial_rasters = surface.RasterCountForTesting();
  spacing = 8;
  CHECK(send());
  CHECK(surface.LayoutAnimatingForTesting());
  CHECK(surface.LayoutBufferPixelsForTesting() > 0);
  CHECK(surface.RasterCountForTesting() == initial_rasters + 1);
  const auto target_shape = surface.ShapingForTesting();
  Pump(65);
  CHECK(surface.LayoutAnimatingForTesting());
  CHECK(!surface.PixelsForTesting().empty());
  CHECK(surface.PixelsForTesting() != initial);
  CHECK(surface.ShapingForTesting() == target_shape);
  CHECK(surface.RasterCountForTesting() == initial_rasters + 1);
  std::cout << "PASS paused spacing has real finite layout frames without reshaping\n";

  spacing = 2;
  CHECK(send());
  CHECK(surface.LayoutAnimatingForTesting());
  CHECK(surface.RasterCountForTesting() == initial_rasters + 2);
  const auto reversed_shape = surface.ShapingForTesting();
  Pump(250);
  CHECK(!surface.LayoutAnimatingForTesting());
  CHECK(surface.LayoutBufferPixelsForTesting() == 0);
  CHECK(surface.ShapingForTesting() == reversed_shape);
  const auto final_pixels = surface.PixelsForTesting();
  const auto final_frames = surface.MotionFramesForTesting();
  Pump(100);
  CHECK(surface.MotionFramesForTesting() == final_frames);
  CHECK(surface.PixelsForTesting() == final_pixels);
  std::cout << "PASS rapid spacing reversal settles and releases its paused clock\n";

  spacing = 7;
  CHECK(send());
  CHECK(surface.LayoutAnimatingForTesting());
  Pump(25);
  motion = false;
  CHECK(send());
  CHECK(!surface.LayoutAnimatingForTesting());
  CHECK(surface.LayoutBufferPixelsForTesting() == 0);
  const auto disabled_frames = surface.MotionFramesForTesting();
  Pump(100);
  CHECK(surface.MotionFramesForTesting() == disabled_frames);
  motion = true;
  spacing = 1;
  CHECK(send());
  CHECK(surface.LayoutAnimatingForTesting());
  surface.Close();
  Pump(100);
  CHECK(!FindOwnedTaskbarWindow(L"DanPlayer.TaskbarLyrics.v1"));
  CHECK(surface.LayoutBufferPixelsForTesting() == 0);
  std::cout << "PASS disabled spacing and close retire the old frame immediately\n";
  return 0;
}
