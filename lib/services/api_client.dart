import 'dart:convert';
import 'dart:async';
import 'dart:math';
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
    Map<String, String> headers = const {},
    bool authenticated = true,
  }) => _jsonRequest(
    'POST',
    path,
    body: body,
    headers: headers,
    authenticated: authenticated,
  );

  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> body, {
    Map<String, String> headers = const {},
    bool authenticated = true,
  }) => _jsonRequest(
    'PUT',
    path,
    body: body,
    headers: headers,
    authenticated: authenticated,
  );

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
    List<http.MultipartFile> Function()? files,
    Map<String, String> headers = const {},
    void Function(int sent, int total)? onProgress,
    Future<void>? abortTrigger,
  }) => _multipart(
    'POST',
    path,
    fields: fields,
    files: files,
    headers: headers,
    onProgress: onProgress,
    abortTrigger: abortTrigger,
  );

  /// Same as [multipart] but with the PUT method — `PUT /api/drafts/{id}`
  /// replaces a draft server-side.
  Future<Map<String, dynamic>> multipartPut(
    String path, {
    required Map<String, String> fields,
    List<http.MultipartFile> Function()? files,
    Map<String, String> headers = const {},
    void Function(int sent, int total)? onProgress,
    Future<void>? abortTrigger,
  }) => _multipart(
    'PUT',
    path,
    fields: fields,
    files: files,
    headers: headers,
    onProgress: onProgress,
    abortTrigger: abortTrigger,
  );

  Future<Map<String, dynamic>> _multipart(
    String method,
    String path, {
    required Map<String, String> fields,
    required List<http.MultipartFile> Function()? files,
    required Map<String, String> headers,
    required void Function(int sent, int total)? onProgress,
    required Future<void>? abortTrigger,
  }) async {
    final response = await _sendWithRefresh(() async {
      final request = _UploadMultipartRequest(
        method,
        await _uri(path),
        onProgress: onProgress,
        cancelTrigger: abortTrigger,
      );
      request.fields.addAll(fields);
      if (files != null) request.files.addAll(files());
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
    Map<String, String> headers = const {},
    required bool authenticated,
  }) async {
    final response = await _sendWithRefresh(() async {
      final request = http.Request(method, await _uri(path));
      if (body != null) {
        request.headers['content-type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      request.headers.addAll(headers);
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
        () async => request is _UploadMultipartRequest
            ? _sendUpload(request)
            : http.Response.fromStream(
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

  static const int _uploadChunkBytes = 64 * 1024;

  Future<http.Response> _sendUpload(_UploadMultipartRequest multipart) async {
    final total = multipart.contentLength;
    final body = multipart.finalize();
    final abort = Completer<void>();
    var sent = 0;
    var cancelled = false;
    var timedOut = false;
    Timer? idle;
    void stop({required bool timeout}) {
      if (abort.isCompleted) return;
      timedOut = timeout;
      cancelled = !timeout;
      abort.complete();
    }

    void armIdle() {
      idle?.cancel();
      idle = Timer(_requestTimeout, () => stop(timeout: true));
    }

    multipart.cancelTrigger?.whenComplete(() {
      if (sent < total) stop(timeout: false);
    }).ignore();

    Stream<List<int>> counted() async* {
      multipart.onProgress?.call(0, total);
      await for (final chunk in body) {
        var offset = 0;
        while (offset < chunk.length) {
          if (abort.isCompleted) {
            throw http.RequestAbortedException(multipart.url);
          }
          final end = min(offset + _uploadChunkBytes, chunk.length);
          yield chunk is Uint8List
              ? Uint8List.sublistView(chunk, offset, end)
              : chunk.sublist(offset, end);
          sent += end - offset;
          offset = end;
          armIdle();
          multipart.onProgress?.call(sent, total);
        }
      }
    }

    final request = _UploadStreamRequest(
      multipart.method,
      multipart.url,
      counted(),
      abortTrigger: abort.future,
    )..contentLength = total;
    request.headers.addAll(multipart.headers);
    armIdle();
    try {
      final streamed = await Future.any([
        _httpClient.send(request),
        abort.future.then<http.StreamedResponse>(
          (_) => throw http.RequestAbortedException(multipart.url),
        ),
      ]);
      idle?.cancel();
      return await http.Response.fromStream(streamed).timeout(_requestTimeout);
    } catch (_) {
      if (cancelled) {
        throw const ApiException(
          status: 0,
          code: 'upload_cancelled',
          title: 'Upload cancelled',
        );
      }
      if (timedOut) throw TimeoutException('Upload stalled', _requestTimeout);
      rethrow;
    } finally {
      idle?.cancel();
    }
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

class _UploadMultipartRequest extends http.MultipartRequest {
  _UploadMultipartRequest(
    super.method,
    super.url, {
    this.onProgress,
    this.cancelTrigger,
  });

  final void Function(int sent, int total)? onProgress;
  final Future<void>? cancelTrigger;
}

class _UploadStreamRequest extends http.BaseRequest with http.Abortable {
  _UploadStreamRequest(
    super.method,
    super.url,
    this._body, {
    this.abortTrigger,
  });

  final Stream<List<int>> _body;

  @override
  final Future<void>? abortTrigger;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_body);
  }
}
