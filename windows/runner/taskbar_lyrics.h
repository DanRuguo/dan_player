#ifndef RUNNER_TASKBAR_LYRICS_H_
#define RUNNER_TASKBAR_LYRICS_H_
#include <windows.h>
#include <memory>
#include <string>
#include <functional>
#include "taskbar_lyrics_paint.h"

// A non-activating, click-through native taskbar child. It creates no extra
// Flutter engine and never reparents a window or changes process DPI awareness.
struct TaskbarLyricsLayout {
  bool vertical = false;
  int area_count = 0, area_index = 0;
};
class TaskbarLyrics {
 public:
  TaskbarLyrics();
  ~TaskbarLyrics();
  TaskbarLyrics(const TaskbarLyrics&) = delete;
  TaskbarLyrics& operator=(const TaskbarLyrics&) = delete;
  bool Set(bool enabled, std::wstring text, unsigned accent,
           std::wstring family, std::wstring path, bool animate, bool playing,
           std::vector<TaskbarLyricWord> words, std::wstring next_text,
           double position, double rate, std::wstring source, std::wstring line,
           std::int64_t timeline_revision, double line_start, double line_end,
           std::wstring placement = L"auto", std::wstring next_track_text = L"",
           bool show_pause_indicator = false, bool stroke_enabled = false,
           unsigned area_selection = 0, bool paused = false,
           std::wstring color_scheme = L"player", bool show_next_button = false, bool next_button_enabled = false,
           bool animate_layout = false,bool show_next_lyric = true,bool playback_button_enabled = false);
  static bool IsVerticalLayout();
  TaskbarLyricsLayout GetLayout() const;
  void SetLayoutCallback(std::function<void(const TaskbarLyricsLayout&)> callback);
  void SetNextTrackCallback(std::function<void()> callback);
  void SetNextButtonLabel(std::wstring label);
  void SetPlaybackCallback(std::function<void()> callback);
  void SetPlaybackButtonLabels(std::wstring play,std::wstring pause);
#ifdef DAN_TASKBAR_LYRICS_NATIVE_QA
  void FailNextGeometryForTesting(unsigned count);
  void AddOccupiedAreaForTesting(RECT occupied);
  bool LayoutAnimatingForTesting() const;
  unsigned GeometryRequestsForTesting() const;
  unsigned RasterCountForTesting() const;
  ULONGLONG LineAnimationStartForTesting() const;
  void SetSystemLightForTesting(bool light);
  std::vector<std::uint32_t> PixelsForTesting() const;
  size_t LayoutBufferPixelsForTesting() const;
  bool LineAnimatingForTesting() const;
  int ReadOffsetForTesting() const;
  int MetadataOffsetForTesting() const;
  void SetPositionForTesting(double position);
  void UseBarForTesting(HWND bar,std::vector<RECT> occupied);
  unsigned MotionFramesForTesting() const;
  int CurrentChunkForTesting() const;
#endif
  void EnvironmentChanged();
  void Close();
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
  std::function<void(const TaskbarLyricsLayout&)> layout_callback_;
  std::function<void()> next_track_callback_;
  std::function<void()> playback_callback_;
  std::wstring next_button_label_ = L"Next track";
  std::wstring play_label_=L"Play",pause_label_=L"Pause";
};
#endif
