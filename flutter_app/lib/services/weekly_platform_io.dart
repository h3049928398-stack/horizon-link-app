import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/weekly_content.dart';

final _activeClients = <HttpClient>{};
void cancelWeeklyRequests() {
  for (final client in _activeClients.toList()) {
    client.close(force: true);
  }
  _activeClients.clear();
}

Future<File> _file() async {
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  return File('${directory.path}/horizon_link_weekly_v1.json');
}

Future<String?> readWeeklyCache() async {
  final file = await _file();
  return await file.exists() ? file.readAsString() : null;
}

Future<void> writeWeeklyCache(String value) async {
  final file = await _file();
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(value, flush: true);
  if (Platform.isWindows && await file.exists()) await file.delete();
  await temporary.rename(file.path);
}

Future<String> fetchWeekly(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  _activeClients.add(client);
  try {
    return await (() async {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close();
      if (response.statusCode != 200 ||
          response.contentLength > weeklyMaxBytes) {
        throw const HttpException('Invalid weekly response');
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        if (bytes.length + chunk.length > weeklyMaxBytes) {
          throw const HttpException('Weekly response too large');
        }
        bytes.addAll(chunk);
      }
      return utf8.decode(bytes);
    })().timeout(const Duration(seconds: 15));
  } finally {
    _activeClients.remove(client);
    client.close(force: true);
  }
}
