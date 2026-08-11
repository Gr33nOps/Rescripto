import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'backup_exception.dart';

/// Passphrase-based encryption for one backup blob: Argon2id derives a key,
/// AES-256-GCM seals the bytes.
///
/// Deliberately one [encrypt] call over the whole JSON document rather than
/// the per-section encryption the plan sketches — AES-GCM's real hazard is
/// reusing a nonce under the same key, and a single call has exactly one
/// nonce by construction, so there is nothing per-section encryption would
/// additionally protect against here. Splitting the document into sections
/// only pays for itself once something needs to decrypt one section without
/// the others, and nothing here does — [BackupService.preview] reads the
/// same header any successful decrypt already exposes.
///
/// The salt travels in the output (it isn't secret; Argon2id's whole point
/// is that brute-forcing still costs real work per guess) and is never
/// derived from a device identifier — a backup must decrypt on a different
/// phone with only the passphrase.
class BackupCrypto {
  BackupCrypto();

  static const int saltLength = 16;
  static const int _macLength = 16;

  // Argon2id parameters landing near OWASP's minimum-recommended profile
  // (m=19MiB, t=2, p=1) — deliberately not push-the-limit, since this runs
  // on a phone and a scheduled backup (Step 3) must not visibly stall the
  // app on every launch it fires.
  static const int _memory = 19456;
  static const int _iterations = 2;
  static const int _parallelism = 1;

  final _cipher = AesGcm.with256bits();

  Future<Uint8List> encrypt(Uint8List plainBytes, String passphrase) async {
    final salt = _randomBytes(saltLength);
    final key = await _deriveKey(passphrase, salt);
    final box = await _cipher.encrypt(plainBytes, secretKey: key);
    final sealed = box.concatenation();
    return Uint8List.fromList([...salt, ...sealed]);
  }

  /// Throws [BackupCorruptException] if [blob] is too short to have come
  /// from [encrypt], or [BackupWrongPassphraseException] if the
  /// authentication tag doesn't check out — the same symptom whether the
  /// passphrase is wrong or the file was altered in transit.
  Future<Uint8List> decrypt(Uint8List blob, String passphrase) async {
    if (blob.length < saltLength + _cipher.nonceLength + _macLength) {
      throw const BackupCorruptException();
    }
    final salt = blob.sublist(0, saltLength);
    final sealed = blob.sublist(saltLength);
    final key = await _deriveKey(passphrase, salt);
    final box = SecretBox.fromConcatenation(
      sealed,
      nonceLength: _cipher.nonceLength,
      macLength: _macLength,
    );
    try {
      final clear = await _cipher.decrypt(box, secretKey: key);
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const BackupWrongPassphraseException();
    }
  }

  Future<SecretKey> _deriveKey(String passphrase, List<int> salt) {
    final argon2id = Argon2id(
      parallelism: _parallelism,
      memory: _memory,
      iterations: _iterations,
      hashLength: 32,
    );
    return argon2id.deriveKeyFromPassword(password: passphrase, nonce: salt);
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
  }
}
