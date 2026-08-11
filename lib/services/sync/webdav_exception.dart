/// A WebDAV request failed. [statusCode] is null for a transport-level
/// failure (DNS, TLS, connection refused) rather than an HTTP response.
class WebDavException implements Exception {
  const WebDavException(this.statusCode, [this.message]);

  final int? statusCode;
  final String? message;

  bool get isAuthFailure => statusCode == 401 || statusCode == 403;
  bool get isNotFound => statusCode == 404;

  @override
  String toString() => 'WebDavException($statusCode${message != null ? ', $message' : ''})';
}
