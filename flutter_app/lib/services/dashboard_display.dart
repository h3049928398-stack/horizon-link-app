import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class DashboardDisplay {
  static const channel = MethodChannel('horizon_link/dashboard_display');

  static Future<void> setAwake(bool awake) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      return;
    }
    try {
      await channel.invokeMethod<void>('setAwake', awake);
    } on MissingPluginException {
      // This runner has no screen-idle control.
    } on PlatformException catch (error) {
      debugPrint('Dashboard screen-idle control unavailable: ${error.code}');
    }
  }
}
