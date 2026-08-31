#include "installer_core.h"

#include <shellapi.h>
#include <winver.h>

#include <memory>
#include <vector>

using namespace dan::installer;
namespace {
struct Handle {
  HANDLE value = nullptr;
  ~Handle() { if (value && value != INVALID_HANDLE_VALUE) CloseHandle(value); }
};
bool SameProcessImage(HANDLE process, const fs::path& expected) {
  std::wstring text(32768, L'\0');
  DWORD length = static_cast<DWORD>(text.size());
  return QueryFullProcessImageNameW(process, 0, text.data(), &length) &&
         _wcsicmp(std::wstring(text.data(), length).c_str(), expected.c_str()) == 0;
}
bool IsInstallerImage(const fs::path& path) {
  DWORD ignored = 0;
  const DWORD size = GetFileVersionInfoSizeW(path.c_str(), &ignored);
  if (!size || size > 1024 * 1024) return false;
  std::vector<uint8_t> data(size);
  if (!GetFileVersionInfoW(path.c_str(), 0, size, data.data())) return false;
  struct Translation { WORD language, codepage; };
  Translation* translations = nullptr;
  UINT bytes = 0;
  if (!VerQueryValueW(data.data(), L"\\VarFileInfo\\Translation",
                      reinterpret_cast<void**>(&translations), &bytes)) return false;
  for (size_t i = 0; i < bytes / sizeof(Translation); ++i) {
    wchar_t query[96]{};
    swprintf_s(query, L"\\StringFileInfo\\%04x%04x\\ProductName",
               translations[i].language, translations[i].codepage);
    wchar_t* value = nullptr;
    UINT length = 0;
    if (VerQueryValueW(data.data(), query, reinterpret_cast<void**>(&value), &length) &&
        length > 0 && wcscmp(value, L"Dan Player Installer") == 0) return true;
  }
  return false;
}
DWORD Number(const wchar_t* value) {
  if (!value || !*value) throw std::runtime_error("Missing process identity");
  wchar_t* end = nullptr;
  const auto parsed = wcstoull(value, &end, 10);
  if (*end || parsed > MAXDWORD) throw std::runtime_error("Invalid process identity");
  return static_cast<DWORD>(parsed);
}
}  // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  int argc = 0;
  wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (!argv) return 2;
  struct Arguments { wchar_t** value; ~Arguments() { LocalFree(value); } } arguments{argv};
  try {
    if (argc != 9 || wcscmp(argv[1], L"--delete-original") != 0) return 3;
    const DWORD source_pid = Number(argv[2]), inner_pid = Number(argv[3]);
    if (!source_pid || !inner_pid || source_pid == GetCurrentProcessId() || inner_pid == GetCurrentProcessId()) return 4;
    const auto path = CanonicalPath(argv[8]);
    CheckNoReparsePoints(path);
    if (!IsInstallerImage(path)) return 5;
    Handle source{OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, source_pid)};
    Handle inner{OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, inner_pid)};
    if (!source.value || !inner.value || !SameProcessImage(source.value, path)) return 6;
    // Handles, not reusable PIDs, define the processes we wait for.
    const HANDLE processes[] = {source.value, inner.value};
    const DWORD process_count = source_pid == inner_pid ? 1 : 2;
    if (WaitForMultipleObjects(process_count, processes, TRUE, 30000) != WAIT_OBJECT_0) return 7;
    CheckNoReparsePoints(path);
    Handle file{CreateFileW(path.c_str(), GENERIC_READ | DELETE, FILE_SHARE_READ,
        nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr)};
    if (file.value == INVALID_HANDLE_VALUE) return 8;
    BY_HANDLE_FILE_INFORMATION identity{};
    if (!GetFileInformationByHandle(file.value, &identity) ||
        (identity.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) ||
        identity.nNumberOfLinks != 1 || identity.dwVolumeSerialNumber != Number(argv[4]) ||
        identity.nFileIndexHigh != Number(argv[5]) || identity.nFileIndexLow != Number(argv[6]) ||
        Sha256Handle(file.value) != ToUtf8(argv[7])) return 9;
    // The verified HANDLE is marked for deletion, not a newly resolved path.
    // No directory traversal/deletion, wildcard, shell, or delayed reboot task.
    FILE_DISPOSITION_INFO disposition{TRUE};
    if (!SetFileInformationByHandle(file.value, FileDispositionInfo,
                                     &disposition, sizeof(disposition))) return 10;
    return 0;
  } catch (...) { return 11; }
}
