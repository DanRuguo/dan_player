// Runs only the fictional QA installer on a newly-created, never-switched-to
// desktop. This allows Inno's real visible-window cancellation guard to run
// without displaying a window on or inspecting the user's desktop.
#include <windows.h>
#include <filesystem>
#include <iostream>
#include <string>

namespace fs=std::filesystem;
namespace {
bool Sandbox(const fs::path& path) {
  if(!path.is_absolute()) return false;
  for(const auto& part:path) if(part==L"qa-installer") return true;
  return false;
}
std::wstring Quote(const std::wstring& value) {
  if(value.find(L'"')!=std::wstring::npos || (!value.empty()&&value.back()==L'\\'))
    throw std::runtime_error("Invalid QA path");
  return L"\""+value+L"\"";
}
}
int wmain(int argc,wchar_t** argv) {
  if(argc!=5) return 80;
  const fs::path setup=fs::absolute(argv[1]),target=fs::absolute(argv[2]),log=fs::absolute(argv[3]);
  if(!Sandbox(setup)||!Sandbox(target)||!Sandbox(log)||setup.filename().wstring().find(L"-QA.exe")==std::wstring::npos)
    return 81;
  const auto desktop_name=L"DanPlayerInstallerQA-"+std::to_wstring(GetCurrentProcessId())+L"-"+std::to_wstring(GetTickCount64());
  HDESK desktop=CreateDesktopW(desktop_name.c_str(),nullptr,nullptr,0,GENERIC_ALL,nullptr);
  if(!desktop) { std::cerr<<"Private QA desktop unavailable; no fallback attempted. Windows error="<<GetLastError()<<'\n'; return 82; }
  HANDLE job=CreateJobObjectW(nullptr,nullptr);
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
  limits.BasicLimitInformation.LimitFlags=JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if(!job||!SetInformationJobObject(job,JobObjectExtendedLimitInformation,&limits,sizeof(limits))) {
    if(job) CloseHandle(job); CloseDesktop(desktop); return 83;
  }
  DWORD result=84;
  try {
    const bool render=std::wstring(argv[4])==L"render";
    std::wstring command=Quote(setup.wstring())+L" /SP- /SUPPRESSMSGBOXES /NORESTART /QADESKTOP=1 /QASTART=1 ";
    command+=render?L" /QARENDERINSTALL=1 /QARENDERROOT="+Quote(log.parent_path().wstring()):
        L" /QAAUTOINSTALL=1 /QACANCELAFTER="+std::wstring(argv[4]);
    command+=L" /DIR="+Quote(target.wstring())+L" /LOG="+Quote(log.wstring());
    STARTUPINFOW startup{};startup.cb=sizeof(startup);
    startup.lpDesktop=const_cast<wchar_t*>(desktop_name.c_str());
    PROCESS_INFORMATION process{};
    if(CreateProcessW(setup.c_str(),command.data(),nullptr,nullptr,FALSE,CREATE_SUSPENDED|CREATE_NO_WINDOW,
        nullptr,setup.parent_path().c_str(),&startup,&process)) {
      if(AssignProcessToJobObject(job,process.hProcess)) {
        ResumeThread(process.hThread);
        if(WaitForSingleObject(process.hProcess,25000)==WAIT_OBJECT_0)
          GetExitCodeProcess(process.hProcess,&result);
        else {
          std::cerr<<"Owned QA job exceeded 25 seconds; stopping only this test job.\n";
          TerminateJobObject(job,85);WaitForSingleObject(process.hProcess,5000);result=85;
        }
      } else {
        // This exact suspended process has never executed application code.
        TerminateProcess(process.hProcess,86);WaitForSingleObject(process.hProcess,5000);result=86;
      }
      CloseHandle(process.hThread);CloseHandle(process.hProcess);
    }
  } catch(const std::exception& e) { std::cerr<<e.what()<<'\n'; }
  CloseHandle(job);
  if(!CloseDesktop(desktop)) { std::cerr<<"Cannot release private QA desktop: "<<GetLastError()<<'\n'; return 87; }
  std::cout<<"Private QA desktop released; installer exit="<<result<<". No desktop switch or capture.\n";
  return static_cast<int>(result);
}
