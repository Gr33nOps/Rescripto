import 'dart:convert';

/// One decoded Server-Sent Event: an optional `event:` name plus its
/// (possibly multi-line, `\n`-joined) `data:` payload.
///
/// The `event:` name matters because Anthropic dispatches on it —
/// `content_block_delta`, `message_stop`, `error` — while OpenAI and Gemini
/// only ever send `data:` and expect the payload's own JSON shape to say
/// what happened.
class SseEvent {
  const SseEvent({this.event, required this.data});

  final String? event;
  final String data;

  @override
  bool operator ==(Object other) =>
      other is SseEvent && other.event == event && other.data == data;

  @override
  int get hashCode => Object.hash(event, data);

  @override
  String toString() => 'SseEvent(${event ?? 'data'}: $data)';
}

/// Decodes a raw byte stream in `text/event-stream` framing into [SseEvent]s.
///
/// Pure Dart, no Dio — unit-testable directly against canned byte chunks,
/// the same reason `StopSequenceEmitter` was pulled out of `LocalLlmService`.
/// Line-oriented per the SSE spec: an event is a run of `field: value` lines
/// terminated by a blank line. `id:`/`retry:` fields and `:`-prefixed
/// comment/keep-alive lines are recognised and ignored.
class SseDecoder {
  const SseDecoder();

  Stream<SseEvent> decode(Stream<List<int>> bytes) async* {
    String? event;
    final dataLines = <String>[];

    SseEvent? flush() {
      if (dataLines.isEmpty) return null;
      final flushed = SseEvent(event: event, data: dataLines.join('\n'));
      event = null;
      dataLines.clear();
      return flushed;
    }

    // `bytes.transform(utf8.decoder)` throws at runtime when the stream's
    // reified element type is `Uint8List` rather than exactly `List<int>` —
    // which a real HTTP response body always is. `Converter.bind` doesn't
    // hit the same StreamTransformer subtype check, so it's used directly
    // instead of going through `Stream.transform`.
    final lines = utf8.decoder.bind(bytes).transform(const LineSplitter());
    await for (final line in lines) {
      if (line.isEmpty) {
        final flushed = flush();
        if (flushed != null) yield flushed;
        continue;
      }
      if (line.startsWith(':')) continue;

      if (line.startsWith('event:')) {
        event = line.substring('event:'.length).trim();
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring('data:'.length).trim());
      }
      // id: / retry: are valid SSE fields this app has no use for.
    }

    // Some servers close the connection without a final blank line; the
    // last event would otherwise be silently dropped.
    final trailing = flush();
    if (trailing != null) yield trailing;
  }
}
