import 'dart:io';

enum NetworkTargetKind { public, privateOrLocal }

class NetworkPolicyException implements Exception {
  const NetworkPolicyException(this.message);

  final String message;

  @override
  String toString() => message;
}

class NetworkPolicy {
  const NetworkPolicy();

  static const int maxUriLength = 8192;

  Future<NetworkTargetKind> validateHttpTarget(
    Uri uri, {
    required bool allowPrivateNetwork,
  }) async {
    _validateShape(uri);

    final kind = await classifyHost(uri.host);
    if (kind == NetworkTargetKind.privateOrLocal && !allowPrivateNetwork) {
      throw const NetworkPolicyException(
        'This address reaches the local or private network. Enable private '
        'network access only for a provider you trust.',
      );
    }
    return kind;
  }

  void validateHttpUriShape(Uri uri) => _validateShape(uri);

  Future<NetworkTargetKind> classifyHost(String host) async {
    if (host.toLowerCase() == 'localhost') {
      return NetworkTargetKind.privateOrLocal;
    }

    final literal = InternetAddress.tryParse(host);
    final addresses = literal == null
        ? await InternetAddress.lookup(host).timeout(const Duration(seconds: 8))
        : <InternetAddress>[literal];

    if (addresses.isEmpty) {
      throw const NetworkPolicyException('The host did not resolve.');
    }

    return addresses.any(_isPrivateOrLocal)
        ? NetworkTargetKind.privateOrLocal
        : NetworkTargetKind.public;
  }

  void _validateShape(Uri uri) {
    if (uri.toString().length > maxUriLength) {
      throw const NetworkPolicyException('The address is too long.');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const NetworkPolicyException(
        'Only HTTP and HTTPS addresses are allowed.',
      );
    }
    if (!uri.hasAuthority || uri.host.isEmpty) {
      throw const NetworkPolicyException(
        'Enter a complete HTTP or HTTPS address.',
      );
    }
    if (uri.userInfo.isNotEmpty) {
      throw const NetworkPolicyException(
        'Credentials embedded in addresses are not accepted.',
      );
    }
  }

  bool _isPrivateOrLocal(InternetAddress address) {
    if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
      return true;
    }

    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return _isNonPublicIpv4(bytes);
    }

    final isUniqueLocal = (bytes[0] & 0xfe) == 0xfc;
    final isDeprecatedSiteLocal = bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0xc0;
    final isUnspecified = bytes.every((byte) => byte == 0);
    final isDocumentation =
        bytes[0] == 0x20 &&
        bytes[1] == 0x01 &&
        bytes[2] == 0x0d &&
        bytes[3] == 0xb8;
    final isDiscardOnly =
        bytes[0] == 0x01 && bytes.skip(1).take(7).every((byte) => byte == 0);
    final isIpv4Mapped =
        bytes.take(10).every((byte) => byte == 0) &&
        bytes[10] == 0xff &&
        bytes[11] == 0xff;
    return isUniqueLocal ||
        isDeprecatedSiteLocal ||
        isUnspecified ||
        isDocumentation ||
        isDiscardOnly ||
        (isIpv4Mapped && _isNonPublicIpv4(bytes.sublist(12)));
  }

  bool _isNonPublicIpv4(List<int> bytes) =>
      bytes[0] == 0 ||
      bytes[0] == 10 ||
      bytes[0] == 127 ||
      bytes[0] >= 224 ||
      (bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127) ||
      (bytes[0] == 169 && bytes[1] == 254) ||
      (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
      (bytes[0] == 192 && bytes[1] == 0 && bytes[2] == 0) ||
      (bytes[0] == 192 && bytes[1] == 0 && bytes[2] == 2) ||
      (bytes[0] == 192 && bytes[1] == 168) ||
      (bytes[0] == 198 && bytes[1] >= 18 && bytes[1] <= 19) ||
      (bytes[0] == 198 && bytes[1] == 51 && bytes[2] == 100) ||
      (bytes[0] == 203 && bytes[1] == 0 && bytes[2] == 113);
}
