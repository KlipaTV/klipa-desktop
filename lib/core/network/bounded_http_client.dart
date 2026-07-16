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
      ).timeout(totalTimeout);
    } on _BoundedDownloadException catch (error) {
      throw PlaylistDownloadException(error.message);
    } on TimeoutException {
      throw const PlaylistDownloadException('The playlist request timed out.');
    } on NetworkPolicyException catch (error) {
      throw PlaylistDownloadException(error.message);
    } on SocketException {
      throw const PlaylistDownloadException(
        'The playlist host could not be reached.',
      );
    } on HandshakeException {
      throw const PlaylistDownloadException(
        'The playlist server did not present a trusted TLS certificate.',
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
      ).timeout(guideTotalTimeout);
    } on _BoundedDownloadException catch (error) {
      throw GuideDownloadException(error.message);
    } on TimeoutException {
      throw const GuideDownloadException('The guide request timed out.');
    } on NetworkPolicyException catch (error) {
      throw GuideDownloadException(error.message);
    } on SocketException {
      throw const GuideDownloadException(
        'The guide host could not be reached.',
      );
    } on HandshakeException {
      throw const GuideDownloadException(
        'The guide server did not present a trusted TLS certificate.',
      );
    }
  }

  Future<Uint8List> _download(
    Uri initialUri, {
    required bool allowPrivateNetwork,
    required int byteLimit,
    required String resourceName,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 5)
      ..userAgent = 'KlipaPlayer/0.1';
    try {
      return await _get(
        client,
        initialUri,
        allowPrivateNetwork: allowPrivateNetwork,
        byteLimit: byteLimit,
        resourceName: resourceName,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<Uint8List> _get(
    HttpClient client,
    Uri initialUri, {
    required bool allowPrivateNetwork,
    required int byteLimit,
    required String resourceName,
  }) async {
    var uri = initialUri;
    for (var redirects = 0; redirects <= maxRedirects; redirects++) {
      await _networkPolicy.validateHttpTarget(
        uri,
        allowPrivateNetwork: allowPrivateNetwork,
      );

      final request = await client.getUrl(uri);
      request
        ..followRedirects = false
        ..maxRedirects = 0;
      final response = await request.close();

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
        final next = uri.resolve(location);
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

  bool _isRedirect(int statusCode) =>
      statusCode == HttpStatus.movedPermanently ||
      statusCode == HttpStatus.found ||
      statusCode == HttpStatus.seeOther ||
      statusCode == HttpStatus.temporaryRedirect ||
      statusCode == HttpStatus.permanentRedirect;
}
