import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The minimal key-value secret store [CredentialStore] needs.
///
/// `flutter_secure_storage`'s own `FlutterSecureStorage` class works only
/// over a platform channel, so it cannot run inside `flutter test` without a
/// real device. This interface is the seam that lets `CredentialStore`'s
/// orchestration logic — namespacing, index bookkeeping, degrade-on-error —
/// be unit-tested against an in-memory fake instead, the same way
/// `NetworkGuard.httpClientFor` takes an injectable inner `http.Client`.
abstract interface class SecureStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);

  /// Deletes everything this app has ever written to the store — including
  /// any key not tracked by `CredentialStore`'s own SQLite index, e.g. one
  /// left behind by a future format change. `CredentialStore.deleteAll`
  /// calls this as a sweep on top of deleting each known ref individually.
  Future<void> deleteAll();
}

/// Production [SecureStorage], backed by the Android Keystore.
class FlutterSecureStorageAdapter implements SecureStorage {
  FlutterSecureStorageAdapter()
    : _storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(
          encryptedSharedPreferences: true,
          // Some OEM ROMs invalidate the Keystore key on a device restore or
          // OS upgrade; without this, every read after that throws forever.
          // CredentialStore treats that the same as "not configured" rather
          // than a fatal error either way, but resetting here means a write
          // after the reset works again instead of staying wedged.
          resetOnError: true,
        ),
      );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}
