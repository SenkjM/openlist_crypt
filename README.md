# openlist_crypt

[![CI](https://github.com/SenkjM/openlist_crypt/actions/workflows/ci.yaml/badge.svg)](https://github.com/SenkjM/openlist_crypt/actions/workflows/ci.yaml)
[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)

**rclone / OpenList `crypt` 加密存储格式的 Dart 实现。** 可读写由 rclone
`crypt` 后端或 OpenList / Alist crypt 存储加密的远端目录（文件内容 + 文件名），
与 rclone 字节级兼容，用 rclone v1.75.1 `backend/crypt` 的黄金向量验证。

- 纯 Dart，无 Flutter 依赖：Flutter App、CLI、服务端均可用（Dart 3.10+，
  native assets 构建 hook 需要）。
- 默认全部走纯 Dart 实现；**仅文件内容**的 secretbox（XSalsa20-Poly1305）可
  选用 libsodium（FFI）加速。
- EME 文件名加密、文件名编码、scrypt 密钥派生**始终是纯 Dart**，不受
  libsodium 开关影响。
- 随包提供 Android / Linux / macOS / Windows 各架构的预编译 libsodium 1.0.20，
  由构建 hook（Dart/Flutter native assets）**只打包目标架构对应的那一个**；
  没有预编译库的目标（目前是 iOS）或加载失败时自动回退纯 Dart。见
  [支持矩阵](#平台支持矩阵)。

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
   print(libsodiumLoadedPath ?? libsodiumLoadError); // 诊断；随包库显示 asset:package:openlist_crypt/libsodium
   ```

2. **编译期默认值**：`--dart-define=OPENLIST_CRYPT_LIBSODIUM=true`
   （例如 `flutter run --dart-define=OPENLIST_CRYPT_LIBSODIUM=true`）。
   仍会在加载失败时回退 Dart（除非 `secretboxRequireLibsodium = true`）。

3. **库路径覆盖**：环境变量 `OPENLIST_CRYPT_LIBSODIUM_PATH=/abs/path/libsodium.so`
   优先尝试该路径（调试/自定义构建）。

加载顺序：`OPENLIST_CRYPT_LIBSODIUM_PATH` → 随包 native asset
（`package:openlist_crypt/libsodium`，由 Flutter/Dart 按平台放置并解析）→
平台默认名（Android/Linux `libsodium.so`；macOS `libsodium.dylib` /
`sodium.framework`；Windows `libsodium.dll` / `libsodium-26.dll`；以及系统常见
路径）→ 全部失败则纯 Dart。

### 平台支持矩阵

预编译库均为 libsodium **1.0.20**（来源、构建方式与 SHA-256 见
[`native/README.md`](native/README.md) / [`native/SHA256SUMS`](native/SHA256SUMS)）。

| 平台 / ABI | 预编译库 | 来源 | 验证情况 |
|---|---|---|---|
| Android arm64-v8a | ✅ `libsodium.so` | 官方源码 + 官方 dist-build 脚本，NDK r27c，16 KB 对齐 | ✅ 本地实测：APK 只含对应 ABI（split-per-abi / --target-platform / abiFilters）；🔄 CI 构建检查 |
| Android armeabi-v7a | ✅ | 同上 | ✅ 本地实测 APK 剔除；🔄 CI |
| Android x86_64 | ✅ | 同上 | ✅ 本地实测 APK 剔除；🔄 CI（含 x86_64 模拟器运行时加载） |
| Android x86 | ✅ | 同上 | ⚠️ Flutter 已不构建 `android-x86` 目标，Flutter App 中不会打包；仅非 Flutter 宿主可用 |
| Linux x64 | ✅ `libsodium.so`（glibc ≥ 2.17） | 官方源码，Zig 交叉编译 | ✅ 本地实测：`flutter build linux` bundle 只含 x64 库，运行时加载随包库；`dart test` 加载随包库 |
| Linux arm64 | ✅（glibc ≥ 2.17） | 同上 | ✅ 本地 qemu 功能测试（dlopen + secretbox 向量）；🔄 CI（ubuntu-24.04-arm 构建 + 运行） |
| macOS arm64 / x64 | ✅ `libsodium.dylib`（≥ 11.0 / ≥ 10.15） | 官方源码，Zig 交叉编译 | 🔄 仅 CI（`dart test` + `flutter build macos` + 运行） |
| Windows x64 | ✅ `libsodium.dll` | **官方预编译 DLL**（msvc zip，未修改） | 🔄 仅 CI（`dart test` + `flutter build windows`） |
| Windows arm64 | ✅ `libsodium.dll` | 官方源码，Zig（mingw-w64/UCRT）交叉编译 | 🔄 仅 CI（windows-11-arm） |
| iOS（真机 arm64 / 模拟器 arm64、x86_64） | ⏳ 尚未提交 | `Build libsodium (iOS)` 工作流用 Xcode 从官方源码构建，审核后提交到 `native/ios/` | 目前回退纯 Dart；🔄 CI 检查 `flutter build ios` 可构建 |
| Web | ❌ | — | 不支持（依赖 `dart:io` / `dart:ffi`） |

✅ = 已在盒子上实际验证；🔄 = 仅由 GitHub Actions 构建/测试（见
`.github/workflows/`）；⏳ = 待补。

### 只打包目标架构

构建 hook（[`hook/build.dart`](hook/build.dart)）由 Dart/Flutter 工具链**按目标
OS/架构逐个调用**，每次只返回一个库文件，所以：

- `flutter build apk --split-per-abi`：每个 APK 只含自己 ABI 的 `libsodium.so`；
- `flutter build apk --target-platform android-arm64`：只含 `arm64-v8a`；
- 默认 `flutter build apk` / `appbundle`：含 Flutter 默认的 arm、arm64、x64 三个
  ABI（与 `libflutter.so` 一致）；
- 想用 Gradle `abiFilters` 时，需要同时在 `android/gradle.properties` 设置
  `disable-abi-filtering=true`，否则 Flutter Gradle 插件会覆盖 `abiFilters`
  （这对 `libflutter.so` 同样适用）；
- 桌面 / iOS 只打包当前构建目标架构的库（macOS 通用包会合并 arm64 + x64）。

**不需要 libsodium？** 在 App 的 `pubspec.yaml` 中关闭打包，App 中不会有任何
本包的原生库，运行时纯 Dart：

```yaml
hooks:
  user_defines:
    openlist_crypt:
      bundle_libsodium: false
```

> 从旧的手动 `jniLibs` 方式迁移：hook 已自动把 `.so` 放进 `lib/<abi>/`，请删除
> 宿主 `build.gradle.kts` 里指向本包 `native/android` 的 `jniLibs.srcDir`，否则
> 会出现重复的 `lib/<abi>/libsodium.so`。

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
dart test                                   # hook 会为本机打包 libsodium
OPENLIST_CRYPT_EXPECT_BUNDLED=true dart test test/native_asset_test.dart
# 用其它 libsodium 跑 FFI 交叉测试（可选）：
OPENLIST_CRYPT_LIBSODIUM_PATH=/usr/lib/x86_64-linux-gnu/libsodium.so.23 dart test
```

打包剔除验证用的 Flutter App 在 [`tool/verify_app/`](tool/verify_app/)。

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
- 随包的 libsodium 预编译库仍是 **ISC** 许可（未被重新授权为 AGPL），再分发时须保留
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
- **Prebuilt libsodium 1.0.20** for Android (armeabi-v7a, arm64-v8a, x86,
  x86_64), Linux (x64, arm64), macOS (arm64, x64) and Windows (x64, arm64) is
  bundled by a build hook (native assets) that packages **only the binary for
  the build target**. iOS binaries are not committed yet (pure-Dart fallback).
  Opt out with the `bundle_libsodium: false` hook user-define. Provenance and
  SHA-256: [native/README.md](native/README.md).
- **License: AGPL-3.0.** Distributing an app that links this package (or
  offering a modified version over a network) generally requires releasing the
  corresponding source under AGPL-compatible terms. The bundled libsodium binary
  stays under ISC. Third-party notices are in [NOTICE](NOTICE). Not legal advice.
