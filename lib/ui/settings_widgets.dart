import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoSwitch;

import 'theme/settings_tokens.dart';
import 'theme/tokens.dart';

class SfSettingsScaffold extends StatelessWidget {
  const SfSettingsScaffold({
    super.key,
    required this.title,
    required this.children,
    this.controller,
  });
  final String title;
  final List<Widget> children;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final tokens = SfSettingsTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.background,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          key: const ValueKey('settings-scroll'),
          controller: controller,
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _SettingsHeader(title, tokens),
            ),
            SliverList.list(
              children: [
                ...children,
                SizedBox(height: 30 + MediaQuery.paddingOf(context).bottom),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsHeader extends SliverPersistentHeaderDelegate {
  _SettingsHeader(this.title, this.tokens);
  final String title;
  final SfSettingsTokens tokens;
  @override
  double get minExtent => 52;
  @override
  double get maxExtent => 112;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final t = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    return ColoredBox(
      color: tokens.background,
      child: Stack(
        children: [
          Positioned(left: 8, top: 2, child: BackButton(color: tokens.text)),
          Positioned(
            left: 20 + 36 * t,
            top: 57 - 43 * t,
            child: Text(
              title,
              key: ValueKey(
                t == 1 ? 'settings-title-small' : 'settings-title-large',
              ),
              style: TextStyle(
                fontFamily: sfFontFamily,
                fontSize: 30 - 13 * t,
                height: 1.2,
                fontWeight: FontWeight.lerp(
                  FontWeight.w800,
                  FontWeight.w700,
                  t,
                ),
                color: tokens.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SettingsHeader oldDelegate) =>
      oldDelegate.title != title ||
      oldDelegate.tokens.palette != tokens.palette;
}

class SfSettingsSection extends StatelessWidget {
  const SfSettingsSection(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(32, 18, 16, 8),
    child: Text(
      title,
      style: SfSettingsTokens.of(context).detail.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: .5,
      ),
    ),
  );
}

class SfSettingsGroup extends StatelessWidget {
  const SfSettingsGroup({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final tokens = SfSettingsTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(SfSettingsTokens.groupRadius),
          boxShadow: tokens.shadows,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(SfSettingsTokens.groupRadius),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: SfSettingsTokens.dividerInset,
                    ),
                    child: Divider(height: 1, thickness: 1, color: tokens.line),
                  ),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SfSettingsRow extends StatelessWidget {
  const SfSettingsRow({
    super.key,
    required this.title,
    required this.icon,
    this.tone = SfSettingsTone.gray,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.chevron = false,
  });
  final String title;
  final IconData icon;
  final SfSettingsTone tone;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive, chevron;
  @override
  Widget build(BuildContext context) {
    final tokens = SfSettingsTokens.of(context);
    return Material(
      color: tokens.surface,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: SfSettingsTokens.rowInset,
            child: Row(
              children: [
                Container(
                  width: SfSettingsTokens.iconSize,
                  height: SfSettingsTokens.iconSize,
                  decoration: BoxDecoration(
                    color: tokens.iconSurface(tone),
                    borderRadius: BorderRadius.circular(
                      SfSettingsTokens.iconRadius,
                    ),
                  ),
                  child: Icon(icon, size: 19, color: tokens.ink(tone)),
                ),
                const SizedBox(width: SfSettingsTokens.rowGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tokens.title.copyWith(
                          color: destructive ? tokens.danger : null,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tokens.detail,
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 10), trailing!],
                if (chevron) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: tokens.chevron,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SfSettingsSwitch extends StatelessWidget {
  const SfSettingsSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) {
    final tokens = SfSettingsTokens.of(context);
    return SizedBox(
      width: 50,
      height: 30,
      child: OverflowBox(
        minWidth: 59,
        maxWidth: 59,
        minHeight: 39,
        maxHeight: 39,
        child: CupertinoSwitch(
          value: value,
          onChanged: onChanged,
          thumbColor: Colors.white,
          activeTrackColor: tokens.accent,
          inactiveTrackColor: tokens.switchOff,
        ),
      ),
    );
  }
}

class SfSettingsSwitchRow extends StatelessWidget {
  const SfSettingsSwitchRow({
    super.key,
    required this.title,
    required this.icon,
    required this.tone,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });
  final String title;
  final IconData icon;
  final SfSettingsTone tone;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => SfSettingsRow(
    title: title,
    subtitle: subtitle,
    icon: icon,
    tone: tone,
    onTap: onChanged == null ? null : () => onChanged!(!value),
    trailing: SfSettingsSwitch(value: value, onChanged: onChanged),
  );
}

Future<bool> sfSettingsConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required Key confirmKey,
}) async {
  final tokens = SfSettingsTokens.of(context);
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: tokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SfSettingsTokens.groupRadius),
          ),
          title: Text(title, style: tokens.title.copyWith(fontSize: 18)),
          content: Text(message, style: tokens.body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('取消', style: TextStyle(color: tokens.muted)),
            ),
            TextButton(
              key: confirmKey,
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmLabel, style: TextStyle(color: tokens.danger)),
            ),
          ],
        ),
      ) ??
      false;
}

class SfSettingsDocumentPage extends StatelessWidget {
  const SfSettingsDocumentPage({
    super.key,
    required this.title,
    required this.text,
    this.footer,
  });
  final String title;
  final Future<String> text;
  final Widget? footer;
  @override
  Widget build(BuildContext context) => SfSettingsScaffold(
    title: title,
    children: [
      const SizedBox(height: 12),
      SfSettingsGroup(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: FutureBuilder<String>(
              future: text,
              builder: (context, snapshot) => SelectableText(
                snapshot.data ??
                    (snapshot.hasError ? '内容暂时无法读取，请返回后重试。' : '正在读取…'),
                style: SfSettingsTokens.of(context).body,
              ),
            ),
          ),
          ?footer,
        ],
      ),
    ],
  );
}
