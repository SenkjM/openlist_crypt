// Build hook: bundles the prebuilt libsodium shared library for the *target*
// OS / architecture only (Dart & Flutter native assets).
//
// The Dart / Flutter toolchain invokes this hook once per target
// (e.g. once per Android ABI selected via --target-platform / --split-per-abi,
// once per macOS/iOS architecture), so only the matching binary is packaged.
// Targets without a prebuilt binary emit nothing and the package falls back to
// its pure-Dart secretbox at runtime.
//
// Opt out (pure Dart only, no native library in the app) from the root
// application's pubspec.yaml:
//
//   hooks:
//     user_defines:
//       openlist_crypt:
//         bundle_libsodium: false

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

const _package = 'openlist_crypt';

/// Relative path (under `native/`) of the prebuilt library, or null when no
/// binary is shipped for the target.
String? prebuiltPath(OS os, Architecture arch, {IOSSdk? iosSdk}) {
  switch (os) {
    case OS.android:
      final abi = switch (arch) {
        Architecture.arm => 'armeabi-v7a',
        Architecture.arm64 => 'arm64-v8a',
        Architecture.ia32 => 'x86',
        Architecture.x64 => 'x86_64',
        _ => null,
      };
      return abi == null ? null : 'android/$abi/libsodium.so';
    case OS.linux:
      final a = switch (arch) {
        Architecture.x64 => 'x64',
        Architecture.arm64 => 'arm64',
        _ => null,
      };
      return a == null ? null : 'linux/$a/libsodium.so';
    case OS.macOS:
      final a = switch (arch) {
        Architecture.x64 => 'x64',
        Architecture.arm64 => 'arm64',
        _ => null,
      };
      return a == null ? null : 'macos/$a/libsodium.dylib';
    case OS.iOS:
      final sdk = iosSdk == IOSSdk.iPhoneSimulator
          ? 'iphonesimulator'
          : 'iphoneos';
      final a = switch (arch) {
        Architecture.arm64 => 'arm64',
        Architecture.x64 when sdk == 'iphonesimulator' => 'x64',
        _ => null,
      };
      return a == null ? null : 'ios/$sdk/$a/libsodium.dylib';
    case OS.windows:
      final a = switch (arch) {
        Architecture.x64 => 'x64',
        Architecture.arm64 => 'arm64',
        _ => null,
      };
      return a == null ? null : 'windows/$a/libsodium.dll';
    default:
      return null;
  }
}

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    if (input.userDefines['bundle_libsodium'] == false) return;

    final code = input.config.code;
    // Only dynamic libraries are shipped.
    if (code.linkModePreference == LinkModePreference.static) return;

    final rel = prebuiltPath(
      code.targetOS,
      code.targetArchitecture,
      iosSdk: code.targetOS == OS.iOS ? code.iOS.targetSdk : null,
    );
    if (rel == null) return;

    final file = input.packageRoot.resolve('native/$rel');
    if (!File.fromUri(file).existsSync()) return;

    output.assets.code.add(
      CodeAsset(
        package: _package,
        name: 'libsodium',
        linkMode: DynamicLoadingBundled(),
        file: file,
      ),
    );
    output.dependencies.add(file);
  });
}
