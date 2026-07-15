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

class BoundedHttpClient {
  BoundedHttpClient({NetworkPolicy networkPolicy = const NetworkPolicy()})
    : _networkPolicy = networkPolicy;

  static const int maxBytes = 25 * 1024 * 1024;
  static const int maxRedirects = 5;
  static const Duration totalTimeout = Duration(seconds: 60);

  final NetworkPolicy _networkPolicy;

  Future<Uint8List> getPlaylist(
    Uri initialUri, {
    required bool allowPrivateNetwork,
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
      ).timeout(totalTimeout);
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
    } finally {
      client.close(force: true);
    }
  }

  Future<Uint8List> _get(
    HttpClient client,
    Uri initialUri, {
    required bool allowPrivateNetwork,
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
          throw const PlaylistDownloadException(
            'The playlist redirected too many times.',
          );
        }
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null) {
          throw const PlaylistDownloadException(
            'The server returned an invalid redirect.',
          );
        }
        final next = uri.resolve(location);
        if (uri.scheme == 'https' && next.scheme != 'https') {
          throw const PlaylistDownloadException(
            'A secure playlist cannot redirect to an insecure address.',
          );
        }
        uri = next;
        continue;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw PlaylistDownloadException(
          'The playlist server returned HTTP ${response.statusCode}.',
        );
      }
      final declaredLength = response.contentLength;
      if (declaredLength > maxBytes) {
        await response.drain<void>();
        throw const PlaylistDownloadException(
          'The playlist exceeds the 25 MiB limit.',
        );
      }
      final contentType = response.headers.contentType?.mimeType.toLowerCase();
      if (contentType == 'text/html' ||
          contentType == 'application/xhtml+xml') {
        await response.drain<void>();
        throw const PlaylistDownloadException(
          'The address returned a web page instead of a playlist.',
        );
      }

      final builder = BytesBuilder(copy: false);
      var count = 0;
      await for (final chunk in response) {
        count += chunk.length;
        if (count > maxBytes) {
          throw const PlaylistDownloadException(
            'The playlist exceeds the 25 MiB limit.',
          );
        }
        builder.add(chunk);
      }
      return builder.takeBytes();
    }
    throw const PlaylistDownloadException(
      'The playlist could not be downloaded.',
    );
  }

  bool _isRedirect(int statusCode) =>
      statusCode == HttpStatus.movedPermanently ||
      statusCode == HttpStatus.found ||
      statusCode == HttpStatus.seeOther ||
      statusCode == HttpStatus.temporaryRedirect ||
      statusCode == HttpStatus.permanentRedirect;
}
