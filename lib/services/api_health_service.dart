import 'package:http/http.dart' as http;

import 'server_address_store.dart';

/// Checks whether the configured API and its required dependencies are ready.
class ApiHealthService {
  ApiHealthService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Future<bool> isReady(String baseUrl) async {
    final normalized = ServerAddressStore.normalize(baseUrl);
    final response = await _httpClient
        .get(Uri.parse('$normalized/health/ready'))
        .timeout(const Duration(seconds: 5));
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  void close() => _httpClient.close();
}
