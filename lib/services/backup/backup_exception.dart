/// Something [BackupService] or [BackupCrypto] failed at, typed so the UI
/// can show a specific message instead of a raw exception's `toString()`.
sealed class BackupException implements Exception {
  const BackupException();
}

/// The passphrase didn't decrypt the file, or the file was truncated or
/// tampered with — AES-GCM's authentication tag catches both, and there is
/// no way to tell them apart without the original key, so neither message
/// claims to.
class BackupWrongPassphraseException extends BackupException {
  const BackupWrongPassphraseException();
}

/// Too short to even contain a salt and nonce, or not valid JSON once
/// decrypted.
class BackupCorruptException extends BackupException {
  const BackupCorruptException();
}

/// [BackupBundle.formatVersion] is newer than this build understands.
/// Refusing beats guessing at fields this version has never seen.
class BackupNewerFormatException extends BackupException {
  const BackupNewerFormatException(this.foundVersion, this.supportedVersion);

  final int foundVersion;
  final int supportedVersion;
}
