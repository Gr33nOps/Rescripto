# Third-party code

| Directory | What | Version | License |
| --- | --- | --- | --- |
| `llama.cpp` | Text generation engine, built by `packages/rescripto_llama` | b6500 | MIT |
| `flutter_whisper` | Flutter plugin for on-device speech-to-text, adapted for Rescripto | 0.1.0 plus local changes | Apache 2.0 |
| `flutter_whisper/third_party/whisper.cpp` | Speech recognition engine | bundled with the plugin | MIT |

## Changes from upstream

`llama.cpp`:

- Removed files the app never builds that F-Droid's scanner would flag as
  binaries or prebuilt code: `models/ggml-vocab-*.gguf`, `media/`,
  `tools/server/` (including a prebuilt web UI), `examples/llama.android/`
  (it carried a Gradle wrapper JAR), and test fixtures in `tools/mtmd/` and
  `docs/`. With the library-only build options set in
  `packages/rescripto_llama/android/src/main/cpp/CMakeLists.txt`, none of
  them are referenced.
- A CI fix to the Vulkan shader generator (commit `57df8ec`). The Vulkan
  backend is not built for Android.

`flutter_whisper`: restored `miniaudio.h`, static ggml with hidden symbols so
it can't clash with llama.cpp's ggml, an ARMv8.0 CPU baseline, JNI and R8
fixes, and a native library loader that uses Android's extracted library
folder. `git log -- third_party/flutter_whisper` has the details.
