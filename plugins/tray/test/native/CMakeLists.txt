cmake_minimum_required(VERSION 3.16)
project(tray_menu_tests LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
enable_testing()

get_filename_component(TRAY_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
if(WIN32)
  set(FLUTTER_EPHEMERAL "${TRAY_ROOT}/../../windows/flutter/ephemeral"
      CACHE PATH "Flutter Windows engine and client wrapper")
  set(WRAPPER "${FLUTTER_EPHEMERAL}/cpp_client_wrapper")
  function(add_windows_tray_test target source)
    add_executable(${target}
      ${source}
      "${TRAY_ROOT}/windows/tray_window.cpp"
      "${TRAY_ROOT}/windows/tray_menu_session.cpp"
      "${TRAY_ROOT}/windows/tray_menu_icons.cpp"
      "${WRAPPER}/core_implementations.cc"
      "${WRAPPER}/standard_codec.cc"
      "${WRAPPER}/plugin_registrar.cc")
    target_compile_options(${target} PRIVATE /utf-8 /EHsc)
    target_include_directories(${target} PRIVATE
      "${FLUTTER_EPHEMERAL}" "${WRAPPER}/include")
    target_link_libraries(${target} PRIVATE
      "${FLUTTER_EPHEMERAL}/flutter_windows.dll.lib"
      user32 shell32 gdi32 comctl32)
    add_custom_command(TARGET ${target} POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${FLUTTER_EPHEMERAL}/flutter_windows.dll" "$<TARGET_FILE_DIR:${target}>")
  endfunction()
  add_windows_tray_test(tray_menu_state_test windows_menu_state_test.cpp)
  foreach(case checkmarks appearance)
    add_test(NAME tray_${case} COMMAND tray_menu_state_test ${case})
    set_tests_properties(tray_${case} PROPERTIES TIMEOUT 15)
  endforeach()
endif()
