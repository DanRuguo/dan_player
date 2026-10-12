#include "../japanese_phonetic_worker.h"
#include <psapi.h>
#include <array>
#include <chrono>
#include <cstdlib>
#include <iostream>
#include <thread>

namespace jp = japanese_phonetic;
namespace {
using Convert = int (*)(const unsigned char*, std::size_t, const unsigned char*, std::size_t, unsigned char*, std::size_t);
std::string dictionary;
void Check(bool value, const char* label) {
  if (!value) { std::cerr << "FAIL " << label << '\n'; std::exit(1); }
}
std::size_t PrivateBytes() {
  PROCESS_MEMORY_COUNTERS_EX memory{};
  Check(GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&memory), sizeof(memory)), "memory query");
  return memory.PrivateUsage;
}
std::string Read(Convert convert, const std::string& input) {
  std::array<unsigned char, 16384> output{};
  const int size = convert(reinterpret_cast<const unsigned char*>(dictionary.data()), dictionary.size(),
      reinterpret_cast<const unsigned char*>(input.data()), input.size(), output.data(), output.size());
  Check(size > 0 && size <= static_cast<int>(output.size()), "actual offline result");
  std::size_t offset = 0;
  auto number = [&]() {
    Check(offset + 4 <= static_cast<std::size_t>(size), "bounded word header");
    unsigned int value = output[offset] | (output[offset + 1] << 8) |
        (output[offset + 2] << 16) | (output[offset + 3] << 24);
    offset += 4;
    return value;
  };
  auto part = [&]() {
    const auto length = number();
    Check(offset + length <= static_cast<std::size_t>(size), "bounded word bytes");
    std::string value(reinterpret_cast<const char*>(output.data() + offset), length);
    offset += length;
    return value;
  };
  const auto count = number();
  std::string source, reading;
  for (unsigned int index = 0; index < count; ++index) { source += part(); reading += part(); }
  Check(source == input && offset == static_cast<std::size_t>(size), "token original bytes match");
  return reading;
}
std::vector<jp::Reply> Wait(jp::Worker& worker) {
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(8);
  while (std::chrono::steady_clock::now() < deadline) {
    auto replies = worker.TakeReplies();
    if (!replies.empty()) return replies;
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  Check(false, "actual worker timeout");
  return {};
}
}
int wmain(int argc, wchar_t** argv) {
  Check(argc == 3, "pass the isolated Rust DLL and dictionary paths");
  const int path_size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, argv[2], -1, nullptr, 0, nullptr, nullptr);
  Check(path_size > 1, "dictionary path UTF8");
  dictionary.resize(static_cast<std::size_t>(path_size));
  Check(WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, argv[2], -1, dictionary.data(), path_size, nullptr, nullptr) > 0, "dictionary conversion");
  dictionary.pop_back();
  const auto before_load = PrivateBytes();
  HMODULE dll = LoadLibraryExW(argv[1], nullptr, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
  Check(dll != nullptr, "actual Rust DLL load");
  auto convert = reinterpret_cast<Convert>(GetProcAddress(dll, "dan_japanese_reading_words"));
  Check(convert != nullptr, "actual export");
  const auto loaded = PrivateBytes();
  const auto start = std::chrono::steady_clock::now();
  Check(Read(convert, "今日はいい天気です。") == "きょうはいいてんきです。", "official example reading");
  const auto cold_us = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - start).count();
  const auto decoded = PrivateBytes();
  const auto warm_start = std::chrono::steady_clock::now();
  for (int index = 0; index < 1000; ++index) Check(Read(convert, "明日また会えるかな") == "あしたまたあえるかな", "warm exact reading");
  const auto warm_us = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - warm_start).count();
  std::cout << "memory.before=" << before_load << " loaded=" << loaded << " dictionary=" << decoded
            << " cold_us=" << cold_us << " warm_1000_us=" << warm_us << '\n';
  Check(Read(convert, "大人が一昨日東京へ行った。") == "おとながおとといとうきょうへいった。", "compound and inflection reading");
  std::cout << "PASS actual lazy cold and warm Japanese readings\n";

  Check(Read(convert, "\t日本語 ＡＢＣ ① 👩‍👩‍👧‍👦 𱍐 尾\n") == "\tにほんご ＡＢＣ ① 👩‍👩‍👧‍👦 𱍐 お\n", "mixed text complete");
  Check(Read(convert, "カタカナと日本語、ひらがな") == "カタカナとにほんご、ひらがな", "non Han kana retained");
  std::array<unsigned char, 32> guard; guard.fill(0xab);
  Check(convert(reinterpret_cast<const unsigned char*>(dictionary.data()), dictionary.size(),
      reinterpret_cast<const unsigned char*>("日本語"), 9, guard.data(), 1) == -3, "small caller buffer");
  for (auto byte : guard) Check(byte == 0xab, "small buffer untouched");
  std::cout << "PASS actual mixed text unknown glyphs and caller buffer ownership\n";

  {
    jp::Worker worker(nullptr, WM_APP);
    std::vector<std::wstring> texts;
    for (int index = 0; index < 16; ++index) texts.push_back(index % 2 ? L"明日また会えるかな" : L"今日はいい天気です。😀最後");
    worker.Submit(101, texts, dictionary);
    const auto replies = Wait(worker);
    Check(replies.size() == 1 && replies[0].id == 101 && replies[0].available, "owned actual worker reply");
    Check(replies[0].chunks.size() == texts.size(), "entire bounded batch");
    for (std::size_t index = 0; index < texts.size(); ++index) {
      const auto& chunk = replies[0].chunks[index];
      Check(chunk.has_value() && jp::CompleteWords(texts[index], *chunk), "full source alignment");
      std::wstring reading;
      for (const auto& word : *chunk) reading += word.reading.empty() ? word.text : word.reading;
      Check(reading == (index % 2 ? L"あしたまたあえるかな" : L"きょうはいいてんきです。😀さいご"), "actual engine through worker");
    }
    Check(worker.TakeReplies().empty(), "worker drain once");
  }
  std::cout << "PASS actual worker full batch nonempty source aligned kana\n";
  {
    jp::Worker worker(nullptr, WM_APP);
    worker.Submit(102, {std::wstring(101, L'漢')});
    const auto replies = Wait(worker);
    Check(replies.size() == 1 && !replies[0].available && replies[0].chunks.empty(), "invalid actual worker input rejected");
  }
  std::cout << "PASS actual worker invalid UTF16 budget rejected\n";
  Check(convert(nullptr, 0, reinterpret_cast<const unsigned char*>("日本語"), 9, guard.data(), guard.size()) == -4, "missing dictionary status");
  std::cout << "PASS missing optional dictionary is distinguished\n5 passed\n";
  FreeLibrary(dll);
}
