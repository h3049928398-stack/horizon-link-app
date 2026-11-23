enum WebNavigation { internal, external, blocked }

bool _isXiaoheiheHost(String? host) =>
    host == 'xiaoheihe.cn' || (host?.endsWith('.xiaoheihe.cn') ?? false);

/// Optional root-level weekly guide override. Preserve query/escaping verbatim.
String? parseWeeklyGuideUrl(dynamic value) {
  if (value == null) return null;
  if (value is! String ||
      value.isEmpty ||
      value.length > 4096 ||
      RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(value)) {
    throw const FormatException('Invalid weekly guide URL');
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      !uri.hasAuthority ||
      !_isXiaoheiheHost(uri.host.toLowerCase()) ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443 ||
      uri.hasFragment) {
    throw const FormatException('Weekly guide must use Xiaoheihe HTTPS');
  }
  return value;
}

WebNavigation guideNavigation(String initialUrl, String targetUrl) {
  final initial = Uri.tryParse(initialUrl), target = Uri.tryParse(targetUrl);
  if (target == null ||
      target.scheme != 'https' ||
      target.host.isEmpty ||
      target.userInfo.isNotEmpty ||
      target.port != 443) {
    return WebNavigation.blocked;
  }
  final host = target.host.toLowerCase();
  final original = initial?.host.toLowerCase();
  if (host == original ||
      (_isXiaoheiheHost(original) && _isXiaoheiheHost(host)) ||
      ((original == 'forza.net' || original == 'www.forza.net') &&
          (host == 'forza.net' || host.endsWith('.forza.net')))) {
    return WebNavigation.internal;
  }
  return WebNavigation.external;
}
