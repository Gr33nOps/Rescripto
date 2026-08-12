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
/// `MainActivity.kt`'s own doc for why. [pending] is a one-shot queue: a
/// listener applies it (usually to `RewriteController.setSource`) and calls
/// [consume], the same "queue with a single reader" shape already used for
/// the mic transcript and the model-missing banner's tab switch.
class ShareIntentBridge extends ChangeNotifier {
  ShareIntentBridge({MethodChannel? channel}) : _channel = channel ?? const MethodChannel(_channelName) {
    _channel.setMethodCallHandler(_onMethodCall);
    _loadInitialIntent();
  }

  static const _channelName = 'com.rescripto.rescripto/system';

  final MethodChannel _channel;

  IncomingText? _pending;
  IncomingText? get pending => _pending;

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
    _pending = incoming;
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

  /// Call once [pending] has been applied (to `RewriteController.setSource`,
  /// typically) so it isn't reapplied on the next rebuild.
  void consume() {
    _pending = null;
    notifyListeners();
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
