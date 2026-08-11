import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/models/rewrite_request.dart';
import 'package:rescripto/models/tone_preset.dart';
import 'package:rescripto/services/prompt_builder.dart';

void main() {
  group('PromptBuilder.build', () {
    final base = RewriteRequest(
      sourceText: 'we need 2 meet monday for the project review',
      toneId: 'professional',
      intensity: RewriteIntensity.moderate,
      length: RewriteLength.same,
    );

    final tone = ToneLibrary.builtIns.firstWhere((t) => t.id == 'professional');

    test('includes the tone instruction', () {
      final prompt = PromptBuilder.build(base, tone: tone);
      expect(prompt.system, contains(tone.instruction));
    });

    test('puts the source text in the user field, untouched by templating', () {
      final prompt = PromptBuilder.build(base, tone: tone);
      expect(prompt.user, 'we need 2 meet monday for the project review');
    });

    test('adds variant marker when multiple variants requested', () {
      final req = base.copyWith(variantCount: 3);
      final prompt = PromptBuilder.build(req, tone: tone);
      expect(prompt.system, contains('3 different versions'));
      expect(prompt.system, contains(PromptBuilder.variantMarker));
    });

    test('mentions the resolved audience label and custom instruction when provided', () {
      // request.audience holds ids, not display text — the caller resolves
      // them (ConfigStore.audienceById) before this runs, so the prompt
      // must reflect audienceLabels, never request.audience directly.
      final req = base.copyWith(
        audience: ['a_manager_id'],
        customInstruction: 'sound more optimistic',
      );
      final prompt = PromptBuilder.build(
        req,
        tone: tone,
        audienceLabels: const ['a manager'],
      );
      expect(prompt.system, contains('a manager'));
      expect(prompt.system, isNot(contains('a_manager_id')));
      expect(prompt.system, contains('sound more optimistic'));
    });

    test('omits the audience line entirely when audienceLabels is empty', () {
      final req = base.copyWith(audience: ['some_id']);
      final prompt = PromptBuilder.build(req, tone: tone);
      expect(prompt.system, isNot(contains('Audience:')));
    });

    test('never includes raw punctuation noise in single version mode', () {
      final prompt = PromptBuilder.build(base, tone: tone);
      expect(prompt.system, isNot(contains(PromptBuilder.variantMarker)));
    });
  });

  group('PromptBuilder.parseVariants', () {
    test('returns a single cleaned variant', () {
      final parts = PromptBuilder.parseVariants('  A polished rewrite.  ');
      expect(parts, ['A polished rewrite.']);
    });

    test('strips surrounding quotes', () {
      final parts = PromptBuilder.parseVariants('"Quoted output"');
      expect(parts, ['Quoted output']);
    });

    test('splits on marker and trims', () {
      final raw = 'Version A\n${PromptBuilder.variantMarker}\nVersion B';
      final parts = PromptBuilder.parseVariants(raw);
      expect(parts, ['Version A', 'Version B']);
    });

    test('strips "Variant 2:" style prefixes', () {
      final parts = PromptBuilder.parseVariants(
        '${PromptBuilder.variantMarker}Variant 2: Second one',
      );
      expect(parts, ['Second one']);
    });

    test('does not fabricate missing variants', () {
      final raw = 'Only one\n${PromptBuilder.variantMarker}\nOnly one';
      final parts = PromptBuilder.parseVariants(raw, expected: 3);
      expect(parts.length, 2);
    });

    test('returns no variant for empty model output', () {
      final parts = PromptBuilder.parseVariants('');
      expect(parts, isEmpty);
    });
  });
}
