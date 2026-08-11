import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/engine/local/stop_sequence_emitter.dart';

void main() {
  group('StopSequenceEmitter', () {
    test('emits plain text immediately when there are no stop sequences', () {
      final emitter = StopSequenceEmitter(const []);
      expect(emitter.append('Hello'), 'Hello');
      expect(emitter.append(', world'), ', world');
      expect(emitter.isStopped, isFalse);
    });

    test('withholds a marker split across two chunks until it resolves', () {
      // The scenario the hold-back buffer exists for: a 4-char marker arrives
      // as two native tokens, 'ST' then 'OP'. A naive delta emitter would
      // show the 'ST' as real output, then have no way to take it back once
      // the rest of the marker arrives.
      final emitter = StopSequenceEmitter(const ['STOP']);

      // holdBack = len('STOP') - 1 = 3, so the trailing 3 chars (' ST') of
      // this 14-char buffer are not yet provably safe.
      final first = emitter.append('Hello world ST');
      expect(first, 'Hello world', reason: 'the partial marker must not leak out');
      expect(emitter.isStopped, isFalse);

      // Buffer is now 'Hello world STOP more'; the marker resolves at index
      // 12, so only the trailing space held back from the first call — not
      // 'OP more', which arrived after the stop point — is released.
      final second = emitter.append('OP more');
      expect(second, ' ');
      expect(emitter.isStopped, isTrue);

      final result = emitter.finish();
      expect(result.text, 'Hello world ');
      expect(result.finalDelta, isEmpty);
    });

    test('never withholds more than necessary for a short chunk', () {
      final emitter = StopSequenceEmitter(const ['<end_of_turn>']); // len 13
      // Well short of a marker; only the last 12 chars should be withheld.
      final delta = emitter.append('Hi');
      expect(delta, isEmpty);
      final result = emitter.finish();
      expect(result.finalDelta, 'Hi');
    });

    test('releases held-back text once enough arrives to clear it', () {
      final emitter = StopSequenceEmitter(const ['<end_of_turn>']); // len 13
      final chunk = 'a' * 20;
      final delta = emitter.append(chunk);
      // 20 - (13 - 1) = 8 characters are provably safe.
      expect(delta, 'a' * 8);
    });

    test('flushes the full held-back tail when the stream ends cleanly', () {
      final emitter = StopSequenceEmitter(const ['<end_of_turn>']);
      emitter.append('Hello world');
      final result = emitter.finish();
      expect(result.text, 'Hello world');
      expect(result.finalDelta, 'Hello world');
    });

    test('stops on the earliest of several stop sequences', () {
      final emitter = StopSequenceEmitter(const ['<end_of_turn>', '</s>']);
      final delta = emitter.append('Done now</s> trailing junk');
      expect(delta, 'Done now');
      expect(emitter.isStopped, isTrue);
      expect(emitter.finish().text, 'Done now');
    });

    test('ignores further input once stopped', () {
      final emitter = StopSequenceEmitter(const ['</s>']);
      emitter.append('Done</s>');
      expect(emitter.append(' more text'), isEmpty);
      expect(emitter.finish().text, 'Done');
    });

    test('reconstructs the same text a single append would produce', () {
      // Delta emission is a means to an end; concatenating every delta plus
      // the final flush must equal what finish().text reports, chunked any
      // way at all.
      const marker = '<end_of_turn>';
      const full = 'The quick brown fox jumps<end_of_turn>ignored tail';
      for (final chunkSize in [1, 2, 3, 7]) {
        final emitter = StopSequenceEmitter(const [marker]);
        final emitted = StringBuffer();
        for (var i = 0; i < full.length && !emitter.isStopped; i += chunkSize) {
          final end = (i + chunkSize).clamp(0, full.length);
          emitted.write(emitter.append(full.substring(i, end)));
        }
        final result = emitter.finish();
        emitted.write(result.finalDelta);
        expect(
          emitted.toString(),
          result.text,
          reason: 'chunk size $chunkSize',
        );
        expect(result.text, 'The quick brown fox jumps');
      }
    });
  });
}
