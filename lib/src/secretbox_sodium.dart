import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'secretbox_dart.dart' show kSecretboxOverhead;

/// Optional libsodium FFI backend for NaCl secretbox only
/// (`crypto_secretbox_easy` / `crypto_secretbox_open_easy`).
///
/// Layout matches the pure-Dart path and rclone crypt: `tag(16) || ciphertext`,
/// 24-byte nonce, 32-byte key.
///
/// Load strategy (first success wins):
/// 1. `OPENLIST_CRYPT_LIBSODIUM_PATH` — explicit absolute path (tests, custom
///    installs, debugging).
/// 2. The **bundled native asset** `package:openlist_crypt/libsodium`, emitted
///    by this package's build hook (`hook/build.dart`) for the current target
///    OS/architecture only. Resolved by the Dart/Flutter embedder
///    (`@Native(assetId: ...)`), so the per-platform file name and location
///    (`libsodium.so`, `libsodium.dylib` / `sodium.framework`, `libsodium.dll`)
///    are handled by the toolchain.
/// 3. Platform library names on the default search path
///    (`libsodium.so` on Android/Linux, `libsodium.dylib` / framework on
///    Apple, `libsodium.dll` / `libsodium-26.dll` on Windows, and common
///    system locations).
///
/// When nothing loads, [tryLoadLibsodium] returns false and the
/// [SecretboxBackend] logic falls back to pure Dart.

typedef _SodiumInitNative = Int32 Function();
typedef _SodiumInitDart = int Function();

typedef _VersionNative = Pointer<Utf8> Function();
typedef _VersionDart = Pointer<Utf8> Function();

typedef _EasyNative =
    Int32 Function(
      Pointer<Uint8> c,
      Pointer<Uint8> m,
      Uint64 mlen,
      Pointer<Uint8> n,
      Pointer<Uint8> k,
    );
typedef _EasyDart =
    int Function(
      Pointer<Uint8> c,
      Pointer<Uint8> m,
      int mlen,
      Pointer<Uint8> n,
      Pointer<Uint8> k,
    );

typedef _OpenEasyNative =
    Int32 Function(
      Pointer<Uint8> m,
      Pointer<Uint8> c,
      Uint64 clen,
      Pointer<Uint8> n,
      Pointer<Uint8> k,
    );
typedef _OpenEasyDart =
    int Function(
      Pointer<Uint8> m,
      Pointer<Uint8> c,
      int clen,
      Pointer<Uint8> n,
      Pointer<Uint8> k,
    );

/// Asset id of the libsodium shared library bundled by `hook/build.dart`.
const String kLibsodiumAssetId = 'package:openlist_crypt/libsodium';

/// Pseudo-path reported by [libsodiumLoadedPath] when the bundled native
/// asset was used.
const String kLibsodiumBundledAssetLabel = 'asset:$kLibsodiumAssetId';

// ---- Bundled native asset bindings (resolved lazily by the embedder) -------

@Native<_SodiumInitNative>(symbol: 'sodium_init', assetId: kLibsodiumAssetId)
external int _assetSodiumInit();

@Native<_VersionNative>(
  symbol: 'sodium_version_string',
  assetId: kLibsodiumAssetId,
)
external Pointer<Utf8> _assetVersion();

@Native<_EasyNative>(
  symbol: 'crypto_secretbox_easy',
  assetId: kLibsodiumAssetId,
)
external int _assetEasy(
  Pointer<Uint8> c,
  Pointer<Uint8> m,
  int mlen,
  Pointer<Uint8> n,
  Pointer<Uint8> k,
);

@Native<_OpenEasyNative>(
  symbol: 'crypto_secretbox_open_easy',
  assetId: kLibsodiumAssetId,
)
external int _assetOpenEasy(
  Pointer<Uint8> m,
  Pointer<Uint8> c,
  int clen,
  Pointer<Uint8> n,
  Pointer<Uint8> k,
);

// ---- Active bindings -------------------------------------------------------

_EasyDart? _easy;
_OpenEasyDart? _openEasy;
_VersionDart? _version;
String? _loadedPath;
String? _loadError;
bool _loadAttempted = false;

/// Path (or [kLibsodiumBundledAssetLabel]) that successfully loaded, or null.
String? get libsodiumLoadedPath => _loadedPath;

/// Last load failure message (for diagnostics); null if never failed or OK.
String? get libsodiumLoadError => _loadError;

/// Whether libsodium FFI bindings are ready (`sodium_init` succeeded).
bool get libsodiumSecretboxReady => _easy != null && _openEasy != null;

/// Library names / paths tried after the env override and bundled asset.
List<String> _fallbackCandidates() {
  if (Platform.isAndroid) {
    // Host app packaged it in jniLibs (lib/<abi>/libsodium.so) manually.
    return ['libsodium.so'];
  }
  if (Platform.isLinux) {
    return [
      'libsodium.so',
      'libsodium.so.26',
      'libsodium.so.23',
      '/usr/lib/x86_64-linux-gnu/libsodium.so.23',
      '/usr/lib/aarch64-linux-gnu/libsodium.so.23',
    ];
  }
  if (Platform.isIOS) {
    return ['sodium.framework/sodium', 'libsodium.framework/libsodium'];
  }
  if (Platform.isMacOS) {
    return [
      'sodium.framework/sodium',
      'libsodium.dylib',
      'libsodium.26.dylib',
      '/opt/homebrew/lib/libsodium.dylib',
      '/usr/local/lib/libsodium.dylib',
    ];
  }
  if (Platform.isWindows) {
    return ['libsodium.dll', 'libsodium-26.dll'];
  }
  return const [];
}

bool _bindDynamicLibrary(DynamicLibrary lib, String label) {
  final init = lib.lookupFunction<_SodiumInitNative, _SodiumInitDart>(
    'sodium_init',
  );
  // sodium_init: 0 = success first time, 1 = already initialized, -1 = fail
  if (init() == -1) {
    throw StateError('sodium_init returned -1 for $label');
  }
  final easy = lib.lookupFunction<_EasyNative, _EasyDart>(
    'crypto_secretbox_easy',
  );
  final open = lib.lookupFunction<_OpenEasyNative, _OpenEasyDart>(
    'crypto_secretbox_open_easy',
  );
  _VersionDart? version;
  try {
    version = lib.lookupFunction<_VersionNative, _VersionDart>(
      'sodium_version_string',
    );
  } catch (_) {
    version = null;
  }
  _easy = easy;
  _openEasy = open;
  _version = version;
  _loadedPath = label;
  return true;
}

bool _bindBundledAsset() {
  // Throws (ArgumentError / UnsupportedError) when the asset is not bundled
  // for this target, e.g. unsupported ABI or `bundle_libsodium: false`.
  if (_assetSodiumInit() == -1) {
    throw StateError(
      'sodium_init returned -1 for $kLibsodiumBundledAssetLabel',
    );
  }
  _easy = _assetEasy;
  _openEasy = _assetOpenEasy;
  _version = _assetVersion;
  _loadedPath = kLibsodiumBundledAssetLabel;
  return true;
}

/// Attempt to load libsodium. Idempotent; returns whether bindings are ready.
///
/// Never throws: on failure returns false and records [libsodiumLoadError].
bool tryLoadLibsodium({bool forceReload = false}) {
  if (!forceReload && _loadAttempted) return libsodiumSecretboxReady;
  _loadAttempted = true;
  _easy = null;
  _openEasy = null;
  _version = null;
  _loadedPath = null;
  _loadError = null;

  final errors = <String>[];

  final env = Platform.environment['OPENLIST_CRYPT_LIBSODIUM_PATH'];
  if (env != null && env.isNotEmpty) {
    try {
      return _bindDynamicLibrary(DynamicLibrary.open(env), env);
    } catch (e) {
      errors.add('$env: $e');
    }
  }

  try {
    return _bindBundledAsset();
  } catch (e) {
    errors.add('$kLibsodiumBundledAssetLabel: $e');
  }

  for (final path in _fallbackCandidates()) {
    try {
      return _bindDynamicLibrary(DynamicLibrary.open(path), path);
    } catch (e) {
      errors.add('$path: $e');
    }
  }
  _easy = null;
  _openEasy = null;
  _version = null;
  _loadError = errors.isEmpty
      ? 'no libsodium candidates for this platform'
      : errors.join('; ');
  return false;
}

/// libsodium version string when loaded, else null.
String? libsodiumVersionString() {
  if (!tryLoadLibsodium()) return null;
  try {
    return _version?.call().toDartString();
  } catch (_) {
    return null;
  }
}

Uint8List? secretboxOpenSodium(
  Uint8List box,
  Uint8List nonce24,
  Uint8List key32,
) {
  if (box.length < kSecretboxOverhead) return null;
  if (nonce24.length != 24 || key32.length != 32) return null;
  if (!tryLoadLibsodium()) {
    throw StateError('libsodium not loaded: $_loadError');
  }
  final open = _openEasy!;
  final mLen = box.length - kSecretboxOverhead;
  final mPtr = malloc<Uint8>(mLen == 0 ? 1 : mLen);
  final cPtr = malloc<Uint8>(box.length);
  final nPtr = malloc<Uint8>(24);
  final kPtr = malloc<Uint8>(32);
  try {
    cPtr.asTypedList(box.length).setAll(0, box);
    nPtr.asTypedList(24).setAll(0, nonce24);
    kPtr.asTypedList(32).setAll(0, key32);
    final rc = open(mPtr, cPtr, box.length, nPtr, kPtr);
    if (rc != 0) return null;
    return Uint8List.fromList(mPtr.asTypedList(mLen));
  } finally {
    malloc.free(mPtr);
    malloc.free(cPtr);
    malloc.free(nPtr);
    malloc.free(kPtr);
  }
}

Uint8List secretboxSealSodium(
  Uint8List msg,
  Uint8List nonce24,
  Uint8List key32,
) {
  if (nonce24.length != 24 || key32.length != 32) {
    throw ArgumentError('nonce must be 24 bytes and key 32 bytes');
  }
  if (!tryLoadLibsodium()) {
    throw StateError('libsodium not loaded: $_loadError');
  }
  final easy = _easy!;
  final cLen = msg.length + kSecretboxOverhead;
  final cPtr = malloc<Uint8>(cLen);
  final mPtr = malloc<Uint8>(msg.isEmpty ? 1 : msg.length);
  final nPtr = malloc<Uint8>(24);
  final kPtr = malloc<Uint8>(32);
  try {
    if (msg.isNotEmpty) {
      mPtr.asTypedList(msg.length).setAll(0, msg);
    }
    nPtr.asTypedList(24).setAll(0, nonce24);
    kPtr.asTypedList(32).setAll(0, key32);
    final rc = easy(cPtr, mPtr, msg.length, nPtr, kPtr);
    if (rc != 0) {
      throw StateError('crypto_secretbox_easy failed ($rc)');
    }
    return Uint8List.fromList(cPtr.asTypedList(cLen));
  } finally {
    malloc.free(cPtr);
    malloc.free(mPtr);
    malloc.free(nPtr);
    malloc.free(kPtr);
  }
}
