# verify_app

CI-only Flutter app. Generate platform folders, build, and inspect artifacts:

```sh
cd tool/verify_app
flutter create --platforms=android,linux,macos,ios,windows --project-name verify_app .
flutter build apk --release --split-per-abi
unzip -l build/app/outputs/flutter-apk/app-arm64-v8a-release.apk | grep lib/
```

At startup the app prints `OPENLIST_CRYPT_VERIFY loaded=... path=...`; with
`VERIFY_EXIT=1` it exits with 0 when libsodium loaded, 3 otherwise.
