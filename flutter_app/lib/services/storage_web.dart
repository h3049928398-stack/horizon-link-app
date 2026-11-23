import 'package:web/web.dart' as web;

Future<String?> readSaved() async =>
    web.window.localStorage.getItem('horizon-link-flutter-v2');
Future<void> writeSaved(String value) async =>
    web.window.localStorage.setItem('horizon-link-flutter-v2', value);

Future<String?> readConsent() async =>
    web.window.localStorage.getItem('horizon-link-consent');
Future<void> writeConsent(String value) async =>
    web.window.localStorage.setItem('horizon-link-consent', value);
