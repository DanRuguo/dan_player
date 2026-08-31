#include "installer_core.h"
#include <iostream>
#include <fstream>

using namespace dan::installer;
namespace {
PROCESS_INFORMATION Spawn(const fs::path& image, std::wstring arguments) {
  std::wstring command = L"\"" + image.wstring() + L"\" " + arguments;
  STARTUPINFOW startup{}; startup.cb = sizeof(startup); PROCESS_INFORMATION process{};
  if (!CreateProcessW(image.c_str(),command.data(),nullptr,nullptr,FALSE,CREATE_NO_WINDOW,
      nullptr,image.parent_path().c_str(),&startup,&process)) throw std::runtime_error("Cannot start owned QA process");
  CloseHandle(process.hThread); process.hThread = nullptr; return process;
}
DWORD Wait(PROCESS_INFORMATION& process) {
  if (WaitForSingleObject(process.hProcess,10000)!=WAIT_OBJECT_0) throw std::runtime_error("Bounded child timeout; process left intact");
  DWORD code=0; GetExitCodeProcess(process.hProcess,&code); CloseHandle(process.hProcess); return code;
}
}
int wmain(int argc,wchar_t** argv) {
  if (argc!=4) return 2;
  const fs::path base = fs::absolute(argv[1]) / (L"cleanup-"+std::to_wstring(GetTickCount64()));
  bool sandbox=false; for(const auto& part:base) if(part==L"qa-installer") sandbox=true;
  if(!sandbox) return 3;
  fs::create_directories(base);
  const fs::path cleanup=fs::absolute(argv[2]),fixture=fs::absolute(argv[3]);
  try {
    unsigned passed=0;
    for(const int mode:{0,1,2}) {
      const bool wrong_hash = mode == 2;
      const auto directory=base/std::to_wstring(mode);fs::create_directory(directory);
      const auto source=directory/L"setup-fixture.exe";
      fs::copy_file(fixture,source);
      std::ofstream(directory/L"keep.txt")<<"unrelated sibling stays";
      auto original=Spawn(source,L"");
      PROCESS_INFORMATION inner{};
      if(mode==1) inner=Spawn(fixture,L"");
      HANDLE file=CreateFileW(source.c_str(),FILE_READ_ATTRIBUTES,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,
          nullptr,OPEN_EXISTING,0,nullptr);
      BY_HANDLE_FILE_INFORMATION identity{};
      if(file==INVALID_HANDLE_VALUE||!GetFileInformationByHandle(file,&identity)) throw std::runtime_error("Identity fixture failed");
      CloseHandle(file);
      const auto digest=wrong_hash?std::string(64,'0'):Sha256(source);
      auto command=L"--delete-original "+std::to_wstring(original.dwProcessId)+L" "+std::to_wstring(mode==1?inner.dwProcessId:original.dwProcessId)+L" "+
          std::to_wstring(identity.dwVolumeSerialNumber)+L" "+std::to_wstring(identity.nFileIndexHigh)+L" "+
          std::to_wstring(identity.nFileIndexLow)+L" "+FromUtf8(digest)+L" \""+source.wstring()+L"\"";
      auto deleting=Spawn(cleanup,command);
      if(Wait(original)!=0) throw std::runtime_error("Fixture process failed");
      if(mode==1 && Wait(inner)!=0) throw std::runtime_error("Inner fixture process failed");
      const auto result=Wait(deleting);
      std::cout << "cleanup exit=" << result << " source-exists=" << fs::exists(source) << '\n';
      if((wrong_hash && (result==0||!fs::exists(source))) ||
          (!wrong_hash && (result!=0||fs::exists(source))) || !fs::exists(directory/L"keep.txt"))
        throw std::runtime_error("Exact-source self-delete boundary failed");
      ++passed; std::cout<<"PASS cleanup "<<(wrong_hash?"hash mismatch retains file":"exact owned source only")<<'\n';
    }
    auto unrequested=Spawn(cleanup,L"");
    if(Wait(unrequested)==0) throw std::runtime_error("Missing explicit deletion arguments accepted");
    ++passed; std::cout<<"PASS no deletion without explicit request\nRESULT "<<passed<<" cleanup scenarios passed\n";
    return 0;
  } catch(const std::exception& e) { std::cerr<<e.what()<<'\n'; return 1; }
}
