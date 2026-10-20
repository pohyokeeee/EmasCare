import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

abstract final class Palette {
  static const canvas = Color(0xFFF5F6F2),
      ink = Color(0xFF253C32),
      green = Color(0xFF315D4B),
      muted = Color(0xFF637168),
      line = Color(0xFFE1E7DE),
      soft = Color(0xFFEAF0E6),
      gold = Color(0xFF8B682E),
      sand = Color(0xFFF5EDDC);
}

ThemeData emasTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'Manrope',
  scaffoldBackgroundColor: Palette.canvas,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Palette.green,
    primary: Palette.green,
    surface: Colors.white,
  ),
  textTheme: const TextTheme(
    bodyMedium: TextStyle(fontSize: 15, height: 1.55, color: Palette.ink),
    bodyLarge: TextStyle(fontSize: 17, height: 1.5, color: Palette.ink),
    bodySmall: TextStyle(fontSize: 12, height: 1.5, color: Palette.muted),
    titleLarge: TextStyle(
      fontSize: 22,
      height: 1.3,
      fontWeight: FontWeight.w600,
      letterSpacing: -.6,
      color: Palette.ink,
    ),
    titleMedium: TextStyle(
      fontSize: 17,
      height: 1.4,
      fontWeight: FontWeight.w600,
      color: Palette.ink,
    ),
  ),
  tooltipTheme: const TooltipThemeData(
    waitDuration: Duration(milliseconds: 450),
  ),
  dividerTheme: const DividerThemeData(color: Palette.line, space: 30),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
  ),
);

class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.color = Colors.white,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Palette.line.withValues(alpha: .8)),
      boxShadow: [
        BoxShadow(
          color: Palette.ink.withValues(alpha: .025),
          blurRadius: 18,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: child,
  );
}

/// Critically damped press feedback starts on pointer-down and can reverse at
/// any point. Reduced motion retains the immediate color/focus feedback.
class EmasButton extends StatefulWidget {
  const EmasButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.secondary = false,
    this.white = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool secondary, white;
  @override
  State<EmasButton> createState() => _EmasButtonState();
}

class _EmasButtonState extends State<EmasButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scale = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  void press(bool pressed) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _scale.value = 1;
      return;
    }
    _scale.animateWith(
      SpringSimulation(
        SpringDescription.withDampingRatio(mass: 1, stiffness: 650, ratio: 1),
        _scale.value,
        pressed ? 0.975 : 1,
        _scale.velocity,
      ),
    );
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.white
        ? Colors.white
        : widget.secondary
        ? Palette.soft
        : Palette.green;
    final fg = widget.white || widget.secondary ? Palette.green : Colors.white;
    return ScaleTransition(
      scale: _scale,
      child: Semantics(
        button: true,
        enabled: widget.onPressed != null,
        child: Material(
          color: widget.onPressed == null ? Palette.line : bg,
          borderRadius: BorderRadius.circular(15),
          child: InkWell(
            onTap: widget.onPressed,
            onHighlightChanged: press,
            borderRadius: BorderRadius.circular(15),
            splashFactory: NoSplash.splashFactory,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 54),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 13,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: 21, color: fg),
                      const SizedBox(width: 10),
                    ],
                    Flexible(
                      child: Text(
                        widget.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: widget.onPressed == null ? Palette.muted : fg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.icon, this.gold = false});
  final String text;
  final IconData? icon;
  final bool gold;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: gold ? Palette.sand : Palette.soft,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: gold ? Palette.gold : Palette.green),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: gold ? Palette.gold : Palette.green,
            ),
          ),
        ),
      ],
    ),
  );
}

class Avatar extends StatelessWidget {
  const Avatar(this.initials, {super.key, this.size = 44});
  final String initials;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Palette.soft,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2),
    ),
    alignment: Alignment.center,
    child: Text(
      initials,
      style: TextStyle(
        fontSize: size * .30,
        fontWeight: FontWeight.w700,
        color: Palette.green,
      ),
    ),
  );
}

class TitleRow extends StatelessWidget {
  const TitleRow(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 4,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        if (action != null)
          TextButton(
            onPressed: onAction,
            child: Text(action!, style: const TextStyle(fontSize: 13)),
          ),
      ],
    ),
  );
}

class Frosted extends StatelessWidget {
  const Frosted({super.key, required this.child, required this.solid});
  final Widget child;
  final bool solid;
  @override
  Widget build(BuildContext context) => ClipRect(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: solid ? 0 : 18, sigmaY: solid ? 0 : 18),
      child: ColoredBox(
        color: Palette.canvas.withValues(alpha: solid ? 1 : .88),
        child: child,
      ),
    ),
  );
}

class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.gold = false});
  final IconData icon;
  final bool gold;
  @override
  Widget build(BuildContext context) => Container(
    width: 46,
    height: 46,
    decoration: BoxDecoration(
      color: gold ? Palette.sand : Palette.soft,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Icon(icon, color: gold ? Palette.gold : Palette.green, size: 23),
  );
}

class PreviewEmpty extends StatelessWidget {
  const PreviewEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });
  final IconData icon;
  final String title, description;
  @override
  Widget build(BuildContext context) => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconTile(icon),
        const SizedBox(height: 20),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(description, style: const TextStyle(color: Palette.muted)),
      ],
    ),
  );
}
