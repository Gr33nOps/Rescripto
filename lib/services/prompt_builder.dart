import '../engine/prompt_spec.dart';
import '../models/rewrite_request.dart';
import '../models/tone_preset.dart';

/// Builds the rewrite prompt for a request and parses a model's output.
///
/// Pure Dart (no Flutter deps) so it can be unit-tested easily. Provider-
/// neutral: it stops at a [PromptSpec], not a model-specific chat string —
/// wrapping that in a family's markup is `ChatTemplate`'s job
/// (`lib/engine/local/chat_template.dart`), so a cloud engine, which needs
/// system/user text rather than control tokens, can consume this directly.
class PromptBuilder {
  /// Marker line the model is asked to emit between alternative versions.
  static const String variantMarker = '---VARIANT---';

  /// Builds the system + user text for the given request and tone.
  ///
  /// Takes the resolved [tone] rather than a `toneId` and looking it up
  /// internally, so this stays pure once tones move into a user-editable
  /// store (`ConfigStore`, planned) instead of `ToneLibrary`'s static list.
  static PromptSpec build(RewriteRequest request, {required TonePreset tone}) {
    return PromptSpec(
      system: _buildSystemPrompt(request, tone),
      user: request.sourceText.trim(),
    );
  }

  static String _buildSystemPrompt(RewriteRequest request, TonePreset tone) {
    final buffer = StringBuffer()
      ..writeln('You are Rescripto, a professional writing assistant.')
      ..writeln('You rewrite the user\'s rough text into polished writing.')
      ..writeln('')
      ..writeln('Rules you ALWAYS follow:')
      ..writeln('1. Return ONLY the rewritten text. No commentary, no')
      ..writeln('   explanations, no meta text, no "Here is your rewrite".')
      ..writeln(
        '2. Keep the meaning, facts, names, numbers and details intact.',
      )
      ..writeln('3. Never invent facts that are not in the original text.')
      ..writeln('4. If the text is already excellent, a light polish is fine.')
      ..writeln('')
      ..writeln('Tone: ${tone.instruction}');

    final intensity = request.intensity.factor;
    if (intensity <= 0.3) {
      buffer.writeln(
        'Intensity: LIGHT POLISH. Keep the structure and wording '
        'mostly intact, fix awkward phrasing, grammar and flow.',
      );
    } else if (intensity <= 0.65) {
      buffer.writeln(
        'Intensity: MODERATE. Improve sentence structure and word '
        'choice while keeping the original order of ideas.',
      );
    } else {
      buffer.writeln(
        'Intensity: FULL REWRITE. Rework the text completely with '
        'fresh, strong phrasing while preserving the meaning.',
      );
    }

    switch (request.length) {
      case RewriteLength.shorter:
        buffer.writeln(
          'Length: SHORTER. Trim it down substantially. Cut '
          'redundant words while keeping every key point.',
        );
        break;
      case RewriteLength.longer:
        buffer.writeln(
          'Length: LONGER. Expand with relevant detail, smoother '
          'transitions and fuller sentences, without padding or fluff.',
        );
        break;
      case RewriteLength.same:
        buffer.writeln('Length: SAME as the original.');
    }

    if (request.audience.isNotEmpty) {
      buffer.writeln('Audience: written for ${request.audience.join(', ')}.');
    }
    if (request.customInstruction.trim().isNotEmpty) {
      buffer.writeln(
        'Additional instruction: ${request.customInstruction.trim()}',
      );
    }

    if (request.variantCount > 1) {
      buffer.writeln('');
      buffer.writeln(
        'Produce ${request.variantCount} different versions. '
        'Separate every version with a line containing exactly '
        '"$variantMarker".',
      );
    } else {
      buffer.writeln('');
      buffer.writeln('Write a single version.');
    }
    return buffer.toString();
  }

  /// Cleans a raw model response and splits it into multiple variants.
  static List<String> parseVariants(String raw, {int? expected}) {
    var text = raw.trim();
    if (text.startsWith('"') && text.endsWith('"') && text.length > 1) {
      text = text.substring(1, text.length - 1).trim();
    }

    var parts = text.split(variantMarker);
    parts = parts.map(_cleanPart).where((p) => p.isNotEmpty).toList();

    if (parts.isEmpty && text.isNotEmpty) {
      parts = [text.trim()];
    }
    if (expected != null && expected > 0 && parts.length > expected) {
      parts = parts.take(expected).toList();
    }
    return parts;
  }

  static String _cleanPart(String raw) {
    var text = raw.trim();
    text = text.replaceAll(
      RegExp(r'^Variant\s*\d+[\s:]*', caseSensitive: false),
      '',
    );
    text = text.replaceAll(RegExp(r'^-\s*', caseSensitive: false), '');
    text = text.trim();
    return text;
  }
}
