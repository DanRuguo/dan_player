#include "installer_core.h"

#include <fstream>
#include <iostream>
#include <map>
#include <stdexcept>
#include <thread>

using namespace dan::installer;
namespace {
void Check(bool value, const char* message) {
  if (!value) throw std::runtime_error(message);
}
template <typename Action> void Reject(Action action) {
  bool rejected = false;
  try { action(); } catch (const std::exception&) { rejected = true; }
  Check(rejected, "Unsafe operation was accepted");
}
void Write(const fs::path& file, const std::string& value) {
  fs::create_directories(file.parent_path());
  std::ofstream stream(file, std::ios::binary);
  stream << value;
  if (!stream) throw std::runtime_error("Cannot write synthetic fixture");
}
std::string Read(const fs::path& file) {
  std::ifstream stream(file, std::ios::binary);
  return std::string(std::istreambuf_iterator<char>(stream), {});
}
class MemoryRegistry final : public RegistryStore {
 public:
  RegistrySnapshot current;
  RegistrySnapshot Read() override { return current; }
  void Restore(const RegistrySnapshot& value) override { current = value; }
};
struct Fixture {
  fs::path root, payload, manifest_path;
  Context context;
  Manifest manifest;
  MemoryRegistry registry;
  explicit Fixture(const fs::path& directory) : root(directory) {
    context.target = root / L"install";
    context.desktop_link = root / L"redirect-desktop\\Dan Player.lnk";
    context.start_menu_link = root / L"redirect-start\\Dan Player.lnk";
    payload = root / L"payload";
    Write(payload / L"Dan Player.exe", "synthetic-not-an-executable-v2");
    Write(payload / L"data\\app.so", "synthetic-not-aot-v2");
    Write(payload / L"engine.dll", "synthetic-not-a-dll-v2");
    manifest.version = "26.0.4-snapshot.1";
    for (const auto* name : {L"Dan Player.exe", L"data\\app.so", L"engine.dll"}) {
      manifest.files.push_back({name, Sha256(payload / name), fs::file_size(payload / name)});
    }
    manifest_path = root / L"payload.manifest";
    Write(manifest_path, SerializeManifest(manifest));
  }
  void Old(bool portable = false) {
    Write(context.target / L"Dan Player.exe", "synthetic-original-exe-v1");
    Write(context.target / L"data\\app.so", "synthetic-original-aot-v1");
    Write(context.target / L"engine.dll", "synthetic-original-dll-v1");
    Write(context.target / L"keep-me.txt", "unrelated user file must survive");
    Write(context.desktop_link, "original shortcut bytes");
    Write(context.start_menu_link, "original start-menu shortcut bytes");
    registry.current = {true, {{L"DisplayVersion", REG_SZ, {1, 2, 3, 4}}}};
    if (portable) {
      Write(context.target / L"desktop_lyric\\desktop_lyric.exe", "synthetic helper");
      Write(context.target / L"BUILD-PROVENANCE.json", "{\"Product\":\"Dan Player\",\"SourceProject\":\"https://github.com/DanRuguo/dan_player\",\"Version\":\"26.0.3\"}");
      std::string checksums;
      for (const auto* name : {L"Dan Player.exe", L"data/app.so", L"desktop_lyric/desktop_lyric.exe", L"engine.dll"})
        checksums += Sha256(context.target / name) + "  " + ToUtf8(name) + "\r\n";
      Write(context.target / L"SHA256SUMS", checksums);
    } else {
      Manifest previous = manifest;
      previous.version = "26.0.3";
      for (auto& file : previous.files) {
        file.sha256 = Sha256(context.target / file.relative_path);
        file.size = fs::file_size(context.target / file.relative_path);
      }
      Write(context.target / kInstalledManifest, SerializeManifest(previous));
    }
  }
  void SimulateInno(Transaction& transaction) {
    for (const auto& file : manifest.files) Write(context.target / file.relative_path, Read(payload / file.relative_path));
    Write(context.target / kInstalledManifest, Read(manifest_path));
    Write(context.target / L".dan-player-install\\unins000.exe", "synthetic uninstaller");
    Write(context.target / L".dan-player-install\\unins000.dat", "synthetic uninstall log");
    Write(context.desktop_link, "new shortcut bytes");
    Write(context.start_menu_link, "new start shortcut bytes");
    registry.current = {true, {{L"DisplayVersion", REG_SZ, {5, 6}}}};
    for (const auto& file : manifest.files) transaction.RecordWritten(context.target / file.relative_path);
    for (const auto* name : {kInstalledManifest, L".dan-player-install\\unins000.exe", L".dan-player-install\\unins000.dat"})
      transaction.RecordWritten(context.target / name);
    transaction.RecordWritten(context.desktop_link);
    transaction.RecordWritten(context.start_menu_link);
  }
  void CheckOld() {
    Check(Read(context.target / L"Dan Player.exe") == "synthetic-original-exe-v1", "Original EXE not restored");
    Check(Read(context.target / L"engine.dll") == "synthetic-original-dll-v1", "Original DLL not restored");
    Check(Read(context.target / L"keep-me.txt") == "unrelated user file must survive", "Unknown file changed");
    Check(Read(context.desktop_link) == "original shortcut bytes", "Desktop shortcut not restored");
    Check(Read(context.start_menu_link) == "original start-menu shortcut bytes", "Start shortcut not restored");
    Check(registry.current.values.at(0).data == std::vector<uint8_t>({1, 2, 3, 4}), "Registration not restored");
  }
};
}  // namespace

int wmain(int argc, wchar_t** argv) {
  if (argc != 2) return 2;
  fs::path base = fs::absolute(argv[1]).lexically_normal();
  bool sandbox_named = false;
  for (const auto& part : base) if (part == L"qa-installer") sandbox_named = true;
  if (!sandbox_named || !base.is_absolute()) return 3;
  base /= L"core-" + std::to_wstring(GetTickCount64());
  fs::create_directories(base);
  size_t passed = 0, failed = 0;
  auto run = [&](const char* name, const auto& action) {
    try { action(); ++passed; std::cout << "PASS " << name << '\n'; }
    catch (const std::exception& error) { ++failed; std::cout << "FAIL " << name << ": " << error.what() << '\n'; }
  };
  run("version prerelease ordering", [] {
    Check(CompareVersions("26.0.4-snapshot.1", "26.0.4-snapshot.2") < 0, "snapshot order");
    Check(CompareVersions("26.0.4-snapshot.10", "26.0.4-snapshot.2") > 0, "numeric identifiers");
    Check(CompareVersions("26.0.4", "26.0.4-snapshot.99") > 0, "stable order");
    Check(CompareVersions("26.0.4+1", "26.0.4+20") == 0, "metadata precedence");
  });
  run("version rejects malformed inputs", [] {
    for (const auto* version : {"26.0", "26.0.4 snapshot1", "26.00.4", "26.0.4-snapshot.01", "26.0.4-a..b", "26.0.4-a."})
      Reject([&] { CompareVersions(version, "26.0.4"); });
  });
  run("parent directory appends current version", [] {
    DestinationSelection value(L"26.0.4-snapshot.1");
    value.ChooseParent(L"D:\\Apps");
    Check(value.value() == fs::path(L"D:\\Apps\\danplayer_26.0.4-snapshot.1"), "default child");
    value.ChooseParent(L"D:\\NewApps");
    Check(value.value().parent_path() == fs::path(L"D:\\NewApps"), "parent update");
  });
  run("manual final path blocks all later automatic changes", [] {
    DestinationSelection value(L"26.0.4-snapshot.1");
    value.EditFinal(L"D:\\我的播放器");
    value.DiscoverPrevious(L"D:\\Previous");
    value.ChooseParent(L"E:\\Apps", L"E:\\Old");
    Check(value.value() == fs::path(L"D:\\我的播放器") && value.manually_edited(), "manual path overwritten");
  });
  run("verified prior directory wins only before manual editing", [] {
    DestinationSelection value(L"26.0.4-snapshot.1");
    value.ChooseParent(L"D:\\Apps", L"D:\\Apps\\old-player");
    Check(value.value() == fs::path(L"D:\\Apps\\old-player"), "prior path ignored");
  });
  run("path rejects traversal devices ADS roots and UNC", [] {
    for (const auto* path : {L"..\\x", L"data\\..\\x", L"NUL", L"data\\x:stream", L"data\\CON.txt", L"data\\x.", L"data\\x ", L"C:\\x", L"\\server\\share"})
      Check(!IsSafeRelativePath(path), "unsafe relative path");
    for (const auto* path : {L"C:\\", L"relative", L"\\\\server\\share\\app", L"C:\\Apps\\..\\Windows"})
      Reject([&] { CanonicalPath(path); });
    Check(IsSafeRelativePath(L"data\\flutter_assets\\中文.ttf"), "valid Unicode rejected");
  });
  run("logo duration crossfade and reduce-motion", [] {
    Check(!EvaluateLogoFrame(1599, false).finished && EvaluateLogoFrame(1600, false).finished, "1.6 second boundary");
    const auto middle = EvaluateLogoFrame(800, false);
    Check(std::abs(middle.rce - .5) < .001 && std::abs(middle.danruguo - .5) < .001, "continuous crossfade");
    Check(EvaluateLogoFrame(799, true).rce == 1 && EvaluateLogoFrame(800, true).danruguo == 1, "reduced motion boundary");
  });
  run("new installation commits verified payload", [&] {
    Fixture f(base / L"new");
    Transaction transaction(f.context, f.registry);
    transaction.Begin(f.manifest, f.manifest_path);
    f.SimulateInno(transaction);
    transaction.Commit(f.manifest, f.manifest_path);
    Check(!transaction.pending() && fs::exists(transaction.backup_directory() / L"journal"), "commit/backup retention");
  });
  run("upgrade rollback restores files shortcuts and registration", [&] {
    Fixture f(base / L"upgrade"); f.Old();
    Transaction transaction(f.context, f.registry);
    transaction.Begin(f.manifest, f.manifest_path); f.SimulateInno(transaction);
    transaction.Rollback(); f.CheckOld();
    transaction.Rollback(); f.CheckOld();
    Check(fs::exists(transaction.backup_directory() / L"journal"), "backup removed on failure");
  });
  run("portable upgrade rollback preserves unknown files", [&] {
    Fixture f(base / L"portable"); f.Old(true);
    Transaction transaction(f.context, f.registry);
    transaction.Begin(f.manifest, f.manifest_path); f.SimulateInno(transaction);
    transaction.Rollback(); f.CheckOld();
  });
  run("process interruption recovers from durable journal", [&] {
    Fixture f(base / L"crash"); f.Old();
    { Transaction transaction(f.context, f.registry);
      transaction.Begin(f.manifest, f.manifest_path); f.SimulateInno(transaction); }
    Transaction resumed(f.context, f.registry);
    Check(resumed.HasPendingRecovery(), "missing recovery state");
    Reject([&] { resumed.Begin(f.manifest, f.manifest_path); });
    resumed.Rollback(); f.CheckOld();
  });
  run("hash failure cannot commit and can restore", [&] {
    Fixture f(base / L"hash"); f.Old();
    Transaction transaction(f.context, f.registry);
    transaction.Begin(f.manifest, f.manifest_path); f.SimulateInno(transaction);
    Write(f.context.target / L"engine.dll", "corrupt or incomplete new file");
    Reject([&] { transaction.Commit(f.manifest, f.manifest_path); });
    transaction.Rollback(); f.CheckOld();
  });
  run("tampered backup rejects before any restoration write", [&] {
    Fixture f(base / L"tampered"); f.Old();
    Transaction transaction(f.context, f.registry);
    transaction.Begin(f.manifest, f.manifest_path); f.SimulateInno(transaction);
    Write(transaction.backup_directory() / L"files\\0", "tampered backup");
    Reject([&] { transaction.Rollback(); });
    Check(Read(f.context.target / L"Dan Player.exe") == "synthetic-not-an-executable-v2", "partial restoration before validating all backups");
  });
  run("locked application blocks before modification", [&] {
    Fixture f(base / L"locked"); f.Old();
    HANDLE held = CreateFileW((f.context.target / L"Dan Player.exe").c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
    Check(held != INVALID_HANDLE_VALUE, "fixture lock failed");
    Transaction transaction(f.context, f.registry);
    Reject([&] { transaction.Begin(f.manifest, f.manifest_path); });
    CloseHandle(held); f.CheckOld();
  });
  run("newer installed version blocks downgrade", [&] {
    Fixture f(base / L"downgrade"); f.Old();
    auto previous = ReadManifest(f.context.target / kInstalledManifest);
    previous.version = "26.0.4";
    Write(f.context.target / kInstalledManifest, SerializeManifest(previous));
    Transaction transaction(f.context, f.registry);
    Reject([&] { transaction.Begin(f.manifest, f.manifest_path); }); f.CheckOld();
  });
  run("unrelated nonempty and protected destination rejected", [&] {
    Fixture f(base / L"unrelated");
    Write(f.context.target / L"family.txt", "untouched");
    Reject([&] { ValidateTarget(f.context); });
    f.context.forbidden_roots.push_back(f.root);
    Reject([&] { ValidateTarget(f.context); });
    Check(Read(f.context.target / L"family.txt") == "untouched", "unknown data modified");
  });
  run("duplicate and traversal manifest entries rejected", [&] {
    Fixture f(base / L"manifest");
    const auto first = f.manifest.files.front();
    Write(f.manifest_path, SerializeManifest(f.manifest) + first.sha256 + "\t1\tDAN PLAYER.EXE\n");
    Reject([&] { ReadManifest(f.manifest_path); });
    Write(f.manifest_path, "DANPLAYER_PAYLOAD_V1\n26.0.4\n" + first.sha256 + "\t1\t../outside.txt\n");
    Reject([&] { ReadManifest(f.manifest_path); });
  });
  run("Flutter native asset manifest is installed and rolled back", [&] {
    Fixture f(base / L"native-assets");
    const fs::path relative = L"native_assets.json";
    Write(f.payload / relative, "{\"fixture\":\"new-native-assets\"}");
    f.manifest.files.push_back({relative, Sha256(f.payload / relative), fs::file_size(f.payload / relative)});
    Write(f.manifest_path, SerializeManifest(f.manifest));
    Check(ReadManifest(f.manifest_path).files.size() == 4, "Flutter manifest rejected");
    Write(f.context.target / relative, "{\"fixture\":\"old-native-assets\"}");
    f.Old();
    Transaction transaction(f.context, f.registry);
    transaction.Begin(f.manifest, f.manifest_path); f.SimulateInno(transaction);
    transaction.VerifyInstalled(f.manifest, f.manifest_path);
    transaction.Rollback(); f.CheckOld();
    Check(Read(f.context.target / relative) == "{\"fixture\":\"old-native-assets\"}", "Original native manifest not restored");
  });
  run("native asset allowance does not admit neighboring unknown JSON", [&] {
    Fixture f(base / L"native-assets-boundary");
    const auto hash = f.manifest.files.front().sha256;
    for (const auto* relative : {"native_assets_private.json", "native_assets.json.bak", "native-assets.json", "settings.json", "../native_assets.json"}) {
      Write(f.manifest_path, "DANPLAYER_PAYLOAD_V1\n26.0.4-snapshot.1\n" + hash + "\t1\t" + relative + "\n");
      Reject([&] { ReadManifest(f.manifest_path); });
    }
  });
  run("snapshot documents are accepted without widening root ownership", [&] {
    Fixture f(base / L"snapshot-documents");
    f.manifest.version = "26.0.5-snapshot.1";
    for (const auto* name : {L"26.0.5-snapshot.1-validation.md",
                            L"26.0.5-snapshot.1-player-research.md",
                            L"26.0.5-snapshot.1-computer-use.md",
                            L"release-26.0.5-snapshot.1.md", L"replay-gain.md",
                            L"26.0.5-snapshot.2-validation.md", L"release-26.0.5-snapshot.2.md"}) {
      Write(f.payload / name, "synthetic bundled documentation");
      f.manifest.files.push_back({name, Sha256(f.payload / name), fs::file_size(f.payload / name)});
    }
    const auto accepted = SerializeManifest(f.manifest);
    Write(f.manifest_path, accepted);
    Check(ReadManifest(f.manifest_path).files.size() == 10, "Snapshot documents rejected");
    const auto hash = f.manifest.files.front().sha256;
    for (const auto* name : {"personal-notes.md", "replay-gain.md.bak",
                            "26.0.5-snapshot.3-validation.md", "settings.json",
                            "docs/replay-gain.md", "../replay-gain.md"}) {
      Write(f.manifest_path, accepted + hash + "\t1\t" + name + "\n");
      Reject([&] { ReadManifest(f.manifest_path); });
      auto unknown = f.manifest;
      unknown.files.push_back({FromUtf8(name), hash, 1});
      Reject([&] { SerializeManifest(unknown); });
    }
  });
  run("shared lyric portable layout retains strict identity checks", [&] {
    Fixture f(base / L"shared-lyrics"); f.Old(true);
    fs::remove(f.context.target / L"desktop_lyric/desktop_lyric.exe");
    Check(!IsRecognizedInstallation(f.context.target), "Truncated old layout accepted");
    const auto marker = f.context.target / L"DESKTOP-LYRIC-MODE";
    const auto write_checksums = [&](bool with_helper) {
      std::string sums;
      for (const auto* name : {L"Dan Player.exe", L"data/app.so", L"DESKTOP-LYRIC-MODE"})
        sums += Sha256(f.context.target / name) + "  " + ToUtf8(name) + "\n";
      if (with_helper) sums += Sha256(f.context.target / L"desktop_lyric/desktop_lyric.exe") +
          "  desktop_lyric/desktop_lyric.exe\n";
      Write(f.context.target / L"SHA256SUMS", sums);
    };
    Write(marker, "shared-executable-v1\n");
    write_checksums(false);
    Check(IsRecognizedInstallation(f.context.target), "Shared executable layout rejected");
    Write(marker, "shared-executable-v2\n");
    write_checksums(false);
    Check(!IsRecognizedInstallation(f.context.target), "Unknown layout accepted");
    Write(marker, "shared-executable-v1\n");
    write_checksums(false);
    Write(marker, "shared-executable-v1\r\n");
    Check(!IsRecognizedInstallation(f.context.target), "Modified layout marker accepted");
    Write(marker, "shared-executable-v1\n");
    Write(f.context.target / L"desktop_lyric/desktop_lyric.exe", "mixed helper");
    write_checksums(true);
    Check(!IsRecognizedInstallation(f.context.target), "Mixed layout accepted");
  });
  for (size_t index = 0; index < 5; ++index) {
    run(("injected backup failure " + std::to_string(index)).c_str(), [&] {
      Fixture f(base / (L"backup-fault-" + std::to_wstring(index))); f.Old();
      Transaction transaction(f.context, f.registry, [&](const char* stage, size_t i) {
        if (std::string(stage) == "backup" && i == index) throw std::runtime_error("injected IO failure");
      });
      Reject([&] { transaction.Begin(f.manifest, f.manifest_path); }); f.CheckOld();
      Check(!transaction.pending(), "unprepared journal marked writable");
    });
  }
  for (size_t index = 0; index < 3; ++index) {
    run(("injected verification failure " + std::to_string(index)).c_str(), [&] {
      Fixture f(base / (L"verify-fault-" + std::to_wstring(index))); f.Old();
      Transaction transaction(f.context, f.registry, [&](const char* stage, size_t i) {
        if (std::string(stage) == "verify" && i == index) throw std::runtime_error("injected verification failure");
      });
      transaction.Begin(f.manifest, f.manifest_path); f.SimulateInno(transaction);
      Reject([&] { transaction.Commit(f.manifest, f.manifest_path); });
      transaction.Rollback(); f.CheckOld();
    });
  }
  run("failed restoration remains recoverable on retry", [&] {
    Fixture f(base / L"restore-fault"); f.Old();
    Transaction transaction(f.context, f.registry, [](const char* stage, size_t index) {
      if (std::string(stage) == "restore" && index == 1) throw std::runtime_error("injected restore failure");
    });
    transaction.Begin(f.manifest, f.manifest_path); f.SimulateInno(transaction);
    Reject([&] { transaction.Rollback(); });
    Transaction retry(f.context, f.registry);
    Check(retry.HasPendingRecovery(), "lost partial recovery state");
    retry.Rollback(); f.CheckOld();
  });
  run("late failure after verification remains recoverable", [&] {
    Fixture f(base / L"late-failure"); f.Old();
    Transaction tx(f.context, f.registry);
    tx.Begin(f.manifest, f.manifest_path); f.SimulateInno(tx);
    tx.VerifyInstalled(f.manifest, f.manifest_path);
    Check(tx.pending(), "verification disarmed rollback");
    tx.Rollback(); f.CheckOld();
  });
  run("unknown file created after begin survives in place", [&] {
    Fixture f(base / L"new-conflict");
    Transaction tx(f.context, f.registry); tx.Begin(f.manifest, f.manifest_path);
    Write(f.context.target / L"engine.dll", "unrelated later file");
    Reject([&] { tx.Rollback(); });
    Check(Read(f.context.target / L"engine.dll") == "unrelated later file", "unowned new file deleted");
    Check(tx.HasPendingRecovery(), "conflict lost recovery state");
  });
  run("later modified original is retained before restoration", [&] {
    Fixture f(base / L"modified-conflict"); f.Old();
    Transaction tx(f.context, f.registry); tx.Begin(f.manifest, f.manifest_path);
    Write(f.context.target / L"engine.dll", "later user bytes");
    tx.Rollback(); f.CheckOld();
    bool retained = false;
    for (const auto& entry : fs::directory_iterator(tx.backup_directory() / L"conflicts"))
      if (Read(entry.path()) == "later user bytes") retained = true;
    Check(retained, "later user bytes were overwritten without a verified copy");
  });
  run("hard-linked managed file rejected before modification", [&] {
    Fixture f(base / L"hardlink"); f.Old();
    const auto outside = f.root / L"outside.bin";
    Write(outside, "outside untouched");
    Check(DeleteFileW((f.context.target / L"engine.dll").c_str()) != FALSE, "fixture unlink");
    Check(CreateHardLinkW((f.context.target / L"engine.dll").c_str(), outside.c_str(), nullptr) != FALSE, "fixture hardlink");
    Transaction tx(f.context, f.registry);
    Reject([&] { tx.Begin(f.manifest, f.manifest_path); });
    Check(Read(outside) == "outside untouched", "outside link content changed");
  });
  run("hard-linked backup rejected before restoration", [&] {
    Fixture f(base / L"backup-hardlink"); f.Old();
    Transaction tx(f.context, f.registry); tx.Begin(f.manifest, f.manifest_path); f.SimulateInno(tx);
    const auto backup = tx.backup_directory() / L"files/0";
    Check(CreateHardLinkW((f.root / L"outside.bin").c_str(), backup.c_str(), nullptr) != FALSE, "fixture hardlink");
    Reject([&] { tx.Rollback(); });
    Check(Read(f.context.target / L"Dan Player.exe") == "synthetic-not-an-executable-v2", "restore mutated before link check");
  });
  run("same handle SHA256 works with delete access", [&] {
    Fixture f(base / L"handle-hash");
    const auto path = f.payload / L"engine.dll";
    const auto expected = Sha256(path);
    HANDLE file = CreateFileW(path.c_str(), GENERIC_READ | DELETE, FILE_SHARE_READ, nullptr,
        OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    Check(file != INVALID_HANDLE_VALUE, "delete access fixture open");
    std::string actual;
    try { actual = Sha256Handle(file); } catch (...) { CloseHandle(file); throw; }
    CloseHandle(file);
    Check(actual == expected, "same-handle self-delete hash failed");
  });
  run("new install rollback removes only managed empty directories", [&] {
    Fixture f(base / L"new-rollback");
    Transaction tx(f.context, f.registry); tx.Begin(f.manifest, f.manifest_path); f.SimulateInno(tx);
    tx.Rollback();
    Check(!fs::exists(f.context.target), "managed empty target left behind");
  });
  run("forged portable marker is not enough", [&] {
    Fixture f(base / L"portable-forged"); f.Old(true);
    Write(f.context.target / L"Dan Player.exe", "different executable");
    Check(!IsRecognizedInstallation(f.context.target), "portable checksum proof was ignored");
  });
  run("empty manual path stays empty and is rejected", [] {
    DestinationSelection selected(L"26.0.4-snapshot.1"); selected.EditFinal(L"");
    selected.ChooseParent(L"D:\\Apps");
    Check(selected.value().empty(), "empty manual path replaced");
    Reject([&] { CanonicalPath(selected.value()); });
  });
  run("another live owner cannot recover the same destination", [&] {
    Fixture f(base / L"concurrent"); f.Old();
    Transaction first(f.context, f.registry); first.Begin(f.manifest, f.manifest_path);
    bool rejected = false;
    std::thread other([&] {
      try { Transaction second(f.context, f.registry); second.Rollback(); }
      catch (const std::exception&) { rejected = true; }
    });
    other.join();
    Check(rejected && first.HasPendingRecovery(), "live journal was taken over");
    first.Rollback(); f.CheckOld();
  });
  std::cout << "RESULT " << passed << " passed, " << failed << " failed; fixtures=" << ToUtf8(base.wstring()) << '\n';
  return failed ? 1 : 0;
}
