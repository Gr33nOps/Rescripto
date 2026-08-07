/// A single rewrite produced by the local model.
class RewriteOutput {
  const RewriteOutput({
    required this.text,
    this.tokensGenerated = 0,
    this.generationTimeMs = 0,
  });

  final String text;
  final int tokensGenerated;
  final int generationTimeMs;

  double get tokensPerSecond =>
      generationTimeMs > 0 ? (tokensGenerated * 1000) / generationTimeMs : 0;

  bool get isEmpty => text.trim().isEmpty;
}
