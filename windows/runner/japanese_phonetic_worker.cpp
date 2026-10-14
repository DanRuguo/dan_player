#include "japanese_phonetic_worker.h"

#include <roapi.h>
#include <windows.globalization.h>
#include <wrl.h>
#include <wrl/wrappers/corewrappers.h>

#include <utility>
#include <array>

#pragma comment(lib, "runtimeobject.lib")

namespace japanese_phonetic {
namespace {
using Microsoft::WRL::ComPtr;
using Microsoft::WRL::Wrappers::HString;
using Microsoft::WRL::Wrappers::HStringReference;
using Analyzer = ABI::Windows::Globalization::IJapanesePhoneticAnalyzerStatics;

// Reuse the player's already loaded Rust DLL. Hold a module reference until the
// worker stops, so a late result never calls into a retired library.
class OfflineReader {
 public:
  OfflineReader() {
    if (GetModuleHandleExW(0, L"rust_lib_dan_player.dll", &module_)) {
      convert_ = reinterpret_cast<Convert>(GetProcAddress(module_, "dan_japanese_reading_words"));
    }
  }
  ~OfflineReader() { if (module_) FreeLibrary(module_); }
  bool available() const { return convert_ != nullptr; }
  Chunk Read(const std::wstring& text, const std::string& path, bool* missing) const {
    if (!convert_) return std::nullopt;
    const int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text.data(),
        static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
    if (size <= 0 || size > 400) return std::nullopt;
    std::string input(static_cast<std::size_t>(size), '\0');
    if (!WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text.data(),
        static_cast<int>(text.size()), input.data(), size, nullptr, nullptr)) return std::nullopt;
    std::array<unsigned char, 16384> output{};
    const int length = convert_(reinterpret_cast<const unsigned char*>(path.data()), path.size(),
        reinterpret_cast<const unsigned char*>(input.data()), input.size(), output.data(), output.size());
    if (length == -4) *missing = true;
    if (length <= 0 || length > static_cast<int>(output.size())) return std::nullopt;
    std::size_t offset = 0;
    auto number = [&](unsigned int* value) {
      if (offset + 4 > static_cast<std::size_t>(length)) return false;
      *value = output[offset] | (output[offset + 1] << 8) |
          (output[offset + 2] << 16) | (output[offset + 3] << 24);
      offset += 4;
      return true;
    };
    auto string = [&](std::wstring* value) {
      unsigned int bytes = 0;
      if (!number(&bytes) || bytes == 0 || bytes > 8000 ||
          offset + bytes > static_cast<std::size_t>(length)) return false;
      const auto source = reinterpret_cast<const char*>(output.data() + offset);
      const int units = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, source,
          static_cast<int>(bytes), nullptr, 0);
      if (units <= 0 || units > 2000) return false;
      value->resize(static_cast<std::size_t>(units));
      if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, source,
          static_cast<int>(bytes), value->data(), units)) return false;
      offset += bytes;
      return true;
    };
    unsigned int count = 0;
    if (!number(&count) || count == 0 || count > 100) return std::nullopt;
    std::vector<Word> words;
    for (unsigned int index = 0; index < count; ++index) {
      Word word;
      if (!string(&word.text) || !string(&word.reading)) return std::nullopt;
      words.push_back(std::move(word));
    }
    if (offset != static_cast<std::size_t>(length) || !CompleteWords(text, words)) return std::nullopt;
    return words;
  }
 private:
  using Convert = int (*)(const unsigned char*, std::size_t, const unsigned char*, std::size_t,
                         unsigned char*, std::size_t);
  HMODULE module_ = nullptr;
  Convert convert_ = nullptr;
};

std::wstring ReadString(const HString& value) {
  UINT32 length = 0;
  const wchar_t* text = value.GetRawBuffer(&length);
  return text ? std::wstring(text, length) : std::wstring();
}

bool HasHan(const std::wstring& text) {
  for (std::size_t index = 0; index < text.size(); ++index) {
    unsigned int scalar = text[index];
    if (scalar >= 0xd800 && scalar <= 0xdbff && index + 1 < text.size()) {
      scalar = 0x10000 + ((scalar - 0xd800) << 10) + (text[++index] - 0xdc00);
    }
    if (scalar == 0x3005 || scalar == 0x303b ||
        (scalar >= 0x3400 && scalar <= 0x9fff) ||
        (scalar >= 0xf900 && scalar <= 0xfaff) ||
        (scalar >= 0x20000 && scalar <= 0x323af)) return true;
  }
  return false;
}

Chunk Analyze(Analyzer* analyzer, const std::wstring& text) {
  ComPtr<__FIVectorView_1_Windows__CGlobalization__CJapanesePhoneme> phonemes;
  if (FAILED(analyzer->GetWordsWithMonoRubyOption(
          HStringReference(text.c_str(), static_cast<unsigned int>(text.size())).Get(),
          true, &phonemes)) || !phonemes) return std::nullopt;
  UINT32 size = 0;
  if (FAILED(phonemes->get_Size(&size)) || size > 100) return std::nullopt;
  std::vector<Word> words;
  words.reserve(size);
  std::size_t reading_units = 0;
  for (UINT32 index = 0; index < size; ++index) {
    ComPtr<ABI::Windows::Globalization::IJapanesePhoneme> phoneme;
    HString display, reading;
    if (FAILED(phonemes->GetAt(index, &phoneme)) || !phoneme ||
        FAILED(phoneme->get_DisplayText(display.GetAddressOf())) ||
        FAILED(phoneme->get_YomiText(reading.GetAddressOf()))) return std::nullopt;
    auto original = ReadString(display);
    auto yomi = ReadString(reading);
    if (original.size() > 100 || yomi.size() > 2000) return std::nullopt;
    const bool han = HasHan(original);
    if (!han) yomi = original;
    if (han) for (auto& unit : yomi) {
      if (unit >= 0x30a1 && unit <= 0x30f6) unit -= 0x60;
    }
    reading_units += yomi.size();
    if (reading_units > 2000) return std::nullopt;
    words.push_back({std::move(original), std::move(yomi)});
  }
  if (!CompleteWords(text, words)) return std::nullopt;
  return words;
}
}  // namespace

bool ValidChunks(const std::vector<std::wstring>& chunks) {
  if (chunks.empty() || chunks.size() > 16) return false;
  for (const auto& text : chunks) {
    if (text.empty() || text.size() > 100) return false;
    for (std::size_t index = 0; index < text.size(); ++index) {
      const auto unit = static_cast<unsigned int>(text[index]);
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++index == text.size()) return false;
        const auto next = static_cast<unsigned int>(text[index]);
        if (next < 0xdc00 || next > 0xdfff) return false;
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        return false;
      }
    }
  }
  return true;
}

bool CompleteWords(const std::wstring& input, const std::vector<Word>& words) {
  std::size_t offset = 0;
  for (const auto& word : words) {
    if (word.text.empty() || word.text.size() > input.size() - offset ||
        input.compare(offset, word.text.size(), word.text) != 0) return false;
    offset += word.text.size();
  }
  return offset == input.size();
}

Worker::Worker(HWND window, UINT message, AnalyzeChunk analyze)
    : window_(window), message_(message), analyze_(std::move(analyze)) {}

Worker::~Worker() {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    stopped_ = true;
    window_ = nullptr;
    if (pending_) pending_->cancelled = true;
    if (active_) active_->cancelled = true;
    pending_.reset();
  }
  wake_.notify_one();
  if (thread_.joinable()) thread_.join();
}

void Worker::Submit(std::uint64_t id, std::vector<std::wstring> chunks,
                    std::string dictionary_path) {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (stopped_) return;
    if (active_) active_->cancelled = true;
    if (pending_) pending_->cancelled = true;
    auto next = std::make_shared<Job>();
    next->id = id;
    next->chunks = std::move(chunks);
    next->dictionary_path = std::move(dictionary_path);
    pending_ = std::move(next);
    completed_.clear();
    if (!thread_.joinable()) thread_ = std::thread(&Worker::Run, this);
  }
  wake_.notify_one();
}

void Worker::Cancel() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (active_) active_->cancelled = true;
  if (pending_) pending_->cancelled = true;
  pending_.reset();
  completed_.clear();
}

std::vector<Reply> Worker::TakeReplies() {
  std::lock_guard<std::mutex> lock(mutex_);
  std::vector<Reply> replies;
  replies.swap(completed_);
  return replies;
}

void Worker::Run() {
  const HRESULT initialized = RoInitialize(RO_INIT_SINGLETHREADED);
  {
    ComPtr<Analyzer> analyzer;
    OfflineReader offline;
    for (;;) {
      std::shared_ptr<Job> job;
      {
        std::unique_lock<std::mutex> lock(mutex_);
        wake_.wait(lock, [&] { return stopped_ || pending_ != nullptr; });
        if (stopped_) break;
        job = std::move(pending_);
        active_ = job;
      }
      Reply reply;
      reply.id = job->id;
      if (SUCCEEDED(initialized) && !analyze_ && !analyzer && !job->cancelled) {
        RoGetActivationFactory(
            HStringReference(RuntimeClass_Windows_Globalization_JapanesePhoneticAnalyzer).Get(),
            IID_PPV_ARGS(&analyzer));
      }
      reply.available = (analyze_ || analyzer || offline.available()) && ValidChunks(job->chunks);
      if (reply.available) {
        for (const auto& text : job->chunks) {
          if (job->cancelled) break;
          auto chunk = analyze_ ? analyze_(text)
                               : analyzer ? Analyze(analyzer.Get(), text) : Chunk{};
          if (!analyze_ && !chunk && !job->cancelled) {
            chunk = offline.Read(text, job->dictionary_path, &reply.dictionary_missing);
          }
          reply.chunks.push_back(std::move(chunk));
        }
      }
      {
        std::lock_guard<std::mutex> lock(mutex_);
        active_.reset();
        // Cancellation resolves on the UI thread immediately. Suppress late
        // data and HWND messages, including during main-window teardown.
        if (!stopped_ && !job->cancelled) {
          completed_.push_back(std::move(reply));
          if (window_) PostMessageW(window_, message_, 0, 0);
        }
      }
    }
  }
  if (SUCCEEDED(initialized)) RoUninitialize();
}
}  // namespace japanese_phonetic
