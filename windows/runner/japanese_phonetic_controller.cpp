#include "japanese_phonetic_controller.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <string>
#include <utility>

#include "japanese_phonetic_worker.h"

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using List = flutter::EncodableList;
using Result = flutter::MethodResult<Value>;

UINT CompletionMessage() {
  static const UINT message = RegisterWindowMessageW(L"DanPlayer.JapanesePhonetic.Completed");
  return message;
}

std::wstring FromUtf8(const std::string& text) {
  if (text.empty() || text.size() > 400) return {};
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
      text.data(), static_cast<int>(text.size()), nullptr, 0);
  if (length <= 0 || length > 100) return {};
  std::wstring result(length, L'\0');
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
      static_cast<int>(text.size()), result.data(), length)) return {};
  return result;
}

std::string ToUtf8(const std::wstring& text) {
  if (text.empty()) return {};
  const int length = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
      text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
  if (length <= 0) return {};
  std::string result(length, '\0');
  if (!WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text.data(),
      static_cast<int>(text.size()), result.data(), length, nullptr, nullptr)) return {};
  return result;
}

Value Unavailable() { return Value(Map{{Value("available"), Value(false)}}); }
}  // namespace

class JapanesePhoneticController::Impl {
 public:
  Impl(HWND window, flutter::FlutterEngine* engine)
      : worker_(window, CompletionMessage()),
        channel_(std::make_unique<flutter::MethodChannel<Value>>(
            engine->messenger(), "dan_player/japanese_phonetic",
            &flutter::StandardMethodCodec::GetInstance())) {
    channel_->SetMethodCallHandler([this](const auto& call, auto result) {
      Drain();
      if (call.method_name() == "cancel") {
        Cancel();
        result->Success();
        return;
      }
      if (call.method_name() != "analyze") {
        result->NotImplemented();
        return;
      }
      const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
      const auto entry = args ? args->find(Value("chunks")) : Map::const_iterator();
      const auto* chunks = args && entry != args->end() ? std::get_if<List>(&entry->second) : nullptr;
      std::vector<std::wstring> texts;
      if (chunks && chunks->size() <= 16) {
        for (const auto& chunk : *chunks) {
          const auto* text = std::get_if<std::string>(&chunk);
          if (!text) break;
          texts.push_back(FromUtf8(*text));
        }
      }
      if (!chunks || texts.size() != chunks->size() ||
          !japanese_phonetic::ValidChunks(texts) || CompletionMessage() == 0) {
        result->Success(Unavailable());
        return;
      }
      Cancel();
      result_ = std::move(result);
      const auto path_entry = args->find(Value("dictionaryPath"));
      const auto* path = path_entry != args->end() ? std::get_if<std::string>(&path_entry->second) : nullptr;
      worker_.Submit(++id_, std::move(texts), path && path->size() <= 32768 ? *path : std::string());
    });
  }

  ~Impl() {
    channel_->SetMethodCallHandler(nullptr);
    Cancel();
  }

  void Cancel() {
    worker_.Cancel();
    if (result_) {
      auto previous = std::move(result_);
      previous->Success(Unavailable());
    }
  }

  bool Handle(UINT message) {
    if (message != CompletionMessage()) return false;
    Drain();
    return true;
  }

  void Drain() {
    for (auto& reply : worker_.TakeReplies()) {
      if (reply.id != id_ || !result_) continue;
      auto result = std::move(result_);
      if (!reply.available) {
        result->Success(Unavailable());
        continue;
      }
      List chunks;
      for (const auto& chunk : reply.chunks) {
        if (!chunk) {
          chunks.emplace_back();
          continue;
        }
        List words;
        for (const auto& word : *chunk) {
          words.emplace_back(Map{{Value("text"), Value(ToUtf8(word.text))},
                                 {Value("reading"), Value(ToUtf8(word.reading))}});
        }
        chunks.emplace_back(std::move(words));
      }
      result->Success(Value(Map{{Value("available"), Value(true)},
                                {Value("dictionaryMissing"), Value(reply.dictionary_missing)},
                                {Value("chunks"), Value(std::move(chunks))}}));
    }
  }

 private:
  japanese_phonetic::Worker worker_;
  std::unique_ptr<flutter::MethodChannel<Value>> channel_;
  std::unique_ptr<Result> result_;
  std::uint64_t id_ = 0;
};

JapanesePhoneticController::JapanesePhoneticController(HWND window, flutter::FlutterEngine* engine)
    : impl_(std::make_unique<Impl>(window, engine)) {}
JapanesePhoneticController::~JapanesePhoneticController() = default;
bool JapanesePhoneticController::HandleMessage(UINT message) { return impl_->Handle(message); }
