import '../../models/ai_model.dart';
import '../prompt_spec.dart';

/// Stop markers common to most instruction-tuned GGUF releases, on top of
/// whichever marker is specific to a family's own turn syntax below. Kept as
/// a safety net for stray base-model-style output, matching the flat list
/// `LocalLlmService.stopSequences` used to carry as a single undifferentiated
/// list for every family.
const List<String> _commonStopSequences = [
  '<|end_of_text|>',
  '<|endoftext|>',
  '</s>',
];

/// Wraps a [PromptSpec] in the chat markup a model family expects, and knows
/// the turn marker that ends its own output.
///
/// Rendering and stop sequences used to live apart — the template in
/// `PromptBuilder._wrapChat`, the markers in `LocalLlmService.stopSequences`
/// as one flat list for every family. That split is exactly what produced
/// the bug fixed in 1.0.3: the list carried `<|end_of_turn|>` (pipe-wrapped)
/// while Gemma 3 actually emits `<end_of_turn>`, so a Gemma rewrite that hit
/// no other stop condition ran to the full token budget. Pairing the two on
/// one object makes that mismatch a same-file diff instead of a cross-file one.
abstract class ChatTemplate {
  const ChatTemplate();

  String render(PromptSpec spec);

  List<String> get stopSequences;

  factory ChatTemplate.forFamily(ModelFamily family) => switch (family) {
    ModelFamily.gemma => const _GemmaChatTemplate(),
    ModelFamily.llama => const _LlamaChatTemplate(),
    ModelFamily.qwen => const _ChatMlTemplate(),
  };
}

/// Gemma has no system role, so the instructions and the draft have to share
/// a single user turn. That merge is where a real bug lived: joined by a bare
/// blank line, the rules ran straight into the text with nothing marking the
/// seam, and the model would reply *"I don't see any text provided"* while
/// quoting that very text back. `PromptSpec.user` now arrives already fenced
/// by `PromptBuilder` (see its `textStart` doc), and the label below gives
/// the seam a second, explicit boundary.
class _GemmaChatTemplate extends ChatTemplate {
  const _GemmaChatTemplate();

  @override
  String render(PromptSpec spec) =>
      '<start_of_turn>user\n'
      '${spec.system}\n\n'
      '--- END OF INSTRUCTIONS ---\n\n'
      'Rewrite the text below and output only the rewritten text.\n\n'
      '${spec.user}<end_of_turn>\n<start_of_turn>model\n';

  @override
  List<String> get stopSequences => const [
    '<end_of_turn>',
    ..._commonStopSequences,
  ];
}

class _LlamaChatTemplate extends ChatTemplate {
  const _LlamaChatTemplate();

  @override
  String render(PromptSpec spec) =>
      '<|start_header_id|>system<|end_header_id|>\n\n'
      '${spec.system}<|eot_id|>'
      '<|start_header_id|>user<|end_header_id|>\n\n${spec.user}<|eot_id|>'
      '<|start_header_id|>assistant<|end_header_id|>\n\n';

  @override
  List<String> get stopSequences => const [
    '<|eot_id|>',
    ..._commonStopSequences,
  ];
}

class _ChatMlTemplate extends ChatTemplate {
  const _ChatMlTemplate();

  @override
  String render(PromptSpec spec) =>
      '<|im_start|>system\n${spec.system}<|im_end|>\n'
      '<|im_start|>user\n${spec.user}<|im_end|>\n'
      '<|im_start|>assistant\n';

  @override
  List<String> get stopSequences => const [
    '<|im_end|>',
    ..._commonStopSequences,
  ];
}
