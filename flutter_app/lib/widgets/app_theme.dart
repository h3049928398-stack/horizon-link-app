import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import 'liquid_glass.dart';
export '../l10n.dart';

const appBackground = Color(0xff101115),
    appSurface = Color(0xff1a1c22),
    appAccent = Color(0xffc0f35b),
    appMuted = Color(0xff8c8f9e);

/// Fixed colors above remain available to the black-background racing canvases.
extension AppPalette on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get appSurface => Theme.of(this).colorScheme.surface;
  Color get appAccent => Theme.of(this).colorScheme.primary;
  Color get appMuted => Theme.of(this).colorScheme.onSurfaceVariant;

  OutlinedBorder panelShape(
    double radius, {
    BorderSide side = BorderSide.none,
  }) {
    if (LiquidGlass.enabledOf(this)) {
      return RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(radius + 4),
        side: side,
      );
    }
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: side,
    );
  }
}

ThemeData buildTheme({Brightness brightness = Brightness.dark}) {
  final dark = brightness == Brightness.dark;
  final background = dark ? appBackground : const Color(0xfff3f5f7);
  final surface = dark ? appSurface : Colors.white;
  final accent = dark ? appAccent : const Color(0xff426916);
  final muted = dark ? appMuted : const Color(0xff58616d);
  final foreground = dark ? Colors.white : const Color(0xff19212b);
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: brightness,
    surface: surface,
    primary: accent,
  ).copyWith(onSurface: foreground, onSurfaceVariant: muted);
  return ThemeData(
    brightness: brightness,
    useMaterial3: true,
    fontFamily: 'Chinese',
    scaffoldBackgroundColor: background,
    colorScheme: scheme,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: foreground,
      elevation: 0,
      centerTitle: false,
      systemOverlayStyle: dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      titleTextStyle: TextStyle(
        fontFamily: 'Chinese',
        color: foreground,
        fontSize: 23,
        fontWeight: FontWeight.w700,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xff17191e) : surface,
      indicatorColor: accent.withValues(alpha: .12),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? accent : muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: 'Chinese',
          fontSize: 11,
          color: s.contains(WidgetState.selected) ? accent : muted,
        ),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: dark ? const Color(0xff2b2e37) : const Color(0xffe1e5e9),
      space: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: dark ? const Color(0xff17210b) : Colors.white,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontFamily: 'Chinese',
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      showDragHandle: true,
    ),
  );
}

class SectionLabel extends StatelessWidget {
  final String text, trailing;
  const SectionLabel(this.text, {super.key, this.trailing = ''});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 14),
    child: Row(
      children: [
        Expanded(
          child: LText(
            text,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
        if (trailing.isNotEmpty) ...[
          const SizedBox(width: 16),
          Flexible(
            child: LText(
              trailing,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, color: context.appMuted),
            ),
          ),
        ],
      ],
    ),
  );
}

class AppGroup extends StatelessWidget {
  final List<Widget> children;
  const AppGroup({super.key, required this.children});
  @override
  Widget build(BuildContext context) => Material(
    color: context.appSurface,
    shape: context.panelShape(18),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
}
