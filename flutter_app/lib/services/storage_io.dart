import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<File> _file() async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  return File('${dir.path}/horizon_link_v2.json');
}

Future<String?> readSaved() async {
  final file = await _file();
  return await file.exists() ? file.readAsString() : null;
}

Future<void> writeSaved(String value) async {
  final file = await _file();
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(value, flush: true);
  // Same-directory rename keeps a completed JSON file on interruption.
  if (Platform.isWindows && await file.exists()) await file.delete();
  await temporary.rename(file.path);
}

Future<File> _consentFile() async => File(
  '${(await getApplicationSupportDirectory()).path}/privacy_consent.txt',
);
Future<String?> readConsent() async {
  final file = await _consentFile();
  return await file.exists() ? file.readAsString() : null;
}

Future<void> writeConsent(String value) async {
  final file = await _consentFile();
  await file.parent.create(recursive: true);
  final temp = File('${file.path}.tmp');
  await temp.writeAsString(value, flush: true);
  if (Platform.isWindows && await file.exists()) await file.delete();
  await temp.rename(file.path);
}
