#include "touch_sound_controller.h"

#include <Windows.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <mmreg.h>
#include <xaudio2.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <memory>
#include <string>

namespace {

constexpr char kChannelName[] = "dan_player/touch_sound";
constexpr UINT32 kSampleRate = 48000;
constexpr size_t kFrameCount = 960;        // 20.0 ms total buffer
constexpr size_t kActiveFrames = 576;      // 12.0 ms active resonator window
constexpr size_t kAttackFrames = 22;       // 0.45 ms raised-cosine soft attack
constexpr size_t kVoicePoolCount = 4;      // Polyphonic overlap for rapid taps
constexpr double kPi = 3.14159265358979323846;

using XAudio2CreateProc = HRESULT(STDAPICALLTYPE*)(IXAudio2**, UINT32,
                                                   XAUDIO2_PROCESSOR);

// Synthesizes the modern Android (Material You / Android 14-15) default
// Effect_Tick waveform: a subtle, warm, short capacitive micro-tap with zero
// DC offset and exact zero endpoints so audio drivers never pop on start/stop.
std::array<float, kFrameCount> BuildAndroidEffectTickSamples() {
  std::array<double, kFrameCount> work{};
  double phase1 = 0.0;
  double phase2 = 0.0;
  double phase3 = 0.0;
  const double two_pi = 2.0 * kPi;

  for (size_t i = 0; i < kActiveFrames; ++i) {
    const double t = static_cast<double>(i) / static_cast<double>(kSampleRate);
    const double attack =
        i < kAttackFrames
            ? (0.5 - 0.5 * std::cos(kPi * static_cast<double>(i) /
                                    static_cast<double>(kAttackFrames)))
            : 1.0;
    const double tail =
        t > 0.009 ? (0.5 + 0.5 * std::cos(kPi * (t - 0.009) / 0.003)) : 1.0;

    // Mode 1: warm tactile body (315 Hz -> 165 Hz pitch drop).
    const double f1 = 165.0 + 150.0 * std::exp(-t / 0.0026);
    phase1 += two_pi * f1 / static_cast<double>(kSampleRate);
    const double m1 = std::sin(phase1) * std::exp(-t / 0.0021) * 0.44;

    // Mode 2: matte ceramic/wood tap core (1580 Hz -> 1160 Hz).
    const double f2 = 1160.0 + 420.0 * std::exp(-t / 0.0015);
    phase2 += two_pi * f2 / static_cast<double>(kSampleRate);
    const double m2 = std::sin(phase2) * std::exp(-t / 0.0011) * 0.38;

    // Mode 3: crisp fingertip transient (2920 Hz, 0.48 ms decay).
    phase3 += two_pi * 2920.0 / static_cast<double>(kSampleRate);
    const double m3 = std::sin(phase3) * std::exp(-t / 0.00048) * 0.22;

    work[i] = (m1 + m2 + m3) * attack * tail;
  }

  // Remove residual DC bias inside the active window while keeping endpoints 0.
  double weighted_sum = 0.0;
  double weight_total = 0.0;
  for (size_t i = 0; i < kActiveFrames; ++i) {
    const double t = static_cast<double>(i) / static_cast<double>(kSampleRate);
    const double w =
        (i < kAttackFrames
             ? (0.5 - 0.5 * std::cos(kPi * static_cast<double>(i) /
                                     static_cast<double>(kAttackFrames)))
             : 1.0) *
        (t > 0.009 ? (0.5 + 0.5 * std::cos(kPi * (t - 0.009) / 0.003)) : 1.0);
    weighted_sum += work[i];
    weight_total += w;
  }
  if (weight_total > 0.0) {
    const double dc_adjust = weighted_sum / weight_total;
    for (size_t i = 0; i < kActiveFrames; ++i) {
      const double t =
          static_cast<double>(i) / static_cast<double>(kSampleRate);
      const double w =
          (i < kAttackFrames
               ? (0.5 - 0.5 * std::cos(kPi * static_cast<double>(i) /
                                       static_cast<double>(kAttackFrames)))
               : 1.0) *
          (t > 0.009 ? (0.5 + 0.5 * std::cos(kPi * (t - 0.009) / 0.003)) : 1.0);
      work[i] -= dc_adjust * w;
    }
  }

  double peak = 0.0;
  for (size_t i = 0; i < kActiveFrames; ++i) {
    peak = std::max(peak, std::abs(work[i]));
  }
  const double scale = peak > 1e-9 ? (0.22 / peak) : 0.0;

  std::array<float, kFrameCount> out{};
  for (size_t i = 0; i < kActiveFrames; ++i) {
    out[i] = static_cast<float>(work[i] * scale);
  }
  return out;
}

class EngineErrorObserver final : public IXAudio2EngineCallback {
 public:
  explicit EngineErrorObserver(std::atomic<bool>* device_lost)
      : device_lost_(device_lost) {}

  void STDMETHODCALLTYPE OnProcessingPassStart() override {}
  void STDMETHODCALLTYPE OnProcessingPassEnd() override {}
  void STDMETHODCALLTYPE OnCriticalError(HRESULT /*error*/) override {
    if (device_lost_) {
      device_lost_->store(true, std::memory_order_release);
    }
  }

 private:
  std::atomic<bool>* device_lost_;
};

}  // namespace

struct TouchSoundController::Impl {
  HMODULE xaudio_module = nullptr;
  XAudio2CreateProc create_proc = nullptr;
  bool load_attempted = false;

  IXAudio2* engine = nullptr;
  IXAudio2MasteringVoice* mastering_voice = nullptr;
  std::array<IXAudio2SourceVoice*, kVoicePoolCount> voices{};
  size_t next_voice = 0;
  std::atomic<bool> device_lost{false};
  EngineErrorObserver observer{&device_lost};

  const std::array<float, kFrameCount> samples = BuildAndroidEffectTickSamples();
  XAUDIO2_BUFFER buffer{};
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel;

  explicit Impl(flutter::FlutterEngine* flutter_engine) {
    buffer.AudioBytes = static_cast<UINT32>(samples.size() * sizeof(float));
    buffer.pAudioData = reinterpret_cast<const BYTE*>(samples.data());
    buffer.Flags = XAUDIO2_END_OF_STREAM;

    channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        flutter_engine->messenger(), kChannelName,
        &flutter::StandardMethodCodec::GetInstance());
    channel->SetMethodCallHandler([this](const auto& call, auto result) {
      if (call.method_name() != "playTick") {
        result->NotImplemented();
        return;
      }
      double gain = 1.0;
      if (call.arguments()) {
        if (const auto* map =
                std::get_if<flutter::EncodableMap>(call.arguments())) {
          const auto it = map->find(flutter::EncodableValue("gain"));
          if (it != map->end()) {
            if (const auto* d = std::get_if<double>(&it->second)) {
              gain = *d;
            } else if (const auto* i = std::get_if<int32_t>(&it->second)) {
              gain = static_cast<double>(*i);
            }
          }
        }
      }
      if (!std::isfinite(gain)) gain = 1.0;
      gain = std::clamp(gain, 0.0, 1.5);
      result->Success(flutter::EncodableValue(PlayTick(static_cast<float>(gain))));
    });
  }

  ~Impl() {
    if (channel) {
      channel->SetMethodCallHandler(nullptr);
      channel.reset();
    }
    ReleaseAudioGraph();
    if (xaudio_module) {
      FreeLibrary(xaudio_module);
      xaudio_module = nullptr;
      create_proc = nullptr;
    }
  }

  void ReleaseAudioGraph() {
    for (auto*& voice : voices) {
      if (voice) {
        voice->Stop(0);
        voice->FlushSourceBuffers();
        voice->DestroyVoice();
        voice = nullptr;
      }
    }
    if (mastering_voice) {
      mastering_voice->DestroyVoice();
      mastering_voice = nullptr;
    }
    if (engine) {
      engine->UnregisterForCallbacks(&observer);
      engine->StopEngine();
      engine->Release();
      engine = nullptr;
    }
    device_lost.store(false, std::memory_order_release);
  }

  bool EnsureAudioGraph() {
    if (device_lost.load(std::memory_order_acquire)) {
      ReleaseAudioGraph();
    }
    if (engine && mastering_voice) return true;

    if (!load_attempted) {
      load_attempted = true;
      xaudio_module = LoadLibraryExW(L"xaudio2_9.dll", nullptr,
                                     LOAD_LIBRARY_SEARCH_SYSTEM32);
      if (xaudio_module) {
        create_proc = reinterpret_cast<XAudio2CreateProc>(
            GetProcAddress(xaudio_module, "XAudio2Create"));
      }
    }
    if (!create_proc) return false;

    if (FAILED(create_proc(&engine, 0, XAUDIO2_DEFAULT_PROCESSOR)) || !engine) {
      engine = nullptr;
      return false;
    }
    engine->RegisterForCallbacks(&observer);

    if (FAILED(engine->CreateMasteringVoice(
            &mastering_voice, 2, kSampleRate, 0, nullptr, nullptr,
            AudioCategory_SoundEffects)) ||
        !mastering_voice) {
      ReleaseAudioGraph();
      return false;
    }

    WAVEFORMATEX format{};
    format.wFormatTag = WAVE_FORMAT_IEEE_FLOAT;
    format.nChannels = 1;
    format.nSamplesPerSec = kSampleRate;
    format.wBitsPerSample = 32;
    format.nBlockAlign = 4;
    format.nAvgBytesPerSec = kSampleRate * 4;

    for (size_t i = 0; i < kVoicePoolCount; ++i) {
      if (FAILED(engine->CreateSourceVoice(&voices[i], &format, 0,
                                           XAUDIO2_DEFAULT_FREQ_RATIO)) ||
          !voices[i]) {
        ReleaseAudioGraph();
        return false;
      }
    }
    return true;
  }

  bool PlayTick(float gain) {
    if (gain <= 0.0f) return false;
    if (!EnsureAudioGraph()) return false;

    IXAudio2SourceVoice* voice = voices[next_voice % kVoicePoolCount];
    next_voice = (next_voice + 1) % kVoicePoolCount;
    if (!voice) return false;

    voice->Stop(0);
    voice->FlushSourceBuffers();
    voice->SetVolume(gain);
    if (FAILED(voice->SubmitSourceBuffer(&buffer))) return false;
    if (FAILED(voice->Start(0))) return false;
    return true;
  }
};

TouchSoundController::TouchSoundController(flutter::FlutterEngine* engine)
    : impl_(std::make_unique<Impl>(engine)) {}

TouchSoundController::~TouchSoundController() = default;
