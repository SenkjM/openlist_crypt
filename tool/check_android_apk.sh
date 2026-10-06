#!/usr/bin/env bash
# check_android_apk.sh <apk> <abi>[,<abi>...]
# Asserts the APK contains lib/<abi>/libsodium.so for exactly the given ABIs.
set -euo pipefail
apk=$1; want=$(echo "$2" | tr ',' '\n' | sort | tr '\n' ' ')
echo "== $apk"
unzip -l "$apk" | awk '/lib\//{print $1, $4}'
got=$(unzip -Z1 "$apk" | sed -n 's#^lib/\([^/]*\)/libsodium\.so$#\1#p' | sort | tr '\n' ' ')
if [ "$got" != "$want" ]; then
  echo "libsodium ABIs: got [$got], want [$want]" >&2; exit 1
fi
echo "OK libsodium ABIs: [$got]"
