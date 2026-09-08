cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "appearance_palette_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

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
target_link_libraries(${BINARY_NAME} PRIVATE "shell32.lib" "ole32.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# Explicit opt-in, hidden native HWND regression. It is never part of a normal
# release build/install and does not run a Flutter engine or touch user data.
add_executable(desktop_lyric_owned_window_test EXCLUDE_FROM_ALL
  "tests/owned_window_test.cpp"
  "win32_window.cpp"
)
apply_standard_settings(desktop_lyric_owned_window_test)
target_compile_definitions(desktop_lyric_owned_window_test PRIVATE "NOMINMAX")
target_include_directories(desktop_lyric_owned_window_test PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}" "${FLUTTER_MANAGED_DIR}/ephemeral")
# This target runs only after the helper build has generated its SDK files.
# Do not link Flutter's INTERFACE target: it carries flutter_assemble, which
# would regenerate Dart kernels without installing the matching release AOT.
add_library(desktop_lyric_test_flutter SHARED IMPORTED)
set_target_properties(desktop_lyric_test_flutter PROPERTIES
  IMPORTED_IMPLIB "${FLUTTER_MANAGED_DIR}/ephemeral/flutter_windows.dll.lib"
  IMPORTED_LOCATION "${FLUTTER_MANAGED_DIR}/ephemeral/flutter_windows.dll"
)
target_link_libraries(desktop_lyric_owned_window_test PRIVATE
  desktop_lyric_test_flutter "dwmapi.lib" "gdi32.lib")
set_target_properties(desktop_lyric_owned_window_test PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/palette_tests"
)

# Opt-in hidden real-AOT engine benchmark, run only after a matching helper
# Release bundle exists. Never depend on flutter/flutter_wrapper_app or their
# flutter_assemble step: tests must not regenerate the bundle's kernel/AOT.
# Compile private copies of the four SDK wrapper sources so CMake cannot attach
# their generated-source custom command to this target either.
set(PALETTE_TEST_WRAPPER_ROOT "${FLUTTER_MANAGED_DIR}/ephemeral/cpp_client_wrapper")
if(EXISTS "${PALETTE_TEST_WRAPPER_ROOT}/flutter_engine.cc")
  set(PALETTE_TEST_WRAPPER_SOURCES)
  foreach(PALETTE_TEST_WRAPPER_NAME
      core_implementations standard_codec flutter_engine flutter_view_controller)
    set(PALETTE_TEST_WRAPPER_COPY
      "${CMAKE_CURRENT_BINARY_DIR}/palette_engine_wrapper/${PALETTE_TEST_WRAPPER_NAME}.cc")
    configure_file(
      "${PALETTE_TEST_WRAPPER_ROOT}/${PALETTE_TEST_WRAPPER_NAME}.cc"
      "${PALETTE_TEST_WRAPPER_COPY}" COPYONLY)
    list(APPEND PALETTE_TEST_WRAPPER_SOURCES "${PALETTE_TEST_WRAPPER_COPY}")
  endforeach()
  add_executable(desktop_lyric_palette_engine_test EXCLUDE_FROM_ALL
    "tests/palette_engine_test.cpp"
    "appearance_palette_window.cpp"
    "win32_window.cpp"
    ${PALETTE_TEST_WRAPPER_SOURCES}
  )
  apply_standard_settings(desktop_lyric_palette_engine_test)
  target_compile_definitions(desktop_lyric_palette_engine_test PRIVATE "NOMINMAX")
  target_include_directories(desktop_lyric_palette_engine_test PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}" "${FLUTTER_MANAGED_DIR}/ephemeral"
    "${PALETTE_TEST_WRAPPER_ROOT}" "${PALETTE_TEST_WRAPPER_ROOT}/include")
  target_link_libraries(desktop_lyric_palette_engine_test PRIVATE
    desktop_lyric_test_flutter "dwmapi.lib" "gdi32.lib" "ole32.lib")
  set_target_properties(desktop_lyric_palette_engine_test PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/palette_tests")
  add_custom_command(TARGET desktop_lyric_palette_engine_test POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
      "$<TARGET_FILE:desktop_lyric_test_flutter>"
      "$<TARGET_FILE_DIR:desktop_lyric_palette_engine_test>"
    VERBATIM)
endif()
