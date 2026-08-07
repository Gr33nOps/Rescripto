/// Result of a local speech-to-text pass.
class SpeechResult {
  const SpeechResult({required this.text, required this.language});

  final String text;

  /// ISO language code detected by the model ('' when unknown).
  final String language;

  bool get isEmpty => text.trim().isEmpty;
}
