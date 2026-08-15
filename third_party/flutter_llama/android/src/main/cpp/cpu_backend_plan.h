#pragma once

#include <vector>

struct CpuBackendFeatures {
    bool dotprod = false;
    bool fp16 = false;
    bool i8mm = false;
};

inline std::vector<const char*> cpu_backend_plan(CpuBackendFeatures features) {
    std::vector<const char*> result;
    if (features.dotprod && features.fp16 && features.i8mm) {
        result.push_back("libggml-cpu-android_armv8.6_1.so");
    }
    if (features.dotprod && features.fp16) {
        result.push_back("libggml-cpu-android_armv8.2_2.so");
    }
    if (features.dotprod) {
        result.push_back("libggml-cpu-android_armv8.2_1.so");
    }
    result.push_back("libggml-cpu-android_armv8.0_1.so");
    return result;
}
