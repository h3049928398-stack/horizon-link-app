import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Uses the Android system's text Toast; no Flutter overlay or dependency.
abstract final class DashboardHint {
  static const channel = MethodChannel('horizon_link/dashboard');
  static VoidCallback? _onHidden;

  static Future<void> show(String text, {VoidCallback? onHidden}) {
    _onHidden = onHidden;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'fullscreenHintHidden') {
        // A cancelled older Toast can finish hiding after a newer one is shown.
        // Keep the active callback until cancel(), so its actual dismissal
        // still redraws the dashboard as well.
        _onHidden?.call();
      }
    });
    return _invoke('showFullscreenHint', {'text': text});
  }

  static Future<void> cancel() {
    _onHidden = null;
    return _invoke('cancelFullscreenHint');
  }

  static Future<void> _invoke(
    String method, [
    Map<String, Object>? arguments,
  ]) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Other hosts and widget tests have no Android Toast implementation.
    } on PlatformException catch (error) {
      debugPrint('Dashboard Toast unavailable: ${error.code}');
    }
  }
}
