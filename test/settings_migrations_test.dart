import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/core/constants.dart';
import 'package:rescripto/services/settings_migrations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

void main() {
  group('inferLegacyVersion', () {
    test('treats an untouched install as already current', () async {
      final prefs = await prefsWith({});
      expect(inferLegacyVersion(prefs), SettingsSchema.version);
    });

    test('reads 1 when the 1.0.3 GPU sentinel is present', () async {
      final prefs = await prefsWith({
        AppConstants.keyThemeMode: 'dark',
        AppConstants.keyGpuResetDone: true,
      });
      expect(inferLegacyVersion(prefs), 1);
    });

    test('reads 0 when settings exist without the sentinel', () async {
      final prefs = await prefsWith({
        AppConstants.keyThemeMode: 'dark',
        AppConstants.keyUseGpu: true,
      });
      expect(inferLegacyVersion(prefs), 0);
    });

    test('a lone unrelated key does not look like an existing install', () async {
      final prefs = await prefsWith({'something_else': 'x'});
      expect(inferLegacyVersion(prefs), SettingsSchema.version);
    });
  });

  group('migrateSettings', () {
    test('clears an inherited GPU choice on a pre-1.0.3 install', () async {
      // Up to 1.0.2 the switch did nothing whichever way it was set, so an
      // inherited "on" is a choice nobody actually made.
      final prefs = await prefsWith({
        AppConstants.keyThemeMode: 'dark',
        AppConstants.keyUseGpu: true,
      });

      await migrateSettings(prefs);

      expect(prefs.containsKey(AppConstants.keyUseGpu), isFalse);
      expect(prefs.getString(AppConstants.keyThemeMode), 'dark');
      expect(
        prefs.getInt(AppConstants.keySettingsSchemaVersion),
        SettingsSchema.version,
      );
    });

    test('keeps writing the old sentinel so a downgrade cycle is safe', () async {
      final prefs = await prefsWith({
        AppConstants.keyThemeMode: 'dark',
        AppConstants.keyUseGpu: true,
      });

      await migrateSettings(prefs);

      // 1.0.3 reads this key. Without it, downgrading and upgrading again
      // would re-run the reset and discard a GPU choice made in between.
      expect(prefs.getBool(AppConstants.keyGpuResetDone), isTrue);
    });

    test('leaves a GPU choice alone once already migrated', () async {
      final prefs = await prefsWith({
        AppConstants.keyThemeMode: 'dark',
        AppConstants.keyUseGpu: true,
        AppConstants.keyGpuResetDone: true,
      });

      await migrateSettings(prefs);

      expect(prefs.getBool(AppConstants.keyUseGpu), isTrue);
    });

    test('does not run migrations against a fresh install', () async {
      final prefs = await prefsWith({});

      await migrateSettings(prefs);

      expect(
        prefs.getInt(AppConstants.keySettingsSchemaVersion),
        SettingsSchema.version,
      );
      // The GPU reset never ran, so it left no trace behind.
      expect(prefs.containsKey(AppConstants.keyGpuResetDone), isFalse);
    });

    test('is idempotent', () async {
      final prefs = await prefsWith({
        AppConstants.keyThemeMode: 'dark',
        AppConstants.keyUseGpu: true,
      });

      await migrateSettings(prefs);
      await prefs.setBool(AppConstants.keyUseGpu, true);
      await migrateSettings(prefs);

      expect(prefs.getBool(AppConstants.keyUseGpu), isTrue);
    });
  });
}
