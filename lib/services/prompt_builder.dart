import '../models/rewrite_request.dart';
import '../models/tone_preset.dart';

/// Builds the LLM prompt for a rewrite request and parses the output.
///
/// Pure Dart (no Flutter deps) so it can be unit-tested easily.
class PromptBuilder {
  /// Marker line the model is asked to emit between alternative versions.
  static const String variantMarker = '---VARIANT---';

  /// Builds the full prompt (system + user) for the given request.
  static String build(RewriteRequest request, {required String modelFamily}) {
    final tone = ToneLibrary.byId(request.toneId);
    final system = _buildSystemPrompt(request, tone);
    final user = request.sourceText.trim();
    return _wrapChat(system, user, modelFamily);
  }

  static String _buildSystemPrompt(RewriteRequest request, TonePreset tone) {
    final buffer = StringBuffer()
      ..writeln('You are Rescripto, a professional writing assistant.')
      ..writeln('You rewrite the user\'s rough text into polished writing.')
      ..writeln('')
      ..writeln('Rules you ALWAYS follow:')
      ..writeln('1. Return ONLY the rewritten text. No commentary, no')
      ..writeln('   explanations, no meta text, no "Here is your rewrite".')
      ..writeln('2. Keep the meaning, facts, names, numbers and details intact.')
      ..writeln('3. Never invent facts that are not in the original text.')
      ..writeln('4. If the text is already excellent, a light polish is fine.')
      ..writeln('')
      ..writeln('Tone: ${tone.instruction}');

    final intensity = request.intensity.factor;
    if (intensity <= 0.3) {
      buffer.writeln('Intensity: LIGHT POLISH. Keep the structure and wording '
          'mostly intact, fix awkward phrasing, grammar and flow.');
    } else if (intensity <= 0.65) {
      buffer.writeln('Intensity: MODERATE. Improve sentence structure and word '
          'choice while keeping the original order of ideas.');
    } else {
      buffer.writeln('Intensity: FULL REWRITE. Rework the text completely with '
          'fresh, strong phrasing while preserving the meaning.');
    }

    switch (request.length) {
      case RewriteLength.shorter:
        buffer.writeln('Length: SHORTER. Trim it down substantially. Cut '
            'redundant words while keeping every key point.');
        break;
      case RewriteLength.longer:
        buffer.writeln('Length: LONGER. Expand with relevant detail, smoother '
            'transitions and fuller sentences, without padding or fluff.');
        break;
      case RewriteLength.same:
        buffer.writeln('Length: SAME as the original.');
    }

    if (request.audience.isNotEmpty) {
      buffer.writeln(
          'Audience: written for ${request.audience.join(', ')}.');
    }
    if (request.customInstruction.trim().isNotEmpty) {
      buffer.writeln('Additional instruction: ${request.customInstruction.trim()}');
    }

    if (request.variantCount > 1) {
      buffer.writeln('');
      buffer.writeln('Produce ${request.variantCount} different versions. '
          'Separate every version with a line containing exactly '
          '"$variantMarker".');
    } else {
      buffer.writeln('');
      buffer.writeln('Write a single version.');
    }
    return buffer.toString();
  }

  /// Wraps system + user text in the chat template expected by a model family.
  static String _wrapChat(String system, String user, String family) {
    switch (family) {
      case 'gemma':
        return '<bos><start_of_turn>user\n$system\n\n$user<end_of_turn>\n'
            '<start_of_turn>model\n';
      case 'llama':
        return '<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n'
            '$system<|eot_id|>'
            '<|start_header_id|>user<|end_header_id|>\n\n$user<|eot_id|>'
            '<|start_header_id|>assistant<|end_header_id|>\n\n';
      case 'qwen':
      default:
        return '<|im_start|>system\n$system<|im_end|>\n'
            '<|im_start|>user\n$user<|im_end|>\n'
            '<|im_start|>assistant\n';
    }
  }

  /// Cleans a raw model response and splits it into multiple variants.
  static List<String> parseVariants(String raw, {int? expected}) {
    var text = raw.trim();
    if (text.startsWith('"') && text.endsWith('"') && text.length > 1) {
      text = text.substring(1, text.length - 1).trim();
    }

    var parts = text.split(variantMarker);
    parts = parts.map(_cleanPart).where((p) => p.isNotEmpty).toList();

    if (parts.isEmpty) {
      parts = [text.trim()];
    }
    if (expected != null && expected > 1) {
      while (parts.length < expected) {
        parts.add(parts.first);
      }
    }
    return parts;
  }

  static String _cleanPart(String raw) {
    var text = raw.trim();
    text = text.replaceAll(RegExp(r'^Variant\s*\d+[\s:]*', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'^-\s*', caseSensitive: false), '');
    text = text.trim();
    return text;
  }
}
