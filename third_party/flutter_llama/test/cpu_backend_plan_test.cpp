#include <cassert>
#include <string>
#include <vector>

#include "../android/src/main/cpp/cpu_backend_plan.h"

static std::vector<std::string> names(CpuBackendFeatures features) {
    const auto plan = cpu_backend_plan(features);
    return {plan.begin(), plan.end()};
}

int main() {
    assert(names({}) == std::vector<std::string>{
        "libggml-cpu-android_armv8.0_1.so",
    });
    assert(names({true, false, false}) == std::vector<std::string>{
        "libggml-cpu-android_armv8.2_1.so",
        "libggml-cpu-android_armv8.0_1.so",
    });
    assert(names({true, true, false}) == std::vector<std::string>{
        "libggml-cpu-android_armv8.2_2.so",
        "libggml-cpu-android_armv8.2_1.so",
        "libggml-cpu-android_armv8.0_1.so",
    });
    assert(names({true, true, true}) == std::vector<std::string>{
        "libggml-cpu-android_armv8.6_1.so",
        "libggml-cpu-android_armv8.2_2.so",
        "libggml-cpu-android_armv8.2_1.so",
        "libggml-cpu-android_armv8.0_1.so",
    });
}
