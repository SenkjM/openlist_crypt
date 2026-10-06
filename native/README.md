# Prebuilt libsodium 1.0.20 (optional secretbox backend)

These shared libraries are used **only** for the content secretbox
(`crypto_secretbox_easy` / `crypto_secretbox_open_easy`). EME filename
encryption, name encodings and scrypt are always pure Dart.

They are bundled automatically by the package build hook
([`hook/build.dart`](../hook/build.dart), Dart/Flutter native assets) — **only
the file matching the build target's OS + architecture is packaged**. Targets
without a file here fall back to the pure-Dart secretbox at runtime.

## Source and verification

All binaries derive from libsodium **1.0.20** official release files, whose
Ed25519 minisign signatures were verified with the official key
`RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3`
(<https://doc.libsodium.org/installation>):

| Release file | SHA-256 |
|---|---|
| `libsodium-1.0.20.tar.gz` (source) | `ebb65ef6ca439333c2bb41a0c1990587288da07f6c7fd07cb3a18cc18d30ce19` |
| `libsodium-1.0.20-msvc.zip` (official Windows build) | `2ff97f9e3f5b341bdc808e698057bea1ae454f99e29ff6f9b62e14d0eb1b1baa` |

Download: <https://download.libsodium.org/libsodium/releases/>

## Binaries

| Path | Target | How it was produced | SHA-256 |
|---|---|---|---|
| `android/arm64-v8a/libsodium.so` | Android arm64-v8a | source → official `dist-build/android-armv8-a.sh`, NDK r27c, API 21, `-Wl,-z,max-page-size=16384` | `3964a5991281a05b6860a3adc1e65f833c5d188e8b6bb92013ffcf02ac71a366` |
| `android/armeabi-v7a/libsodium.so` | Android armeabi-v7a | `dist-build/android-armv7-a.sh`, same settings | `55a46186b72532e51be77199ce27092cf2bf5d8d55a2ed3ca724b572467a3a95` |
| `android/x86/libsodium.so` | Android x86 | `dist-build/android-x86.sh`, same settings | `683f5231c300cde0b1d74fcfc9ac98e2909b5a6b240d8dabaa99d362128e748e` |
| `android/x86_64/libsodium.so` | Android x86_64 | `dist-build/android-x86_64.sh` (`-march=westmere`), same settings | `3bdf3c23f4d33b087b150671aca68930995f8a49fbfc5ab78a0cf82ba298e173` |
| `linux/x64/libsodium.so` | Linux x86_64, glibc ≥ 2.17 | source → `./configure` with Zig 0.15.2 `zig cc -target x86_64-linux-gnu.2.17`, `-O2`, debug info stripped | `b98b5bf76b9079eb5ce2e4d279abbc047c7d29849e60d87ed53888c71f84413b` |
| `linux/arm64/libsodium.so` | Linux aarch64, glibc ≥ 2.17 | same, `aarch64-linux-gnu.2.17` | `8f54bc4363dfefd6a6bdfb6d26883dfcc76db3bbf27b94b838b50366f4b67aaf` |
| `macos/arm64/libsodium.dylib` | macOS arm64, ≥ 11.0 | source → static build with `zig cc -target aarch64-macos.11.0`, linked to a dylib (`@rpath/libsodium.dylib`, stripped, ad-hoc signed by the linker) | `347564038d7f163fc9fc4be6a4a4b706f33a41a09cafc3f334719f8adbf4aa8c` |
| `macos/x64/libsodium.dylib` | macOS x86_64, ≥ 10.15 | same, `x86_64-macos.10.15` | `60ebb312e71a77e8886da32803d2069f9026032bb65e57caa68affebf3b9c1b2` |
| `windows/x64/libsodium.dll` | Windows x64 | **official prebuilt, unmodified**: `libsodium-1.0.20-msvc.zip` → `libsodium/x64/Release/v143/dynamic/libsodium.dll` (needs the VC++ 2015-2022 runtime, as Flutter itself does) | `f1b56eb55a86edee37a2614c8bd38272ac325ec6fa6fa7a4088a4d1a42815c4c` |
| `windows/arm64/libsodium.dll` | Windows arm64 | source → `./configure` with `zig cc -target aarch64-windows-gnu` (mingw-w64, UCRT); the official msvc zip has no ARM64 DLL | `d6819a473fdbec1a56fc34ba02dec944563b685db3d33945b5f8ef7f2dd34711` |
| `ios/…` | iOS device arm64 / simulator arm64 + x86_64 | **not committed yet** — built from source with Xcode by the `Build libsodium (iOS)` workflow ([`tool/libsodium/build_ios.sh`](../tool/libsodium/build_ios.sh)); until then iOS uses pure Dart | — |

Machine-readable list: [`SHA256SUMS`](SHA256SUMS).

### Reproducing

```sh
# Android (NDK r27c)
ANDROID_NDK_HOME=/path/to/android-ndk-r27c tool/libsodium/build_android.sh
# Windows x64 (official DLL)
tool/libsodium/fetch_windows_x64.sh
# Linux x64/arm64, macOS arm64/x64, Windows arm64 (Zig 0.15.2)
ZIG=/path/to/zig STRIP=llvm-strip tool/libsodium/build_zig.sh
# iOS (macOS + Xcode)
tool/libsodium/build_ios.sh
```

Every script re-downloads the official files and checks SHA-256 + minisign.
The Android, Linux and Windows x64 outputs above were reproduced
bit-for-bit (the earlier in-tree `arm64-v8a` build from Webdav_Media_Manager,
SHA-256 `704a03b2…e97e`, is reproduced exactly by the same script **without**
the 16 KB page-size flag). macOS and Windows arm64 builds are deterministic
when run from the same checkout path.

## How it is packaged and loaded

* **Build time** — `hook/build.dart` maps the target
  (`android/{armeabi-v7a,arm64-v8a,x86,x86_64}`, `linux/{x64,arm64}`,
  `macos/{arm64,x64}`, `ios/{iphoneos,iphonesimulator}/…`,
  `windows/{x64,arm64}`) to one file and emits it as code asset
  `package:openlist_crypt/libsodium` (`DynamicLoadingBundled`). Flutter places
  it in `lib/<abi>/libsodium.so` (Android), `bundle/lib/libsodium.so`
  (Linux), a framework in the app bundle (macOS/iOS) or next to the `.exe`
  (Windows). Opt out with the user-define `bundle_libsodium: false`.
* **Run time** — `tryLoadLibsodium()` tries `OPENLIST_CRYPT_LIBSODIUM_PATH`,
  then the bundled asset, then platform names (`libsodium.so`,
  `libsodium.dylib`, `sodium.framework/sodium`, `libsodium.dll`, …). If all
  fail, the pure-Dart secretbox is used.

## License notices

libsodium is ISC licensed; see [LICENSE.libsodium](LICENSE.libsodium) and
[LICENSE_NOTE.md](LICENSE_NOTE.md). Keep the ISC copyright notice with any
redistribution of these binaries (e.g. in your app's open-source licenses
screen).
