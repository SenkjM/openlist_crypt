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
- Bundled prebuilt Android **arm64-v8a** `libsodium.so` (official 1.0.20,
  ISC). Other ABIs fall back to pure Dart.

Licensing:

- AGPL-3.0. Upstream notices (rclone MIT, Max-Sum/base32768 MIT,
  golang.org/x/crypto BSD-3-Clause, libsodium ISC) in `NOTICE`.

> Note: while developed in-tree the package carried internal versions
> 0.2.0 / 0.2.1 that were never published. Public versioning restarts at 0.1.0.
