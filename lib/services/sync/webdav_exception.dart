/// A WebDAV request failed. [statusCode] is null for a transport-level
/// failure (DNS, TLS, connection refused) rather than an HTTP response.
class WebDavException implements Exception {
  const WebDavException(this.statusCode, [this.message]);

  final int? statusCode;
  final String? message;

  bool get isAuthFailure => statusCode == 401 || statusCode == 403;
  bool get isNotFound => statusCode == 404;

  /// A conditional PUT's `If-Match` failed — the file changed on the server
  /// between [SyncService.push]'s conflict check and the write itself.
  bool get isConflict => statusCode == 412;

  @override
  String toString() => 'WebDavException($statusCode${message != null ? ', $message' : ''})';
}
