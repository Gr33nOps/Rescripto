import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/services/backup/backup_crypto.dart';
import 'package:rescripto/services/backup/backup_exception.dart';

void main() {
  final crypto = BackupCrypto();

  group('BackupCrypto', () {
    test('round-trips arbitrary bytes with the correct passphrase', () async {
      final plain = Uint8List.fromList(utf8.encode('hello backup world'));
      final encrypted = await crypto.encrypt(plain, 'correct horse battery staple');
      final decrypted = await crypto.decrypt(encrypted, 'correct horse battery staple');

      expect(utf8.decode(decrypted), 'hello backup world');
    });

    test('the same plaintext encrypts to different bytes each time (random salt+nonce)', () async {
      final plain = Uint8List.fromList(utf8.encode('same input'));
      final a = await crypto.encrypt(plain, 'passphrase');
      final b = await crypto.encrypt(plain, 'passphrase');

      expect(a, isNot(equals(b)));
    });

    test('the wrong passphrase throws BackupWrongPassphraseException', () async {
      final plain = Uint8List.fromList(utf8.encode('secret contents'));
      final encrypted = await crypto.encrypt(plain, 'right passphrase');

      await expectLater(
        crypto.decrypt(encrypted, 'wrong passphrase'),
        throwsA(isA<BackupWrongPassphraseException>()),
      );
    });

    test('a tampered byte in the ciphertext is caught, not silently accepted', () async {
      final plain = Uint8List.fromList(utf8.encode('integrity matters'));
      final encrypted = await crypto.encrypt(plain, 'passphrase');
      final tampered = Uint8List.fromList(encrypted);
      tampered[tampered.length - 1] ^= 0xFF;

      await expectLater(
        crypto.decrypt(tampered, 'passphrase'),
        throwsA(isA<BackupWrongPassphraseException>()),
      );
    });

    test('a blob too short to contain a salt and nonce is rejected as corrupt', () async {
      await expectLater(
        crypto.decrypt(Uint8List.fromList([1, 2, 3]), 'passphrase'),
        throwsA(isA<BackupCorruptException>()),
      );
    });

    test('an empty plaintext round-trips too', () async {
      final encrypted = await crypto.encrypt(Uint8List(0), 'passphrase');
      final decrypted = await crypto.decrypt(encrypted, 'passphrase');
      expect(decrypted, isEmpty);
    });
  });
}
