#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"
#include "windows_shell.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  auto command_line_arguments = GetCommandLineArguments();
  PlayerInstanceLease instance_lease(command_line_arguments);
  if (!instance_lease.is_primary()) {
    if (!instance_lease.forwarded()) {
      MessageBoxW(nullptr,
          L"Dan Player 正在启动或暂未响应，请稍后重试。",
          L"Dan Player", MB_OK | MB_ICONINFORMATION);
    }
    ::CoUninitialize();
    return instance_lease.forwarded() ? EXIT_SUCCESS : EXIT_FAILURE;
  }

  flutter::DartProject project(L"data");
  project.set_ui_thread_policy(flutter::UIThreadPolicy::RunOnSeparateThread);

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  const int window_width = 1280;
  const int window_height = 720;
  int origin_x = (GetSystemMetrics(SM_CXSCREEN) - window_width) / 2;
  int origin_y = (GetSystemMetrics(SM_CYSCREEN) - window_height) / 2;
  if (origin_x < 0) {
    origin_x = 0;
  }
  if (origin_y < 0) {
    origin_y = 0;
  }
  Win32Window::Point origin(origin_x, origin_y);
  Win32Window::Size size(window_width, window_height);
  if (!window.Create(L"Dan Player", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
