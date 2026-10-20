import 'package:flutter/material.dart';

import '../app/services.dart';
import '../domain/exercise.dart';
import 'exercise_video.dart';
import 'theme.dart';

/// Every move in the library, filterable by category; tap to watch. Opened
/// from the chat ("看看动作库", "有哪些拉伸动作" → [initial]) or the drawer.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, this.initial});

  /// Category picked when the page opens (from the chat).
  final ExerciseCategory? initial;
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late ExerciseCategory? _cat = widget.initial;

  @override
  Widget build(BuildContext context) {
    final lib = AppServices.of(context).library;
    final list = lib.all.where((e) => _cat == null || e.category == _cat).toList();
    return Scaffold(
      appBar: SfTopBar(title: '动作库', caption: '${lib.length} 个动作 · 点开看示范'),
      body: Column(children: [
        SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(SfSpace.x4, SfSpace.x1, SfSpace.x4, SfSpace.x2),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: SfSpace.x2),
                child: SfChoiceChip(
                  key: const ValueKey('cat-all'),
                  label: '全部',
                  selected: _cat == null,
                  onTap: () => setState(() => _cat = null),
                ),
              ),
              for (final c in ExerciseCategory.values)
                Padding(
                  padding: const EdgeInsets.only(right: SfSpace.x2),
                  child: SfChoiceChip(
                    key: ValueKey('cat-${c.name}'),
                    label: c.zh,
                    selected: _cat == c,
                    onTap: () => setState(() => _cat = c),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: SfMotion.medium,
            switchInCurve: SfMotion.standard,
            child: list.isEmpty
                ? SfEmptyState(
                    key: ValueKey('empty-$_cat'),
                    icon: SfGlyph.grid,
                    title: '这一类还没有动作',
                    body: '动作库会随动作包更新，先看看别的分类。',
                    action: '看全部',
                    onAction: () => setState(() => _cat = null),
                  )
                : _grid(context, list),
          ),
        ),
      ]),
    );
  }

  Widget _grid(BuildContext context, List<Exercise> list) => LayoutBuilder(
    key: ValueKey('grid-$_cat'),
    builder: (context, bounds) {
      final tileWidth = (bounds.maxWidth - SfSpace.x4 * 2 - SfSpace.x3) / 2;
      final scaler = MediaQuery.textScalerOf(context);
      final title = SfType.callout;
      final caption = SfType.caption;
      // A square image plus two text lines and their spacing. A fixed
      // aspect ratio leaves too little text room on narrow screens or
      // with larger system text; round each line up for font metrics.
      final textHeight = (scaler.scale(title.fontSize!) * title.height!).ceil() +
          (scaler.scale(caption.fontSize!) * caption.height!).ceil();
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(SfSpace.x4, SfSpace.x1, SfSpace.x4, SfSpace.x6),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: SfSpace.x4,
          crossAxisSpacing: SfSpace.x3,
          mainAxisExtent: tileWidth + SfSpace.x2 + 2 + textHeight,
        ),
        itemCount: list.length,
        itemBuilder: (_, i) => _Tile(exercise: list[i], onTap: () => _show(list[i])),
      );
    },
  );

  void _show(Exercise e) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    sheetAnimationStyle: SfMotion.sheet,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(SfSpace.x4, 0, SfSpace.x4, SfSpace.x4),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          ExerciseVideo(exercise: e, radius: SfRadius.lg),
          const SizedBox(height: SfSpace.x4),
          Text(e.name, style: SfType.title.copyWith(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: SfSpace.x1),
          Text(
            [
              e.category.zh,
              levelZh(e.level),
              e.equipment.isEmpty ? '徒手' : e.equipment.map((q) => q.zh).join('/'),
              if (e.unilateral) '左右各做',
            ].join(' · '),
            style: SfType.label,
          ),
          const SizedBox(height: SfSpace.x4),
          _line(SfGlyph.figure, '练到', e.muscles.join('、')),
          const SizedBox(height: SfSpace.x3),
          _line(SfGlyph.subtitles, '要领', e.cue),
          if (e.cautions.isNotEmpty) ...[
            const SizedBox(height: SfSpace.x3),
            _line(SfGlyph.bandage, '注意', '${e.cautions.join('、')}不适时减小幅度或换动作', color: SfColors.caution),
          ],
        ]),
      ),
    ),
  );

  Widget _line(SfGlyph icon, String label, String text, {Color? color}) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: SfIcon(icon, size: 18, color: color ?? SfColors.faint),
      ),
      const SizedBox(width: SfSpace.x2),
      SizedBox(width: 36, child: Text(label, style: SfType.label.copyWith(color: color ?? SfColors.muted, height: 1.6))),
      Expanded(child: Text(text, style: SfType.body.copyWith(fontSize: 15, height: 1.55, color: color))),
    ],
  );
}

/// The cover as the tile's top (concentric corners, no box inside a box),
/// name and meta below.
class _Tile extends StatelessWidget {
  const _Tile({required this.exercise, required this.onTap});
  final Exercise exercise;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = exercise;
    final stage = sfStageFor(e);
    return SfPressable(
      semanticLabel: e.name,
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SfRadius.lg),
            boxShadow: SfColors.cardShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(SfRadius.lg),
            child: AspectRatio(
              aspectRatio: 1,
              child: ColoredBox(
                color: stage.mediaStage,
                child: Image.asset(sfPoster(e), fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(SfSpace.x1, SfSpace.x2 + 2, SfSpace.x1, 0),
          child: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: SfType.callout.copyWith(fontWeight: FontWeight.w600)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SfSpace.x1),
          child: Text(
            '${e.category.zh} · ${levelZh(e.level)} · ${e.equipment.isEmpty ? '徒手' : e.equipment.map((q) => q.zh).join('/')}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SfType.caption.copyWith(color: SfColors.muted),
          ),
        ),
      ]),
    );
  }
}
