cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "desktop_integration.cpp"
  "flutter_window.cpp"
  "installer_launch_core.cpp"
  "installer_launcher.cpp"
  "main.cpp"
  "utils.cpp"
  "window_backdrop.cpp"
  "windows_shell.cpp"
  "win32_window.cpp"
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
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "shell32.lib" "ole32.lib" "uuid.lib"
  "gdi32.lib" "advapi32.lib" "bcrypt.lib" "crypt32.lib" "wintrust.lib" "version.lib" "propsys.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

add_executable(windows_shell_policy_test EXCLUDE_FROM_ALL
  "tests/windows_shell_policy_test.cpp")
set_target_properties(windows_shell_policy_test PROPERTIES
  CXX_STANDARD 17 CXX_STANDARD_REQUIRED YES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/desktop_tests")

add_executable(installer_launch_test EXCLUDE_FROM_ALL
  "tests/installer_launch_test.cpp"
  "tests/installer_launch_fixture.rc"
  "installer_launch_core.cpp"
)
target_compile_definitions(installer_launch_test PRIVATE "NOMINMAX")
target_link_libraries(installer_launch_test PRIVATE
  "bcrypt.lib" "crypt32.lib" "wintrust.lib" "version.lib" "shell32.lib")
if(MSVC)
  target_compile_options(installer_launch_test PRIVATE /W4 /WX /utf-8)
endif()
set_target_properties(installer_launch_test PROPERTIES
  CXX_STANDARD 17 CXX_STANDARD_REQUIRED YES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/desktop_tests"
)

# Capability/fallback tests have no Win32/Flutter dependencies. Keep their
# executable outside runner/Release so it never enters the portable app package.
add_executable(window_backdrop_policy_test EXCLUDE_FROM_ALL
  "tests/window_backdrop_policy_test.cpp"
)
set_target_properties(window_backdrop_policy_test PROPERTIES
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED YES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/backdrop_tests"
)

add_executable(window_backdrop_updates_test EXCLUDE_FROM_ALL
  "tests/window_backdrop_updates_test.cpp"
)
target_compile_definitions(window_backdrop_updates_test PRIVATE "NOMINMAX")
set_target_properties(window_backdrop_updates_test PROPERTIES
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED YES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/backdrop_tests"
)

add_executable(desktop_integration_policy_test EXCLUDE_FROM_ALL
  "tests/desktop_integration_policy_test.cpp"
)

add_executable(desktop_integration_fonts_test EXCLUDE_FROM_ALL
  "tests/desktop_integration_fonts_test.cpp"
)

add_executable(desktop_integration_blur_test EXCLUDE_FROM_ALL
  "tests/desktop_integration_blur_test.cpp"
)

add_executable(desktop_integration_paint_test EXCLUDE_FROM_ALL
  "tests/desktop_integration_paint_test.cpp"
)
target_compile_definitions(desktop_integration_paint_test PRIVATE "NOMINMAX")
target_link_libraries(desktop_integration_paint_test PRIVATE "gdi32.lib" "user32.lib")
set_target_properties(desktop_integration_paint_test PROPERTIES
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED YES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/desktop_tests"
)
target_compile_definitions(desktop_integration_blur_test PRIVATE "NOMINMAX")
target_link_libraries(desktop_integration_blur_test PRIVATE "gdi32.lib" "gdiplus.lib" "user32.lib")
set_target_properties(desktop_integration_blur_test PROPERTIES
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED YES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/desktop_tests"
)
target_compile_definitions(desktop_integration_fonts_test PRIVATE "NOMINMAX")
target_link_libraries(desktop_integration_fonts_test PRIVATE "gdi32.lib" "gdiplus.lib")
set_target_properties(desktop_integration_fonts_test PROPERTIES
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED YES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/desktop_tests"
)

add_executable(taskbar_thumbnail_policy_test EXCLUDE_FROM_ALL
  "tests/taskbar_thumbnail_policy_test.cpp"
)
target_compile_definitions(taskbar_thumbnail_policy_test PRIVATE "NOMINMAX")
set_target_properties(taskbar_thumbnail_policy_test PROPERTIES
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED YES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/desktop_tests"
)

add_executable(taskbar_peek_bitmap_test EXCLUDE_FROM_ALL
  "tests/taskbar_peek_bitmap_test.cpp"
)
target_compile_definitions(taskbar_peek_bitmap_test PRIVATE "NOMINMAX")
target_link_libraries(taskbar_peek_bitmap_test PRIVATE "gdi32.lib" "user32.lib")
set_target_properties(taskbar_peek_bitmap_test PROPERTIES
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED YES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/desktop_tests"
)

add_executable(taskbar_peek_geometry_test EXCLUDE_FROM_ALL
  "tests/taskbar_peek_geometry_test.cpp"
)
target_compile_definitions(taskbar_peek_geometry_test PRIVATE "NOMINMAX")
if(MSVC)
  target_compile_options(taskbar_peek_geometry_test PRIVATE /W4 /WX /utf-8)
endif()
target_link_libraries(taskbar_peek_geometry_test PRIVATE "user32.lib")
set_target_properties(taskbar_peek_geometry_test PROPERTIES
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED YES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/desktop_tests"
)
set_target_properties(desktop_integration_policy_test PROPERTIES
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED YES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/desktop_tests"
)

add_executable(window_resize_policy_test EXCLUDE_FROM_ALL
  "tests/window_resize_policy_test.cpp"
)

add_executable(window_corner_region_test EXCLUDE_FROM_ALL
  "tests/window_corner_region_test.cpp"
)
target_compile_definitions(window_corner_region_test PRIVATE "NOMINMAX")
target_link_libraries(window_corner_region_test PRIVATE "user32.lib" "gdi32.lib")
if(MSVC)
  target_compile_options(window_corner_region_test PRIVATE /W4 /WX /utf-8)
endif()
set_target_properties(window_corner_region_test PROPERTIES
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED YES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/window_tests"
)
target_compile_definitions(window_resize_policy_test PRIVATE "NOMINMAX")
set_target_properties(window_resize_policy_test PROPERTIES
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED YES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/window_tests"
)
