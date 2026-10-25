import 'package:flutter/material.dart';
import 'package:ugk_trainer/ugk_trainer.dart' show DrillMediaPlaybackHandle;

import '../app/services.dart';
import '../domain/exercise.dart';
import 'action_issue_actions.dart';
import 'alpha_artwork.dart';
import 'app_test_library_page.dart';
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
    final testCatalog = AppServices.of(context).testCatalog;
    if (testCatalog != null) {
      return AppTestLibraryPage(catalog: testCatalog, initial: widget.initial);
    }
    final lib = AppServices.of(context).library;
    final list = lib.all
        .where((e) => _cat == null || e.category == _cat)
        .toList();
    return Scaffold(
      appBar: SfTopBar(title: '动作库', caption: '${lib.length} 个动作'),
      body: Column(
        children: [
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(
                SfSpace.x4,
                SfSpace.x1,
                SfSpace.x4,
                SfSpace.x2,
              ),
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
                      title: lib.length == 0 ? '暂时没有已审核的动作' : '这一类还没有动作',
                      body: '动作库会随已审核动作包更新；已保存计划和训练记录仍保留。',
                      action: '看全部',
                      onAction: () => setState(() => _cat = null),
                    )
                  : _grid(context, list),
            ),
          ),
        ],
      ),
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
      final textHeight =
          (scaler.scale(title.fontSize!) * title.height!).ceil() +
          (scaler.scale(caption.fontSize!) * caption.height!).ceil();
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(
          SfSpace.x4,
          SfSpace.x1,
          SfSpace.x4,
          SfSpace.x6,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: SfSpace.x4,
          crossAxisSpacing: SfSpace.x3,
          mainAxisExtent: tileWidth + SfSpace.x2 + 2 + textHeight,
        ),
        itemCount: list.length,
        itemBuilder: (_, i) =>
            _Tile(exercise: list[i], onTap: () => _show(list[i])),
      );
    },
  );

  void _show(Exercise e) => showExerciseDetails(context, e);
}

/// Shared action details for the library and validated coach action cards.
Future<void> showExerciseDetails(BuildContext context, Exercise e) =>
    showModalBottomSheet<void>(
      context: context,
      routeSettings: const RouteSettings(name: 'exercise_details'),
      isScrollControlled: true,
      sheetAnimationStyle: SfMotion.sheet,
      builder: (_) => _ExerciseDetails(exercise: e),
    );

class _ExerciseDetails extends StatefulWidget {
  const _ExerciseDetails({required this.exercise});
  final Exercise exercise;

  @override
  State<_ExerciseDetails> createState() => _ExerciseDetailsState();
}

class _ExerciseDetailsState extends State<_ExerciseDetails> {
  DrillMediaPlaybackHandle? _playback;
  bool _playVideo = false;

  @override
  void dispose() {
    _playback?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.exercise;
    final s = AppServices.of(context);
    final store = s.store.actionIssueStore;
    final playback = store.enabled
        ? (_playback ??= DrillMediaPlaybackHandle())
        : null;
    final alphaPreview =
        !_playVideo &&
        SfAlphaCards.hasCover(e, enabled: SfAlphaCards.enabledOf(context));
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          SfSpace.x4,
          0,
          SfSpace.x4,
          SfSpace.x4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (alphaPreview)
              SfPressable(
                key: const ValueKey('library-alpha-play'),
                semanticLabel: '播放${e.name}示范',
                onTap: () => setState(() => _playVideo = true),
                child: Stack(
                  children: [
                    SfAlphaArtwork(exercise: e),
                    Positioned(
                      right: SfSpace.x3,
                      bottom: SfSpace.x3,
                      child: IgnorePointer(
                        child: ExcludeSemantics(
                          child: SfControlFace(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SfIcon(
                                  SfGlyph.play,
                                  size: 18,
                                  color: SfColors.text,
                                ),
                                const SizedBox(width: SfSpace.x2),
                                Text('播放示范', style: SfType.callout),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              ExerciseVideo(
                exercise: e,
                radius: SfRadius.lg,
                playbackHandle: playback,
              ),
            if (playback != null)
              ActionIssueMarkButton(
                key: const ValueKey('library-action-issue'),
                store: store,
                library: s.library,
                playbackHandle: playback,
                actionIdAtTap: () => e.id,
              ),
            const SizedBox(height: SfSpace.x4),
            Text(
              e.name,
              style: SfType.title.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (s.testCatalog != null) ...[
              const SizedBox(height: SfSpace.x1),
              Text('App 测试版 · 未审', style: SfType.caption),
            ],
            const SizedBox(height: SfSpace.x1),
            Text(
              [
                e.category.zh,
                levelZh(e.level),
                e.effectiveEquipmentIds.isEmpty
                    ? '徒手'
                    : e.effectiveEquipmentIds.map(equipmentLabel).join('/'),
                if (e.unilateral) '左右各做',
              ].join(' · '),
              style: SfType.label,
            ),
            const SizedBox(height: SfSpace.x4),
            _detailLine(SfGlyph.figure, '练到', e.muscles.join('、')),
            const SizedBox(height: SfSpace.x3),
            _detailLine(SfGlyph.subtitles, '要领', e.cue),
            if (e.cautions.isNotEmpty) ...[
              const SizedBox(height: SfSpace.x3),
              _detailLine(
                SfGlyph.bandage,
                '注意',
                '${e.cautions.join('、')}不适时减小幅度或换动作',
                color: SfColors.caution,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Widget _detailLine(SfGlyph icon, String label, String text, {Color? color}) =>
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: SfIcon(icon, size: 18, color: color ?? SfColors.faint),
        ),
        const SizedBox(width: SfSpace.x2),
        SizedBox(
          width: 36,
          child: Text(
            label,
            style: SfType.label.copyWith(
              color: color ?? SfColors.muted,
              height: 1.6,
            ),
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: SfType.body.copyWith(
              fontSize: 15,
              height: 1.55,
              color: color,
            ),
          ),
        ),
      ],
    );

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (SfAlphaCards.hasCover(
            e,
            enabled: SfAlphaCards.enabledOf(context),
          ))
            SfAlphaArtwork(exercise: e, thumbnail: true)
          else
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
                    child: Image.asset(
                      sfPoster(e),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SfSpace.x1,
              SfSpace.x2 + 2,
              SfSpace.x1,
              0,
            ),
            child: Text(
              e.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SfType.callout.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SfSpace.x1),
            child: Text(
              '${e.category.zh} · ${levelZh(e.level)} · ${e.effectiveEquipmentIds.isEmpty ? '徒手' : e.effectiveEquipmentIds.map(equipmentLabel).join('/')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SfType.caption.copyWith(color: SfColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}
