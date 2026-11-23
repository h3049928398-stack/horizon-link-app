import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Both controls are interactive UIKit platform views. UIKit owns hit testing,
/// accessibility and the glass effects. Flutter owns navigation and UDP state.
class IosGlassControls extends StatelessWidget {
  const IosGlassControls({
    super.key,
    required this.labels,
    required this.onAction,
    this.selectedIndex,
  });

  final List<String> labels;
  final ValueChanged<int> onAction;
  final int? selectedIndex;

  @override
  Widget build(BuildContext context) {
    final tabs = selectedIndex != null;
    if (tabs) {
      return _controls(context, 68 + MediaQuery.paddingOf(context).bottom);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final half = (constraints.maxWidth - 12) / 2;
        final stacked = labels.any((label) {
          final painter = TextPainter(
            text: TextSpan(
              text: label,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            textDirection: Directionality.of(context),
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final tooWide = painter.width + 32 > half;
          painter.dispose();
          return tooWide;
        });
        final height = 48 + (scaler.scale(17) - 17).clamp(0.0, double.infinity);
        return _controls(
          context,
          stacked ? 2 * height + 12 : height,
          stacked: stacked,
        );
      },
    );
  }

  Widget _controls(
    BuildContext context,
    double height, {
    bool stacked = false,
  }) {
    final tabs = selectedIndex != null;
    final theme = Theme.of(context);
    final route = ModalRoute.of(context);
    final params = <String, Object>{
      'kind': tabs ? 'tabs' : 'connection',
      'labels': labels,
      if (tabs) 'selected': selectedIndex!,
      if (!tabs) 'stacked': stacked,
      'dark': theme.brightness == Brightness.dark,
      'accent': theme.colorScheme.primary.toARGB32(),
    };
    final content = _NativeControls(params: params, onAction: onAction);
    return SizedBox(
      width: double.infinity,
      height: height,
      child: route == null
          ? content
          : AnimatedBuilder(
              animation: Listenable.merge([
                route.animation,
                route.secondaryAnimation,
              ]),
              child: content,
              builder: (context, child) =>
                  route.isCurrent &&
                      route.animation?.status == AnimationStatus.completed &&
                      (route.secondaryAnimation?.isDismissed ?? true)
                  ? child!
                  : const SizedBox.expand(),
            ),
    );
  }
}

class _NativeControls extends StatefulWidget {
  const _NativeControls({
    super.key,
    required this.params,
    required this.onAction,
  });
  final Map<String, Object> params;
  final ValueChanged<int> onAction;
  @override
  State<_NativeControls> createState() => _NativeControlsState();
}

/// A UIKit option embedded in a Flutter row. Let enclosing scroll views win
/// vertical drags while the system control receives taps and horizontal input.
class IosOptionControl extends StatelessWidget {
  const IosOptionControl({
    super.key,
    required this.kind,
    required this.labels,
    required this.selected,
    required this.onSelect,
    required this.width,
    this.name = '',
    this.hint = '',
    this.symbol = '',
    this.destructive = -1,
    this.height = 44,
    this.color,
  });
  final String kind, name, hint, symbol;
  final List<String> labels;
  final int selected, destructive;
  final double width, height;
  final Color? color;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible =
        TickerMode.valuesOf(context).enabled &&
        ModalRoute.isCurrentOf(context) != false;
    return SizedBox(
      width: width,
      height: height,
      child: visible
          ? _NativeControls(
              key: ValueKey(kind),
              params: {
                'kind': kind,
                'labels': labels,
                'selected': selected,
                'name': name,
                'hint': hint,
                'symbol': symbol,
                'enabled': onSelect != null,
                'destructive': destructive,
                'dark': scheme.brightness == Brightness.dark,
                'accent': (color ?? scheme.primary).toARGB32(),
              },
              onAction: (i) => onSelect?.call(i),
            )
          : null,
    );
  }
}

class _NativeControlsState extends State<_NativeControls> {
  MethodChannel? _channel;
  @override
  void didUpdateWidget(_NativeControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.params, next = widget.params;
    if (next.keys.any((key) => key != 'labels' && old[key] != next[key]) ||
        !listEquals(old['labels'] as List, next['labels'] as List)) {
      _sync();
    }
  }

  Future<void> _sync() async {
    try {
      await _channel?.invokeMethod<void>('update', widget.params);
    } on MissingPluginException {
      // A closing route can dispose the native view before a queued update.
    }
  }

  void _created(int id) {
    if (!mounted) return;
    _channel = MethodChannel('horizon_link/controls/$id')
      ..setMethodCallHandler((call) async {
        final index = call.arguments;
        if (mounted &&
            ModalRoute.isCurrentOf(context) != false &&
            call.method == 'activate' &&
            index is int &&
            index >= 0 &&
            index <
                (widget.params['kind'] == 'switch'
                    ? 2
                    : (widget.params['labels'] as List).length)) {
          widget.onAction(index);
          // UISwitch and UISegmentedControl move before notifying Flutter.
          // Restore the authoritative value if the app declined the change.
          if (widget.params['kind'] == 'switch' ||
              widget.params['kind'] == 'segments') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && widget.params['selected'] != index) _sync();
            });
            WidgetsBinding.instance.ensureVisualUpdate();
          }
        }
      });
    _sync();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UiKitView(
    viewType: 'horizon_link/controls',
    creationParams: widget.params,
    creationParamsCodec: const StandardMessageCodec(),
    onPlatformViewCreated: _created,
    gestureRecognizers: switch (widget.params['kind']) {
      'tabs' || 'connection' => {
        Factory<EagerGestureRecognizer>(EagerGestureRecognizer.new),
      },
      'switch' || 'segments' => {
        Factory<TapGestureRecognizer>(TapGestureRecognizer.new),
        Factory<HorizontalDragGestureRecognizer>(
          HorizontalDragGestureRecognizer.new,
        ),
      },
      _ => {Factory<TapGestureRecognizer>(TapGestureRecognizer.new)},
    },
  );
}
