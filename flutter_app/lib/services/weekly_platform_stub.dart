Future<String?> readWeeklyCache() async => null;
void cancelWeeklyRequests() {}
Future<void> writeWeeklyCache(String value) async {}
Future<String> fetchWeekly(Uri uri) async =>
    throw UnsupportedError('HTTP unavailable');
