#include "installer_core.h"

#include <bcrypt.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <map>
#include <memory>
#include <regex>
#include <set>
#include <sstream>
#include <stdexcept>

namespace dan::installer {
namespace {
constexpr size_t kMaximumEntries = 20000;
constexpr uint64_t kMaximumBytes = 8ULL * 1024 * 1024 * 1024;
constexpr size_t kMaximumJournal = 8 * 1024 * 1024;

struct FileHandle {
  HANDLE value = INVALID_HANDLE_VALUE;
  ~FileHandle() { if (value != INVALID_HANDLE_VALUE) CloseHandle(value); }
};

[[noreturn]] void Fail(const std::string& message) {
  throw std::runtime_error(message);
}
void CheckSingleFile(HANDLE handle) {
  BY_HANDLE_FILE_INFORMATION info{};
  if (!GetFileInformationByHandle(handle, &info) || info.nNumberOfLinks != 1 ||
      (info.dwFileAttributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY)))
    Fail("A managed file must be a single-link regular file");
}
std::wstring Lower(std::wstring value) {
  std::transform(value.begin(), value.end(), value.begin(), towlower);
  return value;
}
bool SamePath(const fs::path& left, const fs::path& right) {
  return Lower(left.lexically_normal().wstring()) ==
         Lower(right.lexically_normal().wstring());
}
bool ValidHash(const std::string& value) {
  return value.size() == 64 && std::all_of(value.begin(), value.end(), [](char c) {
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
  });
}
std::string Hex(const std::string& value) {
  constexpr char digits[] = "0123456789abcdef";
  std::string result;
  for (unsigned char c : value) {
    result += digits[c >> 4];
    result += digits[c & 15];
  }
  return result.empty() ? "-" : result;
}
std::string Unhex(const std::string& value) {
  if (value == "-") return {};
  if (value.size() % 2 || value.size() > kMaximumJournal) Fail("Invalid journal encoding");
  auto digit = [](char c) -> unsigned char {
    if (c >= '0' && c <= '9') return static_cast<unsigned char>(c - '0');
    if (c >= 'a' && c <= 'f') return static_cast<unsigned char>(c - 'a' + 10);
    Fail("Invalid journal encoding");
  };
  std::string result;
  for (size_t i = 0; i < value.size(); i += 2) {
    result += static_cast<char>((digit(value[i]) << 4) | digit(value[i + 1]));
  }
  return result;
}
std::string ReadBounded(const fs::path& path, size_t maximum) {
  CheckNoReparsePoints(path);
  if (!fs::is_regular_file(path) || fs::file_size(path) > maximum) Fail("Invalid bounded input");
  std::ifstream stream(path, std::ios::binary);
  if (!stream) Fail("Cannot read input");
  std::string text((std::istreambuf_iterator<char>(stream)), {});
  if (!stream.eof() && stream.fail()) Fail("Cannot finish reading input");
  return text;
}
void WriteDurable(const fs::path& path, const std::string& text,
                  bool replace = false) {
  CheckNoReparsePoints(path);
  FileHandle file{CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr,
                            replace ? OPEN_ALWAYS : CREATE_NEW,
                            FILE_ATTRIBUTE_NORMAL | FILE_FLAG_WRITE_THROUGH | FILE_FLAG_OPEN_REPARSE_POINT,
                            nullptr)};
  if (file.value == INVALID_HANDLE_VALUE) Fail("Cannot create transaction journal");
  CheckSingleFile(file.value);
  DWORD written = 0;
  const bool ok = text.size() <= MAXDWORD &&
      WriteFile(file.value, text.data(), static_cast<DWORD>(text.size()), &written,
                nullptr) && written == text.size() && SetEndOfFile(file.value) && FlushFileBuffers(file.value);
  if (!ok) Fail("Cannot persist transaction journal");
}
void CopyVerified(const fs::path& source, const fs::path& destination,
                  const std::string& expected_hash, bool replace) {
  CheckNoReparsePoints(source);
  CheckNoReparsePoints(destination);
  fs::create_directories(destination.parent_path());
  CheckNoReparsePoints(destination.parent_path());
  FileHandle input{CreateFileW(source.c_str(), GENERIC_READ, FILE_SHARE_READ,
      nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr)};
  FileHandle output{CreateFileW(destination.c_str(), GENERIC_READ | GENERIC_WRITE, 0,
      nullptr, replace ? OPEN_ALWAYS : CREATE_NEW,
      FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_WRITE_THROUGH, nullptr)};
  if (input.value == INVALID_HANDLE_VALUE || output.value == INVALID_HANDLE_VALUE)
    Fail("Cannot open bounded backup/restore files");
  CheckSingleFile(input.value); CheckSingleFile(output.value);
  if (Sha256Handle(input.value) != expected_hash) Fail("Backup source changed before copy");
  LARGE_INTEGER beginning{};
  if (!SetFilePointerEx(input.value, beginning, nullptr, FILE_BEGIN)) Fail("Cannot rewind backup");
  std::array<char, 65536> buffer{};
  DWORD read = 0;
  for (;;) {
    if (!ReadFile(input.value, buffer.data(), static_cast<DWORD>(buffer.size()), &read, nullptr)) Fail("Cannot read backup");
    if (!read) break;
    DWORD written = 0;
    if (!WriteFile(output.value, buffer.data(), read, &written, nullptr) || written != read) Fail("Cannot write recovery file");
  }
  if (!SetEndOfFile(output.value) || !FlushFileBuffers(output.value) ||
      Sha256Handle(output.value) != expected_hash) Fail("Backup/restore hash mismatch");
}
std::vector<std::string> Split(const std::string& value, char delimiter) {
  std::vector<std::string> parts;
  std::istringstream input(value);
  std::string part;
  while (std::getline(input, part, delimiter)) parts.push_back(part);
  return parts;
}
std::string ReadState(const fs::path& directory) {
  const fs::path file = directory / L"state";
  return fs::exists(file) ? ReadBounded(file, 40) : "preparing";
}
bool IsPrivateMetadata(const fs::path& relative) {
  const auto name = Lower(relative.generic_wstring());
  return name == L".dan-player-install/payload.manifest" ||
         name == L".dan-player-install/unins000.exe" ||
         name == L".dan-player-install/unins000.dat" ||
         name == L".dan-player-install/unins000.msg";
}
bool IsPayloadNamespace(const fs::path& relative) {
  if (!IsSafeRelativePath(relative)) return false;
  const auto first = Lower(relative.begin()->wstring());
  const auto extension = Lower(relative.extension().wstring());
  if (extension == L".mp3" || extension == L".flac" || extension == L".wav" ||
      extension == L".m4a" || extension == L".ogg" || extension == L".lrc") return false;
  if (first == L"data" || first == L"desktop_lyric" || first == L"bass" ||
      first == L"licenses") return true;
  if (first == L".dan-player-install") {
    return IsPrivateMetadata(relative) ||
           Lower(relative.filename().wstring()) == L"cleanup.exe";
  }
  if (relative.has_parent_path()) return false;
  return extension == L".dll" || first == L"dan player.exe" ||
         first == L"license" || first == L"sha256sums" ||
         first == L"build-provenance.json" || first == L"font-integrity.json" ||
         first == L"native_assets.json" ||
         first == L"portable-readme.txt" || first == L"desktop-experience.md" ||
         first == L"validation.md" || first == L"playlist-migration.md" ||
         first == L"font-integrity.md" || first == L"classification.md" ||
         first == L"classification-readonly-qa.md" || first == L"taskbar-lyrics.md" ||
         first == L"interaction-fixes.md" || first == L"owned-lyric-window.md" ||
         first == L"lyric-motion.md" || first == L"ui-polish-26.0.3.md" ||
         first == L"lyric-emphasis-spectrum-notes.md" || first == L"online-sources.md" ||
         first == L"song-comments-notes.md" || first == L"settings-backgrounds.md" ||
         first == L"lyric-experience.md";
}
uint64_t Number(const std::string& value) {
  if (value.empty() || !std::all_of(value.begin(), value.end(), ::isdigit)) Fail("Invalid numeric field");
  size_t used = 0;
  uint64_t number = 0;
  try { number = std::stoull(value, &used); } catch (...) { Fail("Numeric field overflow"); }
  if (used != value.size()) Fail("Invalid numeric field");
  return number;
}
struct Version {
  std::array<uint64_t, 3> number{};
  std::vector<std::string> pre;
};
Version ParseVersion(const std::string& text) {
  const std::regex pattern(R"(^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$)");
  std::smatch match;
  if (text.size() > 128 || !std::regex_match(text, match, pattern)) Fail("Invalid semantic version");
  Version result;
  for (size_t i = 0; i < 3; ++i) result.number[i] = Number(match[i + 1]);
  if (match[4].matched) {
    if (match[4].str().back() == '.') Fail("Invalid prerelease version");
    result.pre = Split(match[4], '.');
    for (const auto& part : result.pre) {
      if (part.empty()) Fail("Invalid prerelease version");
      const bool numeric = std::all_of(part.begin(), part.end(), ::isdigit);
      if (numeric && part.size() > 1 && part.front() == '0') Fail("Invalid prerelease version");
    }
  }
  return result;
}
Manifest ReadPortableManifest(const fs::path& target) {
  const auto provenance = ReadBounded(target / L"BUILD-PROVENANCE.json", 1024 * 1024);
  if (!std::regex_search(provenance, std::regex(R"("Product"\s*:\s*"Dan Player")")) ||
      provenance.find("https://github.com/DanRuguo/dan_player") == std::string::npos)
    Fail("Portable product identity is missing");
  std::smatch version;
  if (!std::regex_search(provenance, version, std::regex(R"re("Version"\s*:\s*"([^"]+)")re")))
    Fail("Portable version is missing");
  Manifest result; result.version = version[1]; ParseVersion(result.version);
  std::istringstream lines(ReadBounded(target / L"SHA256SUMS", kMaximumJournal));
  std::set<std::wstring> unique;
  std::string line;
  while (std::getline(lines, line)) {
    if (!line.empty() && line.back() == '\r') line.pop_back();
    if (line.size() < 67 || line.substr(64, 2) != "  " || !ValidHash(line.substr(0, 64)))
      Fail("Invalid portable checksum record");
    const fs::path relative = FromUtf8(line.substr(66));
    if (!IsPayloadNamespace(relative) || !unique.insert(Lower(relative.generic_wstring())).second ||
        unique.size() > kMaximumEntries) Fail("Invalid portable checksum path");
    const auto file = target / relative;
    // A modified optional old file is not owned for retirement. Critical player
    // identity must match below; unknown side-by-side files remain untouched.
    if (fs::is_regular_file(file) && Sha256(file) == line.substr(0, 64))
      result.files.push_back({relative, line.substr(0, 64), fs::file_size(file)});
  }
  for (const auto* critical : {L"Dan Player.exe", L"data/app.so", L"desktop_lyric/desktop_lyric.exe"}) {
    if (std::none_of(result.files.begin(), result.files.end(), [&](const auto& f) {
          return Lower(f.relative_path.generic_wstring()) == Lower(critical);
        })) Fail("Portable player identity checksum does not match");
  }
  return result;
}
}  // namespace

std::string ToUtf8(const std::wstring& text) {
  if (text.empty()) return {};
  int length = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text.data(),
      static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
  if (length <= 0) Fail("Invalid Unicode path");
  std::string result(length, '\0');
  WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text.data(),
      static_cast<int>(text.size()), result.data(), length, nullptr, nullptr);
  return result;
}
std::wstring FromUtf8(const std::string& text) {
  if (text.empty()) return {};
  int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
      static_cast<int>(text.size()), nullptr, 0);
  if (length <= 0) Fail("Invalid UTF-8 input");
  std::wstring result(length, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
      static_cast<int>(text.size()), result.data(), length);
  return result;
}
std::string Sha256(const fs::path& path) {
  CheckNoReparsePoints(path);
  FileHandle file{CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
      OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr)};
  if (file.value == INVALID_HANDLE_VALUE) Fail("Cannot open file for SHA256");
  return Sha256Handle(file.value);
}
std::string Sha256Handle(HANDLE file) {
  CheckSingleFile(file);
  LARGE_INTEGER beginning{};
  if (!SetFilePointerEx(file, beginning, nullptr, FILE_BEGIN)) Fail("Cannot rewind file for SHA256");
  BCRYPT_ALG_HANDLE algorithm = nullptr;
  BCRYPT_HASH_HANDLE hash = nullptr;
  if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM,
                                  nullptr, 0) < 0) Fail("SHA256 unavailable");
  struct Cleanup {
    BCRYPT_ALG_HANDLE& algorithm;
    BCRYPT_HASH_HANDLE& hash;
    ~Cleanup() {
      if (hash) BCryptDestroyHash(hash);
      if (algorithm) BCryptCloseAlgorithmProvider(algorithm, 0);
    }
  } cleanup{algorithm, hash};
  if (BCryptCreateHash(algorithm, &hash, nullptr, 0, nullptr, 0, 0) < 0) Fail("Cannot initialize SHA256");
  std::array<char, 65536> buffer{};
  for (;;) {
    DWORD count = 0;
    if (!ReadFile(file, buffer.data(), static_cast<DWORD>(buffer.size()), &count, nullptr)) Fail("Cannot read file for SHA256");
    if (!count) break;
    if (BCryptHashData(hash,
        reinterpret_cast<PUCHAR>(buffer.data()),
        count, 0) < 0) Fail("Cannot compute SHA256");
  }
  std::array<unsigned char, 32> digest{};
  if (BCryptFinishHash(hash, digest.data(), static_cast<ULONG>(digest.size()), 0) < 0) Fail("Cannot finish SHA256");
  return Hex(std::string(reinterpret_cast<char*>(digest.data()), digest.size()));
}

bool IsSafeRelativePath(const fs::path& path) {
  const auto text = path.wstring();
  if (text.empty() || text.size() > 220 || path.is_absolute() || path.has_root_name() || path.has_root_directory()) return false;
  for (wchar_t c : text) if (c < 32 || c == L':' || c == L'*' || c == L'?' || c == L'"' || c == L'|' || c == L'<' || c == L'>') return false;
  for (const auto& component : path) {
    const auto value = component.wstring();
    if (value.empty() || value == L"." || value == L".." ||
        value.back() == L'.' || value.back() == L' ') return false;
    const auto base = Lower(component.stem().wstring());
    if (base == L"con" || base == L"prn" || base == L"aux" || base == L"nul" ||
        (base.size() == 4 && (base.substr(0, 3) == L"com" || base.substr(0, 3) == L"lpt") &&
         base[3] >= L'0' && base[3] <= L'9')) return false;
  }
  return true;
}
fs::path CanonicalPath(const fs::path& path) {
  const auto text = path.wstring();
  if (!path.is_absolute() || text.size() < 4 || text.size() > 240 ||
      text[1] != L':' || text[0] == L'\\' ||
      !IsSafeRelativePath(path.relative_path())) Fail("Choose an absolute local, non-root path");
  return path.lexically_normal();
}
bool IsWithin(const fs::path& path, const fs::path& directory) {
  const auto value = Lower(path.lexically_normal().wstring());
  auto prefix = Lower(directory.lexically_normal().wstring());
  while (!prefix.empty() && (prefix.back() == L'\\' || prefix.back() == L'/')) prefix.pop_back();
  return value.size() > prefix.size() && value.compare(0, prefix.size(), prefix) == 0 &&
         (value[prefix.size()] == L'\\' || value[prefix.size()] == L'/');
}
void CheckNoReparsePoints(const fs::path& path) {
  fs::path current;
  for (const auto& component : path) {
    current /= component;
    const DWORD attributes = GetFileAttributesW(current.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES) {
      const DWORD error = GetLastError();
      if (error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND ||
          current == path.root_name()) continue;
      Fail("Cannot inspect destination path");
    }
    if (attributes & FILE_ATTRIBUTE_REPARSE_POINT) Fail("Symlinks and junctions are not installation targets");
    if (!(attributes & FILE_ATTRIBUTE_DIRECTORY)) {
      FileHandle file{CreateFileW(current.c_str(), FILE_READ_ATTRIBUTES,
          FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
          OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr)};
      if (file.value == INVALID_HANDLE_VALUE) Fail("Cannot inspect file identity");
      CheckSingleFile(file.value);
    }
  }
}
void ValidateTarget(const Context& context) {
  const auto target = CanonicalPath(context.target);
  CheckNoReparsePoints(target);
  for (const auto& forbidden : context.forbidden_roots) {
    if (!forbidden.empty() && (SamePath(target, forbidden) || IsWithin(target, forbidden))) Fail("Protected system or user-data directory");
  }
  if (fs::exists(target) && !fs::is_directory(target)) Fail("Destination is not a directory");
  if (fs::exists(target) && !fs::is_empty(target) && !IsRecognizedInstallation(target)) {
    Fail("Non-empty destination is not a verified Dan Player installation");
  }
}
bool IsRecognizedInstallation(const fs::path& target) {
  try {
    CheckNoReparsePoints(target);
    if (!fs::is_regular_file(target / L"Dan Player.exe")) return false;
    const auto installed = target / kInstalledManifest;
    if (fs::exists(installed)) {
      const auto manifest = ReadManifest(installed);
      return std::any_of(manifest.files.begin(), manifest.files.end(), [&](const auto& f) {
        return Lower(f.relative_path.wstring()) == L"dan player.exe" &&
            Sha256(target / f.relative_path) == f.sha256;
      });
    }
    // Portable releases produced by the existing audited assembler.
    ReadPortableManifest(target);
    return true;
  } catch (...) { return false; }
}
Manifest ReadManifest(const fs::path& path) {
  std::istringstream input(ReadBounded(path, kMaximumJournal));
  std::string line;
  if (!std::getline(input, line) || line != "DANPLAYER_PAYLOAD_V1") Fail("Invalid payload manifest header");
  Manifest result;
  if (!std::getline(input, result.version)) Fail("Missing payload version");
  ParseVersion(result.version);
  std::set<std::wstring> unique;
  uint64_t total = 0;
  while (std::getline(input, line)) {
    if (line.empty()) continue;
    const auto parts = Split(line, '\t');
    if (parts.size() != 3 || !ValidHash(parts[0])) Fail("Invalid payload record");
    PayloadFile file{fs::path(FromUtf8(parts[2])), parts[0], Number(parts[1])};
    if (!IsPayloadNamespace(file.relative_path) ||
        !unique.insert(Lower(file.relative_path.generic_wstring())).second ||
        result.files.size() >= kMaximumEntries || file.size > kMaximumBytes - total) {
      Fail("Unsafe, duplicated, or oversized payload record");
    }
    total += file.size;
    result.files.push_back(std::move(file));
  }
  if (result.files.empty()) Fail("Empty payload");
  return result;
}
std::string SerializeManifest(const Manifest& manifest) {
  ParseVersion(manifest.version);
  std::ostringstream text;
  text << "DANPLAYER_PAYLOAD_V1\n" << manifest.version << '\n';
  for (const auto& file : manifest.files) {
    if (!IsPayloadNamespace(file.relative_path) || !ValidHash(file.sha256)) Fail("Invalid manifest output");
    text << file.sha256 << '\t' << file.size << '\t'
         << ToUtf8(file.relative_path.generic_wstring()) << '\n';
  }
  return text.str();
}
int CompareVersions(const std::string& left, const std::string& right) {
  const auto a = ParseVersion(left), b = ParseVersion(right);
  if (a.number != b.number) return a.number < b.number ? -1 : 1;
  if (a.pre.empty() != b.pre.empty()) return a.pre.empty() ? 1 : -1;
  for (size_t i = 0; i < (std::min)(a.pre.size(), b.pre.size()); ++i) {
    if (a.pre[i] == b.pre[i]) continue;
    const bool an = std::all_of(a.pre[i].begin(), a.pre[i].end(), ::isdigit);
    const bool bn = std::all_of(b.pre[i].begin(), b.pre[i].end(), ::isdigit);
    if (an && bn) return Number(a.pre[i]) < Number(b.pre[i]) ? -1 : 1;
    if (an != bn) return an ? -1 : 1;
    return a.pre[i] < b.pre[i] ? -1 : 1;
  }
  return a.pre.size() == b.pre.size() ? 0 : a.pre.size() < b.pre.size() ? -1 : 1;
}
DestinationSelection::DestinationSelection(std::wstring version) : version_(std::move(version)) {
  ParseVersion(ToUtf8(version_));
}
void DestinationSelection::ChooseParent(const fs::path& parent, const fs::path& old) {
  if (!manually_edited_) value_ = old.empty() ? parent / (L"danplayer_" + version_) : old;
}
void DestinationSelection::DiscoverPrevious(const fs::path& old) {
  if (!manually_edited_ && !old.empty()) value_ = old;
}
void DestinationSelection::EditFinal(const fs::path& path) {
  manually_edited_ = true;
  value_ = path;
}
LogoFrame EvaluateLogoFrame(uint64_t elapsed_ms, bool reduce_motion) {
  if (elapsed_ms >= 1600) return {0, 0, true};
  if (reduce_motion) return elapsed_ms < 800 ? LogoFrame{1, 0, false} : LogoFrame{0, 1, false};
  const double position = std::clamp((static_cast<double>(elapsed_ms) - 680.0) / 240.0, 0.0, 1.0);
  const double eased = position * position * (3.0 - 2.0 * position);
  const double fade_in = std::clamp(static_cast<double>(elapsed_ms) / 100.0, 0.0, 1.0);
  const double fade_out = std::clamp((1600.0 - static_cast<double>(elapsed_ms)) / 100.0, 0.0, 1.0);
  return {(1.0 - eased) * fade_in, eased * fade_out, false};
}

Transaction::Transaction(Context context, RegistryStore& registry, FaultInjector inject)
    : context_(std::move(context)), registry_(registry), inject_(std::move(inject)) {
  context_.target = CanonicalPath(context_.target);
  // A product-specific sibling, never the install root or a user-wide temp tree.
  backup_directory_ = context_.target.parent_path() /
      (L"." + context_.target.filename().wstring() + L".danplayer-recovery");
  // Independent of SetupMutex/session/version: one live owner per exact local
  // destination. A collision is fail-closed, never permission to recover it.
  uint64_t identity = 14695981039346656037ULL;
  for (const auto c : Lower(context_.target.wstring())) {
    identity ^= static_cast<uint16_t>(c); identity *= 1099511628211ULL;
  }
  const auto name = L"Global\\DanPlayerInstallerTarget-" + std::to_wstring(identity);
  target_lock_ = CreateMutexW(nullptr, FALSE, name.c_str());
  if (!target_lock_) Fail("Cannot acquire destination installation lock");
  const auto wait = WaitForSingleObject(target_lock_, 0);
  if (wait != WAIT_OBJECT_0 && wait != WAIT_ABANDONED) {
    CloseHandle(target_lock_); target_lock_ = nullptr;
    Fail("Another installer is still using this destination; close it and retry");
  }
}
Transaction::~Transaction() {
  if (target_lock_) { ReleaseMutex(target_lock_); CloseHandle(target_lock_); }
}
void Transaction::Inject(const char* stage, size_t index) const {
  if (inject_) inject_(stage, index);
}
void Transaction::CheckDestination(const fs::path& path) const {
  const auto absolute = CanonicalPath(path);
  const bool shortcut = (!context_.desktop_link.empty() && SamePath(absolute, context_.desktop_link)) ||
                        (!context_.start_menu_link.empty() && SamePath(absolute, context_.start_menu_link));
  if (!shortcut && (!IsWithin(absolute, context_.target) ||
      !IsPayloadNamespace(absolute.lexically_relative(context_.target)))) Fail("Journal destination escapes product boundary");
  CheckNoReparsePoints(absolute);
}
void Transaction::WriteState(const std::string& state) {
  const auto temporary = backup_directory_ / L"state.next";
  WriteDurable(temporary, state, true);
  if (!MoveFileExW(temporary.c_str(), (backup_directory_ / L"state").c_str(),
                    MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) Fail("Cannot commit journal state");
}
bool Transaction::HasPendingRecovery() const {
  if (!fs::exists(backup_directory_)) return false;
  CheckNoReparsePoints(backup_directory_);
  const auto state = ReadState(backup_directory_);
  return state == "prepared" || state == "restoring";
}
void Transaction::Begin(const Manifest& payload, const fs::path& manifest_source) {
  if (pending_) Fail("Transaction already active");
  ValidateTarget(context_);
  // Reparse/duplicate/budget validation is shared with persisted manifests.
  const auto checked = ReadManifest(manifest_source);
  if (SerializeManifest(checked) != SerializeManifest(payload)) Fail("Payload changed before installation");
  if (HasPendingRecovery()) Fail("A previous installation needs recovery before proceeding");
  if (fs::exists(backup_directory_)) {
    const auto owner = ReadBounded(backup_directory_ / L"owner", 2048);
    if (owner != ToUtf8(context_.target.wstring())) Fail("Unrecognized recovery directory");
    const auto archive = fs::path(backup_directory_.wstring() + L".retained-" +
        std::to_wstring(GetTickCount64()) + L"-" + std::to_wstring(GetCurrentProcessId()));
    if (fs::exists(archive) || !MoveFileW(backup_directory_.c_str(), archive.c_str())) Fail("Cannot retain previous backup safely");
  }
  fs::create_directories(backup_directory_ / L"files");
  CheckNoReparsePoints(backup_directory_);
  WriteDurable(backup_directory_ / L"owner", ToUtf8(context_.target.wstring()));
  WriteState("preparing");
  records_.clear();
  new_directories_.clear();
  std::map<std::wstring, fs::path> destinations;
  for (const auto& file : payload.files) destinations.emplace(Lower(file.relative_path.generic_wstring()), context_.target / file.relative_path);
  const auto installed_manifest = context_.target / kInstalledManifest;
  if (fs::exists(installed_manifest) || fs::exists(context_.target / L"BUILD-PROVENANCE.json")) {
    const auto previous = fs::exists(installed_manifest) ? ReadManifest(installed_manifest) : ReadPortableManifest(context_.target);
    if (CompareVersions(payload.version, previous.version) < 0) Fail("A newer version is already installed");
    for (const auto& file : previous.files) {
      // Unknown or user-modified obsolete files remain untouched.
      const auto old_path = context_.target / file.relative_path;
      if (fs::is_regular_file(old_path) && Sha256(old_path) == file.sha256) {
        destinations.emplace(Lower(file.relative_path.generic_wstring()), old_path);
      }
    }
  }
  for (const auto* name : {kInstalledManifest,
       L".dan-player-install\\unins000.exe", L".dan-player-install\\unins000.dat",
       L".dan-player-install\\unins000.msg"}) {
    destinations.emplace(Lower(name), context_.target / name);
  }
  if (!context_.desktop_link.empty()) destinations.emplace(L"!desktop", context_.desktop_link);
  if (!context_.start_menu_link.empty()) destinations.emplace(L"!startmenu", context_.start_menu_link);
  registry_before_ = registry_.Read();
  std::set<std::wstring> new_directories;
  for (const auto& pair : destinations) {
    for (auto directory = pair.second.parent_path();
         IsWithin(directory, context_.target) || SamePath(directory, context_.target);
         directory = directory.parent_path()) {
      if (!fs::exists(directory)) new_directories.insert(directory.wstring());
    }
  }
  for (const auto& directory : new_directories) new_directories_.emplace_back(directory);
  uint64_t cost = 0;
  for (const auto& pair : destinations) {
    const auto& destination = pair.second;
    CheckDestination(destination);
    const DWORD attributes = GetFileAttributesW(destination.c_str());
    const bool existed = attributes != INVALID_FILE_ATTRIBUTES;
    if (existed && (attributes & FILE_ATTRIBUTE_DIRECTORY)) Fail("A directory occupies a managed file path");
    if (existed) {
      const uint64_t size = fs::file_size(destination);
      if (size > kMaximumBytes - cost) Fail("Backup exceeds safety budget");
      cost += size;
    }
  }
  uint64_t payload_bytes = 0;
  for (const auto& file : payload.files) payload_bytes += file.size;
  ULARGE_INTEGER available{};
  if (!GetDiskFreeSpaceExW(backup_directory_.c_str(), &available, nullptr, nullptr) ||
      available.QuadPart < cost + payload_bytes + 16 * 1024 * 1024) Fail("Insufficient space for installation and rollback");
  for (const auto& pair : destinations) {
    const auto& destination = pair.second;
    CheckDestination(destination);
    BackupRecord record;
    record.destination = destination;
    for (const auto& file : payload.files) {
      if (SamePath(destination, context_.target / file.relative_path)) record.expected_hash = file.sha256;
    }
    if (SamePath(destination, installed_manifest)) record.expected_hash = Sha256(manifest_source);
    record.original_attributes = GetFileAttributesW(destination.c_str());
    record.existed = record.original_attributes != INVALID_FILE_ATTRIBUTES;
    if (record.existed) {
      // No force-close or restart-replace. Locks fail before any installation.
      HANDLE probe = CreateFileW(destination.c_str(), GENERIC_READ | GENERIC_WRITE | DELETE,
                                FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
      if (probe == INVALID_HANDLE_VALUE) Fail("A managed file is in use or not writable; close Dan Player and retry");
      CloseHandle(probe);
      record.original_hash = Sha256(destination);
      CopyVerified(destination, backup_directory_ / L"files" /
          std::to_wstring(records_.size()), record.original_hash, false);
    }
    records_.push_back(record);
    Inject("backup", records_.size() - 1);
  }
  WriteJournal();
  WriteState("prepared");
  pending_ = true;
}
void Transaction::WriteJournal() {
  std::ostringstream journal;
  journal << "DANPLAYER_RECOVERY_V2\n" << Hex(ToUtf8(context_.target.wstring())) << '\n';
  journal << registry_before_.existed << ' ' << registry_before_.values.size() << '\n';
  for (const auto& value : registry_before_.values) {
    journal << value.type << ' ' << Hex(ToUtf8(value.name)) << ' '
            << Hex(std::string(value.data.begin(), value.data.end())) << '\n';
  }
  journal << records_.size() << '\n';
  for (const auto& record : records_) {
    journal << record.existed << ' ' << record.original_attributes << ' '
            << (record.existed ? record.original_hash : "-") << ' '
            << (record.expected_hash.empty() ? "-" : record.expected_hash) << ' '
            << Hex(ToUtf8(record.destination.wstring())) << '\n';
  }
  journal << new_directories_.size() << '\n';
  for (const auto& directory : new_directories_) journal << Hex(ToUtf8(directory.wstring())) << '\n';
  if (journal.str().size() > kMaximumJournal) Fail("Recovery journal exceeds safety budget");
  WriteDurable(backup_directory_ / L"journal", journal.str());
}
void Transaction::LoadJournal() {
  CheckNoReparsePoints(backup_directory_);
  if (ReadBounded(backup_directory_ / L"owner", 2048) != ToUtf8(context_.target.wstring())) Fail("Recovery owner mismatch");
  std::istringstream input(ReadBounded(backup_directory_ / L"journal", kMaximumJournal));
  std::string header, target;
  if (!std::getline(input, header) || header != "DANPLAYER_RECOVERY_V2" ||
      !std::getline(input, target) || FromUtf8(Unhex(target)) != context_.target.wstring()) Fail("Invalid recovery journal identity");
  size_t count = 0;
  unsigned existed = 0;
  if (!(input >> existed >> count) || existed > 1 || count > 256) Fail("Invalid registry snapshot");
  registry_before_ = {};
  registry_before_.existed = existed != 0;
  for (size_t i = 0; i < count; ++i) {
    RegistryValue value;
    std::string name, data;
    if (!(input >> value.type >> name >> data)) Fail("Invalid registry snapshot");
    value.name = FromUtf8(Unhex(name));
    const auto bytes = Unhex(data);
    value.data.assign(bytes.begin(), bytes.end());
    registry_before_.values.push_back(std::move(value));
  }
  if (!(input >> count) || count > kMaximumEntries + 8) Fail("Invalid recovery file count");
  records_.clear();
  new_directories_.clear();
  std::set<std::wstring> unique;
  for (size_t i = 0; i < count; ++i) {
    BackupRecord record;
    std::string path;
    if (!(input >> existed >> record.original_attributes >> record.original_hash >> record.expected_hash >> path) || existed > 1) Fail("Invalid recovery record");
    if (record.expected_hash == "-") record.expected_hash.clear();
    record.existed = existed != 0;
    record.destination = fs::path(FromUtf8(Unhex(path)));
    if ((record.existed && !ValidHash(record.original_hash)) ||
        (!record.expected_hash.empty() && !ValidHash(record.expected_hash)) ||
        !unique.insert(Lower(record.destination.wstring())).second) Fail("Invalid or duplicate recovery record");
    CheckDestination(record.destination);
    records_.push_back(std::move(record));
  }
  if (!(input >> count) || count > kMaximumEntries * 8) Fail("Invalid recovery directory count");
  for (size_t i = 0; i < count; ++i) {
    std::string encoded;
    if (!(input >> encoded)) Fail("Invalid recovery directory");
    const auto directory = CanonicalPath(fs::path(FromUtf8(Unhex(encoded))));
    if (!SamePath(directory, context_.target) && !IsWithin(directory, context_.target)) Fail("Recovery directory escapes target");
    CheckNoReparsePoints(directory);
    new_directories_.push_back(directory);
  }
  std::string extra;
  if (input >> extra) Fail("Unexpected recovery journal content");
  pending_ = true;
}
void Transaction::RecordWritten(const fs::path& file) {
  if (!pending_) Fail("No transaction for installed-file receipt");
  CheckDestination(file);
  for (size_t i = 0; i < records_.size(); ++i) {
    if (!SamePath(file, records_[i].destination)) continue;
    const auto digest = Sha256(file);
    if (!records_[i].expected_hash.empty() && records_[i].expected_hash != digest)
      Fail("Installed file differs from the embedded manifest");
    fs::create_directories(backup_directory_ / L"written");
    WriteDurable(backup_directory_ / L"written" / std::to_wstring(i), digest, true);
    return;
  }
  Fail("Installed-file receipt is outside the manifest");
}
void Transaction::Rollback() {
  if (!pending_) {
    if (!HasPendingRecovery()) return;
    LoadJournal();
  }
  // Validate ALL backups before writing ANY restored file.
  for (size_t i = 0; i < records_.size(); ++i) {
    CheckDestination(records_[i].destination);
    if (records_[i].existed && Sha256(backup_directory_ / L"files" /
        std::to_wstring(i)) != records_[i].original_hash) Fail("Recovery backup was changed; originals retained");
  }
  // A process interruption may be followed by unrelated edits. Preserve every
  // changed current file before restoring originals; never erase unowned new
  // bytes. Conflicts are content-addressed and retained, not silently replaced.
  std::vector<std::string> current_hashes(records_.size());
  std::vector<bool> removable(records_.size(), false);
  bool unresolved = false;
  for (size_t i = 0; i < records_.size(); ++i) {
    const auto& record = records_[i];
    if (!fs::exists(record.destination)) continue;
    auto& digest = current_hashes[i];
    digest = Sha256(record.destination);
    auto expected = record.expected_hash;
    const auto receipt = backup_directory_ / L"written" / std::to_wstring(i);
    if (expected.empty() && fs::exists(receipt)) {
      expected = ReadBounded(receipt, 64);
      if (!ValidHash(expected)) Fail("Invalid installed-file receipt");
    }
    removable[i] = !expected.empty() && digest == expected;
    if (!record.existed && !removable[i]) { unresolved = true; continue; }
    if (record.existed && digest != record.original_hash) {
      const auto conflict = backup_directory_ / L"conflicts" /
          (std::to_wstring(i) + L"-" + FromUtf8(digest));
      if (!fs::exists(conflict)) CopyVerified(record.destination, conflict, digest, false);
      else if (Sha256(conflict) != digest) Fail("Retained conflict file changed");
    }
  }
  WriteState("restoring");
  for (size_t i = 0; i < records_.size(); ++i) {
    const auto& record = records_[i];
    CheckDestination(record.destination);
    Inject("restore", i);
    if (fs::exists(record.destination) && Sha256(record.destination) != current_hashes[i])
      Fail("Destination changed during recovery; backups retained");
    if (record.existed) {
      if (fs::exists(record.destination) && !SetFileAttributesW(record.destination.c_str(), FILE_ATTRIBUTE_NORMAL)) Fail("Cannot prepare rollback destination");
      CopyVerified(backup_directory_ / L"files" / std::to_wstring(i),
                   record.destination, record.original_hash, true);
      if (!SetFileAttributesW(record.destination.c_str(), record.original_attributes)) Fail("Cannot restore original attributes");
    } else if (fs::exists(record.destination) && removable[i]) {
      if (!fs::is_regular_file(record.destination) || !DeleteFileW(record.destination.c_str())) Fail("Cannot remove partial new managed file");
    }
  }
  registry_.Restore(registry_before_);
  if (unresolved) Fail("Unknown new files were preserved in place; move them aside before retrying recovery");
  std::sort(new_directories_.begin(), new_directories_.end(), [](const auto& a, const auto& b) {
    return a.wstring().size() > b.wstring().size();
  });
  for (const auto& directory : new_directories_) {
    CheckNoReparsePoints(directory);
    // Never recursively remove a directory, including one created by Setup.
    if (fs::is_directory(directory) && fs::is_empty(directory) && !RemoveDirectoryW(directory.c_str())) Fail("Cannot remove empty installation directory");
  }
  WriteState("restored");
  pending_ = false;
}
void Transaction::VerifyInstalled(const Manifest& payload, const fs::path& manifest_source) {
  if (!pending_) Fail("No installation transaction to commit");
  for (size_t i = 0; i < payload.files.size(); ++i) {
    const auto& file = payload.files[i];
    const auto destination = context_.target / file.relative_path;
    CheckDestination(destination);
    Inject("verify", i);
    if (!fs::is_regular_file(destination) || fs::file_size(destination) != file.size ||
        Sha256(destination) != file.sha256) Fail("Installed payload verification failed; rollback required");
  }
  const auto installed_manifest = context_.target / kInstalledManifest;
  if (!fs::is_regular_file(installed_manifest) || Sha256(installed_manifest) != Sha256(manifest_source)) Fail("Installed manifest verification failed");
  // Retire only unmodified obsolete files from the previous owned manifest.
  std::set<std::wstring> retained;
  for (const auto& file : payload.files) retained.insert(Lower((context_.target / file.relative_path).wstring()));
  for (size_t i = 0; i < records_.size(); ++i) {
    const auto& record = records_[i];
    if (!record.existed || !IsWithin(record.destination, context_.target) ||
        retained.count(Lower(record.destination.wstring())) ||
        IsPrivateMetadata(record.destination.lexically_relative(context_.target))) continue;
    CheckDestination(record.destination);
    if (fs::is_regular_file(record.destination) && Sha256(record.destination) == record.original_hash) {
      Inject("retire", i);
      if (!DeleteFileW(record.destination.c_str())) Fail("Cannot retire old managed file; rollback required");
    }
  }
}
void Transaction::Commit(const Manifest& payload, const fs::path& manifest_source) {
  VerifyInstalled(payload, manifest_source);
  WriteState("committed");
  pending_ = false;
}
}  // namespace dan::installer
