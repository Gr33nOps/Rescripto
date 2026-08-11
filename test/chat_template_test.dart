import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/engine/local/chat_template.dart';
import 'package:rescripto/engine/prompt_spec.dart';
import 'package:rescripto/models/ai_model.dart';

void main() {
  const spec = PromptSpec(system: 'Be concise.', user: 'we need 2 meet monday');

  group('ChatTemplate.forFamily', () {
    test('wraps with ChatML template for qwen', () {
      final template = ChatTemplate.forFamily(ModelFamily.qwen);
      final rendered = template.render(spec);
      expect(rendered, startsWith('<|im_start|>system\n'));
      expect(rendered, contains('<|im_start|>user\n'));
      expect(rendered, contains('we need 2 meet monday'));
      expect(rendered, endsWith('<|im_start|>assistant\n'));
    });

    test('wraps with gemma template for gemma', () {
      final template = ChatTemplate.forFamily(ModelFamily.gemma);
      final rendered = template.render(spec);
      expect(rendered, startsWith('<start_of_turn>user\n'));
      expect(rendered, endsWith('<start_of_turn>model\n'));
    });

    test('wraps with llama template for llama', () {
      final template = ChatTemplate.forFamily(ModelFamily.llama);
      final rendered = template.render(spec);
      expect(rendered, contains('<|start_header_id|>system<|end_header_id|>'));
      expect(rendered, contains('<|start_header_id|>assistant<|end_header_id|>'));
    });

    test('every ModelFamily has a template', () {
      // Exhaustive over the enum rather than a hand-maintained list, so a
      // new family added to the catalog without a template fails to compile
      // here instead of silently falling through to the wrong markup.
      for (final family in ModelFamily.values) {
        expect(ChatTemplate.forFamily(family), isNotNull);
      }
    });
  });

  group('ChatTemplate.stopSequences', () {
    // The turn marker each family closes its assistant turn with. Regression
    // coverage for the 1.0.3 bug: the list carried the pipe-wrapped
    // '<|end_of_turn|>', which matches no model, while Gemma 3 actually emits
    // '<end_of_turn>' — so a Gemma rewrite that hit no other stop condition
    // ran to the full token budget.
    const turnMarkers = {
      ModelFamily.gemma: '<end_of_turn>',
      ModelFamily.llama: '<|eot_id|>',
      ModelFamily.qwen: '<|im_end|>',
    };

    for (final entry in turnMarkers.entries) {
      test('${entry.key.name} covers its own turn terminator', () {
        final stopSequences = ChatTemplate.forFamily(entry.key).stopSequences;
        expect(stopSequences, contains(entry.value));
      });
    }

    test('does not carry the pipe-wrapped Gemma marker, which matches nothing', () {
      final stopSequences = ChatTemplate.forFamily(ModelFamily.gemma).stopSequences;
      expect(stopSequences, isNot(contains('<|end_of_turn|>')));
    });

    test('every family also carries the common fallback markers', () {
      for (final family in ModelFamily.values) {
        final stopSequences = ChatTemplate.forFamily(family).stopSequences;
        expect(stopSequences, containsAll(['<|end_of_text|>', '<|endoftext|>', '</s>']));
      }
    });
  });

  group('ModelCatalog', () {
    test('every catalog model has a template for its family', () {
      for (final model in ModelCatalog.models) {
        expect(() => ChatTemplate.forFamily(model.family), returnsNormally);
      }
    });
  });
}
