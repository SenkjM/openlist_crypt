#!/usr/bin/env bash
# Linux x64/arm64 (glibc >= 2.17), macOS arm64/x64 and Windows arm64 from the
# official source, cross-compiled on Linux with Zig 0.15.2 (`zig cc`).
#
#   ZIG=/path/to/zig tool/libsodium/build_zig.sh
source "$(dirname "$0")/common.sh"
ZIG=${ZIG:-zig}
STRIP=${STRIP:-llvm-strip}
export ZIG_GLOBAL_CACHE_DIR=$WORK/zig-cache ZIG_LOCAL_CACHE_DIR=$WORK/zig-cache

wrappers() { # <dir> <zig target>
  mkdir -p "$1/bin"
  printf '#!/bin/sh\nexec %s cc -target %s "$@"\n' "$ZIG" "$2" > "$1/bin/cc"
  printf '#!/bin/sh\nexec %s ar "$@"\n' "$ZIG" > "$1/bin/ar"
  printf '#!/bin/sh\nexec %s ranlib "$@"\n' "$ZIG" > "$1/bin/ranlib"
  chmod +x "$1/bin/"*
}

configure_make() { # <dir> <src> <autoconf host> <extra configure args...>
  local d=$1 src=$2 host=$3; shift 3
  (
    cd "$src"
    lt_cv_deplibs_check_method=pass_all \
    CC=$d/bin/cc AR=$d/bin/ar RANLIB=$d/bin/ranlib CFLAGS="-O2" \
      ./configure --host="$host" --prefix="$d/out" \
      --disable-dependency-tracking "$@" > "$d/configure.log" 2>&1
    make -j"$(nproc 2>/dev/null || echo 4)" > "$d/make.log" 2>&1
    make install > "$d/install.log" 2>&1
  )
}

linux() { # <arch> <zig target> <host>
  local d=$WORK/zig-linux-$1 src
  src=$(fresh_source "$d"); wrappers "$d" "$2"
  configure_make "$d" "$src" "$3" --enable-shared --disable-static
  mkdir -p "$NATIVE_DIR/linux/$1"
  "$STRIP" --strip-debug -o "$NATIVE_DIR/linux/$1/libsodium.so" \
    "$d/out/lib/libsodium.so.26.2.0"
  echo "linux/$1: $(sha256 "$NATIVE_DIR/linux/$1/libsodium.so")"
}

macos() { # <arch> <zig target> <host>
  # Static build, then link a dylib with install name @rpath/libsodium.dylib.
  local d=$WORK/zig-macos-$1 src
  src=$(fresh_source "$d"); wrappers "$d" "$2"
  configure_make "$d" "$src" "$3" --disable-shared --enable-static --with-pic
  rm -rf "$d/objs" && mkdir "$d/objs"
  (cd "$d/objs" && "$ZIG" ar x "$d/out/lib/libsodium.a")
  mkdir -p "$NATIVE_DIR/macos/$1"
  "$ZIG" cc -target "$2" -dynamiclib -o "$NATIVE_DIR/macos/$1/libsodium.dylib" \
    "$d"/objs/*.o -s -Wl,-install_name,@rpath/libsodium.dylib
  echo "macos/$1: $(sha256 "$NATIVE_DIR/macos/$1/libsodium.dylib")"
}

windows_arm64() {
  local d=$WORK/zig-windows-arm64 src
  src=$(fresh_source "$d"); wrappers "$d" aarch64-windows-gnu
  configure_make "$d" "$src" aarch64-w64-mingw32 --enable-shared --disable-static
  mkdir -p "$NATIVE_DIR/windows/arm64"
  cp "$d/out/bin/libsodium-26.dll" "$NATIVE_DIR/windows/arm64/libsodium.dll"
  echo "windows/arm64: $(sha256 "$NATIVE_DIR/windows/arm64/libsodium.dll")"
}

ONLY=${ONLY:-linux,macos,windows}
case ",$ONLY," in *,linux,*)
  linux x64   x86_64-linux-gnu.2.17  x86_64-linux-gnu
  linux arm64 aarch64-linux-gnu.2.17 aarch64-linux-gnu ;; esac
case ",$ONLY," in *,macos,*)
  macos arm64 aarch64-macos.11.0     aarch64-apple-darwin
  macos x64   x86_64-macos.10.15     x86_64-apple-darwin ;; esac
case ",$ONLY," in *,windows,*)
  windows_arm64 ;; esac
