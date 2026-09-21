import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'server_address_store.dart';
import 'token_store.dart';

class ApiClient {
  ApiClient({required this.tokenStore, http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final TokenStore tokenStore;
  final http.Client _httpClient;
  Future<void>? _refreshing;

  Future<Map<String, dynamic>> get(String path, {bool authenticated = true}) =>
      _jsonRequest('GET', path, authenticated: authenticated);

  Future<List<dynamic>> getList(
    String path, {
    bool authenticated = true,
  }) async {
    final response = await _sendWithRefresh(
      () async => http.Request('GET', await _uri(path)),
      authenticated: authenticated,
    );
    if (response.body.isEmpty) return const [];
    final decoded = jsonDecode(response.body);
    // Tolerate the `{ items: [...] }` envelope some endpoints use.
    if (decoded is Map<String, dynamic>) return decoded['items'] as List;
    return decoded as List<dynamic>;
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = true,
  }) => _jsonRequest('POST', path, body: body, authenticated: authenticated);

  Future<void> post(String path, {bool authenticated = true}) async {
    await _sendWithRefresh(
      () async => http.Request('POST', await _uri(path)),
      authenticated: authenticated,
    );
  }

  Future<void> delete(String path, {bool authenticated = true}) async {
    await _sendWithRefresh(
      () async => http.Request('DELETE', await _uri(path)),
      authenticated: authenticated,
    );
  }

  Future<Uint8List> getBytes(String path) async {
    final response = await _sendWithRefresh(
      () async => http.Request('GET', await _uri(path)),
      authenticated: true,
    );
    return response.bodyBytes;
  }

  Future<Map<String, dynamic>> multipart(
    String path, {
    required Map<String, String> fields,
    List<http.MultipartFile> files = const [],
    Map<String, String> headers = const {},
  }) async {
    final response = await _sendWithRefresh(() async {
      final request = http.MultipartRequest('POST', await _uri(path));
      request.fields.addAll(fields);
      request.files.addAll(files);
      request.headers.addAll(headers);
      return request;
    }, authenticated: true);
    return _decodeObject(response.body);
  }

  /// Same as [multipart] but with the PUT method — `PUT /api/drafts/{id}`
  /// replaces a draft server-side.
  Future<Map<String, dynamic>> multipartPut(
    String path, {
    required Map<String, String> fields,
    List<http.MultipartFile> files = const [],
    Map<String, String> headers = const {},
  }) async {
    final response = await _sendWithRefresh(() async {
      final request = http.MultipartRequest('PUT', await _uri(path));
      request.fields.addAll(fields);
      request.files.addAll(files);
      request.headers.addAll(headers);
      return request;
    }, authenticated: true);
    return _decodeObject(response.body);
  }

  /// Bodiless POST with extra headers — used by endpoints that require e.g.
  /// an `Idempotency-Key` without a JSON body.
  Future<Map<String, dynamic>> postWithHeaders(
    String path,
    Map<String, String> headers, {
    bool authenticated = true,
  }) async {
    final response = await _sendWithRefresh(() async {
      final request = http.Request('POST', await _uri(path));
      request.headers.addAll(headers);
      return request;
    }, authenticated: authenticated);
    return _decodeObject(response.body);
  }

  Future<Map<String, dynamic>> _jsonRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
    required bool authenticated,
  }) async {
    final response = await _sendWithRefresh(() async {
      final request = http.Request(method, await _uri(path));
      if (body != null) {
        request.headers['content-type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      return request;
    }, authenticated: authenticated);
    return _decodeObject(response.body);
  }

  /// Short exponential backoff for the documented rate limit (`429` is
  /// bodiless): only idempotent GETs retry automatically, max 3 attempts.
  Future<http.Response> _sendIdempotent(
    Future<http.BaseRequest> Function() createRequest, {
    required String? accessToken,
  }) async {
    const delays = [Duration(seconds: 1), Duration(seconds: 2)];
    var attempt = 0;
    while (true) {
      final response = await _send(
        await createRequest(),
        accessToken: accessToken,
        throwErrors: false,
      );
      if (response.statusCode != 429 || attempt >= delays.length) {
        return response;
      }
      await Future<void>.delayed(delays[attempt]);
      attempt++;
    }
  }

  Future<http.Response> _sendWithRefresh(
    Future<http.BaseRequest> Function() createRequest, {
    required bool authenticated,
  }) async {
    final sentToken = authenticated ? await tokenStore.readAccessToken() : null;
    // Peek at the method to decide about 429 retries — MultipartRequests
    // report POST/PUT, plain Requests report their own method.
    final probe = await createRequest();
    final isGet = probe.method == 'GET';
    Future<http.Response> sendOnce(String? token) async => isGet
        ? _sendIdempotent(createRequest, accessToken: token)
        : _send(await createRequest(), accessToken: token, throwErrors: false);
    var response = await sendOnce(sentToken);
    if (!authenticated || response.statusCode != 401) {
      if (response.statusCode >= 400) {
        throw ApiException.fromResponse(response.statusCode, response.body);
      }
      return response;
    }

    final currentToken = await tokenStore.readAccessToken();
    if (currentToken == sentToken) await _refreshOnce();
    response = await _send(
      await createRequest(),
      accessToken: await tokenStore.readAccessToken(),
    );
    return response;
  }

  Future<http.Response> _send(
    http.BaseRequest request, {
    String? accessToken,
    bool throwErrors = true,
  }) async {
    request.headers['accept'] = 'application/json';
    if (accessToken != null) {
      request.headers['authorization'] = 'Bearer $accessToken';
    }
    final response = await http.Response.fromStream(
      await _httpClient.send(request),
    );
    if (throwErrors && response.statusCode >= 400) {
      throw ApiException.fromResponse(response.statusCode, response.body);
    }
    return response;
  }

  Future<void> _refreshOnce() {
    final existing = _refreshing;
    if (existing != null) return existing;
    final refresh = _refresh();
    _refreshing = refresh;
    return refresh.whenComplete(() {
      if (identical(_refreshing, refresh)) _refreshing = null;
    });
  }

  Future<void> _refresh() async {
    final refreshToken = await tokenStore.readRefreshToken();
    if (refreshToken == null) {
      await tokenStore.clear();
      throw const ApiException(
        status: 401,
        code: 'invalid_refresh_token',
        title: 'Missing refresh token',
      );
    }
    try {
      final request = http.Request('POST', await _uri('/api/auth/refresh'))
        ..headers['content-type'] = 'application/json'
        ..body = jsonEncode({'refreshToken': refreshToken});
      final response = await _send(request);
      final tokens = _decodeObject(response.body);
      await tokenStore.save(
        accessToken: tokens['accessToken'] as String,
        refreshToken: tokens['refreshToken'] as String,
        mailAccountId: tokens['mailAccountId'] as String,
      );
    } on ApiException catch (error) {
      if (error.code == 'invalid_refresh_token') await tokenStore.clear();
      rethrow;
    }
  }

  Future<Uri> _uri(String path) async {
    final base = ServerAddressStore.normalize(await ServerAddressStore.load());
    return Uri.parse('$base/${path.replaceFirst(RegExp(r'^/+'), '')}');
  }

  Map<String, dynamic> _decodeObject(String body) {
    if (body.isEmpty) return const {};
    return jsonDecode(body) as Map<String, dynamic>;
  }

  void close() => _httpClient.close();
}
