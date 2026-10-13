cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# One executable hosts two isolated process roles. Share the existing lyric
# window implementation, including its owned palette and DPI event bridge.
set(DESKTOP_LYRIC_RUNNER "${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/desktop_lyric/windows/runner")

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "desktop_integration.cpp"
  "taskbar_lyrics.cpp"
  "process_resource_monitor.cpp"
  "flutter_window.cpp"
  "installer_launch_core.cpp"
  "installer_launcher.cpp"
  "japanese_phonetic_controller.cpp"
  "japanese_phonetic_worker.cpp"
  "main.cpp"
  "utils.cpp"
  "window_backdrop.cpp"
  "windows_shell.cpp"
  "win32_window.cpp"
  "${DESKTOP_LYRIC_RUNNER}/flutter_window.cpp"
  "${DESKTOP_LYRIC_RUNNER}/appearance_palette_window.cpp"
  "${DESKTOP_LYRIC_RUNNER}/win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)
set_target_properties(${BINARY_NAME} PROPERTIES
  OUTPUT_NAME "${EXECUTABLE_OUTPUT_NAME}")

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Native tray labels contain Unicode. Keep their source encoding independent
# of the build machine's active Windows code page (for example CP936).
if(MSVC)
  target_compile_options(${BINARY_NAME} PRIVATE
    "$<$<COMPILE_LANGUAGE:CXX>:/utf-8>")
endif()

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib" "comctl32.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "shell32.lib" "ole32.lib" "uuid.lib"
  "gdi32.lib" "advapi32.lib" "bcrypt.lib" "crypt32.lib" "wintrust.lib" "version.lib" "propsys.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "uiautomationcore.lib" "gdiplus.lib" "usp10.lib" "pdh.lib" "psapi.lib")

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# Jump List invocations must not cold-load the Flutter/audio dependency graph.
add_executable(dan_player_shell_action WIN32 "shell_action_bridge.cpp")
apply_standard_settings(dan_player_shell_action)
target_link_libraries(dan_player_shell_action PRIVATE shell32 user32)
