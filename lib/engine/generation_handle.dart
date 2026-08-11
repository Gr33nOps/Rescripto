import 'dart:async';

import '../models/rewrite_output.dart';
import 'engine_exception.dart';
import 'engine_stage.dart';

/// Progress notifications a [GenerationHandle] emits while running.
///
/// Deliberately just the two. Completion and failure are not events here —
/// they are observed through [GenerationHandle.done], a single `Future` that
/// either resolves with the result or throws an [EngineException]. Carrying
/// the terminal outcome on both the event stream and a future would leave
/// two places that must agree about how a request ended; this way there is
/// only one.
sealed class GenerationEvent {
  const GenerationEvent();
}

final class StageChanged extends GenerationEvent {
  const StageChanged(this.stage);

  final EngineStage stage;
}

final class TokenDelta extends GenerationEvent {
  const TokenDelta(this.delta);

  /// New text since the last [TokenDelta], never the accumulated string.
  final String delta;
}

/// A single in-flight (or queued) generation request.
///
/// This is the request's identity. Earlier, cancellation was tracked with a
/// monotonically increasing counter on the controller (`_operationId`) and a
/// second field recording which id had been cancelled, with every stream
/// callback re-checking both before touching state. A handle makes that
/// structurally unnecessary: cancelling one closes *its own* stream, so a
/// callback from a stale request has nowhere left to deliver to.
abstract interface class GenerationHandle {
  Stream<GenerationEvent> get events;

  /// Resolves with the finished result, or throws an [EngineException] —
  /// including [GenerationCancelledException] if [cancel] was called.
  Future<RewriteOutput> get done;

  Future<void> cancel();

  /// True as soon as [cancel] has been called, even before it completes.
  bool get isCancelled;
}

/// Base [GenerationHandle] engines construct and drive.
///
/// Shared rather than duplicated per engine: every engine needs the same
/// event-stream-plus-completer plumbing, and only differs in what actually
/// happens when [cancel] is called.
class StreamGenerationHandle implements GenerationHandle {
  StreamGenerationHandle({required this.onCancel});

  final Future<void> Function() onCancel;
  // Non-broadcast: buffers events emitted before the first (and only)
  // listener subscribes. An async engine body runs synchronously to its
  // first await, so the earliest StageChanged events land before start()
  // even returns — a broadcast controller would drop them silently. A
  // handle is one request's identity, so exactly one listener is correct;
  // a second `.listen()` call throws, which is the intended failure mode.
  final _events = StreamController<GenerationEvent>();
  final _completer = Completer<RewriteOutput>();
  bool _isCancelled = false;

  @override
  Stream<GenerationEvent> get events => _events.stream;

  @override
  Future<RewriteOutput> get done => _completer.future;

  @override
  bool get isCancelled => _isCancelled;

  @override
  Future<void> cancel() async {
    if (_isCancelled || _completer.isCompleted) return;
    // Set before awaiting: the engine driving this handle checks isCancelled
    // to decide how to interpret whatever stopGeneration's completion race
    // hands back, and that check must see the request as already cancelled.
    _isCancelled = true;
    await onCancel();
  }

  void emitStage(EngineStage stage) {
    if (!_events.isClosed) _events.add(StageChanged(stage));
  }

  void emitDelta(String delta) {
    if (delta.isEmpty || _events.isClosed) return;
    _events.add(TokenDelta(delta));
  }

  void complete(RewriteOutput result) {
    if (_completer.isCompleted) return;
    _completer.complete(result);
    _events.close();
  }

  void completeError(EngineException error) {
    if (_completer.isCompleted) return;
    _completer.completeError(error);
    _events.close();
  }
}
