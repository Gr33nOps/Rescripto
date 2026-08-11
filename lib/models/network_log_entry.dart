import '../services/network/network_feature.dart';

/// How a logged request ended.
enum NetworkOutcome { allowed, blockedByPolicy, blockedByKillSwitch, failed, cancelled }

/// One row of the network audit trail.
///
/// Deliberately has no field for a request header or a response body, and
/// [path] holds only `Uri.path` — never `Uri.query` or the full URL. This is
/// structural redaction: a field that does not exist on this class cannot be
/// populated with a secret by a future call site that forgets to scrub one.
/// It matters concretely because a cloud provider (Gemini, at least) accepts
/// its API key as a `?key=...` query parameter — logging the full URL would
/// write a live credential into a table the user can view and export.
class NetworkLogEntry {
  const NetworkLogEntry({
    required this.id,
    required this.feature,
    required this.method,
    required this.host,
    required this.path,
    required this.startedAt,
    required this.outcome,
    this.purpose,
    this.duration,
    this.statusCode,
    this.bytesReceived,
  });

  final int id;
  final NetworkFeature feature;
  final String method;
  final String host;
  final String path;
  final DateTime startedAt;
  final NetworkOutcome outcome;

  /// Short human-readable reason, e.g. "Download Gemma 3 1B".
  final String? purpose;

  final Duration? duration;
  final int? statusCode;
  final int? bytesReceived;

  Map<String, Object?> toMap() => {
    'id': id,
    'feature': feature.name,
    'method': method,
    'host': host,
    'path': path,
    'purpose': purpose,
    'started_at': startedAt.toIso8601String(),
    'duration_ms': duration?.inMilliseconds,
    'status_code': statusCode,
    'bytes_received': bytesReceived,
    'outcome': outcome.name,
  };

  factory NetworkLogEntry.fromMap(Map<String, Object?> map) => NetworkLogEntry(
    id: map['id'] as int,
    feature: NetworkFeature.values.byName(map['feature'] as String),
    method: map['method'] as String,
    host: map['host'] as String,
    path: map['path'] as String,
    purpose: map['purpose'] as String?,
    startedAt: DateTime.parse(map['started_at'] as String),
    duration: (map['duration_ms'] as int?) == null
        ? null
        : Duration(milliseconds: map['duration_ms'] as int),
    statusCode: map['status_code'] as int?,
    bytesReceived: map['bytes_received'] as int?,
    outcome: NetworkOutcome.values.byName(map['outcome'] as String),
  );
}
