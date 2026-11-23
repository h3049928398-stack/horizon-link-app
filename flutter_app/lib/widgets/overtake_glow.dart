import 'package:flutter/material.dart';

import 'dash_canvas.dart' show raceYellow;

/// A bright rim light. Only the narrow edge strips are painted, leaving the
/// instrument area fully transparent even at peak opacity.
class OvertakeGlow extends StatefulWidget {
  final bool active;

  const OvertakeGlow({super.key, required this.active});

  @override
  State<OvertakeGlow> createState() => _OvertakeGlowState();
}

class _OvertakeGlowState extends State<OvertakeGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _brightness;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 1,
    );
    _brightness = Tween<double>(begin: .18, end: 1).animate(_pulse);
    if (widget.active) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(OvertakeGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _pulse.value = 1;
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedOpacity(
      opacity: widget.active ? 1 : 0,
      duration: const Duration(milliseconds: 240),
      child: FadeTransition(
        key: const ValueKey('overtake-pulse'),
        opacity: _brightness,
        child: const RepaintBoundary(
          child: CustomPaint(painter: _EdgeGlowPainter()),
        ),
      ),
    ),
  );
}

class _EdgeGlowPainter extends CustomPainter {
  const _EdgeGlowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final depth = (size.shortestSide * .10).clamp(0.0, 40.0);
    if (depth == 0) return;
    final paint = Paint();
    final colors = [
      raceYellow.withValues(alpha: .95),
      raceYellow.withValues(alpha: .38),
      raceYellow.withValues(alpha: 0),
    ];

    void edge(Rect rect, Alignment begin, Alignment end) {
      paint.shader = LinearGradient(
        begin: begin,
        end: end,
        colors: colors,
        stops: const [0, .35, 1],
      ).createShader(rect);
      canvas.drawRect(rect, paint);
    }

    edge(
      Rect.fromLTWH(0, 0, size.width, depth),
      Alignment.topCenter,
      Alignment.bottomCenter,
    );
    edge(
      Rect.fromLTWH(0, size.height - depth, size.width, depth),
      Alignment.bottomCenter,
      Alignment.topCenter,
    );
    edge(
      Rect.fromLTWH(0, 0, depth, size.height),
      Alignment.centerLeft,
      Alignment.centerRight,
    );
    edge(
      Rect.fromLTWH(size.width - depth, 0, depth, size.height),
      Alignment.centerRight,
      Alignment.centerLeft,
    );
  }

  @override
  bool shouldRepaint(_EdgeGlowPainter oldDelegate) => false;
}
