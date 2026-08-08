# Rescripto

Rescripto is a Flutter app for private, on-device text rewriting. User text,
recordings, generated output, settings, and history stay on the device. The app
does use the network to download the AI/voice model files selected by the user;
after download, inference runs locally without an account or API key.

## Features

- Local GGUF rewriting with tone, intensity, length, audience, instructions,
  and up to three requested variants
- Resumable, checksum-verified model downloads
- Local SQLite rewrite history, copy, and share
- Android microphone dictation through whisper.cpp
- Light, dark, and system themes

## Current platform support

| Platform | Text rewriting | Voice dictation |
| --- | --- | --- |
| Android arm64-v8a | Supported | Supported |
| Android armeabi-v7a / x86_64 | Not currently packaged with llama | Not fully supported |
| iOS | Source integration present; requires macOS/Xcode verification | Not implemented |

Do not advertise unsupported Android ABIs for production. Release ABI policy,
signing, and automation are intentionally handled separately from app code.

## Storage and downloads

Text models currently require approximately 769 MiB to 1.93 GiB each. Voice
models range from approximately 74 MiB (Tiny) to 2.88 GiB (Large v3). Downloads
come from Hugging Face. Temporary microphone recordings are deleted after
transcription or cancellation.

## Development setup

Prerequisites:

- Flutter 3.44.9 / Dart 3.12.2 or the project-pinned compatible toolchain
- Java 17
- Android SDK and NDK `26.1.10909125`
- CMake/Ninja installed through Android SDK tools
- For iOS work: macOS, Xcode, CocoaPods, and a real device/simulator build check

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

## Architecture

- `lib/state`: UI operation state and controllers
- `lib/services`: settings, SQLite, downloads, llama, speech, and prompting
- `lib/models`: immutable app/domain models
- `third_party/flutter_llama`: vendored llama.cpp Flutter/native bridge
- `third_party/flutter_whisper`: vendored whisper.cpp Flutter/native bridge

## Licensing and model terms

This repository does not currently include a root project license. The vendored
`flutter_llama` wrapper uses the NativeMindNONC license, which requires written
permission for commercial use. The downloadable Gemma, Llama, and Qwen models
also have their own terms. Resolve those obligations and add appropriate notices
before distributing the app, especially for commercial use.
