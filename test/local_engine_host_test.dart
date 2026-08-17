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

  group('LocalEngineHost — per-request cancellation', () {
    // Regression coverage for a bug where a rewrite and a workflow step
    // could both reach this host: prepare (load) and generate used to be two
    // separate withEngine calls, so a second caller's prepare could land in
    // the gap between them and load a different model before the first
    // caller's generate call ran. LocalLlmEngine now passes both under one
    // withEngine call with a token; these tests pin the host-level contract
    // that fix depends on.
    late LocalEngineHost host;

    setUp(() => host = LocalEngineHost(LocalLlmService()));

    test('isActive is true only for the token currently running', () async {
      final tokenA = Object();
      final started = Completer<void>();
      final blocked = Completer<void>();

      final task = host.withEngine((_) async {
        started.complete();
        await blocked.future;
        return null;
      }, token: tokenA);

      await started.future;
      expect(host.isActive(tokenA), isTrue);
      expect(host.isActive(Object()), isFalse);

      blocked.complete();
      await task;
      expect(host.isActive(tokenA), isFalse);
    });

    test('requestStop calls native stop when the token is active', () async {
      final service = _TrackingLocalLlmService();
      final trackingHost = LocalEngineHost(service);
      final token = Object();
      final started = Completer<void>();
      final blocked = Completer<void>();

      final task = trackingHost.withEngine((_) async {
        started.complete();
        await blocked.future;
        return null;
      }, token: token);

      await started.future;
      await trackingHost.requestStop(token);
      expect(service.stopCalls, 1);

      blocked.complete();
      await task;
    });

    test(
      'requestStop is a no-op for a token still queued behind another one',
      () async {
        // The exact race this exists for: cancelling a queued-but-not-yet-
        // started request must never touch native, or it would cut off
        // whatever unrelated operation is actually running.
        final service = _TrackingLocalLlmService();
        final trackingHost = LocalEngineHost(service);
        final activeToken = Object();
        final queuedToken = Object();
        final activeStarted = Completer<void>();
        final releaseActive = Completer<void>();

        final active = trackingHost.withEngine((_) async {
          activeStarted.complete();
          await releaseActive.future;
          return null;
        }, token: activeToken);

        await activeStarted.future;
        final queued = trackingHost.withEngine(
          (_) async => null,
          token: queuedToken,
        );

        await trackingHost.requestStop(queuedToken);
        expect(
          service.stopCalls,
          0,
          reason: 'the queued token has nothing native running yet',
        );

        releaseActive.complete();
        await active;
        await queued;
      },
    );
  });
}

class _TrackingLocalLlmService extends LocalLlmService {
  int unloadCalls = 0;
  int stopCalls = 0;

  @override
  Future<void> unloadModel() async {
    unloadCalls++;
  }

  @override
  Future<void> stopGeneration() async {
    stopCalls++;
  }
}
