import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/models/ai_model.dart';
import 'package:rescripto/models/history_entry.dart';
import 'package:rescripto/models/rewrite_output.dart';
import 'package:rescripto/models/rewrite_request.dart';
import 'package:rescripto/models/tone_preset.dart';

void main() {
  group('ToneLibrary', () {
    test('has a non-empty tone catalog with unique ids', () {
      final ids = ToneLibrary.builtIns.map((t) => t.id).toSet();
      expect(ids.length, ToneLibrary.builtIns.length);
      expect(ToneLibrary.builtIns, isNotEmpty);
    });
  });

  group('ModelCatalog', () {
    test('every model has a valid https download URL', () {
      for (final model in ModelCatalog.models) {
        expect(model.downloadUrl, startsWith('https://huggingface.co/'));
        expect(model.sizeMb, greaterThan(0));
        expect(model.sizeBytes, greaterThan(0));
        expect(model.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(model.contextSize, greaterThan(0));
      }
    });

    test('default model exists in the catalog', () {
      expect(
        ModelCatalog.byId(ModelCatalog.defaultModel.id)?.id,
        ModelCatalog.defaultModel.id,
      );
    });

    test('byId returns null for an unknown id instead of falling back', () {
      expect(ModelCatalog.byId('not-a-real-model'), isNull);
    });
  });

  group('HistoryEntry', () {
    test('can omit its id for SQLite AUTOINCREMENT inserts', () {
      final entry = HistoryEntry(
        id: 0,
        original: 'rough',
        rewritten: 'polished',
        toneId: 'professional',
        createdAt: DateTime.utc(2026),
      );

      expect(entry.toMap(), containsPair('id', 0));
      expect(entry.toMap(includeId: false), isNot(contains('id')));
    });
  });

  group('RewriteRequest', () {
    test('copyWith overrides only provided fields', () {
      const base = RewriteRequest(
        sourceText: 'hello',
        toneId: 'casual',
        intensity: RewriteIntensity.light,
        length: RewriteLength.shorter,
      );
      final copy = base.copyWith(toneId: 'formal');
      expect(copy.sourceText, 'hello');
      expect(copy.toneId, 'formal');
      expect(copy.intensity, RewriteIntensity.light);
      expect(copy.length, RewriteLength.shorter);
    });
  });

  group('RewriteOutput', () {
    test('computes tokens per second', () {
      const out = RewriteOutput(
        text: 'x',
        tokensGenerated: 100,
        generationTimeMs: 2000,
      );
      expect(out.tokensPerSecond, 50);
    });
  });
}
