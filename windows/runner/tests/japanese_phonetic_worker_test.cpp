#include "../japanese_phonetic_worker.h"

#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <iostream>
#include <mutex>
#include <string>
#include <vector>

namespace jp = japanese_phonetic;

namespace {
int passed = 0;
void Check(bool condition, const char* message) {
  if (!condition) {
    std::cerr << "FAIL " << message << '\n';
    std::exit(1);
  }
}
void Pass(const char* name) {
  ++passed;
  std::cout << "PASS " << name << '\n';
}
std::vector<jp::Reply> Wait(jp::Worker& worker) {
  const auto until = std::chrono::steady_clock::now() + std::chrono::seconds(3);
  while (std::chrono::steady_clock::now() < until) {
    auto replies = worker.TakeReplies();
    if (!replies.empty()) return replies;
    Sleep(1);
  }
  Check(false, "worker completion deadline");
  return {};
}
struct Gate {
  std::mutex mutex;
  std::condition_variable cv;
  bool entered = false;
  bool released = false;
  int calls = 0;
  void Enter() {
    std::unique_lock<std::mutex> lock(mutex);
    ++calls;
    entered = true;
    cv.notify_all();
    cv.wait(lock, [&] { return released; });
  }
  void WaitEntered() {
    std::unique_lock<std::mutex> lock(mutex);
    Check(cv.wait_for(lock, std::chrono::seconds(3), [&] { return entered; }),
          "blocked analyzer started");
  }
  void Release() {
    std::lock_guard<std::mutex> lock(mutex);
    released = true;
    cv.notify_all();
  }
};
}

int main(int argc, char* argv[]) {
  Check(jp::ValidChunks({std::wstring(100, L'漢')}), "exact 100 accepted");
  Check(!jp::ValidChunks({std::wstring(101, L'漢')}), "101 rejected");
  Check(jp::ValidChunks(std::vector<std::wstring>(16, L"漢")), "16 accepted");
  Check(!jp::ValidChunks(std::vector<std::wstring>(17, L"漢")), "17 rejected");
  Check(!jp::ValidChunks({}) && !jp::ValidChunks({L""}), "empty rejected");
  Pass("finite native UTF16 input budget");

  Check(jp::ValidChunks({L"漢\xd83d\xde00"}), "surrogate pair accepted");
  Check(!jp::ValidChunks({L"漢\xd83d"}), "lone high rejected");
  Check(!jp::ValidChunks({L"\xde00漢"}), "lone low rejected");
  Check(!jp::ValidChunks({L"\xd83d漢"}), "malformed pair rejected");
  Pass("native bound rejects divided UTF16");

  Check(jp::CompleteWords(L" 今日\r\n漢 ", {{L" ", L""}, {L"今日", L"きょう"},
        {L"\r\n", L""}, {L"漢", L"かん"}, {L" ", L""}}), "space and tail complete");
  Check(!jp::CompleteWords(L"今日漢", {{L"今日", L"きょう"}}), "missing tail rejected");
  Check(!jp::CompleteWords(L"今日", {{L"今", L"いま"}, {L"別", L"べつ"}}), "changed text rejected");
  Check(!jp::CompleteWords(L"今日", {{L"", L"x"}, {L"今日", L"きょう"}}), "empty token rejected");
  Pass("native display words preserve entire input");

  {
    const DWORD owner = GetCurrentThreadId();
    DWORD analysis_thread = owner;
    jp::Worker worker(nullptr, WM_APP, [&](const std::wstring& text) -> jp::Chunk {
      analysis_thread = GetCurrentThreadId();
      return std::vector<jp::Word>{{text, L"よみ"}};
    });
    worker.Submit(1, {L"漢", L"字"});
    const auto replies = Wait(worker);
    Check(replies.size() == 1 && replies[0].id == 1 && replies[0].available,
          "single owned reply");
    Check(replies[0].chunks.size() == 2 && analysis_thread != owner,
          "analysis outside UI thread");
    Check(worker.TakeReplies().empty(), "drained once");
    Pass("bounded worker runs outside UI and drains once");
  }

  {
    Gate gate;
    jp::Worker worker(nullptr, WM_APP, [&](const std::wstring& text) -> jp::Chunk {
      gate.Enter();
      return std::vector<jp::Word>{{text, L"よみ"}};
    });
    worker.Submit(2, {L"旧", L"残り"});
    gate.WaitEntered();
    worker.Cancel();
    worker.Submit(3, {L"新"});
    gate.Release();
    const auto replies = Wait(worker);
    Check(replies.size() == 1 && replies[0].id == 3, "old reply suppressed");
    Check(gate.calls == 2, "cancelled old batch stops next chunk");
    Pass("cancelled active batch cannot publish or analyze tail");
  }

  {
    Gate gate;
    jp::Worker worker(nullptr, WM_APP, [&](const std::wstring& text) -> jp::Chunk {
      gate.Enter();
      return std::vector<jp::Word>{{text, L"よみ"}};
    });
    worker.Submit(4, {L"旧"});
    gate.WaitEntered();
    for (std::uint64_t id = 5; id <= 100; ++id) worker.Submit(id, {L"新"});
    gate.Release();
    const auto replies = Wait(worker);
    Check(replies.size() == 1 && replies[0].id == 100, "only latest retained");
    Check(gate.calls == 2, "replacement queue finite");
    Pass("rapid retarget retains only one pending owner");
  }

  if (argc > 1 && std::string(argv[1]) == "--actual") {
    jp::Worker worker(nullptr, WM_APP);
    worker.Submit(101, {L"今日は良い天気です。"});
    const auto replies = Wait(worker);
    Check(replies.size() == 1 && replies[0].id == 101, "actual Windows owner");
    if (!replies[0].available || replies[0].chunks.empty() || !replies[0].chunks[0]) {
      std::cout << "SKIP actual Windows Japanese analyzer unavailable\n";
    } else {
      const auto& words = *replies[0].chunks[0];
      Check(jp::CompleteWords(L"今日は良い天気です。", words), "actual entire text");
      std::wstring reading;
      for (const auto& word : words) reading += word.reading.empty() ? word.text : word.reading;
      Check(reading.find(L"きょう") != std::wstring::npos, "actual Hiragana reading");
      Pass("actual offline Windows Hiragana analysis");
    }
  }
  std::cout << passed << " passed\n";
}
