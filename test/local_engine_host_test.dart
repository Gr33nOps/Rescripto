import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/engine/local/local_engine_host.dart';
import 'package:rescripto/services/local_llm_service.dart';

void main() {
  group('LocalEngineHost.withEngine', () {
    // LocalLlmService's constructor only looks up the FlutterLlama.instance
    // singleton — it does not touch the platform channel until a method is
    // called — so a real instance is safe to construct here as long as the
    // test bodies below never call anything on it.
    late LocalEngineHost host;

    setUp(() => host = LocalEngineHost(LocalLlmService()));

    test('runs a single call and returns its result', () async {
      final result = await host.withEngine((_) async => 42);
      expect(result, 42);
    });

    test('serialises overlapping calls instead of running them concurrently', () async {
      final order = <String>[];
      final firstStarted = Completer<void>();

      final first = host.withEngine((_) async {
        order.add('first-start');
        firstStarted.complete();
        // Give the second call every opportunity to jump the queue if the
        // host let it.
        await Future<void>.delayed(const Duration(milliseconds: 30));
        order.add('first-end');
        return 1;
      });

      await firstStarted.future;
      final second = host.withEngine((_) async {
        order.add('second-start');
        return 2;
      });

      expect(await first, 1);
      expect(await second, 2);
      expect(order, ['first-start', 'first-end', 'second-start']);
    });

    test('a failed call does not block the next one from running', () async {
      final failing = host.withEngine((_) async => throw StateError('boom'));
      await expectLater(failing, throwsA(isA<StateError>()));

      final next = await host.withEngine((_) async => 'still works');
      expect(next, 'still works');
    });

    test('isBusy reflects whether a call is currently running', () async {
      expect(host.isBusy, isFalse);
      final started = Completer<void>();
      final blocked = Completer<void>();

      final task = host.withEngine((_) async {
        started.complete();
        await blocked.future;
        return null;
      });

      await started.future;
      expect(host.isBusy, isTrue);
      blocked.complete();
      await task;
      expect(host.isBusy, isFalse);
    });

    test('releaseLoadedModel unloads native memory without deleting files', () async {
      final service = _TrackingLocalLlmService();
      final trackingHost = LocalEngineHost(service);

      await trackingHost.releaseLoadedModel();

      expect(service.unloadCalls, 1);
    });
  });
}

class _TrackingLocalLlmService extends LocalLlmService {
  int unloadCalls = 0;

  @override
  Future<void> unloadModel() async {
    unloadCalls++;
  }
}
