/// Thrown by [SyncService.push] when the remote backup has changed since
/// this device last confirmed its state — via an earlier push or pull —
/// and the caller did not pass `force: true`.
///
/// Distinct from [WebDavException]: that type reports a transport-level
/// failure the request actually made and got a bad response for. This one
/// is raised before the PUT is attempted at all (or, if the server's own
/// `If-Match` catches a narrower race, translated from a 412 response) —
/// either way it means "don't overwrite this without asking the user
/// first", not "the request failed".
class WebDavSyncConflictException implements Exception {
  const WebDavSyncConflictException(this.remoteModifiedAt);

  /// When the server's copy was last modified, if the server reported one.
  final DateTime? remoteModifiedAt;
}
