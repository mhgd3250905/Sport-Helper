import 'package:flutter/material.dart';
import 'package:ugk_trainer/ugk_trainer.dart';

import '../app/app_test_catalog.dart';
import '../app/services.dart';
import '../diagnostics/action_issue.dart';
import '../domain/exercise.dart';
import 'action_issue_form.dart';
import 'alpha_artwork.dart';
import 'library_page.dart';
import 'theme.dart';

/// Internal catalog review surface. Missing prescriptions remain browsable;
/// they are never represented as made-up exercises or doses.
class AppTestLibraryPage extends StatefulWidget {
  const AppTestLibraryPage({super.key, required this.catalog, this.initial});

  final AppTestCatalog catalog;
  final ExerciseCategory? initial;

  @override
  State<AppTestLibraryPage> createState() => _AppTestLibraryPageState();
}

class _AppTestLibraryPageState extends State<AppTestLibraryPage> {
  late ExerciseCategory? _category = widget.initial;

  @override
  Widget build(BuildContext context) {
    final entries = widget.catalog.entries.values
        .where(
          (entry) =>
              _category == null ||
              entry.training?.raw['category'] == _category!.name,
        )
        .toList();
    return Scaffold(
      appBar: const SfTopBar(title: '动作库'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '${widget.catalog.entries.length} 个动作 · App 测试版，未审',
              style: SfType.caption,
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                for (final category in <ExerciseCategory?>[
                  null,
                  ...ExerciseCategory.values,
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SfChoiceChip(
                      key: ValueKey('test-cat-${category?.name ?? 'all'}'),
                      label: category?.zh ?? '全部',
                      selected: category == _category,
                      onTap: () => setState(() => _category = category),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? const Center(child: Text('这一类还没有动作'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final fallback = AppServices.of(
                        context,
                      ).library.tryGet(entry.id);
                      return SfPressable(
                        key: ValueKey('test-action-${entry.id}'),
                        semanticLabel: entry.nameZh,
                        onTap: () => showAppTestExerciseDetails(context, entry),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 104,
                              child: _CatalogArtwork(
                                entry: entry,
                                fallback: fallback?.media,
                                thumbnail: true,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(entry.nameZh, style: SfType.headline),
                                  const SizedBox(height: 6),
                                  Text(
                                    _equipment(entry),
                                    style: SfType.caption,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    entry.trainingEligible
                                        ? '训练说明完整'
                                        : '训练说明待补',
                                    style: SfType.caption,
                                  ),
                                  if (entry.media == null &&
                                      !_hasVideo(context, fallback?.media))
                                    Text('视频素材待补', style: SfType.caption),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

Future<void> showAppTestExerciseDetails(
  BuildContext context,
  AppTestCatalogEntry entry,
) {
  final exercise = AppServices.of(context).library.tryGet(entry.id);
  if (entry.trainingEligible && exercise != null) {
    return showExerciseDetails(context, exercise);
  }
  return showModalBottomSheet<void>(
    context: context,
    routeSettings: const RouteSettings(name: 'app_test_exercise_details'),
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: SfMotion.sheet,
    builder: (_) => _CatalogDetails(entry: entry, fallback: exercise?.media),
  );
}

/// The action and revision come from the catalog entry at the tap. A playback
/// handle accidentally rebound to another action must not attach its position.
Future<ActionIssueContext> captureCatalogActionIssueContext({
  required AppTestCatalogEntry entry,
  required Future<DrillMediaPlaybackSnapshot?> Function() capturePlayback,
  required bool hasVideo,
  DateTime? capturedAt,
}) async {
  final at = capturedAt ?? DateTime.now().toUtc();
  DrillMediaPlaybackSnapshot? snapshot;
  var reason = hasVideo
      ? ActionIssueVideoUnavailableReason.notReady
      : ActionIssueVideoUnavailableReason.noVideo;
  try {
    snapshot = await capturePlayback();
  } on Object {
    reason = ActionIssueVideoUnavailableReason.unavailable;
  }
  final seconds = snapshot?.videoSeconds;
  final valid =
      hasVideo &&
      snapshot?.mediaId == entry.id &&
      snapshot?.ready == true &&
      seconds != null &&
      seconds.isFinite &&
      seconds >= 0;
  if (!valid && snapshot != null && hasVideo) {
    reason = ActionIssueVideoUnavailableReason.unavailable;
  }
  return ActionIssueContext(
    actionId: entry.id,
    revision: entry.revision,
    revisionUnavailableReason: entry.revision == null
        ? 'metadata_not_available'
        : null,
    videoSeconds: valid ? seconds : null,
    videoPositionUnavailableReason: valid ? null : reason,
    capturedAt: valid ? snapshot!.capturedAt : at,
  );
}

class _CatalogDetails extends StatefulWidget {
  const _CatalogDetails({required this.entry, this.fallback});
  final AppTestCatalogEntry entry;
  final ExerciseMedia? fallback;

  @override
  State<_CatalogDetails> createState() => _CatalogDetailsState();
}

class _CatalogDetailsState extends State<_CatalogDetails> {
  final _playback = DrillMediaPlaybackHandle();
  bool _started = false;
  bool _paused = false;
  bool _marking = false;

  @override
  void dispose() {
    _playback.dispose();
    super.dispose();
  }

  Future<void> _mark() async {
    if (_marking) return;
    final store = AppServices.of(context).store.actionIssueStore;
    if (!store.enabled) return;
    setState(() => _marking = true);
    try {
      final capture = await captureCatalogActionIssueContext(
        entry: widget.entry,
        capturePlayback: _playback.capture,
        hasVideo:
            widget.entry.media != null || _hasVideo(context, widget.fallback),
      );
      if (!mounted) return;
      setState(() => _paused = true);
      await showActionIssueForm(context, store: store, capture: capture);
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final alpha = entry.media;
    final fallback = widget.fallback;
    final light = Theme.of(context).brightness == Brightness.light;
    final palette = light ? SfPalette.light : SfPalette.dark;
    final hasVideo = alpha != null || _hasVideo(context, fallback);
    final fields = entry.training?.raw;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              if (_started)
                DrillMediaView(
                  key: ValueKey('test-detail-video-${entry.id}'),
                  media: DrillMedia(
                    id: entry.id,
                    videoAsset: light
                        ? fallback?.lightVideo ?? ''
                        : fallback?.video ?? '',
                    posterAsset:
                        fallback?.playbackPosterFor(light: light) ?? '',
                    duration: alpha?.loopSeconds ?? fallback?.loopSeconds ?? 0,
                    posterTime: 0,
                    packedAlphaVideoAsset: alpha?.packedVideo,
                    packedAlphaPosterAsset: alpha?.playbackPoster,
                    bundledOnly: true,
                    videoAvailable: hasVideo,
                    theme: light ? 'light' : 'dark',
                  ),
                  paused: _paused,
                  stage: palette.mediaStage,
                  errorColor: palette.onStageMuted,
                  errorLabel: '示范暂时无法播放',
                  unavailableLabel: '视频素材待补',
                  playbackHandle: _playback,
                )
              else
                _CatalogArtwork(entry: entry, fallback: fallback),
              if (hasVideo)
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: SfCircleButton(
                    key: ValueKey('test-detail-play-${entry.id}'),
                    icon: _started && !_paused ? SfGlyph.pause : SfGlyph.play,
                    size: 52,
                    tooltip: _started && !_paused ? '暂停示范' : '播放示范',
                    onPressed: () => setState(() {
                      if (!_started) {
                        _started = true;
                        _paused = false;
                      } else {
                        _paused = !_paused;
                      }
                    }),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(entry.nameZh, style: SfType.title),
          const SizedBox(height: 8),
          Text(_equipment(entry), style: SfType.callout),
          const SizedBox(height: 8),
          Text('App 测试版 · 未审', style: SfType.caption),
          if (!entry.trainingEligible) ...[
            const SizedBox(height: 16),
            Text('训练说明待补', style: SfType.headline),
            Text('可预览素材、标记问题；说明补齐后将自动进入 AI 可选范围。', style: SfType.body),
          ] else if (fields != null) ...[
            const SizedBox(height: 16),
            Text(_doseText(fields['defaultDose']), style: SfType.callout),
            if (_strings(fields['muscles']).isNotEmpty)
              Text(
                '目标肌群：${_strings(fields['muscles']).join('、')}',
                style: SfType.body,
              ),
            if (fields['cues'] case final Map cues)
              for (final cue in _strings(cues['zh']))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(cue, style: SfType.body),
                ),
          ],
          if (!hasVideo) ...[
            const SizedBox(height: 12),
            Text('视频素材待补', style: SfType.caption),
          ],
          if (AppServices.of(context).store.actionIssueStore.enabled) ...[
            const SizedBox(height: 20),
            SfTextAction(
              key: ValueKey('test-detail-mark-${entry.id}'),
              label: '标记动作问题',
              icon: SfGlyph.clipboard,
              onPressed: _marking ? null : _mark,
            ),
          ],
        ],
      ),
    );
  }
}

class _CatalogArtwork extends StatelessWidget {
  const _CatalogArtwork({
    required this.entry,
    this.fallback,
    this.thumbnail = false,
  });
  final AppTestCatalogEntry entry;
  final ExerciseMedia? fallback;
  final bool thumbnail;

  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    final alpha = thumbnail ? entry.media?.thumbnail : entry.media?.cover;
    final poster = alpha ?? (light ? fallback?.lightPoster : fallback?.poster);
    if (alpha != null) {
      return RepaintBoundary(
        child: AspectRatio(
          aspectRatio: 1,
          child: SfAlphaCardSurface(
            radius: SfRadius.lg,
            child: SfAlphaAsset(
              asset: alpha,
              errorBuilder: (_, _, _) =>
                  const Center(child: SfIcon(SfGlyph.figure, size: 40)),
            ),
          ),
        ),
      );
    }
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SfRadius.lg),
        child: ColoredBox(
          color: (light ? SfPalette.light : SfPalette.dark).mediaStage,
          child: poster?.isNotEmpty == true
              ? Image.asset(
                  poster!,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) =>
                      const Center(child: SfIcon(SfGlyph.figure, size: 40)),
                )
              : const Center(child: SfIcon(SfGlyph.figure, size: 40)),
        ),
      ),
    );
  }
}

bool _hasVideo(BuildContext context, ExerciseMedia? media) =>
    media?.videoAvailableFor(
      light: Theme.of(context).brightness == Brightness.light,
    ) ??
    false;

List<String> _strings(Object? raw) => raw is List
    ? raw.whereType<String>().where((s) => s.isNotEmpty).toList()
    : [];

String _equipment(AppTestCatalogEntry entry) {
  final authored = _strings(entry.raw['equipmentZh']);
  if (authored.isNotEmpty) return authored.join('、');
  if (entry.equipment.isEmpty) return '徒手';
  return entry.equipment
      .map((id) {
        for (final known in Equipment.values) {
          if (known.name == id) return known.zh;
        }
        return id;
      })
      .join('、');
}

String _doseText(Object? raw) {
  if (raw is! Map) return '';
  final seconds = raw['seconds'] ?? raw['workSeconds'];
  final parts = <String>[
    if (raw['sets'] != null) '${raw['sets']} 组',
    if (raw['mode'] == 'reps' && raw['reps'] != null) '${raw['reps']} 次',
    if (raw['mode'] == 'time' && seconds != null) '$seconds 秒',
    if (raw['holdSeconds'] != null) '每次保持 ${raw['holdSeconds']} 秒',
    if (raw['restSeconds'] != null) '组间休息 ${raw['restSeconds']} 秒',
  ];
  return parts.join(' · ');
}
