cmake_minimum_required(VERSION 3.10)
project(whisper_jni LANGUAGES C CXX)

# ggml requires C++17; the old C++11 setting only worked because ggml's own
# targets override it per-target.
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(WHISPER_CPP ${CMAKE_CURRENT_SOURCE_DIR}/../../../../third_party/whisper.cpp)

# whisper.cpp build options for Android (CPU only).
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_METAL OFF CACHE BOOL "" FORCE)
set(GGML_ACCELERATE OFF CACHE BOOL "" FORCE)

# Whisper is statically linked into libwhisper.so to avoid colliding with the
# llama.cpp ggml libraries. Keep that one copy on the ARMv8-A baseline so every
# arm64-v8a Android phone supported by the APK can load and run it.

# Build whisper.cpp + its bundled ggml as static libraries. The app also links
# llama.cpp (flutter_llama), which ships its own shared libggml-*.so; if whisper
# emitted shared ggml libraries they would collide in the APK at merge time.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

add_subdirectory(${WHISPER_CPP} whisper_cpp)

# Hide the ggml symbols of whisper's bundled copy so they don't leak into the
# JNI library and interpose with llama.cpp's ggml at runtime.
set_target_properties(ggml-base ggml-cpu ggml PROPERTIES
    C_VISIBILITY_PRESET hidden
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON)

# libwhisper.so - JNI bridge. Output name must match Kotlin's
# System.loadLibrary("whisper").
add_library(whisper_jni SHARED whisper_jni.cpp)
set_target_properties(whisper_jni PROPERTIES OUTPUT_NAME whisper)
target_include_directories(whisper_jni PRIVATE
    ${WHISPER_CPP}/include
    ${WHISPER_CPP}/examples)
# Link to whisper (which transitively links ggml).
target_link_libraries(whisper_jni PRIVATE whisper log)
