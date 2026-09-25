import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'firebase_monitoring.dart';
import 'server_address_store.dart';
import 'token_store.dart';

class ApiClient {
  ApiClient({
    required this.tokenStore,
    this._accountId,
    http.Client? httpClient,
    this._requestTimeout = const Duration(seconds: 30),
  }) : _httpClient = httpClient ?? http.Client();

  final TokenStore tokenStore;
  final http.Client _httpClient;
  final Duration _requestTimeout;
  String? _accountId;
  Future<void>? _refreshing;

  /// The account this client's authenticated requests read/write tokens
  /// for. Null until a fresh connect/login response reveals it, or a
  /// restore/switch binds an already-known account up front.
  String? get accountId => _accountId;

  /// Binds this client to [accountId] — called once a connect/login
  /// response reveals a brand-new account's id, or immediately when
  /// restoring/activating an already-known one.
  void bindAccount(String accountId) => _accountId = accountId;

  String get _boundAccountId {
    final id = _accountId;
    if (id == null) {
      throw StateError(
        'ApiClient made an authenticated request before bindAccount().',
      );
    }
    return id;
  }

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

  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = true,
  }) => _jsonRequest('PUT', path, body: body, authenticated: authenticated);

  Future<Map<String, dynamic>> patchJson(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = true,
  }) => _jsonRequest('PATCH', path, body: body, authenticated: authenticated);

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

  Future<http.StreamedResponse> getStream(
    String path, {
    int? rangeStart,
    Future<void>? abortTrigger,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    final accountId = _boundAccountId;
    var token = await tokenStore.readAccessToken(accountId);
    for (var attempt = 0; attempt < 2; attempt++) {
      final uri = await _uri(path);
      final requestAbort = Completer<void>();
      abortTrigger?.then((_) {
        if (!requestAbort.isCompleted) requestAbort.complete();
      });
      final request = http.AbortableRequest(
        'GET',
        uri,
        abortTrigger: requestAbort.future,
      )..headers['accept'] = '*/*';
      if (token != null) request.headers['authorization'] = 'Bearer $token';
      if (rangeStart != null && rangeStart > 0) {
        request.headers['range'] = 'bytes=$rangeStart-';
      }
      late http.StreamedResponse response;
      try {
        response = await _httpClient.send(request).timeout(_requestTimeout);
      } on TimeoutException {
        if (!requestAbort.isCompleted) requestAbort.complete();
        throw const ApiException(
          status: 408,
          code: 'request_timeout',
          title: 'Request timed out',
        );
      } on http.ClientException {
        if (abortTrigger != null) throw http.RequestAbortedException(uri);
        throw const ApiException(
          status: 0,
          code: 'network_unavailable',
          title: 'Network unavailable',
        );
      }
      if (response.statusCode == 401 && attempt == 0) {
        await response.stream.listen((_) {}).cancel();
        final currentToken = await tokenStore.readAccessToken(accountId);
        if (currentToken == token) await _refreshOnce();
        token = await tokenStore.readAccessToken(accountId);
        continue;
      }
      if (response.statusCode >= 400) {
        final body = await response.stream.bytesToString();
        throw ApiException.fromResponse(response.statusCode, body);
      }
      return http.StreamedResponse(
        _withIdleTimeout(
          response.stream,
          requestAbort,
          totalBytes: response.contentLength,
          onProgress: onProgress,
        ),
        response.statusCode,
        contentLength: response.contentLength,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    }
    throw StateError('Unreachable');
  }

  Stream<List<int>> _withIdleTimeout(
    Stream<List<int>> source,
    Completer<void> abort, {
    int? totalBytes,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) {
    late StreamController<List<int>> controller;
    StreamSubscription<List<int>>? subscription;
    Timer? timer;
    var receivedBytes = 0;
    var done = false;
    void finishError(Object error, [StackTrace? stack]) {
      if (done) return;
      done = true;
      timer?.cancel();
      controller.addError(error, stack);
      unawaited(controller.close());
    }

    controller = StreamController<List<int>>(
      onListen: () {
        void arm() {
          timer?.cancel();
          timer = Timer(const Duration(seconds: 30), () {
            if (!abort.isCompleted) abort.complete();
            finishError(
              const ApiException(
                status: 408,
                code: 'request_timeout',
                title: 'Request timed out',
              ),
            );
          });
        }

        arm();
        subscription = source.listen(
          (chunk) {
            arm();
            receivedBytes += chunk.length;
            onProgress?.call(receivedBytes, totalBytes);
            controller.add(chunk);
          },
          onError: (Object error, StackTrace stack) =>
              finishError(error, stack),
          onDone: () {
            if (done) return;
            done = true;
            timer?.cancel();
            unawaited(controller.close());
          },
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () async {
        done = true;
        timer?.cancel();
        await subscription?.cancel();
      },
    );
    abort.future.then((_) {
      finishError(http.RequestAbortedException());
      unawaited(subscription?.cancel());
    });
    return controller.stream;
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
      // Prefer the server's Retry-After (seconds), capped so a bad value
      // can't stall the UI.
      final hinted = int.tryParse(response.headers['retry-after'] ?? '');
      await Future<void>.delayed(
        hinted == null
            ? delays[attempt]
            : Duration(seconds: hinted.clamp(1, 10)),
      );
      attempt++;
    }
  }

  Future<http.Response> _sendWithRefresh(
    Future<http.BaseRequest> Function() createRequest, {
    required bool authenticated,
  }) async {
    final sentToken = authenticated
        ? await tokenStore.readAccessToken(_boundAccountId)
        : null;
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

    final currentToken = await tokenStore.readAccessToken(_boundAccountId);
    if (currentToken == sentToken) await _refreshOnce();
    response = await _send(
      await createRequest(),
      accessToken: await tokenStore.readAccessToken(_boundAccountId),
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
    late final http.Response response;
    try {
      response = await FirebaseMonitoring.traceApiRequest(
        () async => http.Response.fromStream(
          await _httpClient.send(request).timeout(_requestTimeout),
        ).timeout(_requestTimeout),
      );
    } on TimeoutException {
      throw const ApiException(
        status: 408,
        code: 'request_timeout',
        title: 'Request timed out',
      );
    } on http.ClientException {
      throw const ApiException(
        status: 0,
        code: 'network_unavailable',
        title: 'Network unavailable',
      );
    }
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
    final accountId = _boundAccountId;
    final refreshToken = await tokenStore.readRefreshToken(accountId);
    if (refreshToken == null) {
      await tokenStore.clear(accountId);
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
        accountId: accountId,
        accessToken: tokens['accessToken'] as String,
        refreshToken: tokens['refreshToken'] as String,
      );
    } on ApiException catch (error) {
      if (error.code == 'invalid_refresh_token') {
        await tokenStore.clear(accountId);
      }
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
