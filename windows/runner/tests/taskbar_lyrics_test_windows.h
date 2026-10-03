#ifndef RUNNER_TESTS_TASKBAR_LYRICS_TEST_WINDOWS_H_
#define RUNNER_TESTS_TASKBAR_LYRICS_TEST_WINDOWS_H_
#include <windows.h>
#include <cwchar>
inline HWND FindOwnedTaskbarWindow(const wchar_t* name) {
  UINT message=std::wcscmp(name,L"DanPlayer.TaskbarLyrics.v1")==0 ? WM_APP+0x626 :
      std::wcscmp(name,L"DanPlayer.TaskbarLyrics.Next.v1")==0 ? WM_APP+0x627 :
      std::wcscmp(name,L"DanPlayer.TaskbarLyrics.PlayPause.v1")==0 ? WM_APP+0x628 : 0;
  if(message) {
    const HWND control=FindWindowExW(HWND_MESSAGE,nullptr,L"DanPlayer.TaskbarLyrics.Control.v1",nullptr);
    DWORD process=0; GetWindowThreadProcessId(control,&process);
    if(process==GetCurrentProcessId()) return reinterpret_cast<HWND>(SendMessageW(control,message,0,0));
  }
  struct Match { const wchar_t* name; HWND result=nullptr; } match{name};
  const auto inspect=[](HWND window,LPARAM data)->BOOL {
    auto& state=*reinterpret_cast<Match*>(data); wchar_t actual[128]{}; DWORD process=0;
    GetWindowThreadProcessId(window,&process); GetClassNameW(window,actual,128);
    if(process==GetCurrentProcessId() && std::wcscmp(actual,state.name)==0) {state.result=window; return FALSE;}
    return TRUE;
  };
  EnumWindows(inspect,reinterpret_cast<LPARAM>(&match));
  if(!match.result) EnumChildWindows(FindWindowW(L"Shell_TrayWnd",nullptr),inspect,reinterpret_cast<LPARAM>(&match));
  return match.result;
}
#endif
