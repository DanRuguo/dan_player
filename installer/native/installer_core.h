#pragma once

#include <windows.h>

#include <cstdint>
#include <filesystem>
#include <functional>
#include <string>
#include <vector>

namespace dan::installer {
namespace fs = std::filesystem;

inline constexpr wchar_t kProductId[] = L"DanRuguo.DanPlayer";
inline constexpr wchar_t kRegistryKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\"
    L"DanRuguo.DanPlayer_is1";
inline constexpr wchar_t kInstalledManifest[] =
    L".dan-player-install\\payload.manifest";

struct PayloadFile {
  fs::path relative_path;
  std::string sha256;
  uint64_t size = 0;
};

struct Manifest {
  std::string version;
  std::vector<PayloadFile> files;
};

struct RegistryValue {
  std::wstring name;
  uint32_t type = 0;
  std::vector<uint8_t> data;
};

struct RegistrySnapshot {
  bool existed = false;
  std::vector<RegistryValue> values;
};

// Tests use an in-memory implementation; only the bridge knows the HKCU key.
class RegistryStore {
 public:
  virtual ~RegistryStore() = default;
  virtual RegistrySnapshot Read() = 0;
  virtual void Restore(const RegistrySnapshot& snapshot) = 0;
};

struct Context {
  fs::path target;
  fs::path desktop_link;
  fs::path start_menu_link;
  // Production supplies known Windows folders, tests supply their sandbox.
  std::vector<fs::path> forbidden_roots;
};

struct BackupRecord {
  fs::path destination;
  bool existed = false;
  std::string original_hash;
  std::string expected_hash;
  DWORD original_attributes = FILE_ATTRIBUTE_NORMAL;
};

using FaultInjector = std::function<void(const char*, size_t)>;

std::string ToUtf8(const std::wstring& text);
std::wstring FromUtf8(const std::string& text);
std::string Sha256(const fs::path& file);
// Reads the already-validated handle, without reopening a raceable path.
std::string Sha256Handle(HANDLE file);
Manifest ReadManifest(const fs::path& path);
std::string SerializeManifest(const Manifest& manifest);
bool IsSafeRelativePath(const fs::path& path);
bool IsWithin(const fs::path& path, const fs::path& directory);
fs::path CanonicalPath(const fs::path& path);
void CheckNoReparsePoints(const fs::path& path);
void ValidateTarget(const Context& context);
bool IsRecognizedInstallation(const fs::path& target);
int CompareVersions(const std::string& left, const std::string& right);

// No user edit is ever overwritten by a late discovery or a parent picker.
class DestinationSelection {
 public:
  explicit DestinationSelection(std::wstring version);
  void ChooseParent(const fs::path& parent, const fs::path& verified_old = {});
  void DiscoverPrevious(const fs::path& verified_old);
  void EditFinal(const fs::path& path);
  const fs::path& value() const { return value_; }
  bool manually_edited() const { return manually_edited_; }

 private:
  std::wstring version_;
  fs::path value_;
  bool manually_edited_ = false;
};

struct LogoFrame {
  double rce = 0;
  double danruguo = 0;
  bool finished = false;
};
LogoFrame EvaluateLogoFrame(uint64_t elapsed_ms, bool reduce_motion);

// The engine never extracts archives. Inno writes its embedded [Files] entries
// between Begin and Commit; this journal is the explicit rollback supplement.
// Temporary backups support failure recovery and are removed after success.
class Transaction {
 public:
  Transaction(Context context, RegistryStore& registry,
              FaultInjector inject = {});
  ~Transaction();
  Transaction(const Transaction&) = delete;
  Transaction& operator=(const Transaction&) = delete;
  void Begin(const Manifest& payload, const fs::path& manifest_source);
  void VerifyInstalled(const Manifest& payload, const fs::path& manifest_source);
  void RecordWritten(const fs::path& file);
  void Commit(const Manifest& payload, const fs::path& manifest_source);
  void Rollback();
  bool HasPendingRecovery() const;
  bool pending() const { return pending_; }
  const fs::path& backup_directory() const { return backup_directory_; }

 private:
  void CheckDestination(const fs::path& path) const;
  void LoadJournal();
  void CleanupCompletedBackup();
  void WriteJournal();
  void WriteState(const std::string& state);
  void Inject(const char* stage, size_t index) const;
  Context context_;
  RegistryStore& registry_;
  FaultInjector inject_;
  fs::path backup_directory_;
  std::vector<BackupRecord> records_;
  std::vector<fs::path> new_directories_;
  RegistrySnapshot registry_before_;
  bool pending_ = false;
  HANDLE target_lock_ = nullptr;
};
}  // namespace dan::installer
