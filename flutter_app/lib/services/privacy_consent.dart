import 'package:flutter/foundation.dart';

import 'storage.dart' as storage;
import 'release_info.dart';

class PrivacyConsent extends ChangeNotifier {
  PrivacyConsent({
    this.read = storage.readConsent,
    this.write = storage.writeConsent,
  });
  final Future<String?> Function() read;
  final Future<void> Function(String) write;
  bool loaded = false, accepted = false;

  Future<void> load() async {
    try {
      accepted = await read() == ReleaseInfo.policyVersion;
    } catch (_) {
      accepted = false;
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> accept() async {
    await write(ReleaseInfo.policyVersion);
    accepted = true;
    notifyListeners();
  }

  Future<void> revoke() async {
    // Persist first: a failed write must not falsely report a withdrawal.
    await write('');
    accepted = false;
    notifyListeners();
  }
}
