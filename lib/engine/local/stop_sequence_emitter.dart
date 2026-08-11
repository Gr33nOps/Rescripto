import 'dart:math' as math;

/// Turns a growing buffer of appended text into delta output, holding back
/// whatever might still be the start of a stop sequence until either it is
/// ruled out or the input ends.
///
/// Pulled out of `LocalLlmService.generate` specifically so this logic can be
/// unit-tested: `LocalLlmService` wraps a real platform-channel singleton and
/// cannot be constructed in a test without mocking that channel, but the
/// hold-back arithmetic itself has nothing to do with llama.cpp and can be
/// driven directly.
///
/// The old cumulative-string callback re-scanned the whole buffer on every
/// token and could afford to let a partial stop marker show up and then
/// vanish once the rest of it arrived — the caller only ever saw the latest
/// full string, so an earlier, wrong version was simply overwritten. A delta
/// stream cannot un-emit, so this class always withholds the tail that could
/// still turn into a stop sequence, and only lets it out once that stops
/// being possible.
class StopSequenceEmitter {
  StopSequenceEmitter(this.stopSequences)
    : _holdBack = stopSequences.isEmpty
          ? 0
          : stopSequences.map((s) => s.length).reduce(math.max) - 1;

  final List<String> stopSequences;
  final int _holdBack;
  final StringBuffer _buffer = StringBuffer();
  int _emittedLength = 0;
  bool _stopped = false;

  /// True once a complete stop sequence has been found. [append] is a no-op
  /// after this.
  bool get isStopped => _stopped;

  /// Appends [chunk] and returns the new text now safe to emit, or `''`.
  String append(String chunk) {
    if (_stopped || chunk.isEmpty) return '';

    _buffer.write(chunk);
    final raw = _buffer.toString();
    final trimmed = _trim(raw);
    final stopped = trimmed.length < raw.length;

    final safeLength = stopped
        ? trimmed.length
        : math.max(_emittedLength, trimmed.length - _holdBack);

    final delta = safeLength > _emittedLength
        ? trimmed.substring(_emittedLength, safeLength)
        : '';
    _emittedLength = safeLength;
    if (stopped) _stopped = true;
    return delta;
  }

  /// Call once no more chunks will arrive. Nothing further can complete or
  /// rule out a held-back stop sequence, so whatever is left becomes safe.
  ///
  /// Returns the full trimmed text and the delta this call newly released
  /// (empty if [append] already released everything, e.g. because a stop
  /// sequence was found).
  ({String text, String finalDelta}) finish() {
    final text = _trim(_buffer.toString());
    final finalDelta = text.length > _emittedLength
        ? text.substring(_emittedLength)
        : '';
    return (text: text, finalDelta: finalDelta);
  }

  String _trim(String text) {
    var end = text.length;
    for (final sequence in stopSequences) {
      final index = text.indexOf(sequence);
      if (index >= 0 && index < end) end = index;
    }
    return text.substring(0, end);
  }
}
