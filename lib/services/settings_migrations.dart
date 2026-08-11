import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';

/// A single forward step over stored preferences.
typedef SettingsMigration = Future<void> Function(SharedPreferences prefs);

abstract final class SettingsSchema {
  /// The current preference layout.
  ///
  /// 1 — GPU default reset. Shipped in 1.0.3 behind a one-off sentinel key,
  ///     before this versioning existed.
  static const int version = 1;
}

const Map<int, SettingsMigration> _steps = <int, SettingsMigration>{
  1: _v1ResetGpuDefault,
};

/// Brings stored preferences up to [SettingsSchema.version].
///
/// Replaces the previous approach of one bespoke sentinel key per change,
/// which gave no way to tell an install that had skipped a release from one
/// that had never needed the change in the first place.
Future<void> migrateSettings(SharedPreferences prefs) async {
  final from =
      prefs.getInt(AppConstants.keySettingsSchemaVersion) ??
      inferLegacyVersion(prefs);

  for (var version = from + 1; version <= SettingsSchema.version; version++) {
    final step = _steps[version];
    if (step == null) {
      throw StateError(
        'No settings migration registered for version $version. Every version '
        'from 1 to ${SettingsSchema.version} needs an entry in _steps.',
      );
    }
    await step(prefs);
  }

  await prefs.setInt(
    AppConstants.keySettingsSchemaVersion,
    SettingsSchema.version,
  );
}

/// Works out where an install sits when it predates the version key.
///
/// Three cases, distinguished by what is already on disk:
///
/// * nothing this app has ever written — a fresh install, already current;
///   claim the latest version so no migration runs against empty prefs
/// * the 1.0.3 GPU sentinel is present — already at 1
/// * settings exist without the sentinel — 1.0.2 or earlier, so 0
@visibleForTesting
int inferLegacyVersion(SharedPreferences prefs) {
  // Deliberately frozen to exactly what a pre-versioning (pre-1.0.4) build
  // could have written. Do NOT add processing_mode, cloud_provider_id, or
  // any other Phase-2-or-later key here: this list answers "did some old
  // build ever write this key," and a build from before those keys existed
  // could not have. Adding one would misclassify a fresh install that has
  // simply completed onboarding as a legacy install, and replay migrations
  // against it that were never meant to run.
  const written = <String>[
    AppConstants.keySelectedModel,
    AppConstants.keyThemeMode,
    AppConstants.keyThreadCount,
    AppConstants.keyUseGpu,
    AppConstants.keyContextSize,
    AppConstants.keyWhisperModel,
  ];

  if (!written.any(prefs.containsKey)) return SettingsSchema.version;
  return prefs.containsKey(AppConstants.keyGpuResetDone) ? 1 : 0;
}

/// Up to 1.0.2 the GPU switch passed `nGpuLayers: -1`, which llama.cpp reads as
/// "offload nothing" — the toggle did nothing whichever way it was set, while
/// still paying for Vulkan device setup on every model load. Now that it really
/// offloads, an inherited "on" is a choice nobody made, so start everyone off.
Future<void> _v1ResetGpuDefault(SharedPreferences prefs) async {
  await prefs.remove(AppConstants.keyUseGpu);
  // Keep writing the pre-versioning sentinel for one more release. Someone who
  // downgrades to 1.0.3 and upgrades again would otherwise have the reset
  // applied a second time, discarding a GPU choice they made in between.
  await prefs.setBool(AppConstants.keyGpuResetDone, true);
}
