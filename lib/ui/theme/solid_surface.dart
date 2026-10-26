import 'dart:async';

import 'package:flutter/material.dart';

import 'tokens.dart';

enum SfSurfaceLevel { base, card, raised }

/// An opaque painted surface; the layout and interaction remain child-owned.
class SfSolidSurface extends StatelessWidget {
  const SfSolidSurface({
    super.key,
    required this.child,
    this.level = SfSurfaceLevel.card,
    this.radius,
    this.padding,
    this.width,
    this.height,
    this.control = false,
  });

  final Widget child;
  final SfSurfaceLevel level;
  final double? radius;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final bool control;

  @override
  Widget build(BuildContext context) {
    final fill = switch (level) {
      SfSurfaceLevel.base => SfColors.surfaceLow,
      SfSurfaceLevel.card => SfColors.surface,
      SfSurfaceLevel.raised => SfColors.surfaceHigh,
    };
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius ?? 999),
        boxShadow: level == SfSurfaceLevel.card && !control
            ? SfColors.cardShadow
            : null,
      ),
      // Paint the edge without introducing implicit padding or moving hitboxes.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius ?? 999),
        border: Border.all(color: SfColors.line),
      ),
      child: child,
    );
  }
}

OverlayEntry? _solidToastEntry;

void showSfSolidToast(
  BuildContext context,
  String text, {
  required Widget icon,
  double bottom = 112,
}) {
  _solidToastEntry?.remove();
  _solidToastEntry = null;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _SolidToastHost(
      text: text,
      icon: icon,
      bottom: bottom,
      onDone: () {
        if (_solidToastEntry == entry) {
          _solidToastEntry = null;
          entry.remove();
        }
      },
      onDisposed: () {
        if (_solidToastEntry == entry) _solidToastEntry = null;
      },
    ),
  );
  _solidToastEntry = entry;
  overlay.insert(entry);
}

class _SolidToastHost extends StatefulWidget {
  const _SolidToastHost({
    required this.text,
    required this.icon,
    required this.bottom,
    required this.onDone,
    required this.onDisposed,
  });

  final String text;
  final Widget icon;
  final double bottom;
  final VoidCallback onDone, onDisposed;

  @override
  State<_SolidToastHost> createState() => _SolidToastHostState();
}

class _SolidToastHostState extends State<_SolidToastHost> {
  Timer? _hold;

  @override
  void initState() {
    super.initState();
    _hold = Timer(const Duration(seconds: 2), widget.onDone);
  }

  @override
  void dispose() {
    _hold?.cancel();
    widget.onDisposed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inset =
        MediaQuery.viewPaddingOf(context).bottom +
        MediaQuery.viewInsetsOf(context).bottom;
    return Positioned(
      left: 24,
      right: 24,
      bottom: widget.bottom + inset,
      // Informational feedback must not swallow a tap on the plan's start
      // button or another control underneath it.
      child: IgnorePointer(
        child: Semantics(
          liveRegion: true,
          child: Material(
            type: MaterialType.transparency,
            child: SfSolidSurface(
              level: SfSurfaceLevel.raised,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  widget.icon,
                  const SizedBox(width: 8),
                  Expanded(child: Text(widget.text, style: SfType.callout)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
