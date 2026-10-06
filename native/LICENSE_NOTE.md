# License note: bundling precompiled libsodium

This is a short factual note for maintainers, **not legal advice**. Cite the
license texts themselves.

## Project licenses involved

| Component | License (as shipped in-tree) | Location |
|---|---|---|
| `openlist_crypt` (Dart port) | **AGPL-3.0** (+ upstream notices for rclone / base32768 / golang.org/x/crypto) | `LICENSE`, `NOTICE` |
| libsodium (prebuilt `.so` / `.dylib` / `.dll` under `native/`) | **ISC** | `native/LICENSE.libsodium` (from upstream 1.0.20) |

## What the ISC text requires (verbatim gist)

From libsodium's ISC license:

> Permission to use, copy, modify, and/or distribute this software for any
> purpose with or without fee is hereby granted, provided that the above
> copyright notice and this permission notice appear in all copies.

So redistributing the precompiled libsodium binaries is consistent with ISC when
the copyright + permission notice is preserved (this directory keeps
`LICENSE.libsodium`).

## AGPL-3.0 package and host app

`openlist_crypt` is AGPL-3.0; apps that distribute it must comply with the
AGPL-3.0 terms. The ISC notice obligation for libsodium remains. Shipping the binaries inside an AGPL package does **not** by
itself re-license libsodium as AGPL—the ISC terms still apply to that binary.
Keep conveying:

1. AGPL-3.0 for the Dart sources (`LICENSE`).
2. Upstream attributions in `NOTICE`.
3. libsodium ISC notice (`native/LICENSE.libsodium`) alongside the binary.

## Notices to keep when shipping an app that includes the library

- Retain `LICENSE.libsodium` (or equivalent copyright + ISC permission text) in
  the source tree and in any source/binary distribution that includes the
  library (APK/AAB, IPA, desktop bundle). The build hook bundles it
  automatically unless `bundle_libsodium: false` is set.
- Do not strip upstream copyright from the notice file.
- EME / name codecs are unaffected (no libsodium code there).

## Out of scope

Compatibility of AGPL network-copyleft duties with third-party app stores,
trademark questions, and patent claims are **not** assessed here. Re-read the
full AGPL-3.0 and ISC texts before a production release decision.
