## 0.1.0

First standalone release, split out of
[SenkjM/Webdav_Media_Manager](https://github.com/SenkjM/Webdav_Media_Manager)
(`packages/openlist_crypt`) with its git history preserved.

Read side:

- scrypt key derivation (rclone default salt, empty-password all-zero keys).
- Content decryption: `RCLONE\0\0` header, 64 KiB XSalsa20-Poly1305 blocks,
  whole-buffer `decrypt` and per-block `decryptBlock` for range access.
- Filename encryption: EME-AES-256 standard mode, rclone obfuscate mode, off
  mode with configurable suffix; base32 / base64 / base32768 encodings.
- Size arithmetic helpers (`encryptedSize` / `decryptedSize`).
- Golden vectors from rclone v1.75.1 `backend/crypt`.

Write side:

- `RcloneCipher.encryptBlock`, `RcloneCipher.encrypt({nonce})`,
  `RcloneCipher.randomFileNonce()`.
- `RcloneStreamEncrypter`: push-mode streaming encrypter with O(64 KiB) memory
  and a `cipherBytesProduced` progress counter.

Performance:

- Key-schedule hoisting for EME / names (~3x) and content (~1.1x); memoized
  HSalsa20 subkey and reused Poly1305; isolate-friendly key material API.

Optional libsodium backend (content secretbox only):

- `preferLibsodiumSecretbox()` / `preferDartSecretbox()`,
  `--dart-define=OPENLIST_CRYPT_LIBSODIUM=true`, `OPENLIST_CRYPT_LIBSODIUM_PATH`.
  Pure Dart remains the default; filename/EME codecs never use libsodium.
- Prebuilt libsodium 1.0.20 (ISC) for Android armeabi-v7a / arm64-v8a / x86 /
  x86_64 (16 KB page aligned), Linux x64 / arm64, macOS arm64 / x64 and
  Windows x64 / arm64, built from the minisign-verified official source (the
  Windows x64 DLL is the official msvc build). iOS binaries are not included
  yet; iOS uses pure Dart.
- `hook/build.dart` (Dart/Flutter native assets) bundles **only the binary for
  the build target** (per Android ABI, per desktop/iOS architecture). Opt out
  with the `bundle_libsodium: false` hook user-define.
- Runtime loading: `OPENLIST_CRYPT_LIBSODIUM_PATH` → bundled asset
  `package:openlist_crypt/libsodium` → platform library names; falls back to
  pure Dart when nothing loads.
- Requires Dart 3.10+ (build hooks).

Licensing:

- AGPL-3.0. Upstream notices (rclone MIT, Max-Sum/base32768 MIT,
  golang.org/x/crypto BSD-3-Clause, libsodium ISC) in `NOTICE`.

> Note: while developed in-tree the package carried internal versions
> 0.2.0 / 0.2.1 that were never published. Public versioning restarts at 0.1.0.
