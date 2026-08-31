// Real Inno update flow, exclusively inside an owned never-switched desktop.
// The executable copied as "Dan Player.exe" is this synthetic parent fixture.
#include "installer_core.h"
#include <bcrypt.h>
#include <fstream>
#include <iostream>
#include <stdexcept>

using namespace dan::installer;
namespace {
std::wstring Quote(const fs::path& path) { return L"\""+path.wstring()+L"\""; }
void Write(const fs::path& path,const std::string& text) { fs::create_directories(path.parent_path());std::ofstream(path,std::ios::binary)<<text; }
std::string Read(const fs::path& path) { std::ifstream file(path,std::ios::binary);return {std::istreambuf_iterator<char>(file),{}}; }
std::wstring EventName() {
  BYTE bytes[32]{};if(BCryptGenRandom(nullptr,bytes,32,BCRYPT_USE_SYSTEM_PREFERRED_RNG)<0)throw std::runtime_error("RNG");
  std::wstring result=L"Local\\DanPlayer.Update.";
  for(const auto b:bytes) { result+=L"0123456789abcdef"[b>>4];result+=L"0123456789abcdef"[b&15]; }
  return result;
}
bool Sandbox(const fs::path& path) {
  if(!path.is_absolute())return false;
  for(const auto& part:path)if(part==L"qa-installer")return true;
  return false;
}
PROCESS_INFORMATION Spawn(const fs::path& file,std::wstring args,const wchar_t* desktop,DWORD flags=0) {
  std::wstring command=Quote(file)+L" "+args;
  STARTUPINFOW startup{};startup.cb=sizeof(startup);startup.lpDesktop=const_cast<wchar_t*>(desktop);
  PROCESS_INFORMATION process{};
  if(!CreateProcessW(file.c_str(),command.data(),nullptr,nullptr,FALSE,CREATE_NO_WINDOW|flags,
      nullptr,file.parent_path().c_str(),&startup,&process))throw std::runtime_error("Create owned fixture process failed");
  return process;
}
void Check(bool condition,const char* message) { if(!condition)throw std::runtime_error(message); }
}
int wmain(int argc,wchar_t** argv) {
  try {
    if(argc==4&&std::wstring(argv[1])==L"--lock") {
      HANDLE ready=OpenEventW(EVENT_MODIFY_STATE,FALSE,argv[3]);
      HANDLE file=CreateFileW(argv[2],GENERIC_READ,0,nullptr,OPEN_EXISTING,0,nullptr);
      if(!ready||file==INVALID_HANDLE_VALUE)return 60;
      SetEvent(ready);Sleep(7000);CloseHandle(file);CloseHandle(ready);return 0;
    }
    if(argc==9&&std::wstring(argv[1])==L"--parent") {
      const fs::path setup=argv[2],target=argv[3],log=argv[4];
      const std::wstring version=argv[5],mode=argv[6],nonce=argv[7];
      const wchar_t* desktop=argv[8];
      HANDLE ready=CreateEventW(nullptr,TRUE,FALSE,nonce.c_str());
      HANDLE accepted=CreateEventW(nullptr,TRUE,FALSE,(nonce+L".Accepted").c_str());
      if(!ready||!accepted)return 61;
      if(mode==L"locked") {
        const auto lock_event=nonce+L".Lock";
        HANDLE held=CreateEventW(nullptr,TRUE,FALSE,lock_event.c_str());
        auto lock=Spawn(target/L"Dan Player.exe",L"--lock "+Quote(target/L"engine.dll")+L" "+lock_event,desktop);
        CloseHandle(lock.hThread);CloseHandle(lock.hProcess);
        if(WaitForSingleObject(held,3000)!=WAIT_OBJECT_0)return 62;CloseHandle(held);
      }
      const auto pid=mode==L"wrongpid"?L"1":std::to_wstring(GetCurrentProcessId());
      const auto requested=mode==L"wrongversion"?L"0.0.1":version;
      std::wstring args=L"/SP- /SUPPRESSMSGBOXES /NORESTART /DANUPDATE=1 /DIR="+Quote(target)+
          L" /DANPARENTPID="+pid+L" /DANUPDATEVERSION="+requested+L" /DANUPDATEEVENT="+nonce+
          L" /QAUPDATEACTION="+mode+L" /LOG="+Quote(log);
      if(mode==L"failure")args+=L" /QAFAILAFTER=2";
      auto process=Spawn(setup,args,desktop);CloseHandle(process.hThread);
      const DWORD handshake=WaitForSingleObject(ready,5000);
      if(handshake==WAIT_OBJECT_0&&mode!=L"noack")SetEvent(accepted);
      CloseHandle(ready);CloseHandle(accepted);
      if(mode==L"timeout"||mode==L"cancel"||mode==L"wrongpid"||mode==L"wrongversion"||mode==L"noack") {
        const auto state=WaitForSingleObject(process.hProcess,10000);
        DWORD code=999;if(state==WAIT_OBJECT_0)GetExitCodeProcess(process.hProcess,&code);
        Write(log.parent_path()/L"parent-remained-alive.txt",std::to_string(code));
        CloseHandle(process.hProcess);return state==WAIT_OBJECT_0?0:63;
      }
      CloseHandle(process.hProcess);
      if(handshake!=WAIT_OBJECT_0)return 64;
      if(mode==L"retry")Sleep(2700);
      return mode==L"abnormal"?7:0;
    }
    if(argc!=4)return 2;
    const fs::path setup=fs::absolute(argv[1]),root=fs::absolute(argv[2]);
    const std::wstring version=argv[3];
    if(!Sandbox(setup)||!Sandbox(root)||setup.filename().wstring().find(L"-QA.exe")==std::wstring::npos)return 3;
    wchar_t self[32768]{};if(!GetModuleFileNameW(nullptr,self,32768))return 4;
    const auto desktop_name=L"DanPlayerUpdateQA-"+std::to_wstring(GetCurrentProcessId())+L"-"+std::to_wstring(GetTickCount64());
    HDESK desktop=CreateDesktopW(desktop_name.c_str(),nullptr,nullptr,0,GENERIC_ALL,nullptr);
    if(!desktop)throw std::runtime_error("Private desktop unavailable; no GUI fallback");
    unsigned passed=0;
    for(const auto* scenario:{L"none",L"desktop",L"start",L"both",L"timeout",L"cancel",
        L"wrongpid",L"wrongversion",L"retry",L"failure",L"locked",L"abnormal",L"noack"}) {
      const std::wstring mode=scenario;
      const auto folder=root/mode,target=folder/L"虚构播放器 安装目录",log=folder/L"update.log";
      fs::create_directories(target/L".dan-player-install");
      fs::copy_file(self,target/L"Dan Player.exe");Write(target/L"engine.dll","old fictional engine");
      Write(target/L"keep-notes.txt","unmanaged fictional note");
      Manifest old{"26.0.3",{{L"Dan Player.exe",Sha256(target/L"Dan Player.exe"),fs::file_size(target/L"Dan Player.exe")},
          {L"engine.dll",Sha256(target/L"engine.dll"),fs::file_size(target/L"engine.dll")}}};
      Write(target/kInstalledManifest,SerializeManifest(old));
      const bool desktop_link=mode==L"desktop"||mode==L"both",start_link=mode==L"start"||mode==L"both";
      const auto desktop_path=folder/L"redirect-desktop\\Dan Player.lnk",start_path=folder/L"redirect-start\\Dan Player.lnk";
      if(desktop_link)Write(desktop_path,"existing fictional desktop link");
      if(start_link)Write(start_path,"existing fictional start link");
      HANDLE job=CreateJobObjectW(nullptr,nullptr);JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
      limits.BasicLimitInformation.LimitFlags=JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
      Check(job&&SetInformationJobObject(job,JobObjectExtendedLimitInformation,&limits,sizeof(limits)),"create owned job");
      auto parent=Spawn(target/L"Dan Player.exe",L"--parent "+Quote(setup)+L" "+Quote(target)+L" "+Quote(log)+
          L" "+version+L" "+mode+L" "+EventName()+L" "+desktop_name,desktop_name.c_str(),CREATE_SUSPENDED);
      if(!AssignProcessToJobObject(job,parent.hProcess)) {
        // Only the exact suspended fixture, which has executed no application code.
        TerminateProcess(parent.hProcess,65);CloseHandle(parent.hThread);CloseHandle(parent.hProcess);CloseHandle(job);
        throw std::runtime_error("cannot bind fixture job");
      }
      ResumeThread(parent.hThread);CloseHandle(parent.hThread);
      const auto deadline=GetTickCount64()+25000;
      JOBOBJECT_BASIC_ACCOUNTING_INFORMATION accounting{};
      do {
        Check(QueryInformationJobObject(job,JobObjectBasicAccountingInformation,&accounting,sizeof(accounting),nullptr)!=FALSE,"query own job");
        if(!accounting.ActiveProcesses)break;
        Sleep(20);
      }while(GetTickCount64()<deadline);
      if(accounting.ActiveProcesses) {
        TerminateJobObject(job,66);WaitForSingleObject(parent.hProcess,3000);
        CloseHandle(parent.hProcess);CloseHandle(job);throw std::runtime_error("owned update fixture exceeded 25s");
      }
      CloseHandle(parent.hProcess);CloseHandle(job);
      const auto text=Read(log);
      const bool success=mode==L"none"||mode==L"desktop"||mode==L"start"||mode==L"both"||mode==L"retry";
      Check(!text.empty(),"missing actual Inno log");
      Check((text.find("Verified installation committed")!=std::string::npos)==success,"unexpected update commit outcome");
      if(success)Check(Read(target/L"Dan Player.exe")=="fictional new player payload","new synthetic payload not installed");
      else Check(Sha256(target/L"Dan Player.exe")==old.files[0].sha256&&Read(target/L"engine.dll")=="old fictional engine","failed update changed original files");
      Check(Read(target/L"keep-notes.txt")=="unmanaged fictional note","unknown data changed");
      Check(fs::exists(desktop_path)==desktop_link&&fs::exists(start_path)==start_link,"updater added/removed an unselected shortcut");
      if(desktop_link)Check(Read(desktop_path)=="existing fictional desktop link","desktop link changed");
      if(start_link)Check(Read(start_path)=="existing fictional start link","start link changed");
      if(mode==L"wrongpid"||mode==L"wrongversion")Check(text.find("UPDATE REJECTED")!=std::string::npos,"invalid handoff not rejected");
      if(mode==L"timeout"||mode==L"retry")Check(text.find("wait timed out")!=std::string::npos,"missing timeout path");
      if(mode==L"cancel")Check(text.find("QA update cancellation while parent remains alive")!=std::string::npos,"missing wait cancellation");
      if(mode==L"failure")Check(text.find("Original product files and installer metadata restored")!=std::string::npos,"failure did not roll back");
      if(!success&&mode!=L"failure")Check(text.find("Dest filename:")==std::string::npos,"rejected/waiting update reached file installation");
      Check(text.find("Failed to remove temporary directory")==std::string::npos,"Inno temporary cleanup failed");
      ++passed;std::cout<<"PASS actual private-desktop update "<<ToUtf8(mode)<<"; original/shortcut bounds verified\n";
    }
    Check(CloseDesktop(desktop)!=FALSE,"private desktop release");
    std::cout<<"RESULT "<<passed<<" real Inno update scenarios passed; no user desktop, real player, or real shortcut paths\n";
    return 0;
  }catch(const std::exception& error) { std::cerr<<error.what()<<'\n';return 99; }
}
