import 'package:flutter/services.dart';

/// Public release metadata only. Signing secrets never enter Dart defines.
abstract final class ReleaseInfo {
  static const developer = String.fromEnvironment('DEVELOPER_NAME');
  static const email = String.fromEnvironment('CONTACT_EMAIL');
  static const policyUrl = String.fromEnvironment('PRIVACY_POLICY_URL');
  static const effectiveDate = String.fromEnvironment('PRIVACY_EFFECTIVE_DATE');
  static const filing = String.fromEnvironment('APP_FILING_NUMBER');
  static const policyVersion = '2026-11-23.1';
  static const channel = MethodChannel('horizon_link/documents');

  static Future<String> installedVersion() async {
    try {
      return await channel.invokeMethod<String>('version') ?? '—';
    } on MissingPluginException {
      return '—';
    } on PlatformException {
      return '—';
    }
  }
}
