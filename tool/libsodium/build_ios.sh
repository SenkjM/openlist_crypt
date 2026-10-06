#!/usr/bin/env bash
# iOS (device arm64, simulator arm64 + x86_64) dylibs from the official source
# with Xcode clang, using the same configure flags as libsodium's official
# dist-build/apple-xcframework.sh (static build), then linked into a dylib
# with install name @rpath/libsodium.dylib (Flutter/Dart native assets wrap it
# into a framework). Must run on macOS; used by
# .github/workflows/libsodium-apple.yaml.
#
# Output: native/ios/{iphoneos/arm64,iphonesimulator/arm64,iphonesimulator/x64}/libsodium.dylib
source "$(dirname "$0")/common.sh"
MIN_IOS=${MIN_IOS:-13.0}

build_one() { # <sdk> <arch> <autoconf host> <min-version flag> <out arch dir>
  local sdk=$1 arch=$2 host=$3 minflag=$4 outarch=$5 d src sdkpath
  d=$WORK/ios-$sdk-$arch
  src=$(fresh_source "$d")
  sdkpath=$(xcrun --sdk "$sdk" --show-sdk-path)
  local flags="-arch $arch -isysroot $sdkpath $minflag"
  (
    cd "$src"
    export CC="$(xcrun --sdk "$sdk" -f clang)"
    export CFLAGS="-O3 $flags" LDFLAGS="$flags"
    ./configure --host="$host" --prefix="$d/out" \
      --disable-shared --enable-static --with-pic \
      --disable-dependency-tracking > "$d/configure.log" 2>&1
    make -j"$(sysctl -n hw.ncpu)" > "$d/make.log" 2>&1
    make install > "$d/install.log" 2>&1
  )
  mkdir -p "$NATIVE_DIR/ios/$sdk/$outarch"
  "$(xcrun --sdk "$sdk" -f clang)" $flags -dynamiclib \
    -o "$NATIVE_DIR/ios/$sdk/$outarch/libsodium.dylib" \
    -Wl,-all_load "$d/out/lib/libsodium.a" -Wl,-S \
    -install_name @rpath/libsodium.dylib
  echo "ios/$sdk/$outarch: $(sha256 "$NATIVE_DIR/ios/$sdk/$outarch/libsodium.dylib")"
}

build_one iphoneos        arm64  aarch64-apple-darwin23 "-mios-version-min=$MIN_IOS"           arm64
build_one iphonesimulator arm64  aarch64-apple-darwin23 "-mios-simulator-version-min=$MIN_IOS" arm64
build_one iphonesimulator x86_64 x86_64-apple-darwin23  "-mios-simulator-version-min=$MIN_IOS" x64
