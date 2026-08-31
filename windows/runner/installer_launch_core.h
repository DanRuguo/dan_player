#ifndef RUNNER_INSTALLER_LAUNCH_CORE_H_
#define RUNNER_INSTALLER_LAUNCH_CORE_H_

#include <windows.h>

#include <array>
#include <string>

namespace installer_launch {

struct Request {
  std::wstring path;
  std::string sha256;
  std::wstring version;
};

struct Outcome {
  std::string code;
  std::string message;
  DWORD detail = ERROR_SUCCESS;
  bool ok() const { return code.empty(); }
};

using Signer = std::array<unsigned char, 32>;

// The injectable boundary is native-test-only; no Dart method accepts a trust,
// process, current-directory, parent-PID, or timeout override.
class Backend {
 public:
  virtual ~Backend() = default;
  virtual Outcome VerifySigner(HANDLE file, const std::wstring& path,
                               Signer* signer) = 0;
  virtual bool IsInstallerVersion(const std::wstring& path,
                                  const std::wstring& version) = 0;
  virtual Outcome Start(const std::wstring& application,
                        const std::wstring& command_line,
                        const std::wstring& directory) = 0;
};

bool ValidRequest(const Request& request);
std::wstring QuoteArgument(const std::wstring& argument);
std::wstring BuildCommandLine(const std::wstring& installer,
                             const std::wstring& directory, DWORD parent_pid,
                             const std::wstring& version,
                             const std::wstring& ready_event);
Outcome HashFile(HANDLE file, std::string* sha256, HANDLE cancelled = nullptr);
Outcome VerifyTrustedSigner(HANDLE file, const std::wstring& path,
                            Signer* signer);
bool IsInstallerVersion(const std::wstring& path, const std::wstring& version);
Outcome Launch(const Request& request, HANDLE cancelled);
Outcome LaunchWithBackend(const Request& request, HANDLE cancelled,
                          Backend& backend, DWORD ready_timeout_ms = 30000);

}  // namespace installer_launch

#endif
