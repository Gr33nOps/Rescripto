/// Permission to silently send text to a cloud provider after a local
/// rewrite fails, in Hybrid mode.
///
/// A record rather than a bool: sending text to one company is not
/// permission to send it to another, so [providerId] scopes the grant to a
/// single provider, and switching providers means asking again. [version]
/// exists purely so a future release can force re-consent by bumping
/// [currentVersion] — nothing here reads it besides that comparison.
class CloudFallbackConsent {
  const CloudFallbackConsent({
    required this.granted,
    this.grantedAt,
    this.providerId,
    this.version = currentVersion,
  });

  static const currentVersion = 1;

  static const none = CloudFallbackConsent(granted: false);

  final bool granted;
  final DateTime? grantedAt;
  final String? providerId;
  final int version;

  /// Whether this consent actually covers a fallback to [targetProviderId]
  /// right now — granted, current version, and for this exact provider.
  bool coversProvider(String targetProviderId) =>
      granted && version == currentVersion && providerId == targetProviderId;

  Map<String, Object?> toJson() => {
    'granted': granted,
    'grantedAt': grantedAt?.toIso8601String(),
    'providerId': providerId,
    'version': version,
  };

  factory CloudFallbackConsent.fromJson(Map<String, Object?> json) => CloudFallbackConsent(
    granted: json['granted'] as bool? ?? false,
    grantedAt: (json['grantedAt'] as String?) == null
        ? null
        : DateTime.parse(json['grantedAt'] as String),
    providerId: json['providerId'] as String?,
    version: json['version'] as int? ?? currentVersion,
  );
}
