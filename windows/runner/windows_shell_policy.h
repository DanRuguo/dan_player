#pragma once

#include <string>
#include <string_view>
#include <vector>
#include <cwctype>
#include <filesystem>

namespace windows_shell {
inline bool SamePath(const std::filesystem::path& left,
                     const std::filesystem::path& right) {
  auto normalized = [](const std::filesystem::path& path) {
    auto text = path.lexically_normal().wstring();
    while (text.size() > 3 && (text.back() == L'\\' || text.back() == L'/')) text.pop_back();
    for (auto& character : text) {
      character = character == L'/' ? L'\\' : static_cast<wchar_t>(towlower(character));
    }
    return text;
  };
  return normalized(left) == normalized(right);
}

inline bool IsAction(std::string_view action) {
  return action == "showMain" || action == "toggle" || action == "previous" ||
         action == "next" || action == "showMini";
}

inline std::string StartupAction(const std::vector<std::string>& arguments) {
  constexpr std::string_view prefix = "--shell-action=";
  for (const auto& argument : arguments) {
    if (argument.compare(0, prefix.size(), prefix) == 0) {
      const auto action = argument.substr(prefix.size());
      return IsAction(action) ? action : "showMain";
    }
  }
  return "showMain";
}

inline bool IsUninstallerName(std::wstring_view name) {
  if (name.size() != 12 || name.substr(0, 5) != L"unins" ||
      name.substr(8) != L".exe") return false;
  return name[5] >= L'0' && name[5] <= L'9' &&
         name[6] >= L'0' && name[6] <= L'9' &&
         name[7] >= L'0' && name[7] <= L'9';
}
}  // namespace windows_shell
