import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/services/share_intent_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.rescripto.rescripto/system');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mockHandler(Future<Object?> Function(MethodCall call)? handler) {
    messenger.setMockMethodCallHandler(channel, handler);
  }

  Future<void> simulateIncomingText(Map<String, Object?> args) async {
    final call = MethodCall('incomingText', args);
    final data = const StandardMethodCodec().encodeMethodCall(call);
    await messenger.handlePlatformMessage(channel.name, data, (_) {});
  }

  tearDown(() => mockHandler(null));

  group('ShareIntentBridge — cold launch (getInitialIntent)', () {
    test('stays empty when nothing was pending at launch', () async {
      mockHandler((call) async {
        expect(call.method, 'getInitialIntent');
        return null;
      });

      final bridge = ShareIntentBridge(channel: channel);
      await pumpEventQueue();

      expect(bridge.pending, isNull);
      expect(bridge.awaitingProcessTextResult, isFalse);
    });

    test('a writable PROCESS_TEXT selection sets pending and awaitingProcessTextResult', () async {
      mockHandler((call) async => {'text': 'selected text', 'source': 'process_text', 'readOnly': false});

      final bridge = ShareIntentBridge(channel: channel);
      await pumpEventQueue();

      expect(bridge.pending?.text, 'selected text');
      expect(bridge.pending?.source, IncomingTextSource.processText);
      expect(bridge.pending?.readOnly, isFalse);
      expect(bridge.awaitingProcessTextResult, isTrue);
    });

    test('a read-only PROCESS_TEXT selection sets pending but not awaitingProcessTextResult', () async {
      mockHandler((call) async => {'text': 'read-only text', 'source': 'process_text', 'readOnly': true});

      final bridge = ShareIntentBridge(channel: channel);
      await pumpEventQueue();

      expect(bridge.pending?.readOnly, isTrue);
      expect(bridge.awaitingProcessTextResult, isFalse);
    });

    test('a share intent never sets awaitingProcessTextResult', () async {
      mockHandler((call) async => {'text': 'shared text', 'source': 'share', 'readOnly': false});

      final bridge = ShareIntentBridge(channel: channel);
      await pumpEventQueue();

      expect(bridge.pending?.source, IncomingTextSource.share);
      expect(bridge.awaitingProcessTextResult, isFalse);
    });

    test('a tile intent parses as source tile', () async {
      mockHandler((call) async => {'text': 'clipboard text', 'source': 'tile', 'readOnly': false});

      final bridge = ShareIntentBridge(channel: channel);
      await pumpEventQueue();

      expect(bridge.pending?.source, IncomingTextSource.tile);
    });

    test('no platform implementation at all leaves the bridge empty rather than throwing', () async {
      mockHandler(null);

      expect(() => ShareIntentBridge(channel: channel), returnsNormally);
      await pumpEventQueue();
    });
  });

  group('ShareIntentBridge — warm push (incomingText)', () {
    test('an incomingText call updates pending and notifies listeners', () async {
      mockHandler((call) async => null);
      final bridge = ShareIntentBridge(channel: channel);
      await pumpEventQueue();

      var notified = false;
      bridge.addListener(() => notified = true);

      await simulateIncomingText({'text': 'new selection', 'source': 'process_text', 'readOnly': false});

      expect(bridge.pending?.text, 'new selection');
      expect(notified, isTrue);
    });
  });

  group('ShareIntentBridge.consume', () {
    test('clears pending without touching awaitingProcessTextResult', () async {
      mockHandler((call) async => {'text': 'x', 'source': 'process_text', 'readOnly': false});
      final bridge = ShareIntentBridge(channel: channel);
      await pumpEventQueue();

      bridge.consume();

      expect(bridge.pending, isNull);
      expect(bridge.awaitingProcessTextResult, isTrue);
    });
  });

  group('ShareIntentBridge.finishProcessText', () {
    test('invokes finishProcessText with the result text and clears awaitingProcessTextResult', () async {
      MethodCall? captured;
      mockHandler((call) async {
        if (call.method == 'getInitialIntent') {
          return {'text': 'x', 'source': 'process_text', 'readOnly': false};
        }
        captured = call;
        return null;
      });
      final bridge = ShareIntentBridge(channel: channel);
      await pumpEventQueue();
      expect(bridge.awaitingProcessTextResult, isTrue);

      await bridge.finishProcessText('the rewritten text');

      expect(captured?.method, 'finishProcessText');
      expect(captured?.arguments, {'text': 'the rewritten text'});
      expect(bridge.awaitingProcessTextResult, isFalse);
    });

    test('does not throw when there is no platform implementation', () async {
      mockHandler(null);
      final bridge = ShareIntentBridge(channel: channel);
      await pumpEventQueue();

      await expectLater(bridge.finishProcessText('text'), completes);
    });
  });
}
