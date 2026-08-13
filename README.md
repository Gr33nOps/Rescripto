# Rescripto

[![CI](https://github.com/Gr33nOps/Rescripto/actions/workflows/ci.yml/badge.svg)](https://github.com/Gr33nOps/Rescripto/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Gr33nOps/Rescripto?label=release)](https://github.com/Gr33nOps/Rescripto/releases)
[![License](https://img.shields.io/badge/license-Apache%202.0%20%2B%20restrictions-blue.svg)](#license)

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/icon/app_icon_foreground_white.png">
    <img src="assets/icon/app_icon_foreground.png" alt="Rescripto icon" width="96">
  </picture>
</p>

Rescripto is an Android app for rewriting text: fixing tone, trimming
length, aiming it at a different audience. It does that on-device by
default. In **Local** mode, whatever you type, dictate, generate, or save
stays on the phone. The only network call the app makes is to download the
model files you pick, and after that a rewrite doesn't touch the internet
at all. No account, no API key.

**Cloud** and **Hybrid** modes exist for when you want a bigger model than
a phone can run. You bring your own API key for whichever provider you
configure, and you can check exactly what that sends, and to whom, in the
app's own network log at any time.

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

- Local rewriting with GGUF models through llama.cpp: tone, intensity,
  length, audience, free-form instructions, and up to three variants per
  request
- Cloud rewriting is optional, using your own API key with OpenAI,
  Anthropic, Gemini, Groq, OpenRouter, Mistral, Together AI, Ollama, or any
  custom OpenAI-compatible endpoint
- Workflows that chain several rewrite steps together, so each step's
  output becomes the next step's input
- Voice dictation on-device through whisper.cpp, or through a cloud
  speech-to-text provider if you'd rather
- Model downloads from Hugging Face are resumable and checksum-verified
- Rewrite history lives in a local SQLite database, with copy and share
  built in
- Encrypted backup and restore, plus optional WebDAV sync to a server you
  run yourself. The server only ever sees ciphertext
- A real privacy control surface: a network kill switch, per-feature
  toggles for model downloads, cloud rewriting, cloud speech, backup sync,
  and update checks, and a log of every request the app has made or
  blocked
- Share text into Rescripto from any other app, and a Quick Settings tile
- Light, dark, and system themes

## Processing modes

You pick one during onboarding and can change it anytime in Settings →
Processing mode.

- **Local** (the default): rewriting always runs on-device. There's no
  network request a rewrite could trigger.
- **Cloud**: rewriting always goes to whatever provider and model you've
  set up. If nothing's configured, the app says so instead of quietly
  doing nothing.
- **Hybrid**: prefers on-device, and only routes to the cloud automatically
  for long input, over about 1,500 characters, when a provider is
  configured. If the on-device attempt fails, Rescripto asks before
  sending your text anywhere else. The one case that doesn't ask is a
  cloud failure falling back to your own device, since nothing left the
  phone in the first place. The app bar always shows which side a rewrite
  will run on and why, so you're never guessing.

## What leaves the device

| Mode | What's sent | To whom | In the network log? |
| --- | --- | --- | --- |
| Local | Nothing, apart from one-time model downloads | Hugging Face (model files only) | Yes |
| Cloud | The text you're rewriting | Your configured cloud provider | Yes |
| Hybrid | The text you're rewriting, only for long input or after a local failure you approved | Your configured cloud provider | Yes |
| Cloud/system speech-to-text | Your voice recording | Your configured provider, or Android itself for the system recognizer | Cloud: yes. System recognizer: no, that audio path is native code the app can't see |

Every network request the Dart side of the app makes goes through one
chokepoint (`NetworkGuard`) that checks policy first and logs the host and
path. Never a header, a body, or a query string, and never a URL carrying
a credential. Settings → Privacy & network shows that log directly. There's
also a panic button on the same screen: it turns on the kill switch,
cancels anything in flight, disables every cloud provider, and deletes
every saved API key, in that order.

## Install

Signed release builds are on the
[Releases page](https://github.com/Gr33nOps/Rescripto/releases) for every
tagged version, as both an APK and an AAB. Only `arm64-v8a` is packaged;
see [Platform support](#platform-support) for why.

To build from source instead, see [Development setup](#development-setup).

## Platform support

| Platform | Text rewriting | Voice dictation |
| --- | --- | --- |
| Android arm64-v8a | Supported | Supported |
| Android armeabi-v7a / x86_64 | Not currently packaged with llama | Not fully supported |
| iOS | Source integration present, needs macOS/Xcode verification | Not implemented |

Only Android arm64-v8a is packaged for release right now.

### CPU requirement

The native engines are compiled for `armv8.2-a+dotprod`, so the device
needs a 64-bit ARM CPU with the dot-product extension. That's roughly
Cortex-A55/A75 and newer, so phones from about 2018 onward. It's what
makes 4-bit models usable at all: without it, ggml falls back to scalar
kernels and a rewrite takes minutes instead of seconds. On an older core,
the engine just refuses to load and tells you why, rather than crashing on
an illegal instruction.

If you need to support older chips too, switch `GGML_CPU_ARM_ARCH` in
`third_party/flutter_llama/android/src/main/cpp/CMakeLists.txt` to
`GGML_CPU_ALL_VARIANTS` plus `GGML_BACKEND_DL`. llama.cpp ships
Android-specific variants and picks one at runtime from `AT_HWCAP`, but the
backends get `dlopen`ed by directory scan then, which also needs
`useLegacyPackaging = true` so the `.so` files land on disk.

### GPU acceleration

Vulkan is compiled in but off by default. Bringing up a Vulkan device makes
ggml compile several hundred compute pipelines, which can cost minutes on
some Android drivers, and for the 1B to 3B models in this catalog most
phones are faster on CPU anyway. With the setting off, the model loads
with an empty device list so Vulkan never initializes. Build with
`-DFLUTTER_LLAMA_VULKAN=OFF` if you want to drop the backend entirely.

## Storage and downloads

Text models run from about 769 MiB to 1.93 GiB each. Voice models range
from about 74 MiB (Tiny) up to 2.88 GiB (Large v3); Base, at 141 MiB, is
the default and downloads the first time you tap the microphone.
Everything comes from Hugging Face. Temporary microphone recordings get
deleted once transcription finishes or is canceled.

Android's automatic backup is turned off for this app on purpose, so
rewrite history and settings are never copied to Google Drive and don't
get carried over by the device-transfer wizard when you set up a new
phone. Content that's promised to stay on the device shouldn't get
uploaded by the platform behind your back. Moving your data to a new
device is what the in-app encrypted export and WebDAV sync above are for.

## Development setup

You'll need:

- Flutter 3.44.9 / Dart 3.12.2, or the project-pinned compatible toolchain
- Java 17
- Android SDK and NDK `28.2.13676358` (the app and both native plugins pin
  the same version; mismatched NDKs make AGP pick one arbitrarily when
  merging native libraries)
- CMake and Ninja, installed through the Android SDK tools
- For iOS work: macOS, Xcode, CocoaPods, and a real device or simulator to
  check the build on

From the repository root:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

The two vendored Dart packages sit outside root analysis, so check them
separately:

```sh
cd third_party/flutter_llama
flutter analyze lib
flutter test

cd ../flutter_whisper
flutter analyze lib
flutter test
```

### CI and releases

- Every push and pull request to `main` runs analysis, the full test
  suite, and an Android debug build (`.github/workflows/ci.yml`).
- Pushing a `vX.Y.Z` tag that matches the version in `pubspec.yaml` builds
  signed release APK and AAB artifacts and publishes a GitHub release with
  generated notes (`.github/workflows/release.yml`).

If you change dependencies, model paths, or platform support, please
update this README and the in-app About section together so they don't
drift apart.

## Architecture

- `lib/engine`: the `RewriteEngine` abstraction. Local llama.cpp and three
  cloud protocol adapters (`lib/engine/cloud`: OpenAI-compatible,
  Anthropic, Gemini) sit behind one interface, dispatched by
  `lib/services/routing/target_router.dart`
- `lib/speech`: the same idea for speech. Local whisper.cpp, cloud
  transcription, and the system recognizer
- `lib/state`: UI operation state and controllers
- `lib/services`: settings, SQLite, downloads, network policy/guard/log,
  credentials, provider configuration, and prompt building
- `lib/models`: immutable app and domain models
- `third_party/flutter_llama`: vendored llama.cpp Flutter/native bridge
- `third_party/flutter_whisper`: vendored whisper.cpp Flutter/native
  bridge

The deeper explanations live as comments next to the code they describe.
If you want to understand the two pieces most worth reading before
changing anything, start with `lib/services/routing/target_router.dart`
and `lib/services/network/network_guard.dart`.

## Contributing

Bug reports and pull requests are welcome. See
[CONTRIBUTING.md](.github/CONTRIBUTING.md) for the local workflow, coding
conventions, and what a good PR looks like here. Found a security issue?
Please read [SECURITY.md](.github/SECURITY.md) instead of opening a public
issue.

## License

Rescripto's own source code (everything outside `third_party/`) is
licensed under the [Apache License 2.0](LICENSE).

Two other things apply once the app is built and distributed, though:

- **`third_party/flutter_llama`**, the on-device llama.cpp bridge that
  ships in every build, is licensed under NativeMindNONC. See
  [`third_party/flutter_llama/LICENSE`](third_party/flutter_llama/LICENSE).
  It's free for personal, educational, and research use. Any commercial
  use of the built app needs written permission from that license's
  copyright holder first. `third_party/flutter_whisper` is Apache 2.0 and
  doesn't carry that restriction.
- **Downloadable models** (Gemma, Llama, Qwen, Whisper) each come with
  their own license from their publisher, fetched at runtime from Hugging
  Face rather than bundled with the app. Check those terms before
  downloading if you have a specific use in mind.

If you're thinking about anything beyond personal or non-commercial use,
read both license files above first.
