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

    test('includes the tone instruction', () {
      final prompt = PromptBuilder.build(base, modelFamily: 'qwen');
      final tone = ToneLibrary.byId('professional');
      expect(prompt, contains(tone.instruction));
    });

    test('wraps with ChatML template for qwen family', () {
      final prompt = PromptBuilder.build(base, modelFamily: 'qwen');
      expect(prompt, startsWith('<|im_start|>system\n'));
      expect(prompt, contains('<|im_start|>user\n'));
      expect(prompt, contains('we need 2 meet monday'));
      expect(prompt, endsWith('<|im_start|>assistant\n'));
    });

    test('wraps with gemma template for gemma family', () {
      final prompt = PromptBuilder.build(base, modelFamily: 'gemma');
      expect(prompt, startsWith('<start_of_turn>user\n'));
      expect(prompt, endsWith('<start_of_turn>model\n'));
    });

    test('wraps with llama template for llama family', () {
      final prompt = PromptBuilder.build(base, modelFamily: 'llama');
      expect(prompt, contains('<|start_header_id|>system<|end_header_id|>'));
      expect(prompt, contains('<|start_header_id|>assistant<|end_header_id|>'));
    });

    test('adds variant marker when multiple variants requested', () {
      final req = base.copyWith(variantCount: 3);
      final prompt = PromptBuilder.build(req, modelFamily: 'qwen');
      expect(prompt, contains('3 different versions'));
      expect(prompt, contains(PromptBuilder.variantMarker));
    });

    test('mentions audience and custom instruction when provided', () {
      final req = base.copyWith(
        audience: ['a manager'],
        customInstruction: 'sound more optimistic',
      );
      final prompt = PromptBuilder.build(req, modelFamily: 'qwen');
      expect(prompt, contains('a manager'));
      expect(prompt, contains('sound more optimistic'));
    });

    test('never includes raw punctuation noise in single version mode', () {
      final prompt = PromptBuilder.build(base, modelFamily: 'qwen');
      expect(prompt, isNot(contains(PromptBuilder.variantMarker)));
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
