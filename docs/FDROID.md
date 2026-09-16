# Publishing Rescripto on F-Droid

This page covers what's been done to make Rescripto buildable by F-Droid, the
draft build recipe, and the steps that still need a person.

## Current state

| Requirement | Status |
| --- | --- |
| All source code under a FLOSS license | Done. The app and `packages/rescripto_llama` are Apache 2.0. llama.cpp and whisper.cpp are MIT, `third_party/flutter_whisper` is Apache 2.0. The non-commercial `flutter_llama` plugin was removed in 1.3.0. |
| No proprietary libraries or SDKs | Done. No Google Play services, Firebase, analytics or crash reporting. Dependencies come from pub.dev, Google's Maven repository (AndroidX) and Maven Central. |
| No prebuilt binaries in the source tree | Done. Native code is compiled from `third_party/llama.cpp` and `third_party/flutter_whisper/third_party/whisper.cpp`. Test vocabularies, images, a prebuilt web UI and a Gradle wrapper JAR were removed from the vendored llama.cpp. The only JAR left is the app's own standard `android/gradle/wrapper/gradle-wrapper.jar`. |
| Unsigned release build | Done. `flutter build apk --release` without the `ANDROID_KEY*` variables produces an unsigned APK. |
| No Google dependency metadata block | Done. `dependenciesInfo` is disabled in `android/app/build.gradle.kts`. |
| Fastlane metadata | Done: `fastlane/metadata/android/en-US` has the title, descriptions, icon and a changelog per version code. |
| Screenshots | Not added yet. Optional for F-Droid, but the listing looks bare without them. Put PNGs in `fastlane/metadata/android/en-US/images/phoneScreenshots/`. |
| No tracking or update checks | Done. The unused "Update checks" switch was removed in 1.3.0. |
| Version code | `pubspec.yaml` `version: X.Y.Z+N`. `N` is the Android version code and must go up with every release. |

## Anti-features to declare

- **NonFreeNet**: optional. In Cloud or Hybrid mode, text and recordings can
  go to commercial AI services (OpenAI, Anthropic, Google, Groq, xAI and
  others). All of it is off until the user turns it on and adds their own
  API key.

Reviewers may also ask about the models. They are not in the APK. The user
picks one and the app downloads it from Hugging Face, and Gemma and Llama come
with their publishers' own licenses rather than OSI ones. Mention this in the
merge request so the reviewer can decide whether it needs a note.

## Draft build recipe

The recipe submitted as `metadata/com.rescripto.rescripto.yml` in
[fdroiddata](https://gitlab.com/fdroid/fdroiddata). It follows fdroiddata's
[`templates/build-flutter.yml`](https://gitlab.com/fdroid/fdroiddata/-/blob/master/templates/build-flutter.yml),
which reviewers ask new Flutter apps to use. Check it against the current
template before each change, since the Flutter conventions change from time
to time.

```yaml
AntiFeatures:
  NonFreeNet:
    en-US: Can send text to commercial cloud AI services when you turn on Cloud or
      Hybrid mode.
Categories:
  - Writing
License: Apache-2.0
AuthorName: Gr33nOps
SourceCode: https://github.com/Gr33nOps/Rescripto
IssueTracker: https://github.com/Gr33nOps/Rescripto/issues
Changelog: https://github.com/Gr33nOps/Rescripto/blob/main/CHANGELOG.md

AutoName: Rescripto

RepoType: git
Repo: https://github.com/Gr33nOps/Rescripto.git

Builds:
  - versionName: 1.3.0
    versionCode: 192
    commit: <full commit hash, not the tag name>
    output: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
    srclibs:
      - flutter@stable
    rm:
      - ios
    prebuild:
      - flutterVersion=$(sed -n -E "s/.*flutter-version:\ '(.*)'/\1/p" .github/workflows/release.yml)
      - '[[ $flutterVersion ]]'
      - git -C $$flutter$$ checkout -f $flutterVersion
      - export PUB_CACHE=$(pwd)/.pub-cache
      - $$flutter$$/bin/flutter config --no-analytics
      - $$flutter$$/bin/flutter pub get --enforce-lockfile
    scandelete:
      - .pub-cache
    build:
      - export PUB_CACHE=$(pwd)/.pub-cache
      - $$flutter$$/bin/flutter build apk --release --split-per-abi --target-platform="android-arm64"
    ndk: 28.2.13676358

AutoUpdateMode: Version
UpdateCheckMode: Tags ^v[0-9.]+$
VercodeOperation:
  - 10 * %c + 2
UpdateCheckData: pubspec.yaml|version:\s.+\+(\d+)|.|version:\s(.+)\+
CurrentVersion: 1.3.0
CurrentVersionCode: 192
```

Notes on fields above:

- `AntiFeatures` goes at the very top of the file — that's the actual convention
  used across fdroiddata, not just alphabetical placement.
- `commit:` must be the full 40-character commit hash, never a tag or branch
  name.
- The Flutter version is pinned in one place: `flutter-version: '3.44.9'` in
  `.github/workflows/release.yml`. The recipe reads it from there, so keep the
  single quotes, and bumping Flutter for a release needs no fdroiddata change.
- `--split-per-abi` makes `android/app/build.gradle.kts` set the version code
  to `versionCode * 10 + ABI` (1 = armeabi-v7a, 2 = arm64-v8a, 3 = x86_64), so
  1.3.0+19 becomes 192 for arm64. `VercodeOperation` tells F-Droid's auto
  update the same thing. Only arm64 is built, so it has one entry. The GitHub
  release isn't split and keeps the plain version code.
- `--enforce-lockfile` fails the build if `pubspec.lock` is out of date, so
  commit it after every dependency change.
- There's no `Binaries:` or `AllowedAPKSigningKeys` yet. Those turn on
  reproducible-build verification against the GitHub release APK, which fails
  unless the build is byte-for-byte reproducible. That hasn't been set up.
- `UpdateCheckData` takes exactly four `|`-separated fields:
  `<vercode-location>|<vercode-regex>|<versionName-location>|<versionName-regex>`.
  The third field is a literal `.`, meaning "same file as the first field" —
  don't repeat the filename there, or `fdroid lint`/`checkupdates` will fail
  with `ValueError: too many values to unpack`.

Notes for the recipe:

- The native build needs CMake 3.22.1 from the Android SDK and NDK
  `28.2.13676358`. Both are fixed in the Gradle files.
- The build compiles llama.cpp and whisper.cpp from source. Expect it to take
  much longer than a typical Flutter app.
- Only `arm64-v8a` is built. The ABI filter lives in
  `android/app/build.gradle.kts` and both native plugins. The app's
  `ndk.abiFilters` is skipped for split builds, since AGP refuses it alongside
  ABI splits.

## Testing the build locally

These are the same commands the recipe runs:

```sh
flutter pub get --enforce-lockfile
flutter build apk --release --split-per-abi --target-platform android-arm64
```

Leave `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`
and `ANDROID_KEY_PASSWORD` unset. The APK at
`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` should be unsigned
and have version code 192. To install
it on your own device, sign it with a debug key first:

```sh
apksigner sign --ks ~/.android/debug.keystore --ks-pass pass:android app-arm64-v8a-release.apk
```

To run F-Droid's own checks, install
[fdroidserver](https://f-droid.org/docs/Installing_the_Server_and_Repo_Tools/)
and run `fdroid lint com.rescripto.rescripto` and
`fdroid build -v -l com.rescripto.rescripto` inside an fdroiddata checkout
that contains the recipe.

## Still to do by hand

1. Fork fdroiddata on GitLab, add the recipe above as
   `metadata/com.rescripto.rescripto.yml`, and open a merge request.
2. Run `fdroid lint` and a local `fdroid build` first, or let the merge
   request's CI pipeline do it, and fix anything it reports. The scanner
   results and build time on F-Droid's servers can't be checked from this
   repository.
3. Answer the reviewer's questions, especially about NonFreeNet and the
   downloadable models.
4. Optional: reproducible builds. F-Droid can publish the APK signed with
   your own key if its build matches yours byte for byte. That needs a
   `Binaries:` URL in the recipe and a build pinned to the same Flutter, NDK
   and build path. It hasn't been tested for Rescripto, so start without it.
5. Add two to four phone screenshots to
   `fastlane/metadata/android/en-US/images/phoneScreenshots/` (the rewrite
   screen with a result, tones, the privacy screen and the models screen are
   good picks).
6. Once the app is listed, add an F-Droid badge and link to the README's
   Install section.
