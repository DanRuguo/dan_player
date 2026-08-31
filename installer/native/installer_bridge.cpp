#include "installer_core.h"
#include "update_gate.h"

#include <shlobj.h>
#include <tlhelp32.h>

#include <algorithm>
#include <memory>
#include <stdexcept>

using namespace dan::installer;
namespace {
std::wstring last_error;
std::unique_ptr<Transaction> transaction;
std::unique_ptr<DestinationSelection> selection;
std::unique_ptr<UpdateGate> update_gate;
Manifest payload;
fs::path payload_manifest;
fs::path original_setup;
fs::path installed_directory;
bool committed = false;

class ProductRegistry final : public RegistryStore {
 public:
  RegistrySnapshot Read() override {
#ifdef DAN_INSTALLER_TEST_BUILD
    return memory_;
#else
    RegistrySnapshot result;
    HKEY key = nullptr;
    const LONG status = RegOpenKeyExW(HKEY_CURRENT_USER, kRegistryKey, 0,
                                     KEY_READ | KEY_WOW64_64KEY, &key);
    if (status == ERROR_FILE_NOT_FOUND) return result;
    if (status != ERROR_SUCCESS) throw std::runtime_error("Cannot back up installer registration");
    result.existed = true;
    for (DWORD index = 0;; ++index) {
      wchar_t name[16384]{};
      std::vector<uint8_t> data(65536);
      DWORD name_length = 16384, data_length = static_cast<DWORD>(data.size()), type = 0;
      const LONG error = RegEnumValueW(key, index, name, &name_length, nullptr,
                                       &type, data.data(), &data_length);
      if (error == ERROR_NO_MORE_ITEMS) break;
      if (error != ERROR_SUCCESS || index >= 256) {
        RegCloseKey(key);
        throw std::runtime_error("Cannot read bounded installer registration");
      }
      data.resize(data_length);
      result.values.push_back({std::wstring(name, name_length), type, std::move(data)});
    }
    RegCloseKey(key);
    return result;
#endif
  }
  void Restore(const RegistrySnapshot& original) override {
#ifdef DAN_INSTALLER_TEST_BUILD
    memory_ = original;
#else
    HKEY key = nullptr;
    LONG status = RegOpenKeyExW(HKEY_CURRENT_USER, kRegistryKey, 0,
                               KEY_READ | KEY_WRITE | KEY_WOW64_64KEY, &key);
    if (status == ERROR_FILE_NOT_FOUND && !original.existed) return;
    if (status == ERROR_FILE_NOT_FOUND) status = RegCreateKeyExW(HKEY_CURRENT_USER,
        kRegistryKey, 0, nullptr, 0, KEY_READ | KEY_WRITE | KEY_WOW64_64KEY,
        nullptr, &key, nullptr);
    if (status != ERROR_SUCCESS) throw std::runtime_error("Cannot restore installer registration");
    // Values only, at this one constant product key. No recursive registry delete.
    for (;;) {
      wchar_t name[16384]{};
      DWORD length = 16384;
      status = RegEnumValueW(key, 0, name, &length, nullptr, nullptr, nullptr, nullptr);
      if (status == ERROR_NO_MORE_ITEMS) break;
      if (status != ERROR_SUCCESS || RegDeleteValueW(key, name) != ERROR_SUCCESS) {
        RegCloseKey(key);
        throw std::runtime_error("Cannot restore installer registration values");
      }
    }
    for (const auto& value : original.values) {
      if (RegSetValueExW(key, value.name.c_str(), 0, value.type, value.data.data(),
                         static_cast<DWORD>(value.data.size())) != ERROR_SUCCESS) {
        RegCloseKey(key);
        throw std::runtime_error("Cannot restore original registration value");
      }
    }
    RegFlushKey(key);
    RegCloseKey(key);
    if (!original.existed) {
      // Fails harmlessly if an unrelated subkey appeared; never recurses.
      RegDeleteKeyExW(HKEY_CURRENT_USER, kRegistryKey, KEY_WOW64_64KEY, 0);
    }
#endif
  }
 private:
#ifdef DAN_INSTALLER_TEST_BUILD
  RegistrySnapshot memory_;
#endif
} registry;

template <typename Action> int Guard(Action action) {
  try { action(); last_error.clear(); return 1; }
  catch (const std::exception& error) {
    try { last_error = FromUtf8(error.what()); }
    catch (...) { last_error = L"Installer operation failed."; }
    return 0;
  } catch (...) { last_error = L"Unexpected installer error."; return 0; }
}
int CopyText(const std::wstring& value, wchar_t* buffer, int capacity) {
  if (!buffer || capacity < 1) return 0;
  const size_t count = (std::min)(value.size(), static_cast<size_t>(capacity - 1));
  std::copy_n(value.data(), count, buffer);
  buffer[count] = 0;
  return static_cast<int>(count);
}
fs::path KnownFolder(REFKNOWNFOLDERID id) {
  PWSTR path = nullptr;
  if (FAILED(SHGetKnownFolderPath(id, KF_FLAG_DEFAULT, nullptr, &path))) throw std::runtime_error("Cannot locate a Windows known folder");
  fs::path result(path);
  CoTaskMemFree(path);
  return result;
}
bool EqualPath(const fs::path& a, const fs::path& b) {
  return _wcsicmp(a.lexically_normal().c_str(), b.lexically_normal().c_str()) == 0;
}
std::wstring QuoteArgument(const std::wstring& text) {
  std::wstring result = L"\"";
  size_t backslashes = 0;
  for (wchar_t c : text) {
    if (c == L'\\') { ++backslashes; continue; }
    if (c == L'"') result.append(backslashes * 2 + 1, L'\\');
    else result.append(backslashes, L'\\');
    backslashes = 0;
    result += c;
  }
  result.append(backslashes * 2, L'\\');
  result += L'"';
  return result;
}
fs::path ProcessPath(HANDLE process) {
  std::wstring result(32768, L'\0');
  DWORD length = static_cast<DWORD>(result.size());
  if (!QueryFullProcessImageNameW(process, 0, result.data(), &length)) return {};
  result.resize(length);
  return fs::path(result);
}
DWORD FindOriginalSetupProcess() {
  // Only this process and its actual parent chain are eligible, not a scan by
  // executable basename or a user-supplied process id.
  DWORD current = GetCurrentProcessId();
  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return 0;
  std::vector<PROCESSENTRY32W> processes;
  PROCESSENTRY32W entry{}; entry.dwSize = sizeof(entry);
  if (Process32FirstW(snapshot, &entry)) {
    do { processes.push_back(entry); } while (Process32NextW(snapshot, &entry));
  }
  CloseHandle(snapshot);
  for (size_t depth = 0; current && depth < 8; ++depth) {
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, current);
    const bool matches = process && EqualPath(ProcessPath(process), original_setup);
    if (process) CloseHandle(process);
    if (matches) return current;
    const auto found = std::find_if(processes.begin(), processes.end(), [current](const auto& value) { return value.th32ProcessID == current; });
    if (found == processes.end() || found->th32ParentProcessID == current) break;
    current = found->th32ParentProcessID;
  }
  return 0;
}
}  // namespace

#define EXPORT extern "C" __declspec(dllexport)
EXPORT int __stdcall DP_GetError(wchar_t* buffer, int capacity) {
  return CopyText(last_error, buffer, capacity);
}
EXPORT int __stdcall DP_ValidateManifest(const wchar_t* manifest) {
  // Packaging guard: only parse the bounded manifest with the runtime policy.
  // No known-folder/registry access, target selection, transaction, or writes.
  return Guard([&] { ReadManifest(manifest ? manifest : L""); });
}
EXPORT int __stdcall DP_UpdateOpen(const wchar_t* target,const wchar_t* manifest,
    const wchar_t* version,const wchar_t* parent,const wchar_t* event) {
  return Guard([&] {
    if(update_gate)throw std::runtime_error("Updater is already initialized");
    update_gate=std::make_unique<UpdateGate>(target?target:L"",manifest?manifest:L"",
        version?version:L"",parent?parent:L"",event?event:L"");
  });
}
EXPORT int __stdcall DP_UpdatePoll() {
  int state=-1;
  if(!Guard([&] {
    if(!update_gate)throw std::runtime_error("Updater is not initialized");
#ifdef DAN_INSTALLER_TEST_BUILD
    state=update_gate->Poll(1500);
#else
    state=update_gate->Poll();
#endif
  }))return -1;
  return state;
}
EXPORT int __stdcall DP_UpdateRetry() {
  return Guard([&] { if(!update_gate)throw std::runtime_error("Updater is not initialized");update_gate->Retry(); });
}
EXPORT void __stdcall DP_UpdateClose() { update_gate.reset(); }
EXPORT int __stdcall DP_SelectionCreate(const wchar_t* version) {
  return Guard([&] { selection = std::make_unique<DestinationSelection>(version ? version : L""); });
}
EXPORT int __stdcall DP_SelectionParent(const wchar_t* parent) {
  return Guard([&] {
    if (!selection) throw std::runtime_error("No path selection state");
    const fs::path path(parent ? parent : L"");
    selection->ChooseParent(path, IsRecognizedInstallation(path) ? path : fs::path{});
  });
}
EXPORT int __stdcall DP_SelectionEdit(const wchar_t* path) {
  return Guard([&] {
    if (!selection) throw std::runtime_error("No path selection state");
    selection->EditFinal(path ? path : L"");
  });
}
EXPORT int __stdcall DP_SelectionPrevious(const wchar_t* path) {
  return Guard([&] {
    if (!selection) throw std::runtime_error("No path selection state");
    if (path && IsRecognizedInstallation(path)) selection->DiscoverPrevious(path);
  });
}
EXPORT int __stdcall DP_SelectionGet(wchar_t* buffer, int capacity) {
  return selection ? CopyText(selection->value().wstring(), buffer, capacity) : 0;
}
EXPORT int __stdcall DP_Configure(const wchar_t* target, const wchar_t* manifest,
    const wchar_t* desktop_link, const wchar_t* start_menu_link,
    const wchar_t* setup_source) {
  return Guard([&] {
    if (transaction && transaction->pending()) throw std::runtime_error("Finish recovery before changing installation paths");
    Context context;
    context.target = CanonicalPath(target ? target : L"");
    // Empty Pascal UnicodeStrings are null pointers at the DLL boundary.
    context.desktop_link = desktop_link ? desktop_link : L"";
    context.start_menu_link = start_menu_link ? start_menu_link : L"";
#ifdef DAN_INSTALLER_TEST_BUILD
    bool sandbox = false;
    for (const auto& part : context.target) if (part == L"qa-installer") sandbox = true;
    if (!sandbox) throw std::runtime_error("QA installer only accepts the qa-installer sandbox");
    const auto qa = context.target.parent_path();
    if ((!context.desktop_link.empty() && !IsWithin(context.desktop_link, qa / L"redirect-desktop")) ||
        (!context.start_menu_link.empty() && !IsWithin(context.start_menu_link, qa / L"redirect-start"))) throw std::runtime_error("QA shortcut path must be redirected");
#else
    if ((!context.desktop_link.empty() && !EqualPath(context.desktop_link, KnownFolder(FOLDERID_Desktop) / L"Dan Player.lnk")) ||
        (!context.start_menu_link.empty() && !EqualPath(context.start_menu_link, KnownFolder(FOLDERID_Programs) / L"Dan Player.lnk"))) throw std::runtime_error("Shortcut path is not the exact product shortcut");
    wchar_t windows[MAX_PATH]{};
    GetWindowsDirectoryW(windows, MAX_PATH);
    context.forbidden_roots = {windows, KnownFolder(FOLDERID_Documents) / L"Dan Player",
        KnownFolder(FOLDERID_Documents) / L"dan_player",
        KnownFolder(FOLDERID_RoamingAppData) / L"Dan_Ruguo.Inc\\dan_player"};
    // Per-user installer: never requests elevation or writes under Program Files.
    context.forbidden_roots.push_back(KnownFolder(FOLDERID_ProgramFiles));
    context.forbidden_roots.push_back(KnownFolder(FOLDERID_ProgramFilesX86));
    if (EqualPath(context.target, KnownFolder(FOLDERID_Profile)) ||
        EqualPath(context.target, KnownFolder(FOLDERID_Desktop)) ||
        EqualPath(context.target, KnownFolder(FOLDERID_Documents))) throw std::runtime_error("Choose a dedicated application directory");
#endif
    payload_manifest = manifest ? manifest : L"";
    if(update_gate) {
      if(!context.desktop_link.empty()||!context.start_menu_link.empty())throw std::runtime_error("Updater preserves existing shortcuts without creating new ones");
      update_gate->RequireReady(context.target,payload_manifest);
    }
    payload = ReadManifest(payload_manifest);
    original_setup = CanonicalPath(setup_source ? setup_source : L"");
    installed_directory = context.target;
    committed = false;
    transaction = std::make_unique<Transaction>(std::move(context), registry);
  });
}
EXPORT int __stdcall DP_HasRecovery() {
  int result = 0;
  if (!Guard([&] { result = transaction && transaction->HasPendingRecovery() ? 1 : 0; })) return -1;
  return result;
}
EXPORT int __stdcall DP_RecordWritten(const wchar_t* path) {
  return Guard([&] {
    if (!transaction || !path) throw std::runtime_error("No installation transaction");
    // Inno 7 exposes extended DOS paths in CurrentFilename; accept only this
    // exact drive-prefixed representation, then use the strict local validator.
    std::wstring value(path);
    if (value.rfind(L"\\\\?\\", 0) == 0 && value.size() > 6 && value[5] == L':') value.erase(0, 4);
    transaction->RecordWritten(CanonicalPath(value));
  });
}
EXPORT int __stdcall DP_Begin() {
  return Guard([&] {
    if (!transaction) throw std::runtime_error("Installer is not configured");
    if(update_gate)update_gate->RequireReady(installed_directory,payload_manifest);
    transaction->Begin(payload, payload_manifest);
  });
}
EXPORT int __stdcall DP_Commit() {
  return Guard([&] {
    if (!transaction) throw std::runtime_error("Installer is not configured");
    transaction->Commit(payload, payload_manifest);
    committed = true;
  });
}
EXPORT int __stdcall DP_VerifyInstalled() {
  return Guard([&] {
    if (!transaction) throw std::runtime_error("Installer is not configured");
    transaction->VerifyInstalled(payload, payload_manifest);
  });
}
EXPORT int __stdcall DP_Rollback() {
  return Guard([&] { if (transaction) transaction->Rollback(); });
}
EXPORT int __stdcall DP_BackupPath(wchar_t* buffer, int capacity) {
  return transaction ? CopyText(transaction->backup_directory().wstring(), buffer, capacity) : 0;
}
EXPORT int __stdcall DP_DeleteOriginalInstaller() {
  return Guard([&] {
#ifdef DAN_INSTALLER_TEST_BUILD
    throw std::runtime_error("QA installers never delete a running executable");
#else
    if (!committed || !transaction || transaction->pending() || !fs::is_regular_file(installed_directory / kInstalledManifest)) throw std::runtime_error("Installation must succeed before deletion");
    const DWORD original_pid = FindOriginalSetupProcess();
    if (!original_pid) throw std::runtime_error("Cannot verify the original installer process; keeping installer");
    CheckNoReparsePoints(original_setup);
    HANDLE source = CreateFileW(original_setup.c_str(), GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL, nullptr);
    if (source == INVALID_HANDLE_VALUE) throw std::runtime_error("Cannot verify original installer identity");
    BY_HANDLE_FILE_INFORMATION identity{};
    const bool identified = GetFileInformationByHandle(source, &identity) && identity.nNumberOfLinks == 1;
    CloseHandle(source);
    if (!identified) throw std::runtime_error("Original installer identity is ambiguous");
    const auto helper = installed_directory / L".dan-player-install\\cleanup.exe";
    const auto entry = std::find_if(payload.files.begin(), payload.files.end(), [](const auto& file) {
      return file.relative_path.generic_wstring() == L".dan-player-install/cleanup.exe";
    });
    if (entry == payload.files.end() || Sha256(helper) != entry->sha256) throw std::runtime_error("Cleanup helper verification failed");
    std::wstring command = QuoteArgument(helper.wstring()) + L" --delete-original " +
        std::to_wstring(original_pid) + L" " + std::to_wstring(GetCurrentProcessId()) + L" " +
        std::to_wstring(identity.dwVolumeSerialNumber) + L" " +
        std::to_wstring(identity.nFileIndexHigh) + L" " + std::to_wstring(identity.nFileIndexLow) +
        L" " + FromUtf8(Sha256(original_setup)) + L" " + QuoteArgument(original_setup.wstring());
    STARTUPINFOW startup{}; startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(helper.c_str(), command.data(), nullptr, nullptr, FALSE,
                          CREATE_NO_WINDOW, nullptr, installed_directory.c_str(), &startup, &process)) throw std::runtime_error("Cannot start exact-file cleanup");
    CloseHandle(process.hThread); CloseHandle(process.hProcess);
#endif
  });
}
