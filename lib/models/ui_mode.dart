/// How much of the rewrite editor's surface is shown.
enum UiMode {
  /// Tone + rewrite only. Intensity, length, audience, extra instructions,
  /// and variants are hidden and pinned to their defaults — not merely
  /// hidden while still silently affecting the prompt underneath.
  simple,

  /// Every control.
  pro,
}
