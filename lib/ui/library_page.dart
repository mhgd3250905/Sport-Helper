import 'package:flutter/material.dart';

import '../app/services.dart';
import '../domain/exercise.dart';
import 'exercise_video.dart';
import 'theme.dart';

/// Every move in the library, filterable by category; tap to watch.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  ExerciseCategory? _cat;

  @override
  Widget build(BuildContext context) {
    final lib = AppServices.of(context).library;
    final list = lib.all.where((e) => _cat == null || e.category == _cat).toList();
    return Scaffold(
      appBar: AppBar(title: Text('动作库 · ${lib.length}')),
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(SfSpace.x4, SfSpace.x1, SfSpace.x4, SfSpace.x2),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: const Text('全部'), selected: _cat == null,
                    onSelected: (_) => setState(() => _cat = null)),
              ),
              for (final c in ExerciseCategory.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(c.zh), selected: _cat == c,
                      onSelected: (_) => setState(() => _cat = c)),
                ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(SfSpace.x4, SfSpace.x1, SfSpace.x4, SfSpace.x6),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, mainAxisSpacing: SfSpace.x3, crossAxisSpacing: SfSpace.x3, childAspectRatio: .76),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final e = list[i];
              return SfPressable(
                semanticLabel: e.name,
                onTap: () => _show(e),
                child: SfPanel(
                  padding: const EdgeInsets.all(6),
                  radius: SfRadius.md + 2,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(SfRadius.sm),
                      child: AspectRatio(aspectRatio: 1,
                          child: ColoredBox(
                            color: SfColors.mediaStage,
                            child: Image.asset(e.media.poster, fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const SizedBox.shrink()),
                          )),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
                      child: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: SfType.callout.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
                      child: Text('${e.category.zh} · ${levelZh(e.level)} · ${e.equipment.isEmpty ? '徒手' : e.equipment.map((q) => q.zh).join('/')}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: SfType.caption.copyWith(color: SfColors.muted)),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  void _show(Exercise e) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(SfSpace.x4, 0, SfSpace.x4, SfSpace.x4),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          ExerciseVideo(exercise: e, radius: SfRadius.lg),
          const SizedBox(height: SfSpace.x4),
          Text(e.name, style: SfType.title),
          const SizedBox(height: SfSpace.x1),
          Text('目标：${e.muscles.join('、')}${e.unilateral ? ' · 左右各做' : ''}', style: SfType.label),
          const SizedBox(height: SfSpace.x3),
          Text('要领：${e.cue}', style: SfType.body.copyWith(fontSize: 15)),
          if (e.cautions.isNotEmpty) ...[
            const SizedBox(height: SfSpace.x2),
            Text('注意：${e.cautions.join('、')}不适时减小幅度或换动作',
                style: SfType.label.copyWith(color: SfColors.caution)),
          ],
        ]),
      ),
    ),
  );
}
