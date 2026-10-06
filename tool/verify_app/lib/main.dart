import 'dart:io';

import 'package:flutter/material.dart';
import 'package:openlist_crypt/openlist_crypt.dart';

void main() {
  final ok = preferLibsodiumSecretbox();
  final line = 'OPENLIST_CRYPT_VERIFY loaded=$ok path=$libsodiumLoadedPath '
      'version=${libsodiumVersionString()} error=$libsodiumLoadError';
  // On Android/iOS the process stdout is discarded; print() is routed by the
  // Flutter engine to logcat (tag "flutter") / the system log, which is what
  // the emulator CI job greps. Desktop runs keep writing to stdout.
  if (Platform.isAndroid || Platform.isIOS) {
    print(line);
  } else {
    stdout.writeln(line);
  }
  if (Platform.environment['VERIFY_EXIT'] == '1') exit(ok ? 0 : 3);
  runApp(MaterialApp(home: Scaffold(body: Center(child: Text(line)))));
}
