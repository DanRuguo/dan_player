#include "../installer_launch_core.h"

#include <shellapi.h>
#include <algorithm>
#include <filesystem>
#include <iostream>
#include <string>
#include <vector>

namespace {
int checks = 0;
void Check(bool condition, const char* message) {
  ++checks;
  if (!condition) { std::cerr << "FAIL: " << message << '\n'; std::exit(1); }
}

std::vector<std::wstring> Args(const std::wstring& command) {
  int count = 0;
  auto* values = CommandLineToArgvW(command.c_str(), &count);
  Check(values != nullptr, "Windows argv parser");
  std::vector<std::wstring> result(values, values + count);
  LocalFree(values);
  return result;
}

struct Fixture {
  std::filesystem::path directory;
  std::filesystem::path path;
  Fixture() {
    wchar_t temp[MAX_PATH]{};
    Check(GetTempPathW(MAX_PATH, temp) > 0, "temporary directory");
    directory = std::filesystem::path(temp) /
        (L"DanPlayer-launch-QA-" + std::to_wstring(GetCurrentProcessId()) +
         L"-" + std::to_wstring(GetTickCount64()));
    Check(CreateDirectoryW(directory.c_str(), nullptr) != FALSE, "unique fixture directory");
    path = directory / L"更新 installer 테스트.exe";
    const HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr,
                                    CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    Check(file != INVALID_HANDLE_VALUE, "create synthetic non-PE installer");
    DWORD written = 0;
    Check(WriteFile(file, "abc", 3, &written, nullptr) && written == 3, "fixture bytes");
    CloseHandle(file);
  }
  ~Fixture() {
    // Only the exact files created by this fixture; never recursive deletion.
    DeleteFileW(path.c_str());
    RemoveDirectoryW(directory.c_str());
  }
  installer_launch::Request request() const {
    return {path.wstring(),
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
      L"26.0.4-snapshot.1"};
  }
};

struct FakeBackend : installer_launch::Backend {
  int verified = 0;
  int starts = 0;
  int metadata = 0;
  bool mismatch = false;
  bool trusted = true;
  bool correct_version = true;
  bool start_ok = true;
  bool ready = true;
  HANDLE cancel = nullptr;
  bool cancel_at_start = false;
  std::wstring event_name;
  std::wstring locked_path;
  HANDLE held_ready = nullptr;
  HANDLE held_accepted = nullptr;

  ~FakeBackend() override {
    if (held_ready) CloseHandle(held_ready);
    if (held_accepted) CloseHandle(held_accepted);
  }

  installer_launch::Outcome VerifySigner(HANDLE file, const std::wstring& path,
                                          installer_launch::Signer* signer) override {
    ++verified;
    Check(file != INVALID_HANDLE_VALUE, "verification uses held file handle");
    if (!trusted) return {"signature_untrusted", "synthetic untrusted"};
    signer->fill(static_cast<unsigned char>(mismatch ? verified : 1));
    if (verified == 1) locked_path = path;
    return {};
  }
  bool IsInstallerVersion(const std::wstring&, const std::wstring& version) override {
    ++metadata;
    Check(version == L"26.0.4-snapshot.1", "exact version forwarded");
    return correct_version;
  }
  installer_launch::Outcome Start(const std::wstring& application,
                                  const std::wstring& command,
                                  const std::wstring& directory) override {
    ++starts;
    const auto args = Args(command);
    Check(args.size() == 6, "exact bounded argv");
    Check(args[0] == application && application == locked_path, "exact verified EXE, not a shell");
    Check(args[1] == L"/DANUPDATE=1", "update-only mode");
    Check(args[2] == L"/DIR=" + directory, "single Unicode directory argument");
    wchar_t current[32768]{};
    Check(GetModuleFileNameW(nullptr, current, 32768) > 0, "module identity");
    Check(directory == std::filesystem::path(current).parent_path(), "target derived from actual process");
    Check(args[3] == L"/DANPARENTPID=" + std::to_wstring(GetCurrentProcessId()), "current PID only");
    Check(args[4] == L"/DANUPDATEVERSION=26.0.4-snapshot.1", "exact requested version");
    const std::wstring prefix = L"/DANUPDATEEVENT=Local\\DanPlayer.Update.";
    Check(args[5].compare(0, prefix.size(), prefix) == 0 &&
          args[5].size() == prefix.size() + 64, "cryptographic 256-bit handshake name");
    event_name = args[5].substr(std::wstring(L"/DANUPDATEEVENT=").size());
    held_ready = OpenEventW(EVENT_MODIFY_STATE | SYNCHRONIZE, FALSE, event_name.c_str());
    held_accepted = OpenEventW(SYNCHRONIZE, FALSE, (event_name + L".Accepted").c_str());
    Check(held_ready && held_accepted, "two-way events exist before installer startup");
    Check(WaitForSingleObject(held_accepted, 0) == WAIT_TIMEOUT, "no acceptance before READY");
    HANDLE writer = CreateFileW(application.c_str(), GENERIC_WRITE,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
        OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    Check(writer == INVALID_HANDLE_VALUE, "write denied through verified launch");
    Check(!DeleteFileW(application.c_str()), "delete denied through verified launch");
    const auto parent = std::filesystem::path(application).parent_path();
    Check(!MoveFileW(parent.c_str(), (parent.wstring() + L"-renamed").c_str()),
          "ancestor rename denied through verified launch");
    if (!start_ok) return {"start_failed", "synthetic launch failure"};
    if (cancel_at_start) SetEvent(cancel);
    if (ready) {
      Check(SetEvent(held_ready) != FALSE, "synthetic parent-validation READY");
    }
    return {};
  }
};

void ExpectFailure(const installer_launch::Outcome& outcome, const char* code) {
  Check(!outcome.ok() && outcome.code == code, code);
}

}  // namespace

int wmain(int argc, wchar_t* argv[]) {
  if (argc == 3 && std::wstring(argv[1]) == L"--verify-only") {
    const HANDLE file = CreateFileW(argv[2], GENERIC_READ, FILE_SHARE_READ,
        nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    if (file == INVALID_HANDLE_VALUE) return 3;
    installer_launch::Signer signer{};
    const auto outcome = installer_launch::VerifyTrustedSigner(file, argv[2], &signer);
    CloseHandle(file);
    std::cout << "Read-only WinVerifyTrust: "
              << (outcome.ok() ? "trusted" : outcome.code)
              << "; status=" << outcome.detail
              << "; no launch/trust-store mutation.\n";
    return outcome.ok() ? 0 : 2;
  }
  Check(argc == 1, "only default tests or explicit read-only signature probe");
  Fixture fixture;
  const auto request = fixture.request();
  wchar_t module[32768]{};
  Check(GetModuleFileNameW(nullptr, module, 32768) > 0, "resource fixture path");
  Check(installer_launch::IsInstallerVersion(module, request.version),
        "real Windows signed-resource fields match exact product and prerelease version");
  Check(!installer_launch::IsInstallerVersion(module, L"26.0.4"),
        "resource version cannot silently downgrade prerelease to stable");
  Check(!installer_launch::IsInstallerVersion(fixture.path, request.version),
        "non-PE EXE extension is not an installer");
  Check(installer_launch::ValidRequest(request), "valid Unicode/space/preview request");
  for (const auto* bad : {L"relative.exe", L"C:\\x.zip", L"C:\\x.exe:ads", L"\\\\server\\x.exe",
                          L"C:\\x\n.exe", L"C:\\x\".exe", L"C:/x.exe"}) {
    auto changed = request;
    changed.path = bad;
    Check(!installer_launch::ValidRequest(changed), "reject unsafe or non-EXE path");
  }
  for (const auto* bad : {L"", L"1.2", L"1..2", L"1.2.3\" /DIR=X", L"1.2.3\n", L"1.2.3-"}) {
    auto changed = request;
    changed.version = bad;
    Check(!installer_launch::ValidRequest(changed), "reject malformed/injected version");
  }
  for (const auto& original : {std::wstring(L""), std::wstring(L"C:\\Some folder\\"),
                               std::wstring(L"中文 \"quoted\" \\\\"), std::wstring(L"a\\\"b")}) {
    const auto parsed = Args(L"fixture.exe " + installer_launch::QuoteArgument(original));
    Check(parsed.size() == 2 && parsed[1] == original, "Windows argv round-trip");
  }
  {
    FakeBackend fake;
    Check(installer_launch::LaunchWithBackend(request, nullptr, fake, 10).ok(), "safe launch plus READY");
    Check(fake.verified == 2 && fake.starts == 1 && fake.metadata == 1, "all checks precede single launch");
    Check(WaitForSingleObject(fake.held_accepted, 0) == WAIT_OBJECT_0,
          "only live successful handshake authorizes parent-exit update");
  }
  {
    FakeBackend fake;
    auto changed = request;
    changed.sha256[0] = '0';
    ExpectFailure(installer_launch::LaunchWithBackend(changed, nullptr, fake, 10), "hash_mismatch");
    Check(fake.starts == 0 && fake.verified == 0, "wrong hash cannot reach trust or launch");
  }
  {
    FakeBackend fake;
    fake.trusted = false;
    ExpectFailure(installer_launch::LaunchWithBackend(request, nullptr, fake, 10), "signature_untrusted");
    Check(fake.starts == 0, "untrusted identity cannot launch");
  }
  {
    FakeBackend fake;
    fake.mismatch = true;
    ExpectFailure(installer_launch::LaunchWithBackend(request, nullptr, fake, 10), "publisher_mismatch");
    Check(fake.starts == 0 && fake.metadata == 0, "different trusted publisher cannot launch");
  }
  {
    FakeBackend fake;
    fake.correct_version = false;
    ExpectFailure(installer_launch::LaunchWithBackend(request, nullptr, fake, 10), "installer_version_mismatch");
    Check(fake.starts == 0, "not complete requested installer cannot launch");
  }
  {
    FakeBackend fake;
    fake.start_ok = false;
    ExpectFailure(installer_launch::LaunchWithBackend(request, nullptr, fake, 10), "start_failed");
    Check(fake.starts == 1, "start failure not retried");
  }
  {
    FakeBackend fake;
    fake.ready = false;
    ExpectFailure(installer_launch::LaunchWithBackend(request, nullptr, fake, 1), "installer_not_ready");
    Check(fake.starts == 1, "timeout does not launch a second process");
    Check(SetEvent(fake.held_ready) != FALSE, "late READY can succeed on installer's retained handle");
    Check(WaitForSingleObject(fake.held_accepted, 0) == WAIT_TIMEOUT,
          "late READY never authorizes previously timed-out update");
  }
  {
    FakeBackend fake;
    const auto event = CreateEventW(nullptr, TRUE, TRUE, nullptr);
    ExpectFailure(installer_launch::LaunchWithBackend(request, event, fake, 10), "launch_cancelled");
    Check(fake.starts == 0 && fake.verified == 0, "closing player does not start installer");
    ResetEvent(event);
    fake.cancel = event;
    fake.cancel_at_start = true;
    ExpectFailure(installer_launch::LaunchWithBackend(request, event, fake, 10), "launch_cancelled");
    Check(WaitForSingleObject(fake.held_accepted, 0) == WAIT_TIMEOUT,
          "cancelled launch never accepts installer despite READY");
    CloseHandle(event);
  }
  {
    const HANDLE writer = CreateFileW(fixture.path.c_str(), GENERIC_WRITE,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
        OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    Check(writer != INVALID_HANDLE_VALUE, "hold existing writer");
    FakeBackend fake;
    ExpectFailure(installer_launch::LaunchWithBackend(request, nullptr, fake, 10), "installer_locked");
    Check(fake.starts == 0, "existing writer fails closed");
    CloseHandle(writer);
  }
  {
    const auto link = fixture.directory / L"hardlink.exe";
    Check(CreateHardLinkW(link.c_str(), fixture.path.c_str(), nullptr) != FALSE, "fixture hard link");
    FakeBackend fake;
    ExpectFailure(installer_launch::LaunchWithBackend(request, nullptr, fake, 10), "installer_locked");
    Check(DeleteFileW(link.c_str()) != FALSE, "remove exact fixture link");
  }
  {
    const HANDLE file = CreateFileW(fixture.path.c_str(), GENERIC_READ,
        FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    installer_launch::Signer signer{};
    const auto trust = installer_launch::VerifyTrustedSigner(file, fixture.path, &signer);
    ExpectFailure(trust, "signature_untrusted");
    CloseHandle(file);
  }
  std::cout << "installer_launch_test: " << checks
            << " checks passed; synthetic files/injected launch only; no installer process started.\n";
  return 0;
}
