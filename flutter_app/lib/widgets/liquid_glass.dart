import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';

/// Listens once per app, above the Navigator, so sheets and pages share the
/// same capabilities and respond to changes in iOS accessibility settings.
class LiquidGlass extends StatefulWidget {
  const LiquidGlass({super.key, required this.child});

  final Widget child;

  static bool enabledOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_GlassAvailability>()
          ?.enabled ??
      false;

  // The shell's extended Scaffold supplies the height of the floating bar
  // here. Pad the page content, leaving its background visible under the bar.
  static double bottomClearanceOf(BuildContext context) =>
      enabledOf(context) ? MediaQuery.paddingOf(context).bottom : 0;

  @override
  State<LiquidGlass> createState() => _LiquidGlassState();
}

class _LiquidGlassState extends State<LiquidGlass> {
  static const _events = EventChannel('horizon_link/liquid_glass');
  StreamSubscription<dynamic>? _subscription;
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      _subscription = _events.receiveBroadcastStream().listen(
        (value) => _setEnabled(value == true),
        onError: (Object _) => _setEnabled(false),
        onDone: () => _setEnabled(false),
      );
    }
  }

  void _setEnabled(bool enabled) {
    if (mounted && enabled != _enabled) setState(() => _enabled = enabled);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _GlassAvailability(
      enabled: _enabled,
      child: Theme(
        data: _enabled
            ? theme.copyWith(
                bottomSheetTheme: theme.bottomSheetTheme.copyWith(
                  clipBehavior: Clip.antiAlias,
                  shape: const RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(32),
                    ),
                  ),
                ),
                dialogTheme: theme.dialogTheme.copyWith(
                  shape: const RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.all(Radius.circular(28)),
                  ),
                ),
              )
            : theme,
        child: widget.child,
      ),
    );
  }
}

class _GlassAvailability extends InheritedWidget {
  const _GlassAvailability({required this.enabled, required super.child});

  final bool enabled;

  @override
  bool updateShouldNotify(_GlassAvailability oldWidget) =>
      enabled != oldWidget.enabled;
}

/// A decorative UIKit backdrop. The foreground keeps its Flutter gesture
/// targets and semantics. A group shares one native view.
class LiquidGlassSurface extends StatelessWidget {
  const LiquidGlassSurface({
    super.key,
    required this.child,
    this.capsule = false,
  });

  final Widget child;
  final bool capsule;

  @override
  Widget build(BuildContext context) {
    if (!LiquidGlass.enabledOf(context)) return child;
    final route = ModalRoute.of(context);
    if (route == null) return _surface(context, child);

    // Do not composite UIVisualEffectView through a fading dialog transition.
    return AnimatedBuilder(
      animation: Listenable.merge([route.animation, route.secondaryAnimation]),
      child: child,
      builder: (context, child) => _surface(context, child!),
    );
  }

  Widget _surface(BuildContext context, Widget child) {
    final theme = Theme.of(context);
    final route = ModalRoute.of(context);
    final nativeVisible =
        TickerMode.valuesOf(context).enabled &&
        (route == null ||
            (route.isCurrent &&
                route.animation?.status == AnimationStatus.completed &&
                (route.secondaryAnimation?.isDismissed ?? true)));
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: nativeVisible
                  ? UiKitView(
                      key: ValueKey((theme.brightness, capsule)),
                      viewType: 'horizon_link/liquid_glass_surface',
                      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
                      creationParamsCodec: const StandardMessageCodec(),
                      creationParams: {
                        'dark': theme.brightness == Brightness.dark,
                        'capsule': capsule,
                      },
                    )
                  : DecoratedBox(
                      decoration: ShapeDecoration(
                        color: theme.colorScheme.surfaceContainerHigh,
                        shape: capsule
                            ? const StadiumBorder()
                            : const RoundedSuperellipseBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(22),
                                ),
                              ),
                      ),
                    ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Adds a backdrop and room around an existing sheet or dialog action group.
class LiquidGlassActions extends StatelessWidget {
  const LiquidGlassActions({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!LiquidGlass.enabledOf(context)) return child;
    return LiquidGlassSurface(
      child: Padding(padding: const EdgeInsets.all(6), child: child),
    );
  }
}

class LiquidGlassAlertDialog extends StatelessWidget {
  const LiquidGlassAlertDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
  });

  final Widget title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: title,
    content: content,
    actions: LiquidGlass.enabledOf(context)
        ? [
            LiquidGlassActions(
              child: OverflowBar(
                spacing: 8,
                overflowSpacing: 4,
                alignment: MainAxisAlignment.end,
                overflowAlignment: OverflowBarAlignment.end,
                children: actions,
              ),
            ),
          ]
        : actions,
  );
}
