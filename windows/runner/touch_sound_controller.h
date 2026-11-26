#ifndef RUNNER_TOUCH_SOUND_CONTROLLER_H_
#define RUNNER_TOUCH_SOUND_CONTROLLER_H_

#include <flutter/flutter_engine.h>

#include <memory>

// Low-latency Android Material Effect_Tick playback over a dedicated XAudio2
// shared-mode voice pool. Never touches BASS or exclusive-output devices.
class TouchSoundController final {
 public:
  explicit TouchSoundController(flutter::FlutterEngine* engine);
  ~TouchSoundController();

  TouchSoundController(const TouchSoundController&) = delete;
  TouchSoundController& operator=(const TouchSoundController&) = delete;

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_TOUCH_SOUND_CONTROLLER_H_
