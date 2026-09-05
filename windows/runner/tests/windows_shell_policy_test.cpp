#include "../windows_shell_policy.h"

#include <cstdlib>
#include <iostream>

int main() {
  int checks = 0;
  const auto check = [&](bool condition) {
    ++checks;
    if (!condition) std::exit(1);
  };
  using namespace windows_shell;
  check(SamePath(L"C:\\Player\\", L"c:\\player"));
  check(SamePath(L"C:/Player/", L"C:\\Player"));
  check(SamePath(L"C:\\Player\\.\\", L"C:\\Player"));
  check(!SamePath(L"C:\\Player", L"C:\\Player2"));
  check(!SamePath(L"C:\\Player", L"D:\\Player"));
  for (const auto* action : {"showMain", "toggle", "previous", "next", "showMini"}) {
    check(IsAction(action));
    check(StartupAction({std::string("--shell-action=") + action}) == action);
  }
  for (const auto* action : {"exit", "uninstall", "toggle --delete", "", "next\n"}) {
    check(!IsAction(action));
    check(StartupAction({std::string("--shell-action=") + action}) == "showMain");
  }
  check(StartupAction({}) == "showMain");
  check(IsUninstallerName(L"unins000.exe"));
  check(IsUninstallerName(L"unins999.exe"));
  for (const auto* name : {L"unins000.exe /silent", L"..\\unins000.exe",
                         L"unins00.exe", L"unins000.cmd", L"uninsabc.exe"}) {
    check(!IsUninstallerName(name));
  }
  std::cout << checks << " Windows shell policy checks passed\n";
}
