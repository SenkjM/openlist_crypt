// Tests for the build-hook bundled libsodium (native assets).
//
// Set OPENLIST_CRYPT_EXPECT_BUNDLED=true (done in CI on every desktop runner
// that has a prebuilt binary) to assert that the hook-bundled library is the
// one that loads.
import 'dart:io';
import 'dart:typed_data';

import 'package:code_assets/code_assets.dart';
import 'package:openlist_crypt/openlist_crypt.dart';
import 'package:test/test.dart';

import '../hook/build.dart' as hook;

/// Targets with a prebuilt binary committed under native/.
const _shipped = <(OS, Architecture, IOSSdk?)>[
  (OS.android, Architecture.arm, null),
  (OS.android, Architecture.arm64, null),
  (OS.android, Architecture.ia32, null),
  (OS.android, Architecture.x64, null),
  (OS.linux, Architecture.x64, null),
  (OS.linux, Architecture.arm64, null),
  (OS.macOS, Architecture.x64, null),
  (OS.macOS, Architecture.arm64, null),
  (OS.windows, Architecture.x64, null),
  (OS.windows, Architecture.arm64, null),
];

/// Targets the hook maps but whose binaries may not be committed yet.
const _optional = <(OS, Architecture, IOSSdk?)>[
  (OS.iOS, Architecture.arm64, IOSSdk.iPhoneOS),
  (OS.iOS, Architecture.arm64, IOSSdk.iPhoneSimulator),
  (OS.iOS, Architecture.x64, IOSSdk.iPhoneSimulator),
];

void main() {
  group('hook prebuilt mapping', () {
    for (final (os, arch, sdk) in _shipped) {
      test('$os/$arch${sdk == null ? '' : '/$sdk'} has a prebuilt binary', () {
        final rel = hook.prebuiltPath(os, arch, iosSdk: sdk);
        expect(rel, isNotNull);
        expect(
          File('native/$rel').existsSync(),
          isTrue,
          reason: 'missing native/$rel',
        );
      });
    }

    for (final (os, arch, sdk) in _optional) {
      test('$os/$arch/$sdk is mapped (binary optional)', () {
        expect(hook.prebuiltPath(os, arch, iosSdk: sdk), isNotNull);
      });
    }

    test('unsupported targets map to null (pure Dart fallback)', () {
      expect(hook.prebuiltPath(OS.android, Architecture.riscv64), isNull);
      expect(hook.prebuiltPath(OS.linux, Architecture.riscv64), isNull);
      expect(hook.prebuiltPath(OS.windows, Architecture.ia32), isNull);
      expect(
        hook.prebuiltPath(OS.iOS, Architecture.x64, iosSdk: IOSSdk.iPhoneOS),
        isNull,
      );
      expect(hook.prebuiltPath(OS.fuchsia, Architecture.x64), isNull);
    });
  });

  group('runtime load', () {
    tearDown(preferDartSecretbox);

    test('bundled native asset loads when expected', () {
      final expectBundled =
          Platform.environment['OPENLIST_CRYPT_EXPECT_BUNDLED'] == 'true';
      final loaded = tryLoadLibsodium(forceReload: true);
      if (!expectBundled) {
        // Soft: either loads (bundled / system) or reports why not.
        if (!loaded) expect(libsodiumLoadError, isNotNull);
        return;
      }
      expect(loaded, isTrue, reason: libsodiumLoadError);
      expect(libsodiumLoadedPath, kLibsodiumBundledAssetLabel);
      expect(libsodiumVersionString(), '1.0.20');

      // Cross-check against the pure-Dart engine.
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      final nonce = Uint8List.fromList(List.generate(24, (i) => 100 + i));
      final msg = Uint8List.fromList(List.generate(1000, (i) => i * 7));
      final dartBox = secretboxSealDart(msg, nonce, key);
      expect(preferLibsodiumSecretbox(require: true), isTrue);
      expect(secretboxSeal(msg, nonce, key), dartBox);
      expect(secretboxOpen(dartBox, nonce, key), msg);
    });
  });
}
