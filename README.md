# Rescripto

[![CI](https://github.com/Gr33nOps/Rescripto/actions/workflows/ci.yml/badge.svg)](https://github.com/Gr33nOps/Rescripto/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Gr33nOps/Rescripto?label=release)](https://github.com/Gr33nOps/Rescripto/releases)
[![License](https://img.shields.io/badge/license-Apache%202.0%20%2B%20restrictions-blue.svg)](#license)

Rescripto is an Android app for rewriting text — polishing tone, adjusting
length, targeting an audience — **on-device by default**. In **Local** mode,
the text you type, your dictation, generated output, settings, and rewrite
history never leave the phone. The network is touched only to download the
AI/voice model files you explicitly choose; after that, rewriting and
transcription run fully offline, with no account and no API key.

**Cloud** and **Hybrid** modes are opt-in for when you want a bigger model
than a phone can run: you bring your own API key for a provider you
configure, and the app is explicit — in the UI and in an on-device network
log — about exactly what that sends and to whom.

<p align="center">
  <img src="assets/icon/app_icon_foreground.png" alt="Rescripto icon" width="96">
</p>

## Contents

- [Features](#features)
- [Processing modes](#processing-modes)
- [What leaves the device](#what-leaves-the-device)
- [Install](#install)
- [Platform support](#platform-support)
- [Storage and downloads](#storage-and-downloads)
- [Development setup](#development-setup)
- [Architecture](#architecture)
- [Contributing](#contributing)
- [License](#license)

## Features

- **Local rewriting** with GGUF models via llama.cpp — tone, intensity,
  length, audience, free-form instructions, and up to three variants per
  request
- **Optional cloud rewriting** against a provider you configure with your
  own API key: OpenAI, Anthropic, Gemini, Groq, OpenRouter, Mistral,
  Together AI, Ollama, or any custom OpenAI-compatible endpoint
- **Workflows** — chain multiple rewrite steps together, each step's output
  feeding the next
- **Voice dictation** on-device via whisper.cpp, or through a configured
  cloud speech-to-text provider
- **Resumable, checksum-verified model downloads** from Hugging Face
- **Local rewrite history** with copy and share, stored in SQLite on-device
- **Encrypted backup and restore**, plus optional WebDAV sync to a server
  you control — the server only ever sees ciphertext
- **A real privacy control surface**: a network kill switch, per-feature
  network toggles (model downloads, cloud rewriting, cloud speech,
  backup sync, update checks), and an in-app network log auditing every
  request the app has made or blocked
- **Android system integration** — share text into Rescripto from any app
  (`PROCESS_TEXT` / `ACTION_SEND`), and a Quick Settings tile
- Light, dark, and system themes

## Processing modes

Set once during onboarding, changeable anytime in Settings → Processing
mode.

- **Local** (default) — rewriting always runs on-device. No network request
  a rewrite could ever trigger.
- **Cloud** — rewriting always uses the cloud provider and model you've
  selected. Needs at least one configured provider; otherwise the app tells
  you what's missing rather than silently falling back.
- **Hybrid** — prefers on-device; routes to cloud automatically only for
  long input (over ~1,500 characters) when a provider is configured. If
  on-device rewriting fails, Rescripto asks before sending your text to the
  cloud instead of retrying there silently — the one exception is a cloud
  failure falling back *to* your own device, which needs no permission
  since nothing left the phone. The app bar always shows which side a
  rewrite will actually run on, and why.

## What leaves the device

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
directly. A panic button on the same screen turns on the kill switch,
cancels anything in flight, disables every cloud provider, and deletes
every saved API key, in that order.

## Install

Signed release builds (APK and AAB) are published on the
[Releases page](https://github.com/Gr33nOps/Rescripto/releases) for every
tagged version. Only `arm64-v8a` is packaged — see
[Platform support](#platform-support) for why.

To build from source, see [Development setup](#development-setup) below.

## Platform support

| Platform | Text rewriting | Voice dictation |
| --- | --- | --- |
| Android arm64-v8a | Supported | Supported |
| Android armeabi-v7a / x86_64 | Not currently packaged with llama | Not fully supported |
| iOS | Source integration present; requires macOS/Xcode verification | Not implemented |

Only Android arm64-v8a is packaged for release.

### CPU requirement

The native engines are compiled for `armv8.2-a+dotprod`, so the device needs
a 64-bit ARM CPU with the dot-product extension — Cortex-A55/A75 and newer,
roughly 2018 onward. This is what makes 4-bit models usable at all: without
it, ggml falls back to scalar kernels and a rewrite takes minutes instead of
seconds. On an older core, the engine refuses to load and says so, rather
than crashing on an illegal instruction.

To support pre-2018 chips as well, switch `GGML_CPU_ARM_ARCH` in
`third_party/flutter_llama/android/src/main/cpp/CMakeLists.txt` to
`GGML_CPU_ALL_VARIANTS` + `GGML_BACKEND_DL`. llama.cpp ships Android-specific
variants and picks one at runtime from `AT_HWCAP`, but the backends are then
`dlopen`ed by directory scan, which also needs `useLegacyPackaging = true` so
the `.so` files are extracted to disk.

### GPU acceleration

Vulkan is compiled in but off by default. Bringing up a Vulkan device makes
ggml compile several hundred compute pipelines, which costs minutes on many
Android drivers, and for the 1B–3B models in this catalog most phones are
faster on CPU regardless. When the setting is off, the model is loaded with
an empty device list so Vulkan is never initialized. Build with
`-DFLUTTER_LLAMA_VULKAN=OFF` to drop the backend entirely.

## Storage and downloads

Text models currently require approximately 769 MiB to 1.93 GiB each. Voice
models range from approximately 74 MiB (Tiny) to 2.88 GiB (Large v3); Base
(141 MiB) is the default and downloads on the first tap of the microphone.
Downloads come from Hugging Face. Temporary microphone recordings are
deleted after transcription or cancellation.

Android's automatic backup is switched off, so rewrite history and settings
are never copied to Google Drive and are not carried across by the
device-transfer wizard when you set up a new phone. The trade is
deliberate: content that is promised to stay on the device should not be
uploaded by the platform on the app's behalf. Moving your data to a new
device is the job of the in-app encrypted export/WebDAV sync described
above.

## Development setup

Prerequisites:

- Flutter 3.44.9 / Dart 3.12.2, or the project-pinned compatible toolchain
- Java 17
- Android SDK and NDK `28.2.13676358` (the app and both native plugins pin
  the same version; mismatched NDKs make AGP pick one arbitrarily when
  merging the native libraries)
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

The two vendored Dart packages are excluded from root analysis and should be
checked explicitly:

```sh
cd third_party/flutter_llama
flutter analyze lib
flutter test

cd ../flutter_whisper
flutter analyze lib
flutter test
```

### CI and releases

- Every push and pull request to `main` runs analysis, the full test suite,
  and an Android debug build (`.github/workflows/ci.yml`).
- Pushing a `vX.Y.Z` tag that matches `pubspec.yaml`'s version builds signed
  release APK/AAB artifacts and publishes a GitHub release with generated
  notes (`.github/workflows/release.yml`).

If you change dependencies, model paths, or platform support, update both
this README and the in-app About section so they stay aligned.

## Architecture

- `lib/engine` — the `RewriteEngine` abstraction: local llama.cpp and three
  cloud protocol adapters (`lib/engine/cloud`: OpenAI-compatible,
  Anthropic, Gemini) behind one interface, dispatched by
  `lib/services/routing/target_router.dart`
- `lib/speech` — the parallel `SpeechEngine` abstraction: local whisper.cpp,
  cloud transcription, and the system recognizer
- `lib/state` — UI operation state and controllers
- `lib/services` — settings, SQLite, downloads, network policy/guard/log,
  credentials, provider configuration, and prompt building
- `lib/models` — immutable app/domain models
- `third_party/flutter_llama` — vendored llama.cpp Flutter/native bridge
- `third_party/flutter_whisper` — vendored whisper.cpp Flutter/native bridge

Deeper module-level docs live as comments alongside the code they describe
— start at `lib/services/routing/target_router.dart` and
`lib/services/network/network_guard.dart` for the two pieces most worth
understanding before changing anything.

## Contributing

Bug reports and pull requests are welcome — see
[CONTRIBUTING.md](.github/CONTRIBUTING.md) for the local workflow, coding
conventions, and what a good PR looks like. Found a security issue? Please
read [SECURITY.md](.github/SECURITY.md) instead of opening a public issue.

## License

Rescripto's own source code (everything outside `third_party/`) is licensed
under the [Apache License 2.0](LICENSE).

Two things sit on top of that and apply to the app as a whole once it's
built and distributed:

- **`third_party/flutter_llama`** (the on-device llama.cpp bridge that ships
  in every build) is licensed under NativeMindNONC — see
  [`third_party/flutter_llama/LICENSE`](third_party/flutter_llama/LICENSE).
  It's free for non-commercial use (personal, educational, research); any
  commercial use of the built app requires written permission from that
  license's copyright holder. `third_party/flutter_whisper` is Apache 2.0
  and carries no such restriction.
- **Downloadable models** (Gemma, Llama, Qwen, Whisper) each carry their own
  license terms from their respective publishers, fetched at runtime from
  Hugging Face rather than bundled — review those terms for your intended
  use before downloading.

If you're planning anything beyond personal or non-commercial use, read both
license files above before you rely on this project.
