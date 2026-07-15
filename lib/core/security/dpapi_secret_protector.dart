import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'secret_protector.dart';

/// Seals small secrets to the current Windows user through DPAPI.
final class DpapiSecretProtector implements SecretProtector {
  const DpapiSecretProtector();

  static const int _cryptProtectUiForbidden = 0x1;

  @override
  Uint8List protect(Uint8List clearText) {
    _requireWindows();
    return _transform(clearText, protectData: true);
  }

  @override
  Uint8List unprotect(Uint8List protectedData) {
    _requireWindows();
    return _transform(protectedData, protectData: false);
  }

  Uint8List _transform(Uint8List input, {required bool protectData}) {
    if (input.isEmpty) {
      throw ArgumentError.value(input, 'input', 'Must not be empty.');
    }

    return using((arena) {
      final inputBuffer = arena<Uint8>(input.length);
      final inputView = inputBuffer.asTypedList(input.length)..setAll(0, input);
      final inputBlob = arena<CRYPT_INTEGER_BLOB>()
        ..ref.cbData = input.length
        ..ref.pbData = inputBuffer;
      final outputBlob = arena<CRYPT_INTEGER_BLOB>();

      try {
        final result = protectData
            ? CryptProtectData(
                inputBlob,
                null,
                null,
                null,
                _cryptProtectUiForbidden,
                outputBlob,
              )
            : CryptUnprotectData(
                inputBlob,
                null,
                null,
                null,
                _cryptProtectUiForbidden,
                outputBlob,
              );
        if (!result.value) {
          throw WindowsException(result.error.toHRESULT());
        }

        final outputPointer = outputBlob.ref.pbData;
        final outputLength = outputBlob.ref.cbData;
        try {
          return Uint8List.fromList(outputPointer.asTypedList(outputLength));
        } finally {
          if (!protectData) {
            outputPointer
                .asTypedList(outputLength)
                .fillRange(0, outputLength, 0);
          }
          final release = HLOCAL(outputPointer.cast()).close();
          if (!release.value.isNull) {
            throw StateError('Windows could not release DPAPI output memory.');
          }
        }
      } finally {
        inputView.fillRange(0, inputView.length, 0);
      }
    });
  }

  void _requireWindows() {
    if (!Platform.isWindows) {
      throw UnsupportedError('DPAPI is available only on Windows.');
    }
  }
}
