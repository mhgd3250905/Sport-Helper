import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/ui_polish_tokens.dart';

enum SavedPlanAction { show, rename, delete }

/// A route owns dismissal/back handling; its transparent barrier lets our mask
/// leave the original, live SDK card undimmed without cloning/reparenting it.
Future<SavedPlanAction?> showSavedPlanMenu(
  BuildContext context, {
  required Rect Function() cardRect,
  required Rect Function() highlightRect,
  required Listenable cardAnimation,
}) async {
  final route = _SavedPlanMenuRoute(
    cardRect: cardRect,
    highlightRect: highlightRect,
    cardAnimation: cardAnimation,
    themes: InheritedTheme.capture(
      from: context,
      to: Navigator.of(context).context,
    ),
    dark: SfColors.isDark,
    text: SfColors.text,
    secondary: SfSavedPlanTokens.secondary,
  );
  final selection = await Navigator.of(context).push<SavedPlanAction>(route);
  // Finish the reverse animation before an action navigates away from the
  // anchor card or opens another modal route.
  await route.completed;
  return selection;
}

class _SavedPlanMenuRoute extends PopupRoute<SavedPlanAction> {
  _SavedPlanMenuRoute({
    required this.cardRect,
    required this.highlightRect,
    required this.cardAnimation,
    required this.themes,
    required this.dark,
    required this.text,
    required this.secondary,
  });
  final Rect Function() cardRect;
  final Rect Function() highlightRect;
  final Listenable cardAnimation;
  final CapturedThemes themes;
  final bool dark;
  final Color text, secondary;

  @override
  Color get barrierColor => Colors.transparent;
  @override
  bool get barrierDismissible => true;
  @override
  String get barrierLabel => '关闭菜单';
  @override
  Duration get transitionDuration => SfSavedPlanTokens.menuEnter;
  @override
  Duration get reverseTransitionDuration => SfSavedPlanTokens.menuExit;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => themes.wrap(
    AnimatedBuilder(
      animation: Listenable.merge([animation, cardAnimation]),
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final bounds = cardRect();
          final safe = MediaQuery.paddingOf(context);
          final below = bounds.bottom + SfSavedPlanTokens.menuGap;
          final placeBelow =
              below + SfSavedPlanTokens.menuHeight <=
              constraints.maxHeight - safe.bottom;
          final top = placeBelow
              ? below
              : math.max(
                  safe.top,
                  bounds.top -
                      SfSavedPlanTokens.menuGap -
                      SfSavedPlanTokens.menuHeight,
                );
          final left =
              (bounds.right -
                      SfSavedPlanTokens.inset -
                      SfSavedPlanTokens.menuWidth)
                  .clamp(
                    safe.left,
                    math.max(
                      safe.left,
                      constraints.maxWidth -
                          safe.right -
                          SfSavedPlanTokens.menuWidth,
                    ),
                  )
                  .toDouble();
          final curve = animation.status == AnimationStatus.reverse
              ? Curves.easeInCubic
              : Curves.easeOutCubic;
          final progress = curve.transform(animation.value);
          final maskProgress = animation.status == AnimationStatus.reverse
              ? animation.value
              : (animation.value * 180 / 160).clamp(0.0, 1.0);
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  key: const ValueKey('saved-menu-mask'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => navigator!.pop(),
                  child: CustomPaint(
                    painter: _CardMask(
                      card: highlightRect(),
                      radius: 20 * highlightRect().width / bounds.width,
                      color: Colors.black.withValues(
                        alpha: (dark ? .32 : .12) * maskProgress,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: left,
                top: top,
                width: SfSavedPlanTokens.menuWidth,
                child: FadeTransition(
                  opacity: AlwaysStoppedAnimation(progress),
                  child: Transform.scale(
                    scale: .92 + .08 * progress,
                    alignment: placeBelow
                        ? Alignment.topRight
                        : Alignment.bottomRight,
                    child: Material(
                      key: const ValueKey('saved-plan-context-menu'),
                      type: MaterialType.transparency,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: dark ? const Color(0xFF1A2324) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: dark
                                ? Colors.white.withValues(alpha: .08)
                                : const Color(0xFFE3E8E6),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: dark ? .40 : .10,
                              ),
                              offset: const Offset(0, 8),
                              blurRadius: 24,
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _MenuItem(
                                key: const ValueKey('saved-menu-show'),
                                icon: Icons.chat_bubble_outline_rounded,
                                label: '发到对话',
                                text: text,
                                iconColor: secondary,
                                dark: dark,
                                onTap: () =>
                                    navigator!.pop(SavedPlanAction.show),
                              ),
                              _MenuItem(
                                key: const ValueKey('saved-menu-rename'),
                                icon: Icons.edit_outlined,
                                label: '重命名',
                                text: text,
                                iconColor: secondary,
                                dark: dark,
                                onTap: () =>
                                    navigator!.pop(SavedPlanAction.rename),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                                child: SizedBox(
                                  height: 1,
                                  width: double.infinity,
                                  child: ColoredBox(
                                    color: dark
                                        ? Colors.white.withValues(alpha: .08)
                                        : const Color(0xFFE3E8E6),
                                  ),
                                ),
                              ),
                              _MenuItem(
                                key: const ValueKey('saved-menu-delete'),
                                icon: Icons.delete_outline_rounded,
                                label: '删除',
                                text: dark
                                    ? const Color(0xFFFF6B6B)
                                    : const Color(0xFFD64545),
                                iconColor: dark
                                    ? const Color(0xFFFF6B6B)
                                    : const Color(0xFFD64545),
                                dark: dark,
                                onTap: () =>
                                    navigator!.pop(SavedPlanAction.delete),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

class _CardMask extends CustomPainter {
  _CardMask({required this.card, required this.color, required this.radius});
  final Rect card;
  final Color color;
  final double radius;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(card, Radius.circular(radius))),
    Paint()..color = color,
  );
  @override
  bool shouldRepaint(_CardMask oldDelegate) =>
      card != oldDelegate.card ||
      color != oldDelegate.color ||
      radius != oldDelegate.radius;
}

class _MenuItem extends StatefulWidget {
  const _MenuItem({
    super.key,
    required this.icon,
    required this.label,
    required this.text,
    required this.iconColor,
    required this.dark,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color text, iconColor;
  final bool dark;
  final VoidCallback onTap;
  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: widget.onTap,
      onHighlightChanged: (value) => setState(() => _pressed = value),
      splashFactory: NoSplash.splashFactory,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      child: SizedBox(
        height: 48,
        child: Stack(
          children: [
            Positioned.fill(
              left: 6,
              right: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _pressed
                      ? (widget.dark
                            ? Colors.white.withValues(alpha: .06)
                            : const Color(0xFFF1F4F3))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(widget.icon, size: 20, color: widget.iconColor),
                    const SizedBox(width: 12),
                    Text(
                      widget.label,
                      style: SfType.body.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: widget.text,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<String?> renameSavedPlan(BuildContext context, String name) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      elevation: 0,
      backgroundColor: SfCardTokens.fill,
      constraints: const BoxConstraints(maxWidth: double.infinity),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _RenameSheet(name: name),
    );

class _RenameSheet extends StatefulWidget {
  const _RenameSheet({required this.name});
  final String name;
  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  late final _text = TextEditingController(
    text: widget.name,
  )..selection = TextSelection(baseOffset: 0, extentOffset: widget.name.length);
  bool get _canSave =>
      _text.text.trim().isNotEmpty && _text.text.trim() != widget.name.trim();
  void _save() {
    if (_canSave) Navigator.pop(context, _text.text.trim());
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SingleChildScrollView(
      child: SafeArea(
        top: false,
        child: Padding(
          key: const ValueKey('saved-rename-sheet'),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '重命名',
                style: SfType.body.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: SfColors.text,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 48,
                child: TextField(
                  key: const ValueKey('rename-field'),
                  controller: _text,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  style: SfType.body.copyWith(
                    fontSize: 16,
                    color: SfColors.text,
                  ),
                  decoration: InputDecoration(
                    hintText: '计划名称',
                    filled: true,
                    fillColor: SfSavedPlanTokens.insetFill,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _save(),
                ),
              ),
              const SizedBox(height: 20),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _text,
                builder: (context, _, _) => SizedBox(
                  height: 48,
                  child: FilledButton(
                    key: const ValueKey('rename-ok'),
                    onPressed: _canSave ? _save : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: SfColors.accent,
                      foregroundColor: SfColors.onAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      textStyle: SfType.body.copyWith(
                        fontFamily: sfFontFamily,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('保存'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<bool?> confirmDeleteSavedPlan(BuildContext context, String name) =>
    showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        key: const ValueKey('saved-delete-dialog'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        constraints: BoxConstraints.tightFor(
          width: MediaQuery.sizeOf(context).width - 64,
        ),
        backgroundColor: SfCardTokens.fill,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '删除「$name」？',
                style: SfType.body.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: SfColors.text,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '删除后无法恢复',
                style: SfType.body.copyWith(
                  fontSize: 14,
                  color: SfSavedPlanTokens.secondary,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: TextButton.styleFrom(
                          backgroundColor: SfSavedPlanTokens.insetFill,
                          foregroundColor: SfColors.text,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
                        child: const Text('取消'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: TextButton(
                        key: const ValueKey('delete-ok'),
                        onPressed: () => Navigator.pop(context, true),
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFFD64545),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
                        child: const Text('删除'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
