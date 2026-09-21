// Small Jump List command bridge. No Flutter or audio DLL is loaded here.
#include <windows.h>
#include <shellapi.h>
#include <cstdint>
#include <cwctype>
#include <filesystem>
#include <string>
#include "windows_shell_policy.h"

namespace {
std::wstring property;
HWND target = nullptr;
BOOL CALLBACK Find(HWND window, LPARAM) {
  if (!GetPropW(window, property.c_str())) return TRUE;
  target = window;
  return FALSE;
}
}
int WINAPI wWinMain(HINSTANCE, HINSTANCE, wchar_t*, int) {
  int argc = 0;
  wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (!argv) return 1;
  std::wstring argument = argc == 2 ? argv[1] : L"";
  LocalFree(argv);
  const std::wstring prefix = L"--shell-action=";
  if (argument.rfind(prefix, 0) != 0) return 1;
  const auto wide_action = argument.substr(prefix.size());
  std::string action;
  for (const auto ch : wide_action) {
    if (ch > 127) return 1;
    action.push_back(static_cast<char>(ch));
  }
  if (!windows_shell::IsAction(action)) return 1;
  wchar_t module[32768]{};
  if (!GetModuleFileNameW(nullptr, module, 32768)) return 1;
  const auto directory = std::filesystem::path(module).parent_path();
  const auto player = directory / L"Dan Player.exe";
  wchar_t data[32768]{};
  if (GetEnvironmentVariableW(L"DAN_PLAYER_DATA_DIR", data, 32768) >= 32768) return 1;
  const auto identity = player.wstring() + L"|" + data;
  std::uint64_t hash = 14695981039346656037ull;
  for (const auto ch : identity) {
    hash ^= static_cast<std::uint64_t>(towlower(ch));
    hash *= 1099511628211ull;
  }
  wchar_t value[17]{};
  swprintf_s(value, L"%016llx", static_cast<unsigned long long>(hash));
  property = L"DanPlayer.Instance." + std::wstring(value);
  EnumWindows(Find, 0);
  if (target) {
    DWORD process = 0;
    GetWindowThreadProcessId(target, &process);
    AllowSetForegroundWindow(process);
    COPYDATASTRUCT message{0x44504a54, static_cast<DWORD>(action.size()+1),
                           const_cast<char*>(action.c_str())};
    DWORD_PTR accepted = 0;
    return SendMessageTimeoutW(target, WM_COPYDATA, 0,
        reinterpret_cast<LPARAM>(&message), SMTO_ABORTIFHUNG | SMTO_BLOCK,
        1000, &accepted) && accepted == 1 ? 0 : 1;
  }
  // When closed/starting, use the existing single-instance/startup queue.
  SHELLEXECUTEINFOW execute{sizeof(execute)};
  execute.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_FLAG_NO_UI;
  execute.lpFile = player.c_str();
  execute.lpParameters = argument.c_str();
  execute.lpDirectory = directory.c_str();
  execute.nShow = SW_SHOWNORMAL;
  if (!ShellExecuteExW(&execute)) return 1;
  if (execute.hProcess) CloseHandle(execute.hProcess);
  return 0;
}
