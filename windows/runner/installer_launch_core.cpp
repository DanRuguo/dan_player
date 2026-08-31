#include "installer_launch_core.h"

#include <bcrypt.h>
#include <softpub.h>
#include <wincrypt.h>
#include <wintrust.h>

#include <algorithm>
#include <cwctype>
#include <vector>

namespace installer_launch {
namespace {

struct Handle {
  HANDLE value = INVALID_HANDLE_VALUE;
  explicit Handle(HANDLE handle = INVALID_HANDLE_VALUE) : value(handle) {}
  ~Handle() { if (value && value != INVALID_HANDLE_VALUE) CloseHandle(value); }
  Handle(const Handle&) = delete;
  Handle& operator=(const Handle&) = delete;
  Handle(Handle&& other) noexcept : value(other.value) {
    other.value = INVALID_HANDLE_VALUE;
  }
  bool valid() const { return value && value != INVALID_HANDLE_VALUE; }
};

Outcome Error(const char* code, const char* message, DWORD detail = GetLastError()) {
  return {code, message, detail};
}

bool Cancelled(HANDLE handle) {
  return handle && WaitForSingleObject(handle, 0) == WAIT_OBJECT_0;
}

bool IsHex(char value) {
  return (value >= '0' && value <= '9') ||
         (value >= 'a' && value <= 'f') ||
         (value >= 'A' && value <= 'F');
}

bool IsDrivePath(const std::wstring& path) {
  return path.size() > 3 &&
         ((path[0] >= L'A' && path[0] <= L'Z') ||
          (path[0] >= L'a' && path[0] <= L'z')) &&
         path[1] == L':' && path[2] == L'\\' &&
         path.find(L':', 2) == std::wstring::npos;
}

bool IsExe(const std::wstring& path) {
  return path.size() >= 4 &&
         _wcsicmp(path.c_str() + path.size() - 4, L".exe") == 0;
}

std::wstring ModulePath() {
  std::vector<wchar_t> path(32768);
  const DWORD count = GetModuleFileNameW(nullptr, path.data(),
                                        static_cast<DWORD>(path.size()));
  return count && count < path.size() ? std::wstring(path.data(), count) : L"";
}

std::wstring FinalPath(HANDLE file) {
  std::vector<wchar_t> path(32768);
  const DWORD count = GetFinalPathNameByHandleW(file, path.data(),
      static_cast<DWORD>(path.size()), FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
  if (!count || count >= path.size()) return L"";
  std::wstring result(path.data(), count);
  if (result.compare(0, 4, L"\\\\?\\") == 0) result.erase(0, 4);
  return IsDrivePath(result) ? result : L"";
}

struct LockedFile {
  Handle file;
  std::wstring path;
  std::vector<Handle> directories;

  bool Open(const std::wstring& input) {
    // Refuse write/delete sharing while hashing, verifying and starting. A
    // writer already holding access makes this fail closed before verification.
    file.value = CreateFileW(input.c_str(), GENERIC_READ, FILE_SHARE_READ,
        nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    if (!file.valid()) return false;
    BY_HANDLE_FILE_INFORMATION info{};
    if (!GetFileInformationByHandle(file.value, &info) ||
        (info.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY |
                                  FILE_ATTRIBUTE_REPARSE_POINT)) ||
        info.nNumberOfLinks != 1) return false;
    path = FinalPath(file.value);
    if (path.empty() || !IsExe(path)) return false;
    // Lock each canonical ancestor against rename/deletion, without preventing
    // normal writes to sibling files. This closes a directory-swap path race.
    for (size_t end = 3; end < path.size();) {
      const auto directory = path.substr(0, end);
      Handle handle(CreateFileW(directory.c_str(), FILE_READ_ATTRIBUTES,
          FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING,
          FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
      FILE_ATTRIBUTE_TAG_INFO attributes{};
      if (!handle.valid() ||
          !GetFileInformationByHandleEx(handle.value, FileAttributeTagInfo,
                                        &attributes, sizeof(attributes)) ||
          !(attributes.FileAttributes & FILE_ATTRIBUTE_DIRECTORY) ||
          (attributes.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT)) return false;
      directories.push_back(std::move(handle));
      end = path.find(L'\\', end == 3 ? 3 : end + 1);
      if (end == std::wstring::npos) break;
    }
    // Check identity again after acquiring ancestor locks. The held file cannot
    // be replaced; its canonical launch name must still designate this object.
    Handle check(CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                            OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
    BY_HANDLE_FILE_INFORMATION checked{};
    return check.valid() && GetFileInformationByHandle(check.value, &checked) &&
        checked.dwVolumeSerialNumber == info.dwVolumeSerialNumber &&
        checked.nFileIndexHigh == info.nFileIndexHigh &&
        checked.nFileIndexLow == info.nFileIndexLow;
  }
};

std::string Hex(const unsigned char* bytes, size_t size) {
  constexpr char alphabet[] = "0123456789abcdef";
  std::string result(size * 2, '0');
  for (size_t index = 0; index < size; ++index) {
    result[index * 2] = alphabet[bytes[index] >> 4];
    result[index * 2 + 1] = alphabet[bytes[index] & 15];
  }
  return result;
}

bool VersionString(const std::vector<unsigned char>& data, const wchar_t* key,
                   const std::wstring& expected) {
  struct Translation { WORD language; WORD code_page; };
  Translation* translations = nullptr;
  UINT translation_size = 0;
  if (!VerQueryValueW(data.data(), L"\\VarFileInfo\\Translation",
                      reinterpret_cast<void**>(&translations),
                      &translation_size)) return false;
  for (UINT index = 0; index < translation_size / sizeof(Translation); ++index) {
    wchar_t query[128]{};
    swprintf_s(query, L"\\StringFileInfo\\%04x%04x\\%ls",
        translations[index].language, translations[index].code_page, key);
    wchar_t* value = nullptr;
    UINT length = 0;
    if (VerQueryValueW(data.data(), query, reinterpret_cast<void**>(&value),
                       &length) && value && length > 0 &&
        std::wstring(value, length - 1) == expected) return true;
  }
  return false;
}

class SystemBackend final : public Backend {
 public:
  Outcome VerifySigner(HANDLE file, const std::wstring& path,
                       Signer* signer) override {
    return VerifyTrustedSigner(file, path, signer);
  }
  bool IsInstallerVersion(const std::wstring& path,
                          const std::wstring& version) override {
    return installer_launch::IsInstallerVersion(path, version);
  }
  Outcome Start(const std::wstring& application,
                const std::wstring& command_line,
                const std::wstring& directory) override {
    std::vector<wchar_t> command(command_line.begin(), command_line.end());
    command.push_back(L'\0');
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    // Explicit application + quoted argv; never cmd.exe, shell execution,
    // inherited handles, arbitrary target directories, or forced termination.
    if (!CreateProcessW(application.c_str(), command.data(), nullptr, nullptr,
                        FALSE, CREATE_UNICODE_ENVIRONMENT, nullptr,
                        directory.c_str(), &startup, &process)) {
      return Error("start_failed", "Windows could not start the installer.");
    }
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return {};
  }
};

}  // namespace

bool IsInstallerVersion(const std::wstring& path, const std::wstring& version) {
  const DWORD size = GetFileVersionInfoSizeW(path.c_str(), nullptr);
  if (!size || size > 1024 * 1024) return false;
  std::vector<unsigned char> data(size);
  return GetFileVersionInfoW(path.c_str(), 0, size, data.data()) &&
      VersionString(data, L"ProductName", L"Dan Player Installer") &&
      VersionString(data, L"ProductVersion", version);
}

bool ValidRequest(const Request& request) {
  if (request.path.size() > 32000 || !IsDrivePath(request.path) ||
      !IsExe(request.path) || request.sha256.size() != 64 ||
      !std::all_of(request.sha256.begin(), request.sha256.end(), IsHex) ||
      request.version.empty() || request.version.size() > 96) return false;
  for (const auto value : request.path) {
    if (value < 32 || value == L'"' || value == L'/') return false;
  }
  int dots = 0;
  bool in_suffix = false;
  bool previous_digit = false;
  for (const auto value : request.version) {
    const bool digit = value >= L'0' && value <= L'9';
    if (!in_suffix) {
      if (value == L'.') {
        if (!previous_digit || ++dots > 2) return false;
      } else if (value == L'-' || value == L'+') {
        if (dots != 2 || !previous_digit) return false;
        in_suffix = true;
      } else if (!digit) return false;
    } else if (!digit && !(value >= L'a' && value <= L'z') &&
               !(value >= L'A' && value <= L'Z') && value != L'.' &&
               value != L'-' && value != L'+') return false;
    previous_digit = digit;
  }
  return dots == 2 && (previous_digit || (in_suffix &&
      std::iswalnum(request.version.back()) != 0));
}

std::wstring QuoteArgument(const std::wstring& argument) {
  std::wstring result = L"\"";
  size_t slashes = 0;
  for (const auto value : argument) {
    if (value == L'\\') { ++slashes; continue; }
    result.append(slashes * (value == L'"' ? 2 : 1), L'\\');
    if (value == L'"') result.push_back(L'\\');
    result.push_back(value);
    slashes = 0;
  }
  result.append(slashes * 2, L'\\');
  result.push_back(L'"');
  return result;
}

std::wstring BuildCommandLine(const std::wstring& installer,
                             const std::wstring& directory, DWORD parent_pid,
                             const std::wstring& version,
                             const std::wstring& ready_event) {
  return QuoteArgument(installer) + L" /DANUPDATE=1 " +
      QuoteArgument(L"/DIR=" + directory) + L" /DANPARENTPID=" +
      std::to_wstring(parent_pid) + L" " +
      QuoteArgument(L"/DANUPDATEVERSION=" + version) + L" " +
      QuoteArgument(L"/DANUPDATEEVENT=" + ready_event);
}

Outcome HashFile(HANDLE file, std::string* sha256, HANDLE cancelled) {
  BCRYPT_ALG_HANDLE algorithm = nullptr;
  BCRYPT_HASH_HANDLE hash = nullptr;
  if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM,
                                  nullptr, 0) < 0) {
    return Error("hash_failed", "SHA-256 is unavailable.", ERROR_INVALID_DATA);
  }
  const auto close = [&]() {
    if (hash) BCryptDestroyHash(hash);
    BCryptCloseAlgorithmProvider(algorithm, 0);
  };
  if (BCryptCreateHash(algorithm, &hash, nullptr, 0, nullptr, 0, 0) < 0) {
    close();
    return Error("hash_failed", "SHA-256 initialization failed.", ERROR_INVALID_DATA);
  }
  LARGE_INTEGER start{};
  if (!SetFilePointerEx(file, start, nullptr, FILE_BEGIN)) {
    close();
    return Error("hash_failed", "The installer could not be read.");
  }
  std::array<unsigned char, 65536> buffer{};
  DWORD read = 0;
  bool good = true;
  for (;;) {
    if (Cancelled(cancelled)) { good = false; break; }
    if (!ReadFile(file, buffer.data(), static_cast<DWORD>(buffer.size()),
                   &read, nullptr)) { good = false; break; }
    if (!read) break;
    if (BCryptHashData(hash, buffer.data(), read, 0) < 0) { good = false; break; }
  }
  Signer digest{};
  good = good && BCryptFinishHash(hash, digest.data(),
                                  static_cast<ULONG>(digest.size()), 0) >= 0;
  close();
  if (!good) return Error("hash_failed", "The installer hash could not be verified.");
  *sha256 = Hex(digest.data(), digest.size());
  return {};
}

Outcome VerifyTrustedSigner(HANDLE file, const std::wstring& path,
                            Signer* signer) {
  WINTRUST_FILE_INFO info{};
  info.cbStruct = sizeof(info);
  info.pcwszFilePath = path.c_str();
  info.hFile = file;
  WINTRUST_DATA trust{};
  trust.cbStruct = sizeof(trust);
  trust.dwUIChoice = WTD_UI_NONE;
  trust.fdwRevocationChecks = WTD_REVOKE_WHOLECHAIN;
  trust.dwUnionChoice = WTD_CHOICE_FILE;
  trust.pFile = &info;
  trust.dwStateAction = WTD_STATEACTION_VERIFY;
  trust.dwProvFlags = WTD_REVOCATION_CHECK_CHAIN_EXCLUDE_ROOT;
  GUID action = WINTRUST_ACTION_GENERIC_VERIFY_V2;
  // Only EXACT zero is trusted. CN/thumbprint matching never substitutes for
  // Windows trust, and this code never imports or installs any certificate.
  const LONG status = WinVerifyTrust(reinterpret_cast<HWND>(INVALID_HANDLE_VALUE), &action, &trust);
  bool identity = false;
  if (status == ERROR_SUCCESS) {
    const auto provider = WTHelperProvDataFromStateData(trust.hWVTStateData);
    const auto signature = provider
        ? WTHelperGetProvSignerFromChain(provider, 0, FALSE, 0) : nullptr;
    if (signature && signature->csCertChain > 0 && signature->pasCertChain &&
        signature->pasCertChain[0].pCert) {
      DWORD size = static_cast<DWORD>(signer->size());
      identity = CertGetCertificateContextProperty(
          signature->pasCertChain[0].pCert, CERT_SHA256_HASH_PROP_ID,
          signer->data(), &size) && size == signer->size();
    }
  }
  trust.dwStateAction = WTD_STATEACTION_CLOSE;
  WinVerifyTrust(reinterpret_cast<HWND>(INVALID_HANDLE_VALUE), &action, &trust);
  if (status != ERROR_SUCCESS) {
    return Error("signature_untrusted",
        "Windows does not trust this signature. Use manual installation if appropriate; no certificate was installed.",
        static_cast<DWORD>(status));
  }
  if (!identity) return Error("signer_missing", "The verified signing identity is unavailable.");
  return {};
}

Outcome LaunchWithBackend(const Request& request, HANDLE cancelled,
                          Backend& backend, DWORD ready_timeout_ms) {
  if (!ValidRequest(request)) return Error("invalid_request", "Invalid installer request.", ERROR_INVALID_PARAMETER);
  if (Cancelled(cancelled)) return Error("launch_cancelled", "The player is closing.", ERROR_CANCELLED);
  LockedFile installer;
  if (!installer.Open(request.path)) return Error("installer_locked", "The installer cannot be safely opened. Close any writer and try again.");
  std::string actual_hash;
  auto outcome = HashFile(installer.file.value, &actual_hash, cancelled);
  if (!outcome.ok()) return outcome;
  auto expected = request.sha256;
  std::transform(expected.begin(), expected.end(), expected.begin(),
                  [](char value) { return static_cast<char>(std::tolower(value)); });
  if (actual_hash != expected) return Error("hash_mismatch", "The installer SHA-256 does not match the downloaded release.", ERROR_INVALID_DATA);
  LockedFile player;
  if (!player.Open(ModulePath())) return Error("player_identity_failed", "The current player executable cannot be safely identified.");
  Signer installer_signer{}, player_signer{};
  outcome = backend.VerifySigner(installer.file.value, installer.path, &installer_signer);
  if (!outcome.ok()) return outcome;
  outcome = backend.VerifySigner(player.file.value, player.path, &player_signer);
  if (!outcome.ok()) return outcome;
  if (installer_signer != player_signer) return Error("publisher_mismatch", "The installer is not signed with this player's trusted signing certificate.", ERROR_INVALID_DATA);
  if (!backend.IsInstallerVersion(installer.path, request.version)) return Error("installer_version_mismatch", "This is not the requested complete Dan Player installer.", ERROR_INVALID_DATA);
  if (Cancelled(cancelled)) return Error("launch_cancelled", "The player is closing.", ERROR_CANCELLED);
  std::array<unsigned char, 32> nonce{};
  if (BCryptGenRandom(nullptr, nonce.data(), static_cast<ULONG>(nonce.size()),
                       BCRYPT_USE_SYSTEM_PREFERRED_RNG) < 0) {
    return Error("ready_event_failed", "A secure installer handshake could not be created.");
  }
  const auto hex = Hex(nonce.data(), nonce.size());
  const auto event_name = L"Local\\DanPlayer.Update." + std::wstring(hex.begin(), hex.end());
  Handle ready(CreateEventW(nullptr, TRUE, FALSE, event_name.c_str()));
  if (!ready.valid() || GetLastError() == ERROR_ALREADY_EXISTS) return Error("ready_event_failed", "The installer handshake is unavailable.");
  Handle accepted(CreateEventW(nullptr, TRUE, FALSE, (event_name + L".Accepted").c_str()));
  if (!accepted.valid() || GetLastError() == ERROR_ALREADY_EXISTS) return Error("ready_event_failed", "The installer acknowledgement is unavailable.");
  const auto directory = player.path.substr(0, player.path.find_last_of(L'\\'));
  if (directory.size() <= 3) return Error("player_identity_failed", "Updating an installation in a drive root is not supported.", ERROR_INVALID_NAME);
  const auto command = BuildCommandLine(installer.path, directory,
      GetCurrentProcessId(), request.version, event_name);
  if (command.size() >= 32767) return Error("invalid_request", "The installer command is too long.", ERROR_INVALID_PARAMETER);
  outcome = backend.Start(installer.path, command, directory);
  if (!outcome.ok()) return outcome;
  const HANDLE waits[] = {ready.value, cancelled};
  const DWORD result = WaitForMultipleObjects(cancelled ? 2 : 1, waits, FALSE,
                                              ready_timeout_ms);
  if (Cancelled(cancelled)) return Error("launch_cancelled", "The player is closing.", ERROR_CANCELLED);
  if (result != WAIT_OBJECT_0) return Error("installer_not_ready", "The installer did not confirm the update. The player will remain open.", result);
  // The installer may still hold READY after our timeout. Only an explicit
  // reverse acknowledgement authorizes it to wait for exit and then install.
  // Timed-out/cancelled operations NEVER signal Accepted, including late READY.
  if (!SetEvent(accepted.value)) return Error("installer_not_ready", "The update acknowledgement failed. The player will remain open.");
  return {};
}

Outcome Launch(const Request& request, HANDLE cancelled) {
  SystemBackend backend;
  return LaunchWithBackend(request, cancelled, backend);
}

}  // namespace installer_launch
