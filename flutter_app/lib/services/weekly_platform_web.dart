import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../core/weekly_content.dart';

final _activeRequests = <web.AbortController>{};
void cancelWeeklyRequests() {
  for (final request in _activeRequests.toList()) {
    request.abort();
  }
  _activeRequests.clear();
}

Future<String?> readWeeklyCache() async =>
    web.window.localStorage.getItem('horizon-link-weekly-v1');
Future<void> writeWeeklyCache(String value) async =>
    web.window.localStorage.setItem('horizon-link-weekly-v1', value);
Future<String> fetchWeekly(Uri uri) async {
  final abort = web.AbortController();
  _activeRequests.add(abort);
  final timer = Timer(const Duration(seconds: 15), () => abort.abort());
  try {
    final response = await web.window
        .fetch(
          uri.toString().toJS,
          web.RequestInit(
            cache: 'no-cache',
            redirect: 'error',
            signal: abort.signal,
          ),
        )
        .toDart;
    if (response.status != 200) throw StateError('Invalid weekly response');
    final reader =
        response.body?.getReader() as web.ReadableStreamDefaultReader?;
    if (reader == null) throw StateError('Empty response');
    final bytes = <int>[];
    while (true) {
      final chunk = await reader.read().toDart;
      if (chunk.done) break;
      final data = (chunk.value as JSUint8Array).toDart;
      if (bytes.length + data.length > weeklyMaxBytes) {
        await reader.cancel().toDart;
        throw StateError('Weekly response too large');
      }
      bytes.addAll(data);
    }
    return utf8.decode(bytes);
  } finally {
    _activeRequests.remove(abort);
    timer.cancel();
  }
}
