import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Where a piece of [IncomingText] arrived from — mirrors the three native
/// entry points `MainActivity.kt` and `RescriptoTileService.kt` funnel into
/// the same channel.
enum IncomingTextSource { share, processText, tile }

class IncomingText {
  const IncomingText({required this.text, required this.source, required this.readOnly});

  final String text;
  final IncomingTextSource source;

  /// True when the selection this came from can't be replaced in place
  /// (`Intent.EXTRA_PROCESS_TEXT_READONLY`). Only ever true for
  /// [IncomingTextSource.processText] — share and tile text was never a
  /// selection to begin with.
  final bool readOnly;
}

/// Bridges Android's ACTION_PROCESS_TEXT, ACTION_SEND, and Quick Settings
/// tile entry points into the running app.
///
/// One channel, one bridge, no second Flutter engine — see
/// `MainActivity.kt`'s own doc for why. [pending] is the front of a FIFO
/// queue: a listener applies it (usually to `RewriteController.setSource`)
/// and calls [consume], the same "queue with a single reader" shape already
/// used for the mic transcript and the model-missing banner's tab switch.
///
/// A single nullable field used to hold this instead of a real queue — any
/// second arrival before a consumer read and consumed the first silently
/// replaced it, losing that text entirely. Two rapid shares can do this;
/// so can a live `incomingText` call from `_onMethodCall` landing while the
/// async `getInitialIntent` lookup [_loadInitialIntent] kicks off from the
/// constructor is still in flight — whichever resolved second used to win,
/// unconditionally, no matter which one actually arrived first.
class ShareIntentBridge extends ChangeNotifier {
  ShareIntentBridge({MethodChannel? channel}) : _channel = channel ?? const MethodChannel(_channelName) {
    _channel.setMethodCallHandler(_onMethodCall);
    _loadInitialIntent();
  }

  static const _channelName = 'com.rescripto.rescripto/system';

  final MethodChannel _channel;

  final Queue<IncomingText> _queue = Queue<IncomingText>();

  /// The oldest not-yet-consumed intent, if any.
  IncomingText? get pending => _queue.isEmpty ? null : _queue.first;

  /// True once a PROCESS_TEXT request has arrived and hasn't been answered
  /// yet — what the rewrite screen's "Insert & return" action watches for.
  /// Cleared by [finishProcessText]; never set at all for a read-only
  /// selection, since there is nothing to insert back.
  bool _awaitingProcessTextResult = false;
  bool get awaitingProcessTextResult => _awaitingProcessTextResult;

  Future<void> _loadInitialIntent() async {
    final Map<Object?, Object?>? raw;
    try {
      raw = await _channel.invokeMapMethod<Object?, Object?>('getInitialIntent');
    } on MissingPluginException {
      // No platform-side implementation — host tests and non-Android
      // platforms both land here. Nothing pending, nothing to do.
      return;
    }
    if (raw != null) _apply(_parse(raw));
  }

  Future<void> _onMethodCall(MethodCall call) async {
    if (call.method != 'incomingText') return;
    _apply(_parse(call.arguments as Map<Object?, Object?>));
  }

  void _apply(IncomingText incoming) {
    _queue.add(incoming);
    _awaitingProcessTextResult = incoming.source == IncomingTextSource.processText && !incoming.readOnly;
    notifyListeners();
  }

  IncomingText _parse(Map<Object?, Object?> raw) {
    final source = switch (raw['source']) {
      'process_text' => IncomingTextSource.processText,
      'tile' => IncomingTextSource.tile,
      _ => IncomingTextSource.share,
    };
    return IncomingText(
      text: raw['text'] as String,
      source: source,
      readOnly: raw['readOnly'] as bool? ?? false,
    );
  }

  /// Call once [incoming] (read from [pending]) has been applied (to
  /// `RewriteController.setSource`, typically), so it isn't reapplied and
  /// the next queued intent, if any, becomes [pending].
  ///
  /// Only removes [incoming] if it is still the front of the queue —
  /// `HomeShell` can schedule more than one post-frame callback for the
  /// same pending intent before the first one runs (harmless when this was
  /// a single field: consuming twice was just setting null twice). Under a
  /// real queue, an unconditional pop would be wrong: the second callback
  /// would consume whatever arrived *after* the one it actually applied,
  /// silently dropping it the same way the single field used to. Comparing
  /// against the specific instance makes a stale, already-applied call a
  /// no-op instead.
  void consume(IncomingText incoming) {
    if (_queue.isNotEmpty && identical(_queue.first, incoming)) {
      _queue.removeFirst();
      notifyListeners();
    }
  }

  /// Returns [resultText] to whatever app sent the PROCESS_TEXT request and
  /// closes this activity — see `MainActivity.kt`'s own doc for why
  /// declining needs no equivalent call.
  Future<void> finishProcessText(String resultText) async {
    try {
      await _channel.invokeMethod('finishProcessText', {'text': resultText});
    } on MissingPluginException {
      // Nothing to finish on a platform with no native side.
    }
    _awaitingProcessTextResult = false;
    notifyListeners();
  }
}
