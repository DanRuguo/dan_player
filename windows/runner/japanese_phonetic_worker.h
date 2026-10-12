#ifndef RUNNER_JAPANESE_PHONETIC_WORKER_H_
#define RUNNER_JAPANESE_PHONETIC_WORKER_H_

#include <windows.h>

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

namespace japanese_phonetic {

struct Word {
  std::wstring text;
  std::wstring reading;
};
using Chunk = std::optional<std::vector<Word>>;
struct Reply {
  std::uint64_t id = 0;
  bool available = false;
  bool dictionary_missing = false;
  std::vector<Chunk> chunks;
};

// Segmentation belongs to Dart's Characters implementation. The native bound
// validates its batches, including UTF-16, rather than inventing another split.
bool ValidChunks(const std::vector<std::wstring>& chunks);
bool CompleteWords(const std::wstring& input, const std::vector<Word>& words);

// Lazily owns one STA thread; idle work waits without polling or a frame clock.
// At most one executing job and one replacement are retained. Flutter replies
// stay on the window thread and are never touched by this worker.
class Worker {
 public:
  using AnalyzeChunk = std::function<Chunk(const std::wstring&)>;
  Worker(HWND window, UINT message, AnalyzeChunk analyze = {});
  ~Worker();
  Worker(const Worker&) = delete;
  Worker& operator=(const Worker&) = delete;
  void Submit(std::uint64_t id, std::vector<std::wstring> chunks,
              std::string dictionary_path = {});
  void Cancel();
  std::vector<Reply> TakeReplies();

 private:
  struct Job {
    std::uint64_t id;
    std::vector<std::wstring> chunks;
    std::string dictionary_path;
    std::atomic<bool> cancelled{false};
  };
  void Run();
  std::mutex mutex_;
  std::condition_variable wake_;
  HWND window_;
  const UINT message_;
  const AnalyzeChunk analyze_;
  bool stopped_ = false;
  std::shared_ptr<Job> pending_;
  std::shared_ptr<Job> active_;
  std::vector<Reply> completed_;
  std::thread thread_;
};

}  // namespace japanese_phonetic
#endif  // RUNNER_JAPANESE_PHONETIC_WORKER_H_
