#include "update_gate.h"

#include <tlhelp32.h>
#include <algorithm>
#include <map>
#include <set>
#include <stdexcept>

namespace dan::installer {
namespace {
struct Handle {
  HANDLE value;
  ~Handle() { if(value&&value!=INVALID_HANDLE_VALUE)CloseHandle(value); }
};
[[noreturn]] void Fail(const char* message) { throw std::runtime_error(message); }
uint64_t Creation(HANDLE process) {
  FILETIME created{},exited{},kernel{},user{};
  if(!GetProcessTimes(process,&created,&exited,&kernel,&user))Fail("Cannot verify updater process creation time");
  return (static_cast<uint64_t>(created.dwHighDateTime)<<32)|created.dwLowDateTime;
}
DWORD ParentId(const std::wstring& value) {
  if(value.empty()||value.size()>10)Fail("Invalid updater parent process id");
  uint64_t number=0;
  for(const auto c:value) {
    if(c<L'0'||c>L'9')Fail("Invalid updater parent process id");
    number=number*10+static_cast<unsigned>(c-L'0');
    if(number>MAXDWORD)Fail("Invalid updater parent process id");
  }
  if(!number||number==GetCurrentProcessId())Fail("Invalid updater parent process id");
  return static_cast<DWORD>(number);
}
void ValidateEvent(const std::wstring& name) {
  constexpr wchar_t prefix[]=L"Local\\DanPlayer.Update.";
  const size_t offset=std::size(prefix)-1;
  if(name.size()!=offset+64||name.compare(0,offset,prefix)!=0)Fail("Invalid updater readiness event");
  for(size_t i=offset;i<name.size();++i)
    if(!((name[i]>=L'0'&&name[i]<=L'9')||(name[i]>=L'a'&&name[i]<=L'f')||(name[i]>=L'A'&&name[i]<=L'F')))
      Fail("Invalid updater readiness event");
}
void VerifyAncestor(DWORD requested,HANDLE parent) {
  Handle snapshot{CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS,0)};
  if(snapshot.value==INVALID_HANDLE_VALUE)Fail("Cannot verify updater parent chain");
  std::map<DWORD,DWORD> parents;
  PROCESSENTRY32W entry{};entry.dwSize=sizeof(entry);
  if(!Process32FirstW(snapshot.value,&entry))Fail("Cannot verify updater parent chain");
  do { parents.emplace(entry.th32ProcessID,entry.th32ParentProcessID); }
  while(Process32NextW(snapshot.value,&entry));
  DWORD current=GetCurrentProcessId();uint64_t child_created=Creation(GetCurrentProcess());
  for(unsigned depth=0;depth<8;++depth) {
    const auto it=parents.find(current);
    if(it==parents.end()||!it->second||it->second==current)break;
    current=it->second;
    if(current==requested) {
      if(Creation(parent)>child_created)Fail("Updater parent process id was reused");
      return;
    }
    Handle ancestor{OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,current)};
    if(!ancestor.value)break;
    const auto created=Creation(ancestor.value);
    if(created>child_created)break;
    child_created=created;
  }
  Fail("Updater parent is not the process that launched this installer");
}
bool SamePath(const fs::path& a,const fs::path& b) { return _wcsicmp(a.c_str(),b.c_str())==0; }
fs::path ProcessPath(HANDLE process) {
  std::wstring path(32768,L'\0');DWORD length=static_cast<DWORD>(path.size());
  if(!QueryFullProcessImageNameW(process,0,path.data(),&length))Fail("Cannot verify updater parent image");
  path.resize(length);return CanonicalPath(path);
}
void ProbeWritable(const fs::path& file) {
  CheckNoReparsePoints(file);
  if(!fs::exists(file))return;
  if(!fs::is_regular_file(file))Fail("A directory occupies an update file path");
  Handle probe{CreateFileW(file.c_str(),GENERIC_READ|GENERIC_WRITE|DELETE,FILE_SHARE_READ,
      nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr)};
  if(probe.value==INVALID_HANDLE_VALUE)Fail("A player file is still in use or not writable; close the player and retry");
}
}

UpdateGate::UpdateGate(const fs::path& target,const fs::path& manifest,const std::wstring& version,
    const std::wstring& parent_pid,const std::wstring& ready_event) {
  target_=CanonicalPath(target);manifest_=CanonicalPath(manifest);
  ValidateEvent(ready_event);
  const auto requested=ParentId(parent_pid);
  const auto payload=ReadManifest(manifest_);
  if(payload.version!=ToUtf8(version))Fail("Updater version does not match this installer");
  if(!IsRecognizedInstallation(target_))Fail("Updater destination is not a verified player installation");
  Handle parent{OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION|SYNCHRONIZE,FALSE,requested)};
  if(!parent.value||WaitForSingleObject(parent.value,0)!=WAIT_TIMEOUT)Fail("Updater parent must still be running for verification");
  const auto expected=target_/L"Dan Player.exe";
  if(!SamePath(ProcessPath(parent.value),expected))Fail("Updater parent is not Dan Player in the requested directory");
  VerifyAncestor(requested,parent.value);
  CheckNoReparsePoints(expected);
  Handle image{CreateFileW(expected.c_str(),GENERIC_READ,FILE_SHARE_READ,nullptr,
      OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr)};
  if(image.value==INVALID_HANDLE_VALUE)Fail("Cannot hold the verified updater parent image");
  parent_hash_=Sha256Handle(image.value);manifest_hash_=Sha256(manifest_);
  Handle ready{OpenEventW(EVENT_MODIFY_STATE,FALSE,ready_event.c_str())};
  if(!ready.value)Fail("Updater readiness event is unavailable");
  Handle accepted{OpenEventW(SYNCHRONIZE,FALSE,(ready_event+L".Accepted").c_str())};
  if(!accepted.value)Fail("Updater acceptance event is unavailable");
  // The launcher may let its app exit only after this signal. Keep the exact
  // process object alive until installer teardown, even after normal exit.
  if(!SetEvent(ready.value))Fail("Cannot acknowledge updater parent verification");
  parent_=parent.value;parent.value=nullptr;
  image_=image.value;image.value=INVALID_HANDLE_VALUE;
  accepted_=accepted.value;accepted.value=nullptr;
  started_=GetTickCount64();
}
UpdateGate::~UpdateGate() {
  if(image_!=INVALID_HANDLE_VALUE)CloseHandle(image_);
  if(parent_)CloseHandle(parent_);
  if(accepted_)CloseHandle(accepted_);
}
int UpdateGate::Poll(uint64_t timeout_ms) {
  if(handoff_expired_)return 3;
  const DWORD accepted=WaitForSingleObject(accepted_,0);
  if(accepted==WAIT_TIMEOUT) {
    handoff_expired_=GetTickCount64()-started_>=timeout_ms;
    return handoff_expired_?3:0;
  }
  if(accepted!=WAIT_OBJECT_0)Fail("Cannot confirm that the player accepted this update handoff");
  const DWORD state=WaitForSingleObject(parent_,0);
  if(state==WAIT_OBJECT_0) {
    DWORD exit_code=0;
    if(!GetExitCodeProcess(parent_,&exit_code)||exit_code!=0)
      Fail("The verified player did not exit successfully; cancel and restart it before retrying the update");
    if(image_!=INVALID_HANDLE_VALUE) { CloseHandle(image_);image_=INVALID_HANDLE_VALUE; }
    return 1;
  }
  if(state!=WAIT_TIMEOUT)Fail("Cannot wait for the verified updater parent");
  return GetTickCount64()-started_>=timeout_ms?2:0;
}
void UpdateGate::Retry() {
  if(handoff_expired_)Fail("The player no longer accepted this update handoff; start a new update from the player");
  started_=GetTickCount64();
}
void UpdateGate::RequireReady(const fs::path& target,const fs::path& manifest) {
  if(!SamePath(CanonicalPath(target),target_)||!SamePath(CanonicalPath(manifest),manifest_))Fail("Updater destination cannot be changed");
  if(Poll()!=1)Fail("Wait for the verified player process to exit before updating");
  if(Sha256(manifest_)!=manifest_hash_||Sha256(target_/L"Dan Player.exe")!=parent_hash_)
    Fail("Updater input changed after parent verification");
  const auto payload=ReadManifest(manifest_);
  std::set<fs::path> paths;
  for(const auto& file:payload.files)paths.insert(target_/file.relative_path);
  const auto previous=target_/kInstalledManifest;
  if(fs::exists(previous))for(const auto& file:ReadManifest(previous).files)paths.insert(target_/file.relative_path);
  for(const auto* name:{kInstalledManifest,L".dan-player-install\\unins000.exe",
      L".dan-player-install\\unins000.dat",L".dan-player-install\\unins000.msg"})paths.insert(target_/name);
  for(const auto& file:paths)ProbeWritable(file);
}
}  // namespace dan::installer
