import 'generation_handle.dart';

/// Tracks every in-flight [GenerationHandle] so the kill switch can actually
/// stop one.
///
/// Flipping `NetworkPolicy`'s kill switch only affects requests that
/// haven't started yet — `NetworkGuard` checks it once, in `onRequest`,
/// before dispatch. A cloud rewrite already mid-stream has passed that
/// check and is reading bytes from a socket the guard never looks at again.
/// This registry is what lets `PanicService` reach into that: every request
/// registers its handle on `start()` and unregisters on completion, and
/// [cancelAll] just calls [GenerationHandle.cancel] on whatever's left.
class ActiveRequestRegistry {
  final Set<GenerationHandle> _active = {};

  int get activeCount => _active.length;

  void register(GenerationHandle handle) => _active.add(handle);

  void unregister(GenerationHandle handle) => _active.remove(handle);

  /// Cancels every currently-tracked request. Safe to call with nothing
  /// active, and safe to call more than once — [GenerationHandle.cancel] is
  /// itself idempotent.
  Future<void> cancelAll() async {
    final handles = List.of(_active);
    for (final handle in handles) {
      await handle.cancel();
    }
  }
}
