#ifndef RUNNER_INSTALLER_LAUNCHER_H_
#define RUNNER_INSTALLER_LAUNCHER_H_

#include <flutter/flutter_engine.h>
#include <memory>

// Owns a message-only result dispatcher. Trust/hash/process work runs off the
// Flutter platform thread; callbacks and channel destruction stay on it.
class InstallerLauncherController {
 public:
  explicit InstallerLauncherController(flutter::FlutterEngine* engine);
  ~InstallerLauncherController();

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

#endif
