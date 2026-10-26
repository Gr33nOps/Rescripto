import 'package:betto_lang_detector/betto_lang_detector.dart';

/// Conservative offline checks around rewrites from small local models.
///
/// Language detection on a short draft is uncertain. This class only blocks
/// clear language/script drift; an undetermined draft is left to the model.
class LanguageFidelity {
  LanguageFidelity._();

  static final LanguageDetector _detector = LanguageDetector.pureDart();

  static LanguageProfile inspect(String source) {
    final whole = _languageOf(source);
    final parts = _parts(source);
    final languages = <String>{};
    if (whole != null) languages.add(whole);
    for (final part in parts) {
      final code = _languageOf(part);
      if (code != null) languages.add(code);
    }

    final cues = <String>[];
    if (languages.length == 1) {
      final code = languages.single;
      cues.add(_wholeTextCue(code));
    } else if (languages.length > 1) {
      cues.add(
        'Keep the language switches and passage order. Edit only passages '
        'that need correction; copy already-correct passages unchanged. '
        'Never translate a passage to match its neighbours. Keep time '
        'expressions exactly as written.',
      );
      for (final code in languages) {
        cues.add(_passageCue(code));
      }
    }

    return LanguageProfile(source, languages, cues);
  }

  static String? _languageOf(String text) {
    final script = _detector.dominantScript(text);
    final minimum = script == 'Latn' ? 24 : 8;
    if (text.runes.length < minimum) return null;
    return switch (_detector.detect(text)) {
      Detected(best: final guess) => guess.code,
      Undetermined() => null,
    };
  }

  /// A conservative fallback plan for drafts that switch languages at clear
  /// punctuation boundaries. Undetermined short passages stay verbatim.
  static List<LanguagePassage>? mixedPassages(String source) {
    if (inspect(source).languages.length < 2) return null;
    final passages = <LanguagePassage>[];
    var cursor = 0;
    for (final match in RegExp(
      r'[^,.!?;:\n،؛。！？]+[,.!?;:\n،؛。！？]*',
    ).allMatches(source)) {
      if (match.start > cursor) {
        passages.add(LanguagePassage(source.substring(cursor, match.start)));
      }
      final original = match.group(0)!;
      passages.add(LanguagePassage(original, _languageOf(original.trim())));
      cursor = match.end;
    }
    if (cursor < source.length) {
      passages.add(LanguagePassage(source.substring(cursor)));
    }
    if (!passages.any((part) => part.languageCode != null)) return null;
    return passages;
  }

  static List<String> _parts(String text) => text
      .split(RegExp(r'[,.!?;:\n،؛。！？]+'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();

  static String _wholeTextCue(String code) => switch (code) {
    'de' =>
      'Schreibe die gesamte Antwort auf Deutsch. Uebersetze nicht ins Englische.',
    'fr' => 'Réécris toute la réponse en français. Ne traduis pas en anglais.',
    'es' => 'Reescribe toda la respuesta en español. No traduzcas al inglés.',
    'ja' => '回答全体を日本語で書いてください。英語に翻訳しないでください。',
    'ur' => 'پورا جواب اردو میں لکھیں۔ انگریزی میں ترجمہ نہ کریں۔',
    _ =>
      'Write the entire rewrite in the source language (ISO code $code). Do not translate it.',
  };

  static String _passageCue(String code) => switch (code) {
    'de' =>
      'German passages: Überarbeite nur die deutschen Textteile auf Deutsch.',
    'fr' => 'French passages: Réécris les passages français en français.',
    'es' => 'Spanish passages: Reescribe las partes en español en español.',
    'en' => 'English passages: edit those passages in English.',
    'ja' => 'Japanese passages: 日本語の部分は日本語のまま書き直してください。',
    'ur' => 'Urdu passages: اردو حصوں کو اردو میں ہی دوبارہ لکھیں۔',
    _ =>
      'Passages in source language ISO code $code: keep them in that language.',
  };
}

class LanguagePassage {
  const LanguagePassage(this.original, [this.languageCode]);

  final String original;
  final String? languageCode;

  String get sourceText => original.trim();

  String withRewrite(String rewritten) {
    final leading = RegExp(r'^\s*').stringMatch(original) ?? '';
    final trailing = RegExp(r'\s*$').stringMatch(original) ?? '';
    var replacement = rewritten.trim();
    // A standalone model capitalizes a clause that originally followed a
    // comma. Keep its original lower-case start on reconstruction.
    if (RegExp(r'^[a-z]').hasMatch(sourceText) &&
        RegExp(r'^[A-Z]').hasMatch(replacement)) {
      replacement = replacement[0].toLowerCase() + replacement.substring(1);
    }
    return '$leading$replacement$trailing';
  }
}

class LanguageProfile {
  const LanguageProfile(this.source, this.languages, this.promptCues);

  final String source;
  final Set<String> languages;
  final List<String> promptCues;

  /// Rejects a clear translation to English or a change of writing script.
  /// Keeps the source visible for the user to retry with another model.
  bool rejects(String output) {
    final sourceNumbers = RegExp(
      r'\d+',
    ).allMatches(source).map((m) => m.group(0)!).toList();
    final outputNumbers = RegExp(
      r'\d+',
    ).allMatches(output).map((m) => m.group(0)!).toList();
    if (!_sameItems(sourceNumbers, outputNumbers)) return true;

    final sourceScripts = <String>{};
    for (final part in LanguageFidelity._parts(source)) {
      final script = LanguageFidelity._detector.dominantScript(part);
      if (script != null && script != 'Latn') sourceScripts.add(script);
    }
    if (sourceScripts.isNotEmpty) {
      final outputScripts = <String>{};
      for (final part in LanguageFidelity._parts(output)) {
        final script = LanguageFidelity._detector.dominantScript(part);
        if (script != null && script != 'Latn') outputScripts.add(script);
      }
      if (!outputScripts.containsAll(sourceScripts)) return true;
    }

    if (!languages.any((code) => code != 'en')) return false;
    final outputLanguages = <String>{};
    final wholeOutput = LanguageFidelity._languageOf(output);
    if (wholeOutput != null) outputLanguages.add(wholeOutput);
    for (final part in LanguageFidelity._parts(output)) {
      final code = LanguageFidelity._languageOf(part);
      if (code != null) outputLanguages.add(code);
    }
    if (languages.length == 1 &&
        languages.single != 'en' &&
        _hasClearEnglishSyntax(output) &&
        !_hasClearEnglishSyntax(source)) {
      return true;
    }
    // Compare only when the output is unambiguously English. Other pairs of
    // related languages are too easy for a short-text detector to confuse.
    if (!outputLanguages.contains('en') ||
        outputLanguages.length != 1 ||
        !_hasClearEnglishSyntax(output)) {
      return false;
    }
    return languages.any((code) => code != 'en');
  }

  // N-gram detection can call a short German clause English because words
  // such as "online" occur in both. Require several unmistakable English
  // function words before discarding a Latin-script rewrite.
  static bool _hasClearEnglishSyntax(String text) {
    final markers = RegExp(
      r'\b(?:i|but|be|at|the|because|will|would|could|should|have|has|can|cannot|am|is|are|was|were|you|your|we|our|they|their|this|that|with|from|tomorrow)\b',
      caseSensitive: false,
    ).allMatches(text);
    return markers.length >= 2;
  }

  static bool _sameItems(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
