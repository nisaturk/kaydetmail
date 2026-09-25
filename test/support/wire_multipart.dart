import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';

class WirePart {
  const WirePart({
    required this.field,
    required this.filename,
    required this.contentType,
    required this.bytes,
  });

  final String field;
  final String? filename;
  final String? contentType;
  final Uint8List bytes;

  String get text => utf8.decode(bytes);
}

class WireMultipart {
  WireMultipart._(this.method, this.url, this.headers, this.parts);

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final List<WirePart> parts;

  List<WirePart> get files => parts.where((p) => p.filename != null).toList();

  Map<String, String> get fields => {
    for (final part in parts)
      if (part.filename == null) part.field: part.text,
  };

  List<String> values(String field) => [
    for (final part in parts)
      if (part.filename == null && part.field == field) part.text,
  ];

  static Future<WireMultipart> decode(
    http.BaseRequest request,
    Stream<List<int>> body,
  ) async {
    final contentType = request.headers.entries
        .firstWhere((entry) => entry.key.toLowerCase() == 'content-type')
        .value;
    final boundary = RegExp(r'boundary="?([^";]+)"?')
        .firstMatch(contentType)!
        .group(1)!;
    final parts = <WirePart>[];
    await for (final part in MimeMultipartTransformer(boundary).bind(body)) {
      final disposition = part.headers['content-disposition']!;
      String? parameter(String name) =>
          RegExp('(?:^|;)\\s*$name="([^"]*)"')
              .firstMatch(disposition)
              ?.group(1);
      final bytes = await part.fold<BytesBuilder>(
        BytesBuilder(),
        (builder, chunk) => builder..add(chunk),
      );
      parts.add(
        WirePart(
          field: parameter('name')!,
          filename: parameter('filename'),
          contentType: part.headers['content-type'],
          bytes: bytes.takeBytes(),
        ),
      );
    }
    return WireMultipart._(request.method, request.url, request.headers, parts);
  }
}
