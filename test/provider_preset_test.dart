import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/models/provider_preset.dart';

void main() {
  group('ProviderPresetCatalog', () {
    // Regression coverage for the invariant TargetRouter._modelRefFor's own
    // doc comment depends on: every hosted preset ships at least one known
    // model, so a configured-and-enabled provider always has something to
    // route to. OpenRouter shipped with an empty knownModels list — the
    // provider looked fully configured (enabled, keyed, "Test connection"
    // passing) but TargetRouter._cloudTarget still resolved to null, and
    // couldn't tell that apart from no provider being configured at all, so
    // the UI showed the same misleading "no cloud provider configured"
    // reason either way. `custom` (an arbitrary endpoint) and `ollama`
    // (whatever the user has pulled locally) are the only two presets whose
    // model list genuinely cannot be known ahead of time.
    const exemptFromKnownModels = {'custom', 'ollama'};

    test('every preset except custom/ollama ships at least one known model', () {
      for (final preset in ProviderPresetCatalog.all) {
        if (exemptFromKnownModels.contains(preset.id)) continue;
        expect(
          preset.knownModels,
          isNotEmpty,
          reason:
              '${preset.id} has no knownModels — a configured, enabled '
              'provider on this preset would route as if nothing were '
              'configured at all',
        );
      }
    });

    test('every preset id is unique', () {
      final ids = ProviderPresetCatalog.all.map((p) => p.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('byId finds every preset in the catalog by its own id', () {
      for (final preset in ProviderPresetCatalog.all) {
        expect(ProviderPresetCatalog.byId(preset.id), same(preset));
      }
    });

    test('byId returns null for an unknown id, not a first-of-list fallback', () {
      expect(ProviderPresetCatalog.byId('not-a-real-preset'), isNull);
    });
  });
}
