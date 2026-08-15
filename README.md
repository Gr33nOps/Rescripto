<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/icon/app_icon_foreground_white.png">
    <img src="assets/icon/app_icon_foreground.png" alt="Rescripto" width="104">
  </picture>
</p>

<h1 align="center">Rescripto</h1>

<p align="center">
  <strong>Clearer writing, on your terms.</strong><br>
  Rewrite and dictate privately on Android with local models or a cloud provider you choose.
</p>

<p align="center">
  <a href="https://github.com/Gr33nOps/Rescripto/actions/workflows/ci.yml"><img src="https://github.com/Gr33nOps/Rescripto/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
  <a href="https://github.com/Gr33nOps/Rescripto/releases"><img src="https://img.shields.io/github/v/release/Gr33nOps/Rescripto?label=release" alt="Latest release"></a>
  <a href="#license"><img src="https://img.shields.io/badge/license-Apache%202.0%20%2B%20restrictions-blue.svg" alt="License"></a>
</p>

<p align="center">
  <a href="#install">Get the app</a> · <a href="#features">Explore features</a> · <a href="#development">Build from source</a> · <a href=".github/CONTRIBUTING.md">Contribute</a>
</p>

---

Rescripto turns rough notes into clear, natural writing without requiring an
account. Download a model once for private on-device rewrites, or connect a
cloud provider you trust.

## At a glance

| Private by default | Flexible rewriting | Built for your phone |
| :--- | :--- | :--- |
| Local rewrites and dictation stay on-device. | Set tone, intensity, length, audience, and instructions. | Android 7.0+ on 64-bit ARM, with CPU acceleration chosen for your phone. |

## Contents

- [Features](#features)
- [How processing works](#how-processing-works)
- [Privacy & network activity](#privacy--network-activity)
- [Install](#install)
- [Platform support](#platform-support)
- [Storage & downloads](#storage--downloads)
- [Development](#development)
- [Architecture](#architecture)
- [Contributing](#contributing)
- [License](#license)

## Features

- **Private local rewriting** with GGUF models through llama.cpp: tone,
  intensity, length, audience, free-form instructions, and up to three
  variants per request.
- **Optional cloud writing** using your own API key for OpenAI, Anthropic,
  Gemini, Groq, OpenRouter, Mistral, Together AI, Ollama, or a custom
  OpenAI-compatible endpoint.
- **Voice dictation** through whisper.cpp on your device, with optional cloud
  transcription through OpenAI or Groq.
- **Workflows** that chain rewrite steps, feeding each result into the next.
- **Reliable model downloads** from Hugging Face: resumable and
  checksum-verified.
- **Local history and sharing** backed by SQLite, with copy and share built
  in.
- **Encrypted backup and optional WebDAV sync**. A self-hosted sync server
  only receives ciphertext.
- **Transparent privacy controls**: a network kill switch, per-feature
  network toggles, and a log of every request allowed or blocked by the app.
- **Useful Android integration**: share text into Rescripto, use the Quick
  Settings tile, and choose light, dark, or system theme.

## How processing works

Select a mode during onboarding, then change it any time in **Settings →
Processing mode**.

| Mode | Where rewrites run | When text can leave your phone |
| --- | --- | --- |
| **Local** (default) | On your device | Never for a rewrite. Model downloads are a separate, one-time action. |
| **Cloud** | Your configured provider | Every rewrite is sent only to the provider and model you chose. |
| **Hybrid** | On-device first | Only for long input (about 1,500+ characters) or after you approve a failed local attempt going to the cloud. |

The app bar always shows the selected route. Hybrid mode may fall back from a
cloud failure to your device without asking, because that route brings the
text back to the phone rather than sending it elsewhere.

## Privacy & network activity

| Feature | What is sent | Destination | Recorded in the network log? |
| --- | --- | --- | --- |
| Local rewriting | Nothing | None | No |
| Model download | Model file only | Hugging Face | Yes |
| Cloud / Hybrid rewrite | The text being rewritten | Your configured provider | Yes |
| Cloud speech-to-text | Voice recording | Your configured provider | Yes |

Every request made by the app's Dart layer goes through `NetworkGuard`, which
checks the current policy before logging the host and path. It never logs
headers, request bodies, query strings, or credentials. **Settings → Privacy &
network** also includes a panic button that turns on the kill switch, cancels
work in flight, disables providers, and deletes saved API keys.

## Install

For direct installation, download the signed **APK** from the
[latest release](https://github.com/Gr33nOps/Rescripto/releases/latest).
The **AAB** is included for Android store publishing and cannot be installed
directly like an APK. Release builds package `arm64-v8a` only, so review
[Platform support](#platform-support) before installing.

To build the project yourself, continue with [Development](#development).

## Platform support

| Platform | Text rewriting | Voice dictation |
| --- | --- | --- |
| Android `arm64-v8a`, API 24+ | Supported | Supported |
| Android `armeabi-v7a` / `x86_64` | Not packaged | Not packaged |
| iOS | Source integration present; needs macOS/Xcode verification | Not implemented |

Only 64-bit ARM Android builds are distributed. The native engines include a
portable ARMv8-A CPU backend and load more capable CPU variants at runtime when
the phone supports them. Dot-product instructions improve speed, but they are
**not** required for compatibility.

### GPU acceleration

Vulkan support is compiled in but disabled by default. Initializing it can take
minutes on some Android drivers, and the 1B to 3B catalog models are usually
faster on CPU. Build with `-DFLUTTER_LLAMA_VULKAN=OFF` to omit the backend
entirely.

## Storage & downloads

Text models range from roughly **769 MiB to 1.93 GiB**. Voice models range from
about **74 MiB** (Tiny) to **2.88 GiB** (Large v3); the default Base model is
about **141 MiB** and downloads when you first use the microphone. All models
come from Hugging Face. Temporary recordings are deleted after transcription
finishes or is cancelled.

Android automatic backup is intentionally disabled. Your history and settings
will not be silently copied to Google Drive or transferred to another phone by
the setup wizard. Use Rescripto's encrypted export or WebDAV sync when you
decide to move data.

## Development

### Requirements

- Flutter 3.44.9 / Dart 3.12.2, or the project-pinned compatible toolchain
- Java 17
- Android SDK and NDK `28.2.13676358`
- CMake and Ninja from Android SDK tools
- For iOS work: macOS, Xcode, CocoaPods, and a device or simulator

### Quick start

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

The vendored native plugins sit outside root analysis, so verify them too:

```sh
cd third_party/flutter_llama
flutter analyze lib
flutter test

cd ../flutter_whisper
flutter analyze lib
flutter test
```

### CI & releases

- Pushes and pull requests to `main` run analysis, the full test suite, and
  an Android debug build in [CI](.github/workflows/ci.yml).
- A `vX.Y.Z` tag matching `pubspec.yaml` builds signed APK and AAB artifacts,
  then publishes a GitHub release with generated notes.

When you change dependencies, model paths, or platform support, update this
README and the in-app About screen together.

## Architecture

| Area | Responsibility |
| --- | --- |
| `lib/engine` | `RewriteEngine`, local llama.cpp, and cloud protocol adapters |
| `lib/speech` | Local whisper.cpp and optional cloud transcription |
| `lib/state` | UI operation state and controllers |
| `lib/services` | Settings, SQLite, downloads, network policy/logging, credentials, routing, and prompts |
| `lib/models` | Immutable application and domain models |
| `third_party/flutter_llama` | Vendored llama.cpp Flutter/native bridge |
| `third_party/flutter_whisper` | Vendored whisper.cpp Flutter/native bridge |

For the best starting points in the codebase, read
`lib/services/routing/target_router.dart` and
`lib/services/network/network_guard.dart`.

## Contributing

Contributions and bug reports are welcome. Read
[CONTRIBUTING.md](.github/CONTRIBUTING.md) for the local workflow and coding
conventions. For security issues, follow [SECURITY.md](.github/SECURITY.md)
instead of opening a public issue.

## License

Rescripto's own source code, everything outside `third_party/`, is licensed
under the [Apache License 2.0](LICENSE).

Two additional terms matter when building or distributing the app:

- `third_party/flutter_llama`, the on-device llama.cpp bridge included in
  every build, is licensed under
  [NativeMindNONC](third_party/flutter_llama/LICENSE). It is free for
  personal, educational, and research use; commercial use of the built app
  requires written permission from that license's copyright holder.
  `third_party/flutter_whisper` is Apache 2.0.
- Downloadable Gemma, Llama, Qwen, and Whisper models each have their own
  publisher license. They are fetched from Hugging Face at runtime, not bundled
  in the repository.

Please read the linked terms before any commercial use.
