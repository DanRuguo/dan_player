#include "windows_shell.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <propkey.h>
#include <propvarutil.h>
#include <shellapi.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <array>
#include <algorithm>
#include <cstring>
#include <cstdint>
#include <cwctype>
#include <filesystem>
#include <utility>

#include "resource.h"
#include "utils.h"
#include "windows_shell_policy.h"

namespace {
using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;
namespace fs = std::filesystem;
using windows_shell::SamePath;
constexpr ULONG_PTR kActionMessage = 0x44504a54;
constexpr wchar_t kRegistryKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\DanRuguo.DanPlayer_is1";
std::wstring instance_property;
std::wstring application_id = L"DanRuguo.DanPlayer";
std::string initial_action;
bool isolated_data = false;

std::wstring ModulePath() {
  std::wstring result(32768, L'\0');
  const DWORD size = GetModuleFileNameW(nullptr, result.data(),
                                        static_cast<DWORD>(result.size()));
  if (!size || size >= result.size()) return {};
  result.resize(size);
  return result;
}

std::wstring Environment(const wchar_t* name) {
  const auto size = GetEnvironmentVariableW(name, nullptr, 0);
  if (!size || size > 32768) return {};
  std::wstring value(size, L'\0');
  const auto count = GetEnvironmentVariableW(name, value.data(), size);
  if (!count || count >= size) return {};
  value.resize(count);
  return value;
}

std::wstring IdentityHash(std::wstring input) {
  std::uint64_t hash = 14695981039346656037ull;
  for (const auto character : input) {
    hash ^= static_cast<std::uint64_t>(towlower(character));
    hash *= 1099511628211ull;
  }
  wchar_t text[17]{};
  swprintf_s(text, L"%016llx", static_cast<unsigned long long>(hash));
  return text;
}

struct ExistingWindow { HWND window = nullptr; };
BOOL CALLBACK FindExisting(HWND window, LPARAM parameter) {
  if (GetPropW(window, instance_property.c_str())) {
    reinterpret_cast<ExistingWindow*>(parameter)->window = window;
    return FALSE;
  }
  return TRUE;
}

std::wstring ReadRegistryString(HKEY key, const wchar_t* name) {
  DWORD bytes = 0;
  if (RegGetValueW(key, nullptr, name, RRF_RT_REG_SZ, nullptr, nullptr, &bytes) !=
      ERROR_SUCCESS || bytes < sizeof(wchar_t) || bytes > 65536) return {};
  std::vector<wchar_t> text(bytes / sizeof(wchar_t));
  if (RegGetValueW(key, nullptr, name, RRF_RT_REG_SZ, nullptr, text.data(), &bytes) !=
      ERROR_SUCCESS || text.back() != L'\0') return {};
  return text.data();
}

// Resolve paths through handles and refuse reparse points. Uninstall must never
// follow a registry entry belonging to a different copy or a moved directory.
std::wstring FinalPath(HANDLE handle) {
  std::wstring path(32768, L'\0');
  DWORD count = GetFinalPathNameByHandleW(handle, path.data(),
      static_cast<DWORD>(path.size()), FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
  if (!count || count >= path.size()) return {};
  path.resize(count);
  if (path.compare(0, 4, L"\\\\?\\") == 0) path.erase(0, 4);
  return path;
}

struct LockedInstallation {
  std::vector<HANDLE> handles;
  fs::path directory;
  fs::path uninstaller;
  bool registered = false;
  ~LockedInstallation() { for (HANDLE handle : handles) CloseHandle(handle); }

  bool Lock(const fs::path& file, bool is_directory) {
    HANDLE handle = CreateFileW(file.c_str(), GENERIC_READ,
        is_directory ? FILE_SHARE_READ | FILE_SHARE_WRITE : FILE_SHARE_READ,
        nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT |
        (is_directory ? FILE_FLAG_BACKUP_SEMANTICS : 0), nullptr);
    if (handle == INVALID_HANDLE_VALUE) return false;
    handles.push_back(handle);
    BY_HANDLE_FILE_INFORMATION info{};
    return GetFileInformationByHandle(handle, &info) &&
        !(info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) &&
        ((info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) == is_directory &&
        (is_directory || (info.nNumberOfLinks == 1 &&
                          (info.nFileSizeLow || info.nFileSizeHigh))) &&
        SamePath(FinalPath(handle), file);
  }

  bool Inspect() {
    directory = fs::path(ModulePath()).parent_path();
    if (isolated_data || directory.empty()) return false;
    HKEY key = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, kRegistryKey, 0,
                      KEY_QUERY_VALUE | KEY_WOW64_64KEY, &key) != ERROR_SUCCESS) {
      return false;
    }
    const auto location = ReadRegistryString(key, L"InstallLocation");
    const auto command = ReadRegistryString(key, L"UninstallString");
    RegCloseKey(key);
    if (location.empty() || !SamePath(location, directory)) return false;
    registered = true;
    int count = 0;
    auto argv = CommandLineToArgvW(command.c_str(), &count);
    if (!argv) return false;
    const auto candidate = count == 1 ? fs::path(argv[0]) : fs::path();
    LocalFree(argv);
    if (!candidate.is_absolute() ||
        !SamePath(candidate.parent_path(), directory / L".dan-player-install") ||
        !windows_shell::IsUninstallerName(candidate.filename().wstring())) return false;
    fs::path parent = directory.root_path();
    for (const auto& component : directory.relative_path()) {
      parent /= component;
      if (!Lock(parent, true)) return false;
    }
    if (!Lock(candidate.parent_path(), true) || !Lock(candidate, false) ||
        !Lock(fs::path(candidate).replace_extension(L".dat"), false) ||
        !Lock(candidate.parent_path() / L"payload.manifest", false)) return false;
    uninstaller = candidate;
    return true;
  }
};

HRESULT RegisterTasks(const EncodableMap& labels) {
  // Explorer does not inherit DAN_PLAYER_DATA_DIR when invoking a task. Never
  // publish QA commands that would silently reopen the real user's profile.
  if (isolated_data) return S_FALSE;
  ComPtr<ICustomDestinationList> destinations;
  HRESULT result = CoCreateInstance(CLSID_DestinationList, nullptr,
      CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&destinations));
  if (FAILED(result)) return result;
  if (FAILED(result = destinations->SetAppID(application_id.c_str()))) return result;
  UINT slots = 0;
  ComPtr<IObjectArray> removed;
  if (FAILED(result = destinations->BeginList(&slots, IID_PPV_ARGS(&removed)))) return result;
  ComPtr<IObjectCollection> tasks;
  result = CoCreateInstance(CLSID_EnumerableObjectCollection, nullptr,
      CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&tasks));
  const std::array<std::pair<const char*, int>, 5> actions{{
      {"showMain", IDI_TASK_WINDOW}, {"toggle", IDI_TASK_PLAY},
      {"previous", IDI_TASK_PREVIOUS}, {"next", IDI_TASK_NEXT},
      {"showMini", IDI_TASK_MINI}}};
  const auto executable = ModulePath();
  for (const auto& task : actions) {
    if (FAILED(result)) break;
    const auto entry = labels.find(EncodableValue(task.first));
    const auto* value = entry != labels.end()
        ? std::get_if<std::string>(&entry->second) : nullptr;
    if (!value || value->empty() || value->size() > 384 || value->find('\0') != std::string::npos) {
      result = E_INVALIDARG;
      break;
    }
    const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
        value->data(), static_cast<int>(value->size()), nullptr, 0);
    if (length <= 0) { result = E_INVALIDARG; break; }
    std::wstring title(length, L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value->data(),
        static_cast<int>(value->size()), title.data(), length);
    ComPtr<IShellLinkW> link;
    result = CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                              IID_PPV_ARGS(&link));
    if (FAILED(result)) break;
    std::wstring action(task.first, task.first + strlen(task.first));
    result = link->SetPath(executable.c_str());
    if (SUCCEEDED(result)) result = link->SetArguments((L"--shell-action=" + action).c_str());
    if (SUCCEEDED(result)) result = link->SetWorkingDirectory(fs::path(executable).parent_path().c_str());
    if (SUCCEEDED(result)) result = link->SetIconLocation(executable.c_str(), -task.second);
    ComPtr<IPropertyStore> properties;
    if (SUCCEEDED(result)) result = link.As(&properties);
    PROPVARIANT name{};
    if (SUCCEEDED(result)) result = InitPropVariantFromString(title.c_str(), &name);
    if (SUCCEEDED(result)) result = properties->SetValue(PKEY_Title, name);
    PropVariantClear(&name);
    if (SUCCEEDED(result)) result = properties->Commit();
    if (SUCCEEDED(result)) result = tasks->AddObject(link.Get());
  }
  if (SUCCEEDED(result)) result = destinations->AddUserTasks(tasks.Get());
  if (SUCCEEDED(result)) result = destinations->CommitList();
  if (FAILED(result)) destinations->AbortList();
  return result;
}
}  // namespace

PlayerInstanceLease::PlayerInstanceLease(const std::vector<std::string>& arguments) {
  const auto executable = ModulePath();
  const auto data = Environment(L"DAN_PLAYER_DATA_DIR");
  isolated_data = !data.empty();
  const auto identity = IdentityHash(executable + L"|" + data);
  instance_property = L"DanPlayer.Instance." + identity;
  if (isolated_data) application_id += L".QA." + identity;
  SetCurrentProcessExplicitAppUserModelID(application_id.c_str());
  initial_action = windows_shell::StartupAction(arguments);
  const auto name = L"Local\\" + instance_property;
  mutex_ = CreateMutexW(nullptr, FALSE, name.c_str());
  if (!mutex_) return;
  if (GetLastError() != ERROR_ALREADY_EXISTS) {
    primary_ = true;
    const bool explicit_action = std::any_of(arguments.begin(), arguments.end(),
        [](const std::string& value) { return value.rfind("--shell-action=", 0) == 0; });
    if (!explicit_action) initial_action.clear();
    return;
  }
  // Only the short-lived forwarding process waits; the player's platform and
  // render threads are never blocked waiting for another instance to start.
  const auto deadline = GetTickCount64() + 8000;
  do {
    ExistingWindow existing;
    EnumWindows(FindExisting, reinterpret_cast<LPARAM>(&existing));
    if (existing.window) {
      DWORD process = 0;
      GetWindowThreadProcessId(existing.window, &process);
      AllowSetForegroundWindow(process);
      COPYDATASTRUCT data_message{kActionMessage,
          static_cast<DWORD>(initial_action.size() + 1), initial_action.data()};
      DWORD_PTR accepted = 0;
      forwarded_ = SendMessageTimeoutW(existing.window, WM_COPYDATA, 0,
          reinterpret_cast<LPARAM>(&data_message), SMTO_ABORTIFHUNG | SMTO_BLOCK,
          1000, &accepted) != 0 && accepted == 1;
      return;
    }
    Sleep(50);
  } while (GetTickCount64() < deadline);
}

PlayerInstanceLease::~PlayerInstanceLease() { if (mutex_) CloseHandle(mutex_); }

struct WindowsShellController::Impl {
  HWND window;
  bool ready = false;
  std::vector<std::string> pending;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;

  Impl(HWND hwnd, flutter::FlutterEngine* engine) : window(hwnd) {
    // A normal startup has no implicit playback command.
    if (!initial_action.empty()) pending.push_back(std::exchange(initial_action, {}));
    SetPropW(window, instance_property.c_str(), reinterpret_cast<HANDLE>(1));
    channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
        engine->messenger(), "dan_player/windows_shell",
        &flutter::StandardMethodCodec::GetInstance());
    channel->SetMethodCallHandler([this](const auto& call, auto result) {
      try {
        const auto& method = call.method_name();
        if (method == "ready") {
          ready = true;
          flutter::EncodableList actions;
          for (const auto& action : pending) actions.emplace_back(action);
          pending.clear();
          result->Success(EncodableValue(actions));
        } else if (method == "configureTasks") {
          const auto* labels = call.arguments() ? std::get_if<EncodableMap>(call.arguments()) : nullptr;
          const auto status = labels ? RegisterTasks(*labels) : E_INVALIDARG;
          result->Success(EncodableValue(status == S_OK));
        } else if (method == "installationInfo") {
          LockedInstallation install;
          const bool valid = install.Inspect();
          result->Success(EncodableValue(EncodableMap{
              {EncodableValue("kind"), EncodableValue(valid ? "installed" : install.registered ? "unavailable" : "portable")},
              {EncodableValue("directory"), EncodableValue(Utf8FromUtf16(install.directory.c_str()))}}));
        } else if (method == "launchUninstaller") {
          LockedInstallation install;
          if (!install.Inspect()) {
            result->Error("INVALID_INSTALLATION", "The registered uninstaller does not belong to this copy or is unavailable.");
            return;
          }
          // No registry-supplied arguments, shell interpreter, elevation or
          // recursive removal. Inno owns its installed-file uninstall log.
          std::wstring command = L"\"" + install.uninstaller.wstring() +
              L"\" /DANPLAYERPID=" + std::to_wstring(GetCurrentProcessId());
          STARTUPINFOW startup{sizeof(startup)};
          PROCESS_INFORMATION process{};
          if (!CreateProcessW(install.uninstaller.c_str(), command.data(), nullptr,
              nullptr, FALSE, 0, nullptr, install.directory.c_str(), &startup, &process)) {
            result->Error("UNINSTALL_START_FAILED", "Windows could not start the uninstaller.");
          } else {
            CloseHandle(process.hThread);
            CloseHandle(process.hProcess);
            result->Success();
          }
        } else if (method == "openAppFolder") {
          const auto directory = fs::path(ModulePath()).parent_path();
          const auto status = reinterpret_cast<INT_PTR>(ShellExecuteW(window, L"open",
              directory.c_str(), nullptr, nullptr, SW_SHOWNORMAL));
          if (status <= 32) result->Error("OPEN_FOLDER_FAILED", "Windows could not open the application folder.");
          else result->Success();
        } else result->NotImplemented();
      } catch (...) {
        result->Error("SHELL_FAILED", "The Windows operation could not be completed.");
      }
    });
  }
  ~Impl() {
    RemovePropW(window, instance_property.c_str());
    channel->SetMethodCallHandler(nullptr);
  }
};

WindowsShellController::WindowsShellController(HWND window, flutter::FlutterEngine* engine)
    : impl_(std::make_unique<Impl>(window, engine)) {}
WindowsShellController::~WindowsShellController() = default;

std::optional<LRESULT> WindowsShellController::HandleMessage(UINT message, WPARAM, LPARAM lparam) {
  if (message != WM_COPYDATA || !lparam) return std::nullopt;
  const auto* data = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
  if (data->dwData != kActionMessage || !data->lpData || data->cbData < 2 || data->cbData > 32) return LRESULT{0};
  const auto* bytes = static_cast<const char*>(data->lpData);
  if (bytes[data->cbData - 1] != '\0') return LRESULT{0};
  const std::string action(bytes, data->cbData - 1);
  if (!windows_shell::IsAction(action)) return LRESULT{0};
  if (impl_->ready) impl_->channel->InvokeMethod("action", std::make_unique<EncodableValue>(action));
  else if (impl_->pending.size() < 16) impl_->pending.push_back(action);
  else return LRESULT{0};
  return LRESULT{1};
}
