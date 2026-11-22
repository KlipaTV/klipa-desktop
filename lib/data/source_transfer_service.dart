import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/network_policy.dart';

final sourceTransferServiceProvider =
    Provider<SourceTransferService Function()>(
      (ref) => SourceTransferService.new,
    );

/// The receiver's claim token stays in memory for this transfer.
class SourceTransferSlot {
  SourceTransferSlot(this.code, this._claimToken, this._ttl);

  final String code;
  final String _claimToken;
  final Duration _ttl;
  final Stopwatch _age = Stopwatch()..start();
}

class ReceivedSource {
  const ReceivedSource(this.address, {this.xtreamLogin});

  final Uri address;
  final ({String username, String password})? xtreamLogin;
}

class SourceTransferException implements Exception {
  const SourceTransferException(this.message);

  final String message;
}

/// A short-lived connection to Klipa's existing one-use playlist relay.
class SourceTransferService {
  SourceTransferService({@visibleForTesting Uri? endpoint})
    : _endpoint = endpoint ?? Uri.https('klipa.tv');

  static const _maxBytes = 64 * 1024;
  static const _expired = SourceTransferException(
    'The code expired. Generate a new code and try again.',
  );
  static const _unavailable = SourceTransferException(
    'The transfer service is unavailable. Try again in a moment.',
  );
  static const _invalidSource = SourceTransferException(
    'The sender did not provide a supported M3U URL or Xtream login.',
  );

  final Uri _endpoint;
  final _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 5);

  Future<SourceTransferSlot> createSlot() async {
    final (_, body) = await _request(
      'POST',
      _endpoint.replace(path: '/pair/new'),
      headers: const {'X-Klipa-Require-Claim-Token': '1'},
      expectedStatus: HttpStatus.created,
      timeout: const Duration(seconds: 10),
    );
    if (body
        case {
          'code': final String code,
          'claimToken': final String token,
          'claimTokenRequired': true,
          'ttlSeconds': final int ttl,
        }
        when RegExp(r'^\d{3}-\d{3}$').hasMatch(code) &&
            RegExp(r'^[A-Za-z0-9_-]{32}$').hasMatch(token) &&
            ttl > 0 &&
            ttl <= 300) {
      return SourceTransferSlot(code, token, Duration(seconds: ttl));
    }
    throw _unavailable;
  }

  Future<ReceivedSource> waitForSource(SourceTransferSlot slot) async {
    final uri = _endpoint.replace(
      path: '/pair/claim',
      queryParameters: {'code': slot.code},
    );
    while (slot._age.elapsed < slot._ttl) {
      final (status, body) = await _request(
        'GET',
        uri,
        headers: {'X-Klipa-Claim-Token': slot._claimToken},
        expectedStatus: HttpStatus.ok,
        allowEmpty: true,
        timeout: const Duration(seconds: 35),
      );
      if (status == HttpStatus.ok) return _parseSource(body);
      if (slot._age.elapsed < slot._ttl) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    throw _expired;
  }

  ReceivedSource _parseSource(Object? body) {
    final payload = switch (body) {
      {'payload': final Map<Object?, Object?> payload} => payload,
      _ => throw _invalidSource,
    };
    if (payload case {'kind': 'm3u', 'url': final String url}) {
      final headers = payload['headers'];
      if (headers != null && (headers is! Map || headers.isNotEmpty)) {
        throw const SourceTransferException(
          'This playlist uses custom request headers. Klipa Player cannot '
          'import it from your phone.',
        );
      }
      return ReceivedSource(_parseAddress(url));
    }
    if (payload case {
      'kind': 'xtream',
      'server': final String server,
      'username': final String username,
      'password': final String password,
    } when username.trim().isNotEmpty && password.isNotEmpty) {
      final address = _parseAddress(server);
      return ReceivedSource(
        address,
        xtreamLogin: (username: username, password: password),
      );
    }
    throw _invalidSource;
  }

  Uri _parseAddress(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) throw _invalidSource;
    try {
      const NetworkPolicy().validateHttpUriShape(uri);
    } on NetworkPolicyException {
      throw _invalidSource;
    }
    return uri;
  }

  Future<(int, Object?)> _request(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    required int expectedStatus,
    required Duration timeout,
    bool allowEmpty = false,
  }) async {
    Future<(int, Object?)> send() async {
      final request = await _client.openUrl(method, uri);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      headers.forEach(request.headers.set);
      final response = await request.close();
      final status = response.statusCode;
      if (allowEmpty && status == HttpStatus.noContent) return (status, null);
      if (allowEmpty &&
          (status == HttpStatus.notFound || status == HttpStatus.gone)) {
        throw _expired;
      }
      if (status == HttpStatus.tooManyRequests) {
        throw const SourceTransferException(
          'Too many attempts. Wait a minute, then generate a new code.',
        );
      }
      if (status != expectedStatus || response.contentLength > _maxBytes) {
        throw _unavailable;
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        if (bytes.length + chunk.length > _maxBytes) throw _unavailable;
        bytes.add(chunk);
      }
      return (status, jsonDecode(utf8.decode(bytes.takeBytes())));
    }

    try {
      return await send().timeout(timeout);
    } on SourceTransferException {
      rethrow;
    } catch (_) {
      throw _unavailable;
    }
  }

  void close() => _client.close(force: true);
}
