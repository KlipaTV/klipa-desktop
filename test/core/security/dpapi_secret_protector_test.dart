import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:klipa_player_windows/core/security/dpapi_secret_protector.dart';

void main() {
  test(
    'DPAPI seals and restores bytes for the current Windows user',
    () {
      final random = Random.secure();
      final clearText = Uint8List.fromList(
        List<int>.generate(32, (_) => random.nextInt(256)),
      );
      const protector = DpapiSecretProtector();

      final protected = protector.protect(clearText);
      final restored = protector.unprotect(protected);

      expect(protected, isNot(clearText));
      expect(restored, clearText);
    },
    skip: Platform.isWindows ? false : 'DPAPI is a Windows-only API.',
  );
}
