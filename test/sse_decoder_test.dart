import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/engine/cloud/sse_decoder.dart';

Stream<List<int>> _bytesFrom(String text) => Stream.value(utf8.encode(text));

/// Splits [text] into byte chunks at arbitrary points, so decoding is
/// exercised against a payload arriving split mid-line — the way TCP
/// actually delivers a streaming HTTP response.
Stream<List<int>> _chunkedBytesFrom(String text, List<int> splitPoints) async* {
  final bytes = utf8.encode(text);
  var start = 0;
  for (final point in splitPoints) {
    yield bytes.sublist(start, point);
    start = point;
  }
  yield bytes.sublist(start);
}

void main() {
  const decoder = SseDecoder();

  group('SseDecoder.decode', () {
    test('parses a bare data-only event (OpenAI/Gemini shape)', () async {
      final events = await decoder.decode(_bytesFrom('data: {"a":1}\n\n')).toList();
      expect(events, [const SseEvent(event: null, data: '{"a":1}')]);
    });

    test('parses a named event (Anthropic shape)', () async {
      final events = await decoder
          .decode(_bytesFrom('event: message_stop\ndata: {}\n\n'))
          .toList();
      expect(events, [const SseEvent(event: 'message_stop', data: '{}')]);
    });

    test('joins multiple data: lines within one event with a newline', () async {
      final events = await decoder
          .decode(_bytesFrom('data: line one\ndata: line two\n\n'))
          .toList();
      expect(events.single.data, 'line one\nline two');
    });

    test('ignores comment / keep-alive lines starting with a colon', () async {
      final events = await decoder
          .decode(_bytesFrom(':keep-alive\ndata: {"x":1}\n\n'))
          .toList();
      expect(events, [const SseEvent(event: null, data: '{"x":1}')]);
    });

    test('ignores id: and retry: fields', () async {
      final events = await decoder
          .decode(_bytesFrom('id: 42\nretry: 1000\ndata: {"x":1}\n\n'))
          .toList();
      expect(events, [const SseEvent(event: null, data: '{"x":1}')]);
    });

    test('flushes a trailing event even with no final blank line', () async {
      // Some servers close the connection right after the last data line.
      final events = await decoder.decode(_bytesFrom('data: last\n')).toList();
      expect(events, [const SseEvent(event: null, data: 'last')]);
    });

    test('a stream that ends with no pending data yields nothing extra', () async {
      final events = await decoder.decode(_bytesFrom('data: one\n\n')).toList();
      expect(events, hasLength(1));
    });

    test('multiple events in one payload are each emitted separately', () async {
      final events = await decoder
          .decode(_bytesFrom('data: {"n":1}\n\ndata: {"n":2}\n\n'))
          .toList();
      expect(events.map((e) => e.data), ['{"n":1}', '{"n":2}']);
    });

    test('a marker split across two byte chunks is still parsed correctly', () async {
      const text = 'event: message_stop\ndata: {"ok":true}\n\n';
      // Split mid-way through the word "message_stop".
      final splitAt = text.indexOf('essage');
      final events = await decoder
          .decode(_chunkedBytesFrom(text, [splitAt]))
          .toList();
      expect(events, [const SseEvent(event: 'message_stop', data: '{"ok":true}')]);
    });
  });
}
