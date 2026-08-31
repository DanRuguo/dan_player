#include "update_gate.h"
#include <bcrypt.h>
#include <fstream>
#include <iostream>
#include <memory>
#include <stdexcept>

using namespace dan::installer;
namespace {
std::wstring Quote(const fs::path& value) { return L"\""+value.wstring()+L"\""; }
void Write(const fs::path& file,const std::string& value) { std::ofstream(file,std::ios::binary)<<value; }
std::wstring EventName() {
  BYTE bytes[32]{};if(BCryptGenRandom(nullptr,bytes,32,BCRYPT_USE_SYSTEM_PREFERRED_RNG)<0)throw std::runtime_error("RNG");
  std::wstring result=L"Local\\DanPlayer.Update.";
  for(const auto byte:bytes) { result+=L"0123456789abcdef"[byte>>4];result+=L"0123456789abcdef"[byte&15]; }
  return result;
}
PROCESS_INFORMATION Spawn(const fs::path& executable,std::wstring args) {
  std::wstring command=Quote(executable)+L" "+args;
  STARTUPINFOW startup{};startup.cb=sizeof(startup);PROCESS_INFORMATION process{};
  if(!CreateProcessW(executable.c_str(),command.data(),nullptr,nullptr,FALSE,CREATE_NO_WINDOW,
      nullptr,executable.parent_path().c_str(),&startup,&process))throw std::runtime_error("spawn");
  CloseHandle(process.hThread);process.hThread=nullptr;return process;
}
bool Reject(const std::function<void()>& action) {
  try { action();return false; }catch(const std::exception&) { return true; }
}
}
int wmain(int argc,wchar_t** argv) {
  try {
    if(argc==8&&std::wstring(argv[1])==L"--worker") {
      const fs::path target=argv[2],manifest=argv[3],report=argv[6];
      const bool cancel=std::wstring(argv[7])==L"cancel";
      const DWORD pid=std::stoul(argv[4]);
      HANDLE parent=OpenProcess(SYNCHRONIZE,FALSE,pid);
      if(!parent)return 30;
      {
        UpdateGate gate(target,manifest,L"26.0.4-snapshot.1",argv[4],argv[5]);
        if(std::wstring(argv[7])==L"expired") {
          if(gate.Poll(0)!=3)return 38;
          HANDLE late=OpenEventW(EVENT_MODIFY_STATE,FALSE,(std::wstring(argv[5])+L".Accepted").c_str());
          if(!late||!SetEvent(late))return 39;
          CloseHandle(late);
          if(gate.Poll()!=3||!Reject([&]{gate.Retry();})||!Reject([&]{gate.RequireReady(target,manifest);}))return 44;
          Write(report,"PASS expired handoff cannot be revived by late Accepted or retry");
          CloseHandle(parent);return 0;
        }
        HANDLE accepted=OpenEventW(SYNCHRONIZE,FALSE,(std::wstring(argv[5])+L".Accepted").c_str());
        if(!accepted||WaitForSingleObject(accepted,1000)!=WAIT_OBJECT_0)return 37;
        CloseHandle(accepted);
        if(gate.Poll()!=0||gate.Poll(0)!=2||!Reject([&]{gate.RequireReady(target,manifest);}))return 31;
        gate.Retry();if(gate.Poll()!=0)return 32;
        if(!cancel) {
          if(WaitForSingleObject(parent,5000)!=WAIT_OBJECT_0||gate.Poll()!=1)return 33;
          gate.RequireReady(target,manifest);
          if(!Reject([&]{gate.RequireReady(target.parent_path(),manifest);}))return 34;
          HANDLE lock=CreateFileW((target/L"engine.dll").c_str(),GENERIC_READ,0,nullptr,OPEN_EXISTING,0,nullptr);
          if(lock==INVALID_HANDLE_VALUE||!Reject([&]{gate.RequireReady(target,manifest);}))return 35;
          CloseHandle(lock);gate.RequireReady(target,manifest);
          Write(report,"PASS ready + timeout/retry + normal exit + exact target + file-lock preflight");
        }
      }
      if(cancel) {
        if(WaitForSingleObject(parent,0)!=WAIT_TIMEOUT)return 36;
        Write(report,"PASS cancellation releases installer resources without closing parent");
      }
      CloseHandle(parent);return 0;
    }
    if(argc==8&&std::wstring(argv[1])==L"--parent") {
      const fs::path worker=argv[2],target=argv[3],manifest=argv[4],report=argv[6];
      HANDLE ready=CreateEventW(nullptr,TRUE,FALSE,argv[5]);if(!ready)return 40;
      HANDLE accepted=CreateEventW(nullptr,TRUE,FALSE,(std::wstring(argv[5])+L".Accepted").c_str());if(!accepted)return 40;
      auto child=Spawn(worker,L"--worker "+Quote(target)+L" "+Quote(manifest)+L" "+
          std::to_wstring(GetCurrentProcessId())+L" "+argv[5]+L" "+Quote(report)+L" "+argv[7]);
      const DWORD state=WaitForSingleObject(ready,5000);CloseHandle(ready);
      if(state==WAIT_OBJECT_0&&std::wstring(argv[7])!=L"expired")SetEvent(accepted);
      CloseHandle(accepted);
      CloseHandle(child.hProcess);if(state!=WAIT_OBJECT_0)return 41;
      Sleep(350);return 0;
    }
    if(argc==3&&std::wstring(argv[1])==L"--hold") {
      HANDLE event=OpenEventW(SYNCHRONIZE,FALSE,argv[2]);if(!event)return 42;
      const auto result=WaitForSingleObject(event,5000);CloseHandle(event);return result==WAIT_OBJECT_0?0:43;
    }
    if(argc!=2)return 2;
    const auto root=fs::absolute(argv[1])/(L"update-gate-"+std::to_wstring(GetTickCount64()));
    bool sandbox=false;for(const auto& part:root)if(part==L"qa-installer")sandbox=true;
    if(!sandbox)return 3;
    const auto target=root/L"虚构播放器 目录";fs::create_directories(target/L".dan-player-install");
    wchar_t self[32768]{};if(!GetModuleFileNameW(nullptr,self,32768))return 4;
    fs::copy_file(self,target/L"Dan Player.exe");Write(target/L"engine.dll","fictional engine");
    Manifest payload{"26.0.4-snapshot.1",{{L"Dan Player.exe",Sha256(target/L"Dan Player.exe"),fs::file_size(target/L"Dan Player.exe")},
        {L"engine.dll",Sha256(target/L"engine.dll"),fs::file_size(target/L"engine.dll")}}};
    const auto manifest=root/L"payload.manifest";Write(manifest,SerializeManifest(payload));
    Write(target/kInstalledManifest,SerializeManifest(payload));
    const auto old_hash=Sha256(target/L"Dan Player.exe"),engine_hash=Sha256(target/L"engine.dll");
    unsigned passed=0;
    const auto name=EventName();HANDLE event=CreateEventW(nullptr,TRUE,FALSE,name.c_str());
    auto invalid=[&](const std::wstring& version,const std::wstring& pid,const std::wstring& nonce) {
      return Reject([&]{UpdateGate gate(target,manifest,version,pid,nonce);});
    };
    for(const auto& pid:{L"0",L"-1",L"4294967296",L"abc"}) {
      if(!invalid(L"26.0.4-snapshot.1",pid,name))return 5;++passed;
    }
    if(!invalid(L"26.0.4-snapshot.1",std::to_wstring(GetCurrentProcessId()),name))return 6;++passed;
    if(!invalid(L"26.0.3",L"1",name)||!invalid(L"26.0.4-snapshot.1",L"1",L"Local\\forged"))return 7;passed+=2;
    auto unrelated=Spawn(target/L"Dan Player.exe",L"--hold "+name);
    if(!invalid(L"26.0.4-snapshot.1",std::to_wstring(unrelated.dwProcessId),name))return 8;++passed;
    SetEvent(event);if(WaitForSingleObject(unrelated.hProcess,5000)!=WAIT_OBJECT_0)return 9;
    if(!invalid(L"26.0.4-snapshot.1",std::to_wstring(unrelated.dwProcessId),name))return 10;++passed;
    CloseHandle(unrelated.hProcess);CloseHandle(event);
    for(const auto* mode:{L"success",L"cancel",L"expired"}) {
      const auto report=root/(std::wstring(mode)+L".txt");
      auto process=Spawn(target/L"Dan Player.exe",L"--parent "+Quote(self)+L" "+Quote(target)+L" "+
          Quote(manifest)+L" "+EventName()+L" "+Quote(report)+L" "+mode);
      if(WaitForSingleObject(process.hProcess,8000)!=WAIT_OBJECT_0)return 11;
      DWORD exit_code=0;GetExitCodeProcess(process.hProcess,&exit_code);CloseHandle(process.hProcess);
      if(exit_code!=0)return 12;
      for(unsigned i=0;i<50&&!fs::exists(report);++i)Sleep(20);
      if(!fs::exists(report))return 13;
      std::ifstream input(report);std::cout<<input.rdbuf()<<'\n';++passed;
    }
    if(Sha256(target/L"Dan Player.exe")!=old_hash||Sha256(target/L"engine.dll")!=engine_hash||
        fs::exists(fs::path(target.wstring()+L".dan-player-backup")))return 14;
    ++passed;
    std::cout<<"RESULT "<<passed<<" update-gate scenarios passed; synthetic files unchanged; no UI/process termination\n";
    return 0;
  } catch(const std::exception& error) { std::cerr<<error.what()<<'\n';return 99; }
}
