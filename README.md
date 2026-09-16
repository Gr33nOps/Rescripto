<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/icon/app_icon_foreground_white.png">
    <img src="assets/icon/app_icon_foreground.png" alt="Rescripto" width="104">
  </picture>
</p>

<h1 align="center">Rescripto</h1>

<p align="center">
  <strong>Clearer writing, on your terms.</strong><br>
  An Android app that rewrites and dictates text on your phone, or through a cloud provider you pick.
</p>

<p align="center">
  <a href="https://github.com/Gr33nOps/Rescripto/actions/workflows/ci.yml"><img src="https://github.com/Gr33nOps/Rescripto/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
  <a href="https://github.com/Gr33nOps/Rescripto/releases"><img src="https://img.shields.io/github/v/release/Gr33nOps/Rescripto?label=release" alt="Latest release"></a>
  <a href="#license"><img src="https://img.shields.io/badge/license-Apache%202.0-blue.svg" alt="License: Apache 2.0"></a>
</p>

<p align="center">
  <a href="#install">Install</a> · <a href="#features">Features</a> · <a href="#development">Build from source</a> · <a href=".github/CONTRIBUTING.md">Contribute</a>
</p>

---

Paste a rough message, pick a tone, and get back something you'd actually send.
Rescripto keeps your facts, names and numbers as they are and doesn't pad the
text with filler. There's no account. Download a model once and rewriting works
offline, or connect a cloud provider with your own API key.

## Contents

- [Features](#features)
- [How processing works](#how-processing-works)
- [Privacy and network activity](#privacy-and-network-activity)
- [Install](#install)
- [Platform support](#platform-support)
- [Storage and downloads](#storage-and-downloads)
- [Development](#development)
- [Architecture](#architecture)
- [Contributing](#contributing)
- [License](#license)

## Features

- **On-device rewriting** with GGUF models running through llama.cpp. Choose
  from 14 tones or write your own, and in Pro mode set intensity, length,
  audience, extra instructions and up to three versions per request.
- **Writing that sounds like a person wrote it.** Every tone shares one set of
  rules: keep the meaning, keep numbers and names exact, don't add greetings,
  filler or hype, and don't answer a question that was meant to be rewritten.
- **Optional cloud rewriting** with your own key for OpenAI, Anthropic, Google
  Gemini, Groq, xAI, OpenRouter, Mistral, Together AI, Ollama on your network,
  or any OpenAI-compatible endpoint.
- **Voice dictation** with whisper.cpp on the phone, or cloud transcription
  through OpenAI, Groq or xAI.
- **Workflows** that run several rewrite steps in a row.
- **Model downloads** from Hugging Face that resume after a dropped connection
  and are checked against a SHA-256 hash.
- **History** stored in SQLite on the phone, with search, copy and share.
- **Encrypted backups**, automatic weekly local backups, and optional WebDAV
  sync. The sync server only ever receives encrypted data.
- **Privacy controls**: a network kill switch, a switch per network feature,
  and a log of every request the app made or blocked.
- **Android integration**: rewrite selected text from any app's text menu,
  share text into Rescripto, or open it from a Quick Settings tile.

## How processing works

You pick a mode during setup and can change it any time in **Settings →
Processing mode**.

| Mode | Where rewrites run | When text can leave your phone |
| --- | --- | --- |
| **Local** (default) | On your phone | Never for a rewrite. Downloading a model is a separate step. |
| **Cloud** | The provider you set up | Every rewrite goes to the provider and model you chose. |
| **Hybrid** | On your phone first | For long text (about 1,500 characters or more), or when a local rewrite fails and you agree to send it. |

The chip in the app bar always shows where the next rewrite will run. In Hybrid
mode, a failed cloud rewrite can fall back to the phone without asking, because
that keeps the text on the device.

## Privacy and network activity

| Feature | What is sent | Where | In the network log? |
| --- | --- | --- | --- |
| Local rewriting | Nothing | Nowhere | No |
| Model download | A request for the model file | Hugging Face | Yes |
| Cloud or Hybrid rewrite | The text being rewritten | Your provider | Yes |
| Cloud speech-to-text | The voice recording | Your provider | Yes |
| WebDAV sync | An encrypted backup | Your server | Yes |

Every request from the app's Dart code goes through `NetworkGuard`, which
checks the current policy first and then logs the host and path. Headers,
request bodies, query strings and credentials are never logged. **Settings →
Privacy & network** also has a lockdown button that turns on the kill switch,
cancels running requests, disables providers and deletes saved API keys.

Rescripto has no analytics, crash reporting, ads or update checks.

## Install

Download the APK from the
[latest release](https://github.com/Gr33nOps/Rescripto/releases/latest). The
AAB in the same release is for app stores and can't be installed directly.
Releases contain `arm64-v8a` code only, so check
[Platform support](#platform-support) first.

The app builds from source with no proprietary dependencies. An F-Droid build
is being prepared; [docs/FDROID.md](docs/FDROID.md) tracks what's done and
what's left.

## Platform support

| Platform | Text rewriting | Voice dictation |
| --- | --- | --- |
| Android `arm64-v8a`, Android 7.0 (API 24) or newer | Supported | Supported |
| Android `armeabi-v7a` or `x86_64` | Not built | Not built |
| iOS | Not supported | Not supported |

The on-device engines run on the CPU. The APK carries four builds of the llama.cpp
CPU backend, and the app loads the one that matches the phone's processor
features, from plain ARMv8.0 up to ARMv8.6 with int8 matrix multiplication.
Older phones get the baseline build instead of crashing on instructions they
don't have.

There is no GPU acceleration. The llama.cpp Vulkan backend needs system
libraries that Android 7 doesn't have, and the 1B to 3B models in the catalog
run about as fast on a phone's CPU.

## Storage and downloads

Rewrite models take about 769 MB to 1.9 GB each. Voice models range from about
74 MB (Tiny) to 2.9 GB (Large), and the default Base model is about 141 MB. It
downloads the first time you use the microphone. All models come from Hugging
Face. Recordings are deleted once transcription finishes or is cancelled.

Android's automatic backup is turned off for Rescripto, so your history and
settings aren't copied to Google Drive or moved by the new-phone setup wizard.
Use the encrypted export or WebDAV sync when you want to move data.

## Development

### Requirements

- Flutter 3.44.9 with Dart 3.12.2
- Java 17
- Android SDK with NDK `28.2.13676358` and CMake 3.22.1

### Quick start

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
```

The two local plugins have their own checks:

```sh
cd packages/rescripto_llama
flutter pub get
flutter analyze
flutter test

cd ../../third_party/flutter_whisper
flutter pub get
flutter analyze lib
flutter test
```

A release build without signing variables produces an unsigned APK, which is
what F-Droid and other build services expect. See
[docs/FDROID.md](docs/FDROID.md) for the exact build steps.

### CI and releases

- Pushes and pull requests to `main` run analysis, the full test suite, an
  Android lint pass and a debug build ([CI](.github/workflows/ci.yml)).
- Pushing a `vX.Y.Z` tag that matches `pubspec.yaml` builds a signed APK and
  AAB and publishes a GitHub release. The release notes come from that
  version's section in [CHANGELOG.md](CHANGELOG.md).
- The release APK is built so F-Droid can reproduce it byte for byte. Running
  the [Release](.github/workflows/release.yml) workflow by hand builds the
  same APK unsigned and uploads it as an artifact, without publishing.
  [docs/FDROID.md](docs/FDROID.md) explains what the build has to keep the
  same.

When you change what the app downloads or sends, or which devices it supports,
update this README and the in-app Privacy text in the same change.

## Architecture

| Area | What it does |
| --- | --- |
| `lib/engine` | The `RewriteEngine` interface, the local engine, cloud protocol adapters and workflow runner |
| `lib/speech` | On-device whisper.cpp and cloud transcription |
| `lib/services` | Prompts, routing, settings, SQLite, downloads, network policy and logging, credentials, backup and sync |
| `lib/state` | Controllers that hold UI state |
| `lib/models` | Plain data types: tones, providers, requests, results |
| `packages/rescripto_llama` | Rescripto's Flutter plugin for llama.cpp (Kotlin and C++ JNI) |
| `third_party/llama.cpp` | llama.cpp source, build b6500 |
| `third_party/flutter_whisper` | whisper.cpp plugin, adapted for this app |

Good places to start reading: `lib/services/prompt_builder.dart` for how a
rewrite is asked for, `lib/services/routing/target_router.dart` for where it
runs, and `lib/services/network/network_guard.dart` for what may leave the
phone.

## Contributing

Bug reports and pull requests are welcome.
[CONTRIBUTING.md](.github/CONTRIBUTING.md) covers the local setup and what a
good change looks like. Please report security problems through
[SECURITY.md](.github/SECURITY.md) rather than a public issue.

## License

Rescripto, including `packages/rescripto_llama`, is licensed under the
[Apache License 2.0](LICENSE).

Bundled third-party code keeps its own license:

- [llama.cpp](third_party/llama.cpp/LICENSE) and
  [whisper.cpp](third_party/flutter_whisper/third_party/whisper.cpp/LICENSE):
  MIT
- [flutter_whisper](third_party/flutter_whisper/LICENSE): Apache 2.0

The Gemma, Llama, Qwen and Whisper models are not part of this repository.
They're downloaded from Hugging Face when you choose them, and each comes with
its publisher's license.
