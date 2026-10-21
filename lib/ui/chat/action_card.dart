import 'package:flutter/material.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import '../../domain/exercise.dart';
import '../theme.dart' show levelZh;
import '../theme/media_theme.dart';
import '../theme/sf_icons.dart';
import '../theme/tokens.dart';
import '../theme/widgets.dart';

/// Only the SDK gate can supply actions to this card. Names and media resolve
/// from the bundled library so model data never selects an asset or route.
class ActionCard extends StatelessWidget {
  const ActionCard({
    super.key,
    required this.actions,
    required this.library,
    required this.onOpen,
  });

  final coach.ValidatedActions actions;
  final ExerciseLibrary library;
  final ValueChanged<Exercise> onOpen;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: SfPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('动作推荐', style: SfType.callout),
            for (final action in actions.items)
              if (library.tryGet(action.id) case final exercise?)
                Padding(
                  padding: const EdgeInsets.only(top: SfSpace.x3),
                  child: SfPressable(
                    key: ValueKey('coach-action-${action.id}'),
                    semanticLabel: '查看${exercise.name}动作详情',
                    onTap: () => onOpen(exercise),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(SfRadius.sm),
                          child: Image.asset(
                            sfPoster(exercise),
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const SizedBox.square(dimension: 64),
                          ),
                        ),
                        const SizedBox(width: SfSpace.x3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(exercise.name, style: SfType.callout),
                              Text(
                                '${exercise.category.zh} · ${levelZh(exercise.level)}',
                                style: SfType.caption,
                              ),
                              if (action.note case final note?
                                  when note.isNotEmpty)
                                Text(note, style: SfType.caption),
                            ],
                          ),
                        ),
                        const SizedBox(width: SfSpace.x2),
                        SfIcon(
                          SfGlyph.chevronRight,
                          size: 18,
                          color: SfColors.muted,
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
