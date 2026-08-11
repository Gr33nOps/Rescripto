import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/engine/generation_options.dart';

void main() {
  group('GenerationFieldSupport.forEngine', () {
    test('the local engine supports every field', () {
      final support = GenerationFieldSupport.forEngine('local.llama');
      expect(support.topK, isTrue);
      expect(support.repeatPenalty, isTrue);
    });

    test('OpenAI-compatible and Anthropic drop both topK and repeatPenalty', () {
      for (final id in ['cloud.openaiCompatible', 'cloud.anthropic']) {
        final support = GenerationFieldSupport.forEngine(id);
        expect(support.topK, isFalse, reason: id);
        expect(support.repeatPenalty, isFalse, reason: id);
      }
    });

    test('Gemini supports topK but not repeatPenalty', () {
      final support = GenerationFieldSupport.forEngine('cloud.gemini');
      expect(support.topK, isTrue);
      expect(support.repeatPenalty, isFalse);
    });

    test('an unrecognised engine id falls back to full support rather than guessing', () {
      final support = GenerationFieldSupport.forEngine('');
      expect(support.topK, isTrue);
      expect(support.repeatPenalty, isTrue);
    });
  });
}
