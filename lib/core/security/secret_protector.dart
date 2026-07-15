import 'dart:typed_data';

abstract interface class SecretProtector {
  Uint8List protect(Uint8List clearText);

  Uint8List unprotect(Uint8List protectedData);
}
