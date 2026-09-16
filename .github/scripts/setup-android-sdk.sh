#!/usr/bin/env bash
# Installs the Android SDK parts the release build needs under
# /opt/android-sdk, the path F-Droid's build server uses, and points the rest
# of the job at it. The native libraries depend on the NDK's install path, so
# the release APK only matches F-Droid's build when both use the same one.
set -euo pipefail

sdk=/opt/android-sdk
ndk_version=28.2.13676358
sdkmanager="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"

sudo mkdir -p "$sdk"
sudo chown "$(id -u):$(id -g)" "$sdk"

{ yes || true; } | "$sdkmanager" --sdk_root="$sdk" --licenses > /dev/null
# cmdline-tools provides apkanalyzer, which `flutter build appbundle` uses to
# check that native debug symbols were stripped.
"$sdkmanager" --sdk_root="$sdk" \
  "cmdline-tools;latest" \
  "platform-tools" \
  "platforms;android-36" \
  "build-tools;36.0.0" \
  "cmake;3.22.1" \
  "ndk;$ndk_version"

# The runner image also sets the NDK variables to its own NDK.
{
  echo "ANDROID_HOME=$sdk"
  echo "ANDROID_SDK_ROOT=$sdk"
  echo "ANDROID_NDK=$sdk/ndk/$ndk_version"
  echo "ANDROID_NDK_HOME=$sdk/ndk/$ndk_version"
  echo "ANDROID_NDK_ROOT=$sdk/ndk/$ndk_version"
  echo "ANDROID_NDK_LATEST_HOME=$sdk/ndk/$ndk_version"
} >> "$GITHUB_ENV"
