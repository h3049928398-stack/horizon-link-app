import 'dart:convert';
import 'dart:io';

Future<(int, String)> postFeedback(Uri uri, String body) async {
  const responseLimit = 2048;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    return await (() async {
      final request = await client.postUrl(uri);
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final payload = utf8.encode(body);
      request.contentLength = payload.length;
      request.add(payload);
      final response = await request.close();
      final status = response.statusCode;
      if (status != HttpStatus.ok && status != HttpStatus.created) {
        return (status, '');
      }
      if (response.headers.contentType?.mimeType != 'application/json' ||
          response.contentLength > responseLimit) {
        throw const HttpException('Invalid feedback receipt');
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        if (bytes.length + chunk.length > responseLimit) {
          throw const HttpException('Feedback receipt too large');
        }
        bytes.addAll(chunk);
      }
      return (status, utf8.decode(bytes));
    })().timeout(const Duration(seconds: 12));
  } finally {
    client.close(force: true);
  }
}
