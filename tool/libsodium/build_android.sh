#!/usr/bin/env bash
# Android: armeabi-v7a, arm64-v8a, x86, x86_64 from the official source with
# the official dist-build scripts + Android NDK r27c, API 21, linked with
# 16 KB max page size (Google Play requirement for 64-bit ABIs).
#
#   ANDROID_NDK_HOME=/path/to/android-ndk-r27c tool/libsodium/build_android.sh
source "$(dirname "$0")/common.sh"
: "${ANDROID_NDK_HOME:?set ANDROID_NDK_HOME to an Android NDK r27c}"

build_one() { # <dist-build suffix> <abi> <output dir glob>
  local script=$1 abi=$2 glob=$3 src
  src=$(fresh_source "$WORK/android-$abi")
  (
    cd "$src"
    export LIBSODIUM_FULL_BUILD=Y NDK_PLATFORM=android-21
    export LDFLAGS="-Wl,-z,max-page-size=16384"
    ./dist-build/android-$script.sh > "$WORK/android-$abi.log" 2>&1
  )
  mkdir -p "$NATIVE_DIR/android/$abi"
  cp "$src"/$glob/lib/libsodium.so "$NATIVE_DIR/android/$abi/libsodium.so"
  echo "android/$abi: $(sha256 "$NATIVE_DIR/android/$abi/libsodium.so")"
}

build_one armv7-a  armeabi-v7a 'libsodium-android-armv7-a'
build_one armv8-a  arm64-v8a   'libsodium-android-armv8-a+crypto'
build_one x86      x86         'libsodium-android-i686'
build_one x86_64   x86_64      'libsodium-android-westmere'
