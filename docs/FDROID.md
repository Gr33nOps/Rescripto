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
Binaries: https://github.com/Gr33nOps/Rescripto/releases/download/v%v/app-arm64-v8a-release.apk

Builds:
  - versionName: 1.3.1
    versionCode: 202
    commit: <full commit hash of the v1.3.1 tag>
    sudo:
      - mkdir -p /home/runner/work/Rescripto
      - chown -R vagrant /home/runner
    output: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
    srclibs:
      - flutter@stable
    rm:
      - ios
    prebuild:
      - flutterVersion=$(sed -n -E "s/.*flutter-version:\ '(.*)'/\1/p" .github/workflows/release.yml)
      - '[[ $flutterVersion ]]'
      - git -C $$flutter$$ checkout -f $flutterVersion
      - export repo=/home/runner/work/Rescripto/Rescripto
      - cd ..
      - mv com.rescripto.rescripto $repo
      - pushd $repo
      - export PUB_CACHE=$(pwd)/.pub-cache
      - $$flutter$$/bin/flutter config --no-analytics
      - $$flutter$$/bin/flutter pub get --enforce-lockfile
      - popd
      - mv $repo com.rescripto.rescripto
    scandelete:
      - .pub-cache
    build:
      - export repo=/home/runner/work/Rescripto/Rescripto
      - cd ..
      - mv com.rescripto.rescripto $repo
      - pushd $repo
      - export PUB_CACHE=$(pwd)/.pub-cache
      - $$flutter$$/bin/flutter build apk --release --split-per-abi --target-platform="android-arm64"
      - popd
      - mv $repo com.rescripto.rescripto
    ndk: 28.2.13676358

AllowedAPKSigningKeys: 831777242bc27b13dcc0176d972ceb8757c30ba8d01d19d880131a80c294f922

AutoUpdateMode: Version
UpdateCheckMode: Tags ^v[0-9.]+$
VercodeOperation:
  - 10 * %c + 2
UpdateCheckData: pubspec.yaml|version:\s.+\+(\d+)|.|version:\s(.+)\+
CurrentVersion: 1.3.1
CurrentVersionCode: 202
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
  1.3.1+20 becomes 202 for arm64. `VercodeOperation` tells F-Droid's auto
  update the same thing. Only arm64 is built, so it has one entry. The GitHub
  release runs the same split build.
- `--enforce-lockfile` fails the build if `pubspec.lock` is out of date, so
  commit it after every dependency change.
- `Binaries:` and `AllowedAPKSigningKeys` turn on reproducible-build
  verification: F-Droid compares its build with the signed APK from the GitHub
  release and, if they match, publishes that APK with your signature. The
  fingerprint comes from `apksigner verify --print-certs`. See
  [Reproducible builds](#reproducible-builds) for what keeps the two builds
  identical.
- The `sudo`, `cd ..` and `mv` lines move the source to
  `/home/runner/work/Rescripto/Rescripto`, where GitHub Actions builds it.
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

## Reproducible builds

F-Droid only accepts the GitHub release APK if its own build matches it byte
for byte, apart from the signature. Java and Kotlin code and resources already
match across JDK versions. The native libraries are the fragile part, because
they record where and how they were built. The release workflow and the recipe
keep these the same:

| What | How |
| --- | --- |
| Source path | GitHub builds in `/home/runner/work/Rescripto/Rescripto`. The recipe moves the source there. llama.cpp and whisper.cpp embed source paths, and `libapp.so` embeds the plugin registrant's path. |
| Android SDK and NDK path | F-Droid has the SDK in `/opt/android-sdk`. [`.github/scripts/setup-android-sdk.sh`](../.github/scripts/setup-android-sdk.sh) installs it there on GitHub too. |
| Pub cache | Inside the source tree (`.pub-cache`) on both sides. `libdartjni.so` is built from the `jni` package there. |
| Version stamps | llama.cpp and whisper.cpp would ask git for a commit count, hash and dirty flag. The plugins' `CMakeLists.txt` files set fixed values instead. |
| Flutter, NDK, CMake | Flutter from `release.yml`, NDK `28.2.13676358` and CMake 3.22.1 on both sides. |

To check a change before tagging a release, run the Release workflow by hand
(**Actions → Release → Run workflow**). It builds the same APK unsigned and
uploads it as the `unsigned-apk` artifact. Compare it with the APK from the
fdroiddata merge request's `fdroid build` job artifacts. Apart from the
signature files, every entry should be identical.

## Testing the build locally

These are the same commands the recipe runs:

```sh
flutter pub get --enforce-lockfile
flutter build apk --release --split-per-abi --target-platform android-arm64
```

Leave `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`
and `ANDROID_KEY_PASSWORD` unset. The APK at
`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` should be unsigned
and have version code 202. To install
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

1. Follow the merge request,
   [fdroiddata!49009](https://gitlab.com/fdroid/fdroiddata/-/merge_requests/49009),
   until it's merged. Its CI pipeline runs `fdroid lint` and `fdroid build`.
2. Answer the reviewers' questions, especially about NonFreeNet and the
   downloadable models.
3. After each release, check that F-Droid's build still matches the GitHub
   APK. A mismatch blocks that version on F-Droid.
4. Add two to four phone screenshots to
   `fastlane/metadata/android/en-US/images/phoneScreenshots/` (the rewrite
   screen with a result, tones, the privacy screen and the models screen are
   good picks).
5. Once the app is listed, add an F-Droid badge and link to the README's
   Install section.
