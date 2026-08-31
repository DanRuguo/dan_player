#include <windows.h>
int WINAPI wWinMain(HINSTANCE,HINSTANCE,PWSTR,int) {
  // Owned QA process: exits itself, never started from an installed player.
  Sleep(3500);
  return 0;
}
