# Rescripto

Rescripto is a Flutter app for private, on-device text rewriting — on-device by
default, and still the differentiator. In **Local** mode (the default) user
text, recordings, generated output, settings, and history stay on the device;
the network is used only to download the AI and voice models you choose, and
after that, rewriting and dictation run locally without an account or API key.
**Cloud** and **Hybrid** modes are opt-in: they let you rewrite with a cloud AI
provider you configure with your own API key, off by default and gated behind
an explicit choice during onboarding or in Privacy settings. See
[Processing modes](#processing-modes) below for exactly what that changes.

Source, releases, and issue tracking live on GitHub:

- Source: https://github.com/Gr33nOps/Rescripto
- Issues: https://github.com/Gr33nOps/Rescripto/issues
- Releases: https://github.com/Gr33nOps/Rescripto/releases

## Features

- Local GGUF rewriting with tone, intensity, length, audience, instructions,
  and up to three requested variants
- Optional Cloud/Hybrid rewriting against a provider you configure with your
  own API key — OpenAI, Anthropic, Gemini, Groq, OpenRouter, Mistral,
  Together, Ollama, or a custom OpenAI-compatible endpoint
- Resumable, checksum-verified model downloads
- Local SQLite rewrite history, copy, and share
- Android microphone dictation through whisper.cpp, or cloud speech-to-text
  via a configured provider
- A network kill switch, per-feature network toggles, and an in-app network
  log auditing every request the app has made or blocked
- Light, dark, and system themes

## Processing modes

Set once during onboarding, changeable anytime in Settings → Processing mode.

- **Local** (default) — rewriting always runs on-device. No network request
  a rewrite could ever trigger.
- **Cloud** — rewriting always uses the cloud provider and model you've
  selected. Needs at least one configured provider; otherwise the app tells
  you what's missing rather than silently falling back.
- **Hybrid** — prefers on-device; routes to cloud automatically only for
  long input (over ~1,500 characters) when a provider is configured. If
  on-device rewriting fails, Rescripto asks before sending your text to the
  cloud instead of retrying there silently — except when the *cloud* side
  fails and the fallback is *back* to your own device, which needs no
  permission. The AppBar always shows which side a rewrite will actually
  run on, and why.

### What leaves the device

| Mode | What's sent | To whom | In the network log? |
| --- | --- | --- | --- |
| Local | Nothing (beyond one-time model downloads) | Hugging Face (model files only) | Yes |
| Cloud | The text you're rewriting | Your configured cloud provider | Yes |
| Hybrid | The text you're rewriting, only for long input or after a local failure you approved | Your configured cloud provider | Yes |
| Cloud/system speech-to-text | Your voice recording | Your configured provider, or (system recognizer) Android itself | Cloud: yes. System recognizer: **no** — that audio path is native code this app cannot see |

Every Dart-initiated network request goes through one chokepoint
(`NetworkGuard`) that checks policy first and logs host + path — never a
header, body, or query string, and never a URL carrying a credential. The
in-app Network log (Settings → Privacy & network) shows this history
directly, and its own empty state and footer repeat what it cannot see. A
panic button on the same screen turns on the kill switch, cancels anything
in flight, disables every cloud provider, and deletes every saved API key,
in that order.

## Platform support

| Platform | Text rewriting | Voice dictation |
| --- | --- | --- |
| Android arm64-v8a | Supported | Supported |
| Android armeabi-v7a / x86_64 | Not currently packaged with llama | Not fully supported |
| iOS | Source integration present; requires macOS/Xcode verification | Not implemented |

Only Android arm64-v8a is packaged for release. Release ABI policy, signing,
and automation are intentionally handled separately from app code.

### CPU requirement

The native engines are compiled for `armv8.2-a+dotprod`, so the device needs a
64-bit ARM CPU with the dot-product extension — Cortex-A55/A75 and newer, which
is roughly 2018 onwards. This is what makes 4-bit models usable at all: without
it ggml falls back to scalar kernels and a rewrite takes minutes instead of
seconds. On an older core the engine refuses to load and says so rather than
crashing on an illegal instruction.

To support pre-2018 chips as well, switch `GGML_CPU_ARM_ARCH` in
`third_party/flutter_llama/android/src/main/cpp/CMakeLists.txt` for
`GGML_CPU_ALL_VARIANTS` + `GGML_BACKEND_DL`. llama.cpp ships Android-specific
variants and picks one at runtime from `AT_HWCAP`, but the backends are then
`dlopen`ed by directory scan, which also needs `useLegacyPackaging = true` so
the `.so` files are extracted to disk.

### GPU acceleration

Vulkan is compiled in but off by default. Bringing up a Vulkan device makes ggml
compile several hundred compute pipelines, which costs minutes on many Android
drivers, and for the 1B-3B models in this catalog most phones are faster on CPU
regardless. When the setting is off the model is loaded with an empty device
list so Vulkan is never initialized. Build with `-DFLUTTER_LLAMA_VULKAN=OFF` to
drop the backend entirely.

## Storage and downloads

Text models currently require approximately 769 MiB to 1.93 GiB each. Voice
models range from approximately 74 MiB (Tiny) to 2.88 GiB (Large v3); Base
(141 MiB) is the default and downloads on the first tap of the microphone.
Downloads come from Hugging Face. Temporary microphone recordings are deleted
after transcription or cancellation.

Android's automatic backup is switched off, so rewrite history and settings are
never copied to Google Drive and are not carried across by the device-transfer
wizard when you set up a new phone. The trade is deliberate: content that is
promised to stay on the device should not be uploaded by the platform on the
app's behalf. Moving your data to a new device is the job of an explicit
in-app export, which is not built yet.

## Development setup

Prerequisites:

- Flutter 3.44.9 / Dart 3.12.2 or the project-pinned compatible toolchain
- Java 17
- Android SDK and NDK `28.2.13676358` (the app and both native plugins pin the
  same version; mismatched NDKs make AGP pick one arbitrarily when merging the
  native libraries)
- CMake/Ninja installed through Android SDK tools
- For iOS work: macOS, Xcode, CocoaPods, and a real device/simulator build
  check

From the repository root:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

The two vendored Dart packages should also be checked explicitly because root
analysis excludes `third_party`:

```sh
cd third_party/flutter_llama
flutter analyze lib
flutter test

cd ../flutter_whisper
flutter analyze lib
flutter test
```

## GitHub workflow

The repository is set up so GitHub can validate the app without extra manual
steps:

- Pushes and pull requests run analysis, tests, and an Android debug build
- Tagged releases build signed Android APK and AAB artifacts
- Release notes are generated from the GitHub release workflow

If you change dependencies, model paths, or platform support, update both this
README and the in-app About section so they stay aligned.

## Architecture

- `lib/engine`: the `RewriteEngine` abstraction — local llama.cpp and the
  three cloud protocol adapters (`lib/engine/cloud`: OpenAI-compatible,
  Anthropic, Gemini) behind one interface, dispatched by
  `lib/services/routing/target_router.dart`
- `lib/speech`: the parallel `SpeechEngine` abstraction — local whisper.cpp,
  cloud transcription, and (not yet wired to a platform channel) the system
  recognizer
- `lib/state`: UI operation state and controllers
- `lib/services`: settings, SQLite, downloads, network policy/guard/log,
  credentials, provider configuration, and prompting
- `lib/models`: immutable app/domain models
- `third_party/flutter_llama`: vendored llama.cpp Flutter/native bridge
- `third_party/flutter_whisper`: vendored whisper.cpp Flutter/native bridge

## Licensing and model terms

This repository does not currently include a root project license. The vendored
`flutter_llama` wrapper uses the NativeMindNONC license, which requires written
permission for commercial use. The downloadable Gemma, Llama, and Qwen models
also have their own terms. Resolve those obligations and add appropriate
notices before distributing the app, especially for commercial use.
