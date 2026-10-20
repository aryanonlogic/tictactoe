import 'package:flutter/material.dart';

import 'glass.dart';

export 'glass.dart';

const Color kInk = Color(0xFF0A0A0A);
const Color kMist = Color(0xFFF1F1EF);
const Color kLine = Color(0xFFE3E3E0);
const Color kSub = Color(0xFF8A8A86);

ThemeData buildTheme() {
  return ThemeData(
    scaffoldBackgroundColor: Colors.transparent,
    colorScheme: const ColorScheme.light(
      primary: kInk,
      onPrimary: Colors.white,
      secondary: kInk,
      onSecondary: Colors.white,
      surface: Colors.white,
      onSurface: kInk,
    ),
    splashFactory: InkRipple.splashFactory,
    splashColor: const Color(0x14000000),
    highlightColor: Colors.transparent,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
    }),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: kInk)),
    bottomSheetTheme: const BottomSheetThemeData(
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: kInk,
      contentTextStyle: const TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xE6FFFFFF),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
    ),
    dividerTheme: const DividerThemeData(color: kLine, thickness: 1, space: 1),
  );
}

/// Pill-shaped segmented control (black = selected).
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.value, required this.options, required this.onChanged});

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0x8CFFFFFF),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xCCFFFFFF)),
      ),
      child: Row(
        children: [
          for (final e in options.entries)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: e.key == value ? kInk : Colors.transparent,
                    borderRadius: BorderRadius.circular(19),
                  ),
                  child: Text(
                    e.value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: e.key == value ? Colors.white : kInk,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Black pill button used across the app.
class PillButton extends StatelessWidget {
  const PillButton({super.key, required this.label, required this.onPressed, this.width = 168, this.outlined = false});

  final String label;
  final VoidCallback? onPressed;
  final double width;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 52,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: outlined ? Colors.white : kInk,
          foregroundColor: outlined ? kInk : Colors.white,
          shape: StadiumBorder(side: outlined ? const BorderSide(color: kInk, width: 1.2) : BorderSide.none),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.2),
        ),
        child: Text(label),
      ),
    );
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? body,
  String confirm = 'OK',
  String cancel = 'Cancel',
}) async {
  final r = await showGlassDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      content: body == null ? null : Text(body, style: const TextStyle(color: kSub, height: 1.35)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(cancel)),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirm, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  String confirm = 'Save',
}) async {
  final controller = TextEditingController(text: initial);
  final r = await showGlassDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 60,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: hint, counterText: ''),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: Text(confirm, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  final t = r?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

void snack(BuildContext context, String msg) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(content: Text(msg)));
}

/// Settings-style row.
class RowTile extends StatelessWidget {
  const RowTile({super.key, required this.icon, required this.title, this.subtitle, this.onTap, this.trailing});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: kInk),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!, style: const TextStyle(fontSize: 12.5, color: kSub)),
                    ),
                ],
              ),
            ),
            trailing ?? const Icon(Icons.chevron_right, color: kSub),
          ],
        ),
      ),
    );
  }
}
