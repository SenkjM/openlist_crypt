# openlist_crypt

[![CI](https://github.com/SenkjM/openlist_crypt/actions/workflows/ci.yaml/badge.svg)](https://github.com/SenkjM/openlist_crypt/actions/workflows/ci.yaml)
[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)

**rclone / OpenList `crypt` 加密存储格式的 Dart 实现。** 可读写由 rclone
`crypt` 后端或 OpenList / Alist crypt 存储加密的远端目录（文件内容 + 文件名），
与 rclone 字节级兼容，用 rclone v1.75.1 `backend/crypt` 的黄金向量验证。

- 纯 Dart，无 Flutter 依赖：Flutter App、CLI、服务端均可用（Dart 3.5+）。
- 默认全部走纯 Dart 实现；**仅文件内容**的 secretbox（XSalsa20-Poly1305）可
  选用 libsodium（FFI）加速。
- EME 文件名加密、文件名编码、scrypt 密钥派生**始终是纯 Dart**，不受
  libsodium 开关影响。
- 预编译 libsodium `.so` 目前**只提供 Android `arm64-v8a`**；其它 ABI / 平台
  找不到库时自动回退纯 Dart。

> English summary: see [English](#english) at the bottom.

## 实现内容

| 层 | 算法 |
|---|---|
| 密钥派生 | scrypt (N=16384, r=8, p=1, dkLen=80) → dataKey[32] + nameKey[32] + nameTweak[16]；salt 为空时使用 rclone 内置默认 salt；空密码 = 全零密钥（格式本身的约定） |
| 文件内容 | `RCLONE\0\0` 魔数 (8 B) + 随机文件 nonce (24 B) + 64 KiB 明文块，每块是一个 NaCl secretbox（XSalsa20-Poly1305，前置 16 B MAC）。块 nonce = 文件 nonce + 块序号（LE 64 位加法） |
| 文件名 standard 模式 | PKCS7(16) 填充 + EME 宽块 AES-256（nameTweak） |
| 文件名 obfuscate 模式 | rclone 的轮转混淆（nameKey） |
| 文件名 off 模式 | 明文 + 可配置后缀（默认 `.bin`，对应 OpenList `encrypted_suffix`） |
| 文件名编码 | base32（hex 表、小写、无填充）· base64（URL-safe、无填充，OpenList 默认）· base32768（rclone SafeEncoding） |
| 随机访问 | 按块解密，seek 不需要处理前面的块 |

## 安装

```yaml
dependencies:
  openlist_crypt: ^0.1.0
```

或直接用 Git：

```yaml
dependencies:
  openlist_crypt:
    git:
      url: https://github.com/SenkjM/openlist_crypt.git
      ref: main
```

## 用法

```dart
import 'package:openlist_crypt/openlist_crypt.dart';

final cipher = RcloneCipher(
  password: 'testpass',
  salt: 'testsalt',          // '' → rclone 默认 salt
  mode: NameEncryptionMode.standard,
  dirNameEncrypt: true,
  nameEncoding: 'base32',    // 'base32' | 'base64' | 'base32768'
);

// 文件名
final enc = cipher.encryptFileName('hello.txt'); // 9ph489uqiu6hppkcbp0g4328c4
final dir = cipher.encryptDirName('photos');     // ghd9crjufd2a4sartqaskk87rc
print(cipher.decryptFileName(enc));               // hello.txt

// 文件内容（整块）
final cipherBytes = cipher.encrypt(plain);        // 每次随机 nonce
final plain2 = cipher.decrypt(cipherBytes);       // 失败抛 RcloneCipherException

// 随机访问：只解第 k 块
final nonce = RcloneCipher.fileNonceOf(
    cipherBytes.sublist(0, kFileHeaderSize));
final block3 = cipher.decryptBlock(nonce, 3, cipherBytes.sublist(
    kFileHeaderSize + 3 * kBlockSize, kFileHeaderSize + 4 * kBlockSize));

// 尺寸换算（列目录时无需解密）
final cipherLen = RcloneCipher.encryptedSize(plainLen);
final plainLen2 = RcloneCipher.decryptedSize(cipherLen);
```

### 流式加密（上传）

```dart
final enc = RcloneStreamEncrypter(cipher, nonce: RcloneCipher.randomFileNonce());
sink.add(enc.header());                       // 32 B 魔数 + nonce
await for (final chunk in source) {           // chunk 大小无需对齐
  for (final block in enc.push(chunk)) sink.add(block);
}
for (final block in enc.close()) sink.add(block);
// enc.cipherBytesProduced：单调递增的进度（不含 32 B 头）
```

完整可运行示例见 [`example/`](example/)：

- `example/openlist_crypt_example.dart` — 最小示例（文件名 + 内容往返、可选 libsodium）
- `example/decrypt.dart` — 解密一个 rclone crypt 文件
- `example/bench.dart` — 纯 Dart 性能基准

## 可选：libsodium secretbox 后端

**默认使用纯 Dart。** 开启后，只有文件内容的 secretbox（`crypto_secretbox_easy`
/ `crypto_secretbox_open_easy`）走 libsodium；EME 文件名、编码、scrypt 不变。
输出与纯 Dart 完全一致（有交叉测试）。

三种开启/配置方式：

1. **运行时 API**

   ```dart
   final ok = preferLibsodiumSecretbox();          // 找不到库 → 静默回退 Dart，返回 false
   preferLibsodiumSecretbox(require: true);        // 找不到库 → secretbox 调用抛 StateError
   preferDartSecretbox();                          // 强制回到纯 Dart
   print(libsodiumLoadedPath ?? libsodiumLoadError); // 诊断
   ```

2. **编译期默认值**：`--dart-define=OPENLIST_CRYPT_LIBSODIUM=true`
   （例如 `flutter run --dart-define=OPENLIST_CRYPT_LIBSODIUM=true`）。
   仍会在加载失败时回退 Dart（除非 `secretboxRequireLibsodium = true`）。

3. **库路径覆盖**：环境变量 `OPENLIST_CRYPT_LIBSODIUM_PATH=/abs/path/libsodium.so`
   优先尝试该路径。之后依次尝试：Android 打包的 `libsodium.so`、Linux 常见
   soname（`libsodium.so.26` / `.23` / `libsodium.so`）、macOS 常见路径。

### 预编译 `.so`：仅 arm64-v8a

| ABI / 平台 | 预编译库 | 行为 |
|---|---|---|
| Android `arm64-v8a` | ✅ `native/android/arm64-v8a/libsodium.so`（官方 libsodium 1.0.20，NDK r27c） | 宿主 App 打包后可用 libsodium |
| Android `armeabi-v7a` / `x86_64` / `x86` | ❌ | 回退纯 Dart |
| iOS / macOS / Windows / Linux 桌面 | ❌（不随包提供） | 若系统已装 libsodium 或设置了 `OPENLIST_CRYPT_LIBSODIUM_PATH` 则使用，否则回退纯 Dart |
| Web | ❌ | 不支持（包依赖 `dart:io` / `dart:ffi`） |

**注意：** 这是纯 Dart 包，**不会**自动把 `native/` 里的 `.so` 打进 Flutter
APK。Android 宿主 App 需要自行把它加入 `jniLibs`，例如：

```kotlin
// android/app/build.gradle.kts
android {
    sourceSets["main"].jniLibs.srcDir("<path-to>/openlist_crypt/native/android")
}
```

或把 `native/android/arm64-v8a/libsodium.so` 复制到
`android/app/src/main/jniLibs/arm64-v8a/`。详见 [`native/README.md`](native/README.md)。

## 兼容性说明

- **base32768** 移植自 [`Max-Sum/base32768`][base32768]（rclone 自身依赖的 Go
  库），1028 码点字母表原样生成并提交，无需代码生成步骤。
- 黄金向量覆盖文件名、混淆、base64 编码、后缀、内容块，来自 rclone v1.75.1
  `backend/crypt/cipher_test.go`；另有 base32768 0–200 字节往返与 NaCl
  secretbox 参考向量。
- OpenList / Alist 使用同一格式：`filename_encoding=base64` 是 OpenList 默认值，
  `suffix` / `encrypted_suffix`、`directory_name_encryption` 一一对应。

## 测试

```bash
dart pub get
dart analyze
dart test
# 用系统 libsodium 跑 FFI 交叉测试（可选）：
OPENLIST_CRYPT_LIBSODIUM_PATH=/usr/lib/x86_64-linux-gnu/libsodium.so.23 dart test
```

## 许可证（AGPL-3.0）

本包采用 **GNU AGPL-3.0**，见 [LICENSE](LICENSE)。上游声明（rclone MIT、
Max-Sum/base32768 MIT、golang.org/x/crypto BSD-3-Clause、libsodium ISC）见
[NOTICE](NOTICE)。

**使用前请注意 AGPL 的影响（非法律意见）：**

- AGPL-3.0 是强 copyleft 许可证。把本包链接进你的程序并**分发**（例如发布
  APK）时，整个衍生作品通常需要以 AGPL-3.0 兼容条款提供完整源码。
- AGPL 第 13 条额外要求：若修改后的程序**通过网络向用户提供服务**，也需向这些
  用户提供对应源码。
- 闭源 / 专有项目一般不能直接使用本包；请自行评估或联系作者。
- 随包的 `libsodium.so` 仍是 **ISC** 许可（未被重新授权为 AGPL），再分发时须保留
  [`native/LICENSE.libsodium`](native/LICENSE.libsodium) 中的版权与许可声明。
  详见 [`native/LICENSE_NOTE.md`](native/LICENSE_NOTE.md)。

[rclone]: https://github.com/rclone/rclone
[base32768]: https://github.com/Max-Sum/base32768

---

## English

`openlist_crypt` is a Dart implementation of the **rclone / OpenList `crypt`**
encrypted storage format (scrypt key derivation, EME-AES-256 filename
encryption, obfuscate/off name modes, base32/base64/base32768 name encodings,
XSalsa20-Poly1305 64 KiB content blocks, streaming encryption, per-block
random access). It is wire compatible with rclone `backend/crypt` (verified
against rclone v1.75.1 golden vectors) and OpenList/Alist crypt storage.

- **Pure Dart by default.** Only the *content* secretbox can optionally use
  libsodium via FFI: `preferLibsodiumSecretbox()`,
  `--dart-define=OPENLIST_CRYPT_LIBSODIUM=true`, or point
  `OPENLIST_CRYPT_LIBSODIUM_PATH` at a `libsodium` shared library. EME /
  filename codecs / scrypt are always pure Dart.
- **The bundled prebuilt `libsodium.so` (1.0.20) is Android `arm64-v8a` only.**
  Other ABIs and platforms fall back to pure Dart unless a system libsodium is
  found. The host app must add `native/android` to its `jniLibs` itself.
- **License: AGPL-3.0.** Distributing an app that links this package (or
  offering a modified version over a network) generally requires releasing the
  corresponding source under AGPL-compatible terms. The bundled libsodium binary
  stays under ISC. Third-party notices are in [NOTICE](NOTICE). Not legal advice.
