import 'package:flutter/painting.dart';

/// Small per-canvas LRU: changing telemetry cannot grow native paragraphs
/// indefinitely. The owning canvas clears it when fonts change or it disposes.
class DashboardTextCache {
  DashboardTextCache({this.capacity = 256}) : assert(capacity > 0);
  final int capacity;
  final _entries =
      <(String, TextStyle, int, TextAlign, double, String?), TextPainter>{};

  TextPainter layout(
    String text,
    TextStyle style, {
    int maxLines = 1,
    TextAlign align = TextAlign.left,
    double maxWidth = double.infinity,
    String? ellipsis,
  }) {
    final key = (text, style, maxLines, align, maxWidth, ellipsis);
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached;
      return cached;
    }
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      textAlign: align,
      ellipsis: ellipsis,
    )..layout(maxWidth: maxWidth);
    if (_entries.length == capacity) {
      _entries.remove(_entries.keys.first)!.dispose();
    }
    _entries[key] = painter;
    return painter;
  }

  void clear() {
    for (final painter in _entries.values) {
      painter.dispose();
    }
    _entries.clear();
  }
}
