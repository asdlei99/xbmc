include(cmake/scripts/linux/Linkers.txt)

# Main cpp
set(CORE_MAIN_SOURCE ${CMAKE_SOURCE_DIR}/xbmc/platform/posix/main.cpp)

# we always want to use GNU features if available, so set _GNU_SOURCE
set(ARCH_DEFINES -DTARGET_POSIX -DTARGET_LINUX -D_GNU_SOURCE)
set(SYSTEM_DEFINES -D__STDC_CONSTANT_MACROS -D_FILE_OFFSET_BITS=64)
set(PLATFORM_DIR platform/linux)
set(PLATFORMDEFS_DIR platform/posix)
set(CMAKE_SYSTEM_NAME Linux)
if(WITH_ARCH)
  set(ARCH ${WITH_ARCH})
else()
  if(CPU STREQUAL x86_64)
    set(ARCH x86_64-linux)
    set(NEON False)
  elseif(CPU MATCHES "i.86")
    set(ARCH i486-linux)
    set(NEON False)
    add_options(CXX ALL_BUILDS "-msse")
  elseif(CPU STREQUAL arm1176jzf-s)
    set(ARCH arm)
    set(NEON False)
    set(NEON_FLAGS "-mcpu=arm1176jzf-s -mtune=arm1176jzf-s -mfloat-abi=hard -mfpu=vfp")
  elseif(CPU MATCHES "cortex-a7")
    set(ARCH arm)
    set(NEON True)
    set(NEON_FLAGS "-fPIC -mcpu=cortex-a7")
  elseif(CPU MATCHES "cortex-a53")
    set(ARCH arm)
    set(NEON True)
    set(NEON_FLAGS "-fPIC -mcpu=cortex-a53")
  elseif(CPU MATCHES arm)
    set(ARCH arm)
    set(NEON True)
  elseif(CPU MATCHES aarch64 OR CPU MATCHES arm64)
    set(ARCH aarch64)
    set(NEON True)
  elseif(CPU MATCHES riscv64)
    set(ARCH riscv64)
    set(NEON False)
  elseif(CPU MATCHES ppc64le)
    set(ARCH ppc64le)
    set(NEON False)
  else()
    message(SEND_ERROR "Unknown CPU: ${CPU}")
  endif()
endif()

# disable the default gold linker when an alternative was enabled by the user
if(ENABLE_LLD OR ENABLE_MOLD)
  set(ENABLE_GOLD OFF CACHE BOOL "" FORCE)
elseif(ENABLE_GOLD)
  include(LDGOLD)
endif()
if(ENABLE_LLD)
  set(ENABLE_MOLD OFF CACHE BOOL "" FORCE)
  include(LLD)
elseif(ENABLE_MOLD)
  set(ENABLE_LLD OFF CACHE BOOL "" FORCE)
  include(MOLD)
endif()


if(CMAKE_BUILD_TYPE STREQUAL Release OR CMAKE_BUILD_TYPE STREQUAL MinSizeRel)

  # LTO Support, requires cmake >= 3.9
  if(CMAKE_VERSION VERSION_EQUAL 3.9.0 OR CMAKE_VERSION VERSION_GREATER 3.9.0)
    option(USE_LTO "Enable link time optimization. Specify an int for number of parallel jobs" OFF)
    if(USE_LTO)
      include(CheckIPOSupported)
      check_ipo_supported(RESULT HAVE_LTO OUTPUT _output)
      if(HAVE_LTO)
        set(CMAKE_INTERPROCEDURAL_OPTIMIZATION TRUE)

        # override flags to enable parallel processing
        set(NJOBS 2)
        if(USE_LTO MATCHES "^[0-9]+$")
          set(NJOBS ${USE_LTO})
        endif()

        if(CMAKE_COMPILER_IS_GNUCXX)
          # GCC
          # Make sure we strip binaries in Release build
          set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -s")
          set(CMAKE_CXX_COMPILE_OPTIONS_IPO -flto=${NJOBS} -fno-fat-lto-objects)
          set(CMAKE_C_COMPILE_OPTIONS_IPO -flto=${NJOBS} -fno-fat-lto-objects)
        elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
          # CLANG
          set(ENABLE_GOLD OFF CACHE BOOL "gold linker forced to off" FORCE)

          find_package(LLVM REQUIRED)

          if(NOT CLANG_LTO_CACHE)
            set(CLANG_LTO_CACHE ${PROJECT_BINARY_DIR}/.clang-lto.cache)
          endif()
          if(USE_LTO STREQUAL "all")
            set(NJOBS ${USE_LTO})
          endif()

          set(CMAKE_CXX_COMPILE_OPTIONS_IPO -flto=thin)
          set(CMAKE_C_COMPILE_OPTIONS_IPO -flto=thin)
          if(LLD_FOUND)
            set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,--thinlto-jobs=${NJOBS},--thinlto-cache-dir=${CLANG_LTO_CACHE}")
          elseif(MOLD_FOUND)
            set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,--plugin-opt=jobs=${NJOBS},--plugin-opt=cache-dir=${CLANG_LTO_CACHE}")
          endif()
          set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS}")
          set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS}")
        endif()
      else()
        message(WARNING "LTO optimization not supported: ${_output}")
        unset(_output)
      endif()
    endif()
  endif()
endif()

if(KODI_DEPENDSBUILD)
  # Binaries should be directly runnable from host, so include rpath to depends
  set(CMAKE_INSTALL_RPATH "${DEPENDS_PATH}/lib")
  set(CMAKE_BUILD_WITH_INSTALL_RPATH TRUE)
endif()

include(CheckIncludeFiles)
check_include_files("linux/udmabuf.h" HAVE_LINUX_UDMABUF)
if(HAVE_LINUX_UDMABUF)
  list(APPEND ARCH_DEFINES "-DHAVE_LINUX_UDMABUF=1")
else()
  message(STATUS "include/linux/udmabuf.h not found")
endif()

check_include_files("linux/dma-heap.h" HAVE_LINUX_DMA_HEAP)
if(HAVE_LINUX_DMA_HEAP)
  list(APPEND ARCH_DEFINES "-DHAVE_LINUX_DMA_HEAP=1")
else()
  message(STATUS "include/linux/dma-heap.h not found")
endif()

check_include_files("linux/dma-buf.h" HAVE_LINUX_DMA_BUF)
if(HAVE_LINUX_DMA_BUF)
  list(APPEND ARCH_DEFINES "-DHAVE_LINUX_DMA_BUF=1")
else()
  message(STATUS "include/linux/dma-buf.h not found")
endif()

include(CheckSymbolExists)
set(CMAKE_REQUIRED_DEFINITIONS "-D_GNU_SOURCE")
check_symbol_exists("mkostemp" "stdlib.h" HAVE_MKOSTEMP)
set(CMAKE_REQUIRED_DEFINITIONS "")
if(HAVE_MKOSTEMP)
  list(APPEND ARCH_DEFINES "-DHAVE_MKOSTEMP=1")
endif()

set(CMAKE_REQUIRED_DEFINITIONS "-D_GNU_SOURCE")
check_symbol_exists("memfd_create" "sys/mman.h" HAVE_LINUX_MEMFD)
set(CMAKE_REQUIRED_DEFINITIONS "")
if(HAVE_LINUX_MEMFD)
  list(APPEND ARCH_DEFINES "-DHAVE_LINUX_MEMFD=1")
else()
  message(STATUS "memfd_create() not found")
endif()

# Additional SYSTEM_DEFINES
list(APPEND SYSTEM_DEFINES -DHAS_POSIX_NETWORK -DHAS_LINUX_NETWORK)

# Code Coverage
if(CMAKE_BUILD_TYPE STREQUAL Coverage)
  set(COVERAGE_TEST_BINARY ${APP_NAME_LC}-test)
  set(COVERAGE_SOURCE_DIR ${CMAKE_SOURCE_DIR})
  set(COVERAGE_DEPENDS "\${APP_NAME_LC}" "\${APP_NAME_LC}-test")
  set(COVERAGE_EXCLUDES */test/* lib/* */lib/*)
endif()

if(NOT "x11" IN_LIST CORE_PLATFORM_NAME_LC)
  set(ENABLE_VDPAU OFF CACHE BOOL "Disabling VDPAU" FORCE)
endif()

if("x11" IN_LIST CORE_PLATFORM_NAME_LC AND ENABLE_VDPAU)
  set(ENABLE_GLX ON CACHE BOOL "Enabling GLX" FORCE)
endif()

# Architecture endianness detector
include(TestBigEndian)
TEST_BIG_ENDIAN(ARCH_IS_BIGENDIAN)
if(ARCH_IS_BIGENDIAN)
  message(STATUS "Host architecture is big-endian")
  list(APPEND ARCH_DEFINES "-DWORDS_BIGENDIAN=1")
else()
  message(STATUS "Host architecture is little-endian")
endif()
