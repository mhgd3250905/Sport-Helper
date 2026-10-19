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
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
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
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: .78),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final e = list[i];
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _show(e),
                child: Container(
                  decoration: BoxDecoration(color: SfColors.surface, borderRadius: BorderRadius.circular(14)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                      child: AspectRatio(aspectRatio: 1,
                          child: Image.asset(e.media.poster, fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const ColoredBox(color: SfColors.bg))),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                      child: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text('${e.category.zh} · ${levelZh(e.level)} · ${e.equipment.isEmpty ? '徒手' : e.equipment.map((q) => q.zh).join('/')}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: SfColors.muted, fontSize: 12)),
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
    backgroundColor: SfColors.surface,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          ExerciseVideo(exercise: e),
          const SizedBox(height: 10),
          Text(e.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('要领：${e.cue}', style: const TextStyle(height: 1.5)),
          Text('目标：${e.muscles.join('、')}${e.unilateral ? ' · 左右各做' : ''}',
              style: const TextStyle(color: SfColors.muted)),
          if (e.cautions.isNotEmpty)
            Text('注意：${e.cautions.join('、')}不适时减小幅度或换动作',
                style: const TextStyle(color: SfColors.warn, fontSize: 13)),
        ]),
      ),
    ),
  );
}
