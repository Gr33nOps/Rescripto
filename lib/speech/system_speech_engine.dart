import '../models/speech_result.dart';
import 'speech_engine.dart';

/// [SpeechEngine] over Android's built-in `SpeechRecognizer`.
///
/// **Not functional yet.** Talking to `SpeechRecognizer` needs a platform
/// channel, and `MainActivity.kt` doesn't have one — Phase 5 Step 0 is where
/// that foundation gets built, for every native-integration surface at
/// once, not just this one. This class exists now so [SpeechCapabilities]
/// and the "which engine" vocabulary are already correct and in place: in
/// particular, [capabilities] already declares [auditableEgress] false,
/// because `SpeechRecognizer` ships audio from native code on a path
/// nothing in `NetworkGuard`/`NetworkLog` can see, and any UI offering this
/// engine must say so rather than let the network log imply a completeness
/// it doesn't have.
class SystemSpeechEngine implements SpeechEngine {
  const SystemSpeechEngine();

  @override
  String get id => 'system.android';

  @override
  SpeechCapabilities get capabilities => const SpeechCapabilities(
    requiresNetwork: false,
    auditableEgress: false,
    needsLocalModel: false,
  );

  @override
  Future<void> prepare({void Function(double fraction)? onProgress}) async => _unsupported();

  @override
  Future<void> startRecording() async => _unsupported();

  @override
  Future<SpeechResult> stopAndTranscribe({void Function(double fraction)? onProgress}) async =>
      _unsupported();

  Never _unsupported() {
    throw UnsupportedError(
      'The system speech recognizer isn’t available yet — it needs a '
      'platform integration this build doesn’t have.',
    );
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}
