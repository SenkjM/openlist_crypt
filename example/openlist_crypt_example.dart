// Minimal openlist_crypt example: filename + content round trip, with the
// optional libsodium secretbox backend (falls back to pure Dart when the
// shared library is not available).
//
// Run with: dart run example/openlist_crypt_example.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:openlist_crypt/openlist_crypt.dart';

void main() {
  final cipher = RcloneCipher(
    password: 'testpass',
    salt: 'testsalt', // '' → rclone built-in default salt
    mode: NameEncryptionMode.standard,
    dirNameEncrypt: true,
  );

  // Filenames (pure Dart EME, rclone-compatible).
  final encName = cipher.encryptFileName('hello.txt');
  stdout.writeln('hello.txt -> $encName -> ${cipher.decryptFileName(encName)}');

  // Optional: prefer libsodium for content blocks. Returns false (and keeps
  // the pure-Dart path) if no libsodium library can be loaded.
  final sodium = preferLibsodiumSecretbox();
  stdout.writeln(sodium
      ? 'secretbox backend: libsodium ($libsodiumLoadedPath)'
      : 'secretbox backend: pure Dart');

  // Content round trip.
  final plain = Uint8List.fromList(utf8.encode('Hello, rclone crypt!'));
  final encrypted = cipher.encrypt(plain);
  final decrypted = cipher.decrypt(encrypted);
  stdout.writeln('${plain.length} B plain -> ${encrypted.length} B encrypted '
      '(expected ${RcloneCipher.encryptedSize(plain.length)}) -> '
      '"${utf8.decode(decrypted)}"');
}
