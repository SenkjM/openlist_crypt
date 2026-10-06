#!/usr/bin/env bash
# Windows x64: official prebuilt DLL from libsodium-1.0.20-msvc.zip
# (x64/Release/v143/dynamic/libsodium.dll), unmodified.
source "$(dirname "$0")/common.sh"
zip=$(fetch "libsodium-$LIBSODIUM_VERSION-msvc.zip" "$SHA256_MSVC")
rm -rf "$WORK/msvc" && mkdir -p "$WORK/msvc"
unzip -q "$zip" 'libsodium/x64/Release/v143/dynamic/libsodium.dll' -d "$WORK/msvc"
mkdir -p "$NATIVE_DIR/windows/x64"
cp "$WORK/msvc/libsodium/x64/Release/v143/dynamic/libsodium.dll" \
  "$NATIVE_DIR/windows/x64/libsodium.dll"
echo "windows/x64: $(sha256 "$NATIVE_DIR/windows/x64/libsodium.dll")"
