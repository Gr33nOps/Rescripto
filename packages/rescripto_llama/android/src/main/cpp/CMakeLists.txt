cmake_minimum_required(VERSION 3.22.1)
project(rescripto_llama LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(LLAMA_CPP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../../third_party/llama.cpp")
if(NOT EXISTS "${LLAMA_CPP_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "llama.cpp sources not found at ${LLAMA_CPP_DIR}")
endif()

# Only the library: no tools, examples, tests, server, or network features.
set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS ON CACHE BOOL "" FORCE)

# Build one CPU backend per Android feature level and load the right one at
# runtime (see cpu_backend_candidates in the JNI source). Compiling dot-product
# or i8mm instructions into a single library would crash older phones.
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_BACKEND_DL ON CACHE BOOL "" FORCE)
if(ANDROID_ABI STREQUAL "arm64-v8a")
    set(GGML_CPU_ALL_VARIANTS ON CACHE BOOL "" FORCE)
else()
    # Only used for x86_64 emulator test builds: one generic CPU backend,
    # libggml-cpu.so. Release APKs are arm64-v8a only.
    set(GGML_CPU_ALL_VARIANTS OFF CACHE BOOL "" FORCE)
endif()
set(GGML_LLAMAFILE ON CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)

# CPU only. The ggml Vulkan backend needs loader symbols that Android 7 (API
# 24) does not have, and the 1B-3B models Rescripto offers run as fast or
# faster on a phone's CPU.
set(GGML_VULKAN OFF CACHE BOOL "" FORCE)
set(GGML_OPENCL OFF CACHE BOOL "" FORCE)

add_subdirectory("${LLAMA_CPP_DIR}" llama_cpp)

add_library(rescripto_llama SHARED rescripto_llama_jni.cpp)
target_link_libraries(rescripto_llama PRIVATE llama ggml ggml-base log)
