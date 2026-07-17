import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../security/network_policy.dart';

class PlaylistDownloadException implements Exception {
  const PlaylistDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GuideDownloadException implements Exception {
  const GuideDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _BoundedDownloadException implements Exception {
  const _BoundedDownloadException(this.message);

  final String message;
}

class BoundedHttpClient {
  BoundedHttpClient({NetworkPolicy networkPolicy = const NetworkPolicy()})
    : _networkPolicy = networkPolicy;

  static const int maxBytes = 25 * 1024 * 1024;
  static const int maxGuideBytes = 32 * 1024 * 1024;
  static const int maxRedirects = 5;
  static const Duration totalTimeout = Duration(seconds: 60);
  static const Duration guideTotalTimeout = Duration(seconds: 120);

  final NetworkPolicy _networkPolicy;

  Future<Uint8List> getPlaylist(
    Uri initialUri, {
    required bool allowPrivateNetwork,
  }) async {
    try {
      return await _download(
        initialUri,
        allowPrivateNetwork: allowPrivateNetwork,
        byteLimit: maxBytes,
        resourceName: 'playlist',
        timeout: totalTimeout,
      );
    } on _BoundedDownloadException catch (error) {
      throw PlaylistDownloadException(error.message);
    } on TimeoutException {
      throw const PlaylistDownloadException('The playlist request timed out.');
    } on NetworkPolicyException catch (error) {
      throw PlaylistDownloadException(error.message);
    } on HandshakeException {
      throw const PlaylistDownloadException(
        'The playlist server did not present a trusted TLS certificate.',
      );
    } on TlsException {
      throw const PlaylistDownloadException(
        'The playlist server could not establish a secure connection.',
      );
    } on SocketException {
      throw const PlaylistDownloadException(
        'The playlist host could not be reached.',
      );
    } on HttpException {
      throw const PlaylistDownloadException(
        'The playlist connection ended before the response was complete.',
      );
    }
  }

  Future<Uint8List> getGuide(
    Uri initialUri, {
    required bool allowPrivateNetwork,
  }) async {
    try {
      return await _download(
        initialUri,
        allowPrivateNetwork: allowPrivateNetwork,
        byteLimit: maxGuideBytes,
        resourceName: 'guide',
        timeout: guideTotalTimeout,
      );
    } on _BoundedDownloadException catch (error) {
      throw GuideDownloadException(error.message);
    } on TimeoutException {
      throw const GuideDownloadException('The guide request timed out.');
    } on NetworkPolicyException catch (error) {
      throw GuideDownloadException(error.message);
    } on HandshakeException {
      throw const GuideDownloadException(
        'The guide server did not present a trusted TLS certificate.',
      );
    } on TlsException {
      throw const GuideDownloadException(
        'The guide server could not establish a secure connection.',
      );
    } on SocketException {
      throw const GuideDownloadException(
        'The guide host could not be reached.',
      );
    } on HttpException {
      throw const GuideDownloadException(
        'The guide connection ended before the response was complete.',
      );
    }
  }

  Future<Uint8List> _download(
    Uri initialUri, {
    required bool allowPrivateNetwork,
    required int byteLimit,
    required String resourceName,
    required Duration timeout,
  }) async {
    // The connection is pinned to a single address that the policy already
    // classified, so the socket never re-resolves and drifts onto a private
    // address after the check (DNS rebinding). _get selects which classified
    // address to try, falling back across them if one is unreachable.
    InternetAddress? attempt;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 5)
      ..userAgent = 'KlipaPlayer/0.1'
      ..connectionFactory = (uri, proxyHost, proxyPort) =>
          Socket.startConnect(attempt!, uri.port);
    try {
      return await _get(
        client,
        initialUri,
        allowPrivateNetwork: allowPrivateNetwork,
        byteLimit: byteLimit,
        resourceName: resourceName,
        useAddress: (address) => attempt = address,
      ).timeout(timeout);
    } finally {
      // Runs on timeout too, aborting an in-flight transfer instead of
      // leaving the socket and buffer alive until idle timeout.
      client.close(force: true);
    }
  }

  Future<Uint8List> _get(
    HttpClient client,
    Uri initialUri, {
    required bool allowPrivateNetwork,
    required int byteLimit,
    required String resourceName,
    required void Function(InternetAddress) useAddress,
  }) async {
    var uri = initialUri;
    for (var redirects = 0; redirects <= maxRedirects; redirects++) {
      final addresses = await _networkPolicy.resolveHttpTarget(
        uri,
        allowPrivateNetwork: allowPrivateNetwork,
      );

      final response = await _open(
        client,
        uri,
        addresses: addresses,
        useAddress: useAddress,
      );

      if (_isRedirect(response.statusCode)) {
        if (redirects == maxRedirects) {
          await response.drain<void>();
          throw _BoundedDownloadException(
            'The $resourceName redirected too many times.',
          );
        }
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null) {
          throw _BoundedDownloadException(
            'The $resourceName server returned an invalid redirect.',
          );
        }
        final Uri next;
        try {
          next = uri.resolve(location);
        } on FormatException {
          throw _BoundedDownloadException(
            'The $resourceName server returned an invalid redirect.',
          );
        }
        if (uri.scheme == 'https' && next.scheme != 'https') {
          throw _BoundedDownloadException(
            'A secure $resourceName cannot redirect to an insecure address.',
          );
        }
        uri = next;
        continue;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw _BoundedDownloadException(
          'The $resourceName server returned HTTP ${response.statusCode}.',
        );
      }
      final declaredLength = response.contentLength;
      if (declaredLength > byteLimit) {
        await response.drain<void>();
        throw _BoundedDownloadException(
          'The $resourceName exceeds the ${byteLimit ~/ (1024 * 1024)} MiB limit.',
        );
      }
      final contentType = response.headers.contentType?.mimeType.toLowerCase();
      if (contentType == 'text/html' ||
          contentType == 'application/xhtml+xml') {
        await response.drain<void>();
        throw _BoundedDownloadException(
          'The address returned a web page instead of a $resourceName.',
        );
      }

      final builder = BytesBuilder(copy: false);
      var count = 0;
      await for (final chunk in response) {
        count += chunk.length;
        if (count > byteLimit) {
          throw _BoundedDownloadException(
            'The $resourceName exceeds the ${byteLimit ~/ (1024 * 1024)} MiB limit.',
          );
        }
        builder.add(chunk);
      }
      return builder.takeBytes();
    }
    throw _BoundedDownloadException(
      'The $resourceName could not be downloaded.',
    );
  }

  Future<HttpClientResponse> _open(
    HttpClient client,
    Uri uri, {
    required List<InternetAddress> addresses,
    required void Function(InternetAddress) useAddress,
  }) async {
    for (var i = 0; i < addresses.length; i++) {
      useAddress(addresses[i]);
      try {
        final request = await client.getUrl(uri);
        request
          ..followRedirects = false
          ..maxRedirects = 0;
        return await request.close();
      } on SocketException {
        // A classified address was unreachable; try the next one before
        // giving up, without ever re-resolving the host.
        if (i == addresses.length - 1) rethrow;
      }
    }
    throw const SocketException('No classified address was reachable.');
  }

  bool _isRedirect(int statusCode) =>
      statusCode == HttpStatus.movedPermanently ||
      statusCode == HttpStatus.found ||
      statusCode == HttpStatus.seeOther ||
      statusCode == HttpStatus.temporaryRedirect ||
      statusCode == HttpStatus.permanentRedirect;
}
