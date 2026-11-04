import 'dart:convert';

import 'package:flutter/services.dart';

/// App-owned, unreviewed Pose-Hub AI drafts, included only for this test build.
/// Loading tags does not change the SDK's action scope or admission gates.
Future<Map<String, Map<String, Object?>>> loadAppAiTags({
  AssetBundle? bundle,
}) async {
  final raw =
      jsonDecode(
            await (bundle ?? rootBundle).loadString(
              'assets/coach/ai-tags/actions.json',
            ),
          )
          as Map<String, dynamic>;
  return Map.unmodifiable({
    for (final entry in raw.entries)
      entry.key: Map<String, Object?>.unmodifiable(
        Map<String, Object?>.from(entry.value as Map),
      ),
  });
}
