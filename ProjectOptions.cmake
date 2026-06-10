include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


include(CheckCXXSourceCompiles)


macro(embedded_core_supports_sanitizers)
  # Emscripten doesn't support sanitizers
  if(EMSCRIPTEN)
    set(SUPPORTS_UBSAN OFF)
    set(SUPPORTS_ASAN OFF)
  elseif((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)

    message(STATUS "Sanity checking UndefinedBehaviorSanitizer, it should be supported on this platform")
    set(TEST_PROGRAM "int main() { return 0; }")

    # Check if UndefinedBehaviorSanitizer works at link time
    set(CMAKE_REQUIRED_FLAGS "-fsanitize=undefined")
    set(CMAKE_REQUIRED_LINK_OPTIONS "-fsanitize=undefined")
    check_cxx_source_compiles("${TEST_PROGRAM}" HAS_UBSAN_LINK_SUPPORT)

    if(HAS_UBSAN_LINK_SUPPORT)
      message(STATUS "UndefinedBehaviorSanitizer is supported at both compile and link time.")
      set(SUPPORTS_UBSAN ON)
    else()
      message(WARNING "UndefinedBehaviorSanitizer is NOT supported at link time.")
      set(SUPPORTS_UBSAN OFF)
    endif()
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    if (NOT WIN32)
      message(STATUS "Sanity checking AddressSanitizer, it should be supported on this platform")
      set(TEST_PROGRAM "int main() { return 0; }")

      # Check if AddressSanitizer works at link time
      set(CMAKE_REQUIRED_FLAGS "-fsanitize=address")
      set(CMAKE_REQUIRED_LINK_OPTIONS "-fsanitize=address")
      check_cxx_source_compiles("${TEST_PROGRAM}" HAS_ASAN_LINK_SUPPORT)

      if(HAS_ASAN_LINK_SUPPORT)
        message(STATUS "AddressSanitizer is supported at both compile and link time.")
        set(SUPPORTS_ASAN ON)
      else()
        message(WARNING "AddressSanitizer is NOT supported at link time.")
        set(SUPPORTS_ASAN OFF)
      endif()
    else()
      set(SUPPORTS_ASAN ON)
    endif()
  endif()
endmacro()

macro(embedded_core_setup_options)
  option(embedded_core_ENABLE_HARDENING "Enable hardening" ON)
  option(embedded_core_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    embedded_core_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    embedded_core_ENABLE_HARDENING
    OFF)

  embedded_core_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR embedded_core_PACKAGING_MAINTAINER_MODE)
    option(embedded_core_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(embedded_core_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(embedded_core_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(embedded_core_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(embedded_core_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(embedded_core_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(embedded_core_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(embedded_core_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(embedded_core_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(embedded_core_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(embedded_core_ENABLE_PCH "Enable precompiled headers" OFF)
    option(embedded_core_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(embedded_core_ENABLE_IPO "Enable IPO/LTO" ON)
    option(embedded_core_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(embedded_core_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(embedded_core_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(embedded_core_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(embedded_core_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(embedded_core_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(embedded_core_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(embedded_core_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(embedded_core_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(embedded_core_ENABLE_PCH "Enable precompiled headers" OFF)
    option(embedded_core_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      embedded_core_ENABLE_IPO
      embedded_core_WARNINGS_AS_ERRORS
      embedded_core_ENABLE_SANITIZER_ADDRESS
      embedded_core_ENABLE_SANITIZER_LEAK
      embedded_core_ENABLE_SANITIZER_UNDEFINED
      embedded_core_ENABLE_SANITIZER_THREAD
      embedded_core_ENABLE_SANITIZER_MEMORY
      embedded_core_ENABLE_UNITY_BUILD
      embedded_core_ENABLE_CLANG_TIDY
      embedded_core_ENABLE_CPPCHECK
      embedded_core_ENABLE_COVERAGE
      embedded_core_ENABLE_PCH
      embedded_core_ENABLE_CACHE)
  endif()

  embedded_core_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (embedded_core_ENABLE_SANITIZER_ADDRESS OR embedded_core_ENABLE_SANITIZER_THREAD OR embedded_core_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(embedded_core_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(embedded_core_global_options)
  if(embedded_core_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    embedded_core_enable_ipo()
  endif()

  embedded_core_supports_sanitizers()

  if(embedded_core_ENABLE_HARDENING AND embedded_core_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR embedded_core_ENABLE_SANITIZER_UNDEFINED
       OR embedded_core_ENABLE_SANITIZER_ADDRESS
       OR embedded_core_ENABLE_SANITIZER_THREAD
       OR embedded_core_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${embedded_core_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${embedded_core_ENABLE_SANITIZER_UNDEFINED}")
    embedded_core_enable_hardening(embedded_core_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(embedded_core_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(embedded_core_warnings INTERFACE)
  add_library(embedded_core_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  embedded_core_set_project_warnings(
    embedded_core_warnings
    ${embedded_core_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  include(cmake/Linker.cmake)
  # Must configure each target with linker options, we're avoiding setting it globally for now

  if(NOT EMSCRIPTEN)
    include(cmake/Sanitizers.cmake)
    embedded_core_enable_sanitizers(
      embedded_core_options
      ${embedded_core_ENABLE_SANITIZER_ADDRESS}
      ${embedded_core_ENABLE_SANITIZER_LEAK}
      ${embedded_core_ENABLE_SANITIZER_UNDEFINED}
      ${embedded_core_ENABLE_SANITIZER_THREAD}
      ${embedded_core_ENABLE_SANITIZER_MEMORY})
  endif()

  set_target_properties(embedded_core_options PROPERTIES UNITY_BUILD ${embedded_core_ENABLE_UNITY_BUILD})

  if(embedded_core_ENABLE_PCH)
    target_precompile_headers(
      embedded_core_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(embedded_core_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    embedded_core_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(embedded_core_ENABLE_CLANG_TIDY)
    embedded_core_enable_clang_tidy(embedded_core_options ${embedded_core_WARNINGS_AS_ERRORS})
  endif()

  if(embedded_core_ENABLE_CPPCHECK)
    embedded_core_enable_cppcheck(${embedded_core_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(embedded_core_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    embedded_core_enable_coverage(embedded_core_options)
  endif()

  if(embedded_core_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(embedded_core_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(embedded_core_ENABLE_HARDENING AND NOT embedded_core_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR embedded_core_ENABLE_SANITIZER_UNDEFINED
       OR embedded_core_ENABLE_SANITIZER_ADDRESS
       OR embedded_core_ENABLE_SANITIZER_THREAD
       OR embedded_core_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    embedded_core_enable_hardening(embedded_core_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
