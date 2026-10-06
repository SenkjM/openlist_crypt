# Shared settings for the libsodium build scripts. Source, don't execute.
set -euo pipefail

LIBSODIUM_VERSION=1.0.20
LIBSODIUM_BASE_URL=https://download.libsodium.org/libsodium/releases
# Official minisign public key (https://doc.libsodium.org/installation).
LIBSODIUM_MINISIGN_KEY=RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3

# SHA-256 of the official, minisign-verified release files.
SHA256_SRC=ebb65ef6ca439333c2bb41a0c1990587288da07f6c7fd07cb3a18cc18d30ce19   # libsodium-1.0.20.tar.gz
SHA256_MSVC=2ff97f9e3f5b341bdc808e698057bea1ae454f99e29ff6f9b62e14d0eb1b1baa  # libsodium-1.0.20-msvc.zip

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
NATIVE_DIR=$REPO_ROOT/native
WORK=${WORK:-$REPO_ROOT/.dart_tool/libsodium-build}
mkdir -p "$WORK/dl"

sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# fetch <file> <expected-sha256>: download, verify SHA-256 and (if minisign is
# installed) the upstream signature.
fetch() {
  local f=$1 want=$2
  local out=$WORK/dl/$f
  [ -f "$out" ] || curl -fsSL -o "$out" "$LIBSODIUM_BASE_URL/$f"
  local got; got=$(sha256 "$out")
  if [ "$got" != "$want" ]; then
    echo "SHA-256 mismatch for $f: got $got, want $want" >&2; exit 1
  fi
  if command -v minisign >/dev/null; then
    [ -f "$out.minisig" ] || curl -fsSL -o "$out.minisig" "$LIBSODIUM_BASE_URL/$f.minisig"
    minisign -Vq -P "$LIBSODIUM_MINISIGN_KEY" -m "$out" -x "$out.minisig"
  else
    echo "warning: minisign not installed, signature of $f not checked" >&2
  fi
  echo "$out"
}

# fresh_source <dir>: extract the verified source tarball into <dir>.
fresh_source() {
  local d=$1 tgz
  tgz=$(fetch "libsodium-$LIBSODIUM_VERSION.tar.gz" "$SHA256_SRC")
  rm -rf "$d" && mkdir -p "$d"
  tar xzf "$tgz" -C "$d"
  echo "$d/libsodium-$LIBSODIUM_VERSION"
}
