import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/models/ai_model.dart';
import 'package:rescripto/services/local_llm_service.dart';

void main() {
  group('LocalLlmService.stopSequences', () {
    // The turn marker each family closes its assistant turn with. If a family's
    // marker is missing from the stop list and the model does not emit an EOS
    // token, generation runs on to the full token budget — minutes of wasted
    // compute and a reply with template junk glued to the end.
    const terminators = {
      'gemma': '<end_of_turn>',
      'llama': '<|eot_id|>',
      'qwen': '<|im_end|>',
    };

    for (final entry in terminators.entries) {
      test('covers the ${entry.key} turn terminator', () {
        expect(LocalLlmService.stopSequences, contains(entry.value));
      });
    }

    test('covers every family in the model catalog', () {
      for (final model in ModelCatalog.models) {
        expect(
          terminators,
          contains(model.family),
          reason:
              '${model.id} uses chat family "${model.family}", which has no '
              'known turn terminator in this test. Add it here and to '
              'LocalLlmService.stopSequences.',
        );
      }
    });

    test('does not carry the pipe-wrapped Gemma marker, which matches nothing', () {
      expect(LocalLlmService.stopSequences, isNot(contains('<|end_of_turn|>')));
    });
  });
}
