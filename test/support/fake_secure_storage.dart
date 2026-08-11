import 'package:rescripto/services/credentials/secure_storage.dart';

/// In-memory stand-in for the platform Keystore, shared by any test that
/// needs a [CredentialStore] without a real platform channel — which
/// `FlutterSecureStorageAdapter` needs and `flutter test` has no device to
/// back.
class FakeSecureStorage implements SecureStorage {
  final Map<String, String> values = {};

  /// When set, every call throws — simulates a Keystore invalidated by a
  /// device restore or OS upgrade.
  bool broken = false;

  void _checkBroken() {
    if (broken) throw StateError('Keystore unavailable');
  }

  @override
  Future<String?> read(String key) async {
    _checkBroken();
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    _checkBroken();
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _checkBroken();
    values.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _checkBroken();
    values.clear();
  }
}
