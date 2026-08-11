import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/core/icon_catalog.dart';
import 'package:rescripto/models/tone_preset.dart';

void main() {
  group('IconCatalog', () {
    test('every built-in tone icon token resolves to a real icon', () {
      // The whole point of routing icons through this catalog is that a
      // token with no entry silently renders as the fallback glyph in
      // release (--tree-shake-icons) while doing nothing suspicious in
      // debug. A built-in tone with a typo'd token would be invisible to
      // both `flutter analyze` and a debug run — this is the one test that
      // would actually catch it.
      for (final tone in ToneLibrary.builtIns) {
        expect(
          IconCatalog.resolve(tone.iconToken),
          isNot(IconCatalog.fallback),
          reason: '${tone.id} has iconToken "${tone.iconToken}", which is '
              'not in IconCatalog',
        );
      }
    });

    test('falls back for an unknown token', () {
      expect(IconCatalog.resolve('not_a_real_token'), IconCatalog.fallback);
    });

    test('falls back for a null token', () {
      expect(IconCatalog.resolve(null), IconCatalog.fallback);
    });

    test('falls back for an empty token', () {
      // What ConfigStore.toneById synthesises for an unknown tone id.
      expect(IconCatalog.resolve(''), IconCatalog.fallback);
    });

    test('every built-in tone token is unique', () {
      // Not a correctness requirement of the catalog itself, but two tones
      // sharing an icon would be a content mistake worth catching here.
      final tokens = ToneLibrary.builtIns.map((t) => t.iconToken).toList();
      expect(tokens.toSet().length, tokens.length);
    });

    test('offers more than one icon per built-in tone, for the tone editor\'s picker', () {
      expect(IconCatalog.tokens.length, greaterThan(ToneLibrary.builtIns.length));
    });

    test('every token in the catalog resolves to a real icon', () {
      for (final token in IconCatalog.tokens) {
        expect(IconCatalog.resolve(token), isNot(IconCatalog.fallback));
      }
    });

    test('every token in the catalog is unique', () {
      final tokens = IconCatalog.tokens.toList();
      expect(tokens.toSet().length, tokens.length);
    });
  });
}
