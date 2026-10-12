#ifndef RUNNER_JAPANESE_PHONETIC_CONTROLLER_H_
#define RUNNER_JAPANESE_PHONETIC_CONTROLLER_H_

#include <flutter/flutter_engine.h>
#include <windows.h>

#include <memory>

class JapanesePhoneticController {
 public:
  JapanesePhoneticController(HWND window, flutter::FlutterEngine* engine);
  ~JapanesePhoneticController();
  bool HandleMessage(UINT message);
 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_JAPANESE_PHONETIC_CONTROLLER_H_
