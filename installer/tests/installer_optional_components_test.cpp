#include "installer_core.h"

#include <fstream>
#include <iostream>
#include <stdexcept>

using namespace dan::installer;
namespace {
void Check(bool value, const char* message) {
  if (!value) throw std::runtime_error(message);
}
void Write(const fs::path& file, const std::string& value) {
  fs::create_directories(file.parent_path());
  std::ofstream output(file, std::ios::binary);
  output << value;
  if (!output) throw std::runtime_error("Cannot write isolated fixture");
}
std::string Read(const fs::path& file) {
  std::ifstream input(file, std::ios::binary);
  return std::string(std::istreambuf_iterator<char>(input), {});
}
class MemoryRegistry final : public RegistryStore {
 public:
  RegistrySnapshot Read() override { return {}; }
  void Restore(const RegistrySnapshot&) override {}
};
struct Fixture {
  Context context;
  fs::path manifest_path;
  Manifest payload;
  MemoryRegistry registry;
  explicit Fixture(const fs::path& root) {
    context.target = root / L"install";
    payload.version = "26.1.1";
    for (const auto* name : {L"Dan Player.exe", L"data/app.so"}) {
      Write(context.target / name, "original synthetic player bytes");
      const auto source = root / L"payload" / name;
      Write(source, "new synthetic player bytes");
      payload.files.push_back({name, Sha256(source), fs::file_size(source)});
    }
    manifest_path = root / L"new.manifest";
    Write(manifest_path, SerializeManifest(payload));
    Write(context.target / L"unrelated/saved-notes.txt", "unrelated user content");
  }
  void Install() {
    Transaction transaction(context, registry);
    transaction.Begin(payload, manifest_path);
    for (const auto& file : payload.files) {
      Write(context.target / file.relative_path, "new synthetic player bytes");
      transaction.RecordWritten(context.target / file.relative_path);
    }
    Write(context.target / kInstalledManifest, Read(manifest_path));
    transaction.RecordWritten(context.target / kInstalledManifest);
    transaction.Commit(payload, manifest_path);
    Check(!transaction.pending(), "Installation did not commit");
    Check(Read(context.target / L"unrelated/saved-notes.txt") ==
              "unrelated user content", "Unrelated content changed");
  }
};
}  // namespace

int wmain(int argc, wchar_t** argv) {
  if (argc != 2) return 2;
  const auto base = fs::absolute(argv[1]).lexically_normal();
  bool qa = false;
  for (const auto& part : base) if (part == L"qa-local") qa = true;
  if (!qa || !base.is_absolute()) return 3;
  CheckNoReparsePoints(base);
  const auto root = base / (L"optional-components-" + std::to_wstring(GetTickCount64()));
  fs::create_directories(root);
  size_t passed = 0, failed = 0;
  const auto run = [&](const char* name, const auto& action) {
    try { action(); ++passed; std::cout << "PASS " << name << '\n'; }
    catch (const std::exception& error) {
      ++failed; std::cout << "FAIL " << name << ": " << error.what() << '\n';
    }
  };
  run("installed FFmpeg omitted by core update remains intact", [&] {
    for (const auto* component_root : {L"tools/ffmpeg", L"tool/ffmpeg"}) {
      Fixture fixture(root / (std::wstring(component_root) == L"tool/ffmpeg" ?
                             L"ffmpeg-tool" : L"ffmpeg-tools"));
      Manifest previous = fixture.payload;
      previous.version = "26.0.6";
      for (auto& file : previous.files) {
        file.sha256 = Sha256(fixture.context.target / file.relative_path);
        file.size = fs::file_size(fixture.context.target / file.relative_path);
      }
      for (const auto* name : {L"ffmpeg.exe", L"ffprobe.exe", L"avcodec-61.dll", L"LICENSE"}) {
        const auto relative = fs::path(component_root) / name;
        Write(fixture.context.target / relative, "existing optional FFmpeg bytes");
        previous.files.push_back({relative, Sha256(fixture.context.target / relative),
                                  fs::file_size(fixture.context.target / relative)});
      }
      Write(fixture.context.target / kInstalledManifest, SerializeManifest(previous));
      fixture.Install();
      for (const auto* name : {L"ffmpeg.exe", L"ffprobe.exe", L"avcodec-61.dll", L"LICENSE"}) {
        Check(Read(fixture.context.target / component_root / name) ==
                  "existing optional FFmpeg bytes", "Existing FFmpeg component deleted");
      }
    }
  });
  run("portable Japanese dictionary survives same-directory core installation", [&] {
    for (const auto* component_root : {L"tool/japanese_readings", L"tools/japanese_readings"}) {
      Fixture fixture(root / (std::wstring(component_root) == L"tool/japanese_readings" ?
                              L"portable-tool" : L"portable-tools"));
      Write(fixture.context.target / L"BUILD-PROVENANCE.json",
            "{\"Product\":\"Dan Player\",\"SourceProject\":\"https://github.com/DanRuguo/dan_player\",\"Version\":\"26.1.1\"}");
      Write(fixture.context.target / L"DESKTOP-LYRIC-MODE", "shared-executable-v1\n");
      std::string checksums;
      for (const auto* name : {L"Dan Player.exe", L"data/app.so", L"DESKTOP-LYRIC-MODE"}) {
        checksums += Sha256(fixture.context.target / name) + "  " + ToUtf8(name) + "\n";
      }
      for (const auto* name : {L"ffmpeg.exe", L"ffprobe.exe", L"ffplay.exe", L"LICENSE", L"README.txt"}) {
        const auto relative = fs::path(L"tool/ffmpeg") / name;
        Write(fixture.context.target / relative, "existing portable FFmpeg bytes");
        checksums += Sha256(fixture.context.target / relative) + "  " +
                     ToUtf8(relative.generic_wstring()) + "\n";
      }
      for (const auto* name : {L"ipadic-reading.bin.gz", L"MODULE.json", L"README.txt",
                              L"licenses/LINDERA/LICENSE", L"licenses/IPADIC/NOTICE.txt",
                              L"licenses/IPADIC/PROVENANCE.md"}) {
        const auto relative = fs::path(component_root) / name;
        Write(fixture.context.target / relative, "existing optional dictionary data");
        checksums += Sha256(fixture.context.target / relative) + "  " +
                     ToUtf8(relative.generic_wstring()) + "\n";
      }
      Write(fixture.context.target / L"SHA256SUMS", checksums);
      Check(IsRecognizedInstallation(fixture.context.target), "New portable dictionary layout rejected");
      for (const auto* unexpected : {L"tool/japanese_readings/unknown.exe",
                                    L"tools/japanese_readings/nested/ipadic-reading.bin.gz"}) {
        auto invalid = fixture.payload;
        invalid.files.push_back({unexpected, std::string(64, '0'), 1});
        bool rejected = false;
        try { SerializeManifest(invalid); } catch (const std::exception&) { rejected = true; }
        Check(rejected, "Unexpected component path was accepted");
      }
      fixture.Install();
      for (const auto* name : {L"ffmpeg.exe", L"ffprobe.exe", L"ffplay.exe", L"LICENSE", L"README.txt"}) {
        Check(Read(fixture.context.target / L"tool/ffmpeg" / name) ==
                  "existing portable FFmpeg bytes", "Portable FFmpeg component deleted");
      }
      for (const auto* name : {L"ipadic-reading.bin.gz", L"MODULE.json", L"README.txt",
                              L"licenses/LINDERA/LICENSE", L"licenses/IPADIC/NOTICE.txt",
                              L"licenses/IPADIC/PROVENANCE.md"}) {
        Check(Read(fixture.context.target / component_root / name) ==
                  "existing optional dictionary data", "Existing dictionary component deleted");
      }
    }
  });
  std::cout << passed << " passed, " << failed << " failed\n";
  // Leave failed fixtures for evidence. Successful isolated fixtures are removed.
  if (!failed) fs::remove_all(root);
  return failed ? 1 : 0;
}
