/// What kind of secret a [CredentialRef] points to.
enum CredentialKind {
  /// A provider API key (OpenAI, Anthropic, Gemini, Groq, OpenRouter,
  /// Mistral, a custom OpenAI-compatible endpoint).
  apiKey,

  /// A bearer/session token, for a provider that issues one instead of a
  /// static key.
  bearerToken,

  /// A WebDAV/Nextcloud password (Phase 4 sync). Lives in the same store
  /// under the same kill switch as everything else here.
  webdavPassword,

  /// The passphrase `BackupScheduler` encrypts an unattended scheduled
  /// backup with — never used for a manual export, which always prompts
  /// for a fresh passphrase instead. Storing it in the Keystore is no
  /// weaker a guarantee than everything else this store already protects;
  /// an automatic backup has no user present to type one in.
  backupPassphrase,
}

/// Identifies one secret in [CredentialStore] without ever carrying the
/// secret itself.
///
/// `providerId` + `accountId` + `kind` together are what let nine cloud
/// providers, several custom OpenAI-compatible endpoints, and a WebDAV
/// password all live in the same store without colliding — a user can hold
/// more than one key for the same provider (`accountId`), and the same
/// provider can hold more than one kind of secret.
class CredentialRef {
  const CredentialRef({
    required this.providerId,
    this.accountId = 'default',
    required this.kind,
  });

  final String providerId;
  final String accountId;
  final CredentialKind kind;

  /// The key this ref resolves to in the platform Keystore. `v1` so a future
  /// format change is enumerable and migratable rather than ambiguous.
  String get storageKey => 'cred.v1.$providerId.$accountId.${kind.name}';

  @override
  bool operator ==(Object other) =>
      other is CredentialRef &&
      other.providerId == providerId &&
      other.accountId == accountId &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(providerId, accountId, kind);

  // Safe to print: nothing here is the secret itself, only where to find it.
  @override
  String toString() => 'CredentialRef($providerId, $accountId, ${kind.name})';
}
