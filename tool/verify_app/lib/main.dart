import 'dart:io';

import 'package:flutter/material.dart';
import 'package:openlist_crypt/openlist_crypt.dart';

void main() {
  final ok = preferLibsodiumSecretbox();
  final line = 'OPENLIST_CRYPT_VERIFY loaded=$ok path=$libsodiumLoadedPath '
      'version=${libsodiumVersionString()} error=$libsodiumLoadError';
  stdout.writeln(line);
  if (Platform.environment['VERIFY_EXIT'] == '1') exit(ok ? 0 : 3);
  runApp(MaterialApp(home: Scaffold(body: Center(child: Text(line)))));
}
