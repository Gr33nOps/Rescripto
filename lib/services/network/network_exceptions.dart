import 'network_feature.dart';

/// Why [NetworkGuard] refused to let a request through.
enum NetworkBlockReason {
  /// The global "disable all network access" switch is on.
  killSwitch,

  /// This specific [NetworkFeature] is turned off.
  featureDisabled,

  /// A `cloudRewrite` request carried a secret in its query string, which
  /// this app refuses to send — and refuses to log, since a query string is
  /// exactly what a URL-based API key rides in.
  secretInUrl,
}

/// Thrown by both `NetworkGuard.dioFor` (wrapped in a `DioException`) and
/// `NetworkGuard.httpClientFor` (thrown directly) when a request is blocked
/// before it ever reaches the network.
class NetworkBlockedByPolicyException implements Exception {
  const NetworkBlockedByPolicyException({
    required this.feature,
    required this.reason,
  });

  final NetworkFeature feature;
  final NetworkBlockReason reason;

  @override
  String toString() =>
      'NetworkBlockedByPolicyException(${feature.name}, ${reason.name})';
}
