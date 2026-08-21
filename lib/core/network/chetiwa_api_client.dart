import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'installation_id_provider.dart';

final class ChetiwaApiException implements Exception {
  const ChetiwaApiException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  final String code;
  final String message;
  final int? statusCode;

  bool get isNetworkFailure => statusCode == null;

  @override
  String toString() => '$code: $message';
}

final class ChetiwaApiClient {
  ChetiwaApiClient({
    required Uri baseUri,
    required http.Client client,
    InstallationIdProvider installationIdProvider =
        const InstallationIdProvider(),
  }) : _baseUri = baseUri,
       _client = client,
       _installationIdProvider = installationIdProvider;

  final Uri _baseUri;
  final http.Client _client;
  final InstallationIdProvider _installationIdProvider;
  final Map<Uri, _CachedApiBody> _responseCache = {};

  Future<Map<String, dynamic>> getData(
    String path, {
    Map<String, String> query = const {},
  }) async {
    final uri = _baseUri.resolve(path).replace(queryParameters: query);
    final cached = _responseCache[uri];
    try {
      final installationId = await _installationIdProvider.getOrCreate();
      final response = await _client
          .get(
            uri,
            headers: <String, String>{
              'accept': 'application/json',
              'x-chetiwa-device-id': installationId,
              if (cached != null) 'if-none-match': cached.etag,
            },
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 304 && cached != null) {
        return _decodeData(cached.body);
      }
      if (response.statusCode != 200) {
        throw _exceptionFromResponse(response);
      }
      final etag = response.headers['etag'];
      if (etag != null && etag.isNotEmpty) {
        _writeCache(uri, _CachedApiBody(etag: etag, body: response.body));
      }
      return _decodeData(response.body);
    } on ChetiwaApiException {
      rethrow;
    } on TimeoutException {
      throw const ChetiwaApiException(
        code: 'network_timeout',
        message: 'Le service météo met trop de temps à répondre.',
      );
    } on http.ClientException {
      throw const ChetiwaApiException(
        code: 'network_unavailable',
        message: 'Le service météo est inaccessible.',
      );
    } on FormatException {
      throw const ChetiwaApiException(
        code: 'invalid_response',
        message: 'Le service météo a renvoyé une réponse invalide.',
        statusCode: 502,
      );
    }
  }

  Future<Map<String, dynamic>> postData(
    String path,
    Map<String, Object?> body,
  ) => _writeData('POST', path, body);

  Future<Map<String, dynamic>> patchData(
    String path,
    Map<String, Object?> body,
  ) => _writeData('PATCH', path, body);

  Future<void> delete(String path) async {
    await _requestWithoutCache('DELETE', path);
  }

  Future<Map<String, dynamic>> _writeData(
    String method,
    String path,
    Map<String, Object?> body,
  ) async {
    final response = await _requestWithoutCache(
      method,
      path,
      body: jsonEncode(body),
    );
    return _decodeData(response.body);
  }

  Future<http.Response> _requestWithoutCache(
    String method,
    String path, {
    String? body,
  }) async {
    final uri = _baseUri.resolve(path);
    try {
      final installationId = await _installationIdProvider.getOrCreate();
      final request = http.Request(method, uri)
        ..headers.addAll(<String, String>{
          'accept': 'application/json',
          'x-chetiwa-device-id': installationId,
          if (body != null) 'content-type': 'application/json',
        });
      if (body != null) request.body = body;
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 15));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _exceptionFromResponse(response);
      }
      return response;
    } on ChetiwaApiException {
      rethrow;
    } on TimeoutException {
      throw const ChetiwaApiException(
        code: 'network_timeout',
        message: 'Le service météo met trop de temps à répondre.',
      );
    } on http.ClientException {
      throw const ChetiwaApiException(
        code: 'network_unavailable',
        message: 'Le service météo est inaccessible.',
      );
    } on FormatException {
      throw const ChetiwaApiException(
        code: 'invalid_response',
        message: 'Le service météo a renvoyé une réponse invalide.',
        statusCode: 502,
      );
    }
  }

  Map<String, dynamic> _decodeData(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected a JSON object');
    }
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Expected a data object');
    }
    return data;
  }

  ChetiwaApiException _exceptionFromResponse(http.Response response) {
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final error = decoded['error'] as Map<String, dynamic>;
      return ChetiwaApiException(
        code: error['code'] as String? ?? 'api_error',
        message: error['message'] as String? ?? 'Service météo indisponible.',
        statusCode: response.statusCode,
      );
    } on Object {
      return ChetiwaApiException(
        code: 'http_${response.statusCode}',
        message: 'Service météo indisponible (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
  }

  void _writeCache(Uri uri, _CachedApiBody value) {
    _responseCache.remove(uri);
    while (_responseCache.length >= 32) {
      _responseCache.remove(_responseCache.keys.first);
    }
    _responseCache[uri] = value;
  }
}

final class _CachedApiBody {
  const _CachedApiBody({required this.etag, required this.body});

  final String etag;
  final String body;
}
