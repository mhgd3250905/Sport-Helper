import 'dart:convert';
import 'dart:io';

import 'package:smartfit/app/app_test_catalog.dart';
import 'package:smartfit/app/app_test_content.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart' show PoseHubActionLibrary;

import '../support.dart';

/// Product catalogue/profile and model scripts using the SDK public protocol.
/// The fixture never sets an Agent ledger or admits a card itself.
class CoachV2Fixtures {
  CoachV2Fixtures._(this.library, this.catalog, this.profile);
  final ExerciseLibrary library;
  final coach.Catalog catalog;
  final coach.CoachProfile profile;

  static Future<CoachV2Fixtures> load() async {
    final config = File('.dart_tool/package_config.json');
    final packages =
        (jsonDecode(config.readAsStringSync()) as Map)['packages'] as List;
    final trainer = packages.cast<Map>().singleWhere(
      (p) => p['name'] == 'ugk_trainer',
    );
    final root = config.absolute.uri.resolve("${trainer['rootUri']}/");
    final bytes = await File.fromUri(
      root.resolve(
        '${PoseHubActionLibrary.assetRoot.replaceFirst('packages/ugk_trainer/', '')}catalog.json',
      ),
    ).readAsBytes();
    final sdk = coach.PoseHubAppTestCatalog.fromBytes(bytes);
    final content = AppTestContent.build(
      catalog: AppTestCatalog.fromSdk(sdk),
      legacyLibrary: loadLibrary(),
    );
    return CoachV2Fixtures._(
      content.library,
      content.coachCatalog,
      coach.CoachProfile.fromJson(
        jsonDecode(File('assets/coach/smartfit.json').readAsStringSync()),
      ),
    );
  }

  static const stretching = ['s-butterfly', 's-frog', 's-kneel-hipflex'];
  static const alternativeStretching = [
    's-butterfly',
    'h-adductor-rock',
    's-figure4',
  ];
  static const core = ['h-crunch', 'h-reverse-crunch', 'h-superman'];

  List<Object> planTurn({
    String prefix = 'plan',
    int? minutes = 10,
    String? minutesQuote = '10分钟',
    String? sceneQuote = '在家',
    String? equipmentQuote = '徒手',
    String? goalQuote = '拉伸',
    List<String> goals = const ['purpose.stretch'],
    List<String> ids = stretching,
    bool reuse = false,
    String? operation,
    String? operationQuote,
    Map<String, Object?> fields = const {},
  }) => [
    batch([
      call('$prefix-start', 'start_task', {
        'type': 'plan',
        if (reuse) 'reuse': true,
      }),
      call('$prefix-params', 'set_params', {
        'fields': {
          if (sceneQuote != null) 'scene': sourced('home', sceneQuote),
          if (equipmentQuote != null)
            'equipment': sourced(<String>[], equipmentQuote),
          if (goalQuote != null) 'goal': sourced(goals, goalQuote),
          if (minutes != null) 'minutes': sourced(minutes, minutesQuote!),
          if (operation != null)
            'operation': sourced(operation, operationQuote!),
          ...fields,
        },
      }),
      for (final id in ids)
        call('$prefix-search-$id', 'search_actions', {
          'tags': <String>[],
          'keywords': catalog[id]!.name.of('en'),
        }),
      call('$prefix-draft', 'draft_plan', {
        'title': '舒展练习',
        'blocks': [
          {
            'kind': 'main',
            'items': [
              for (final id in ids) {'id': id},
            ],
          },
        ],
      }),
    ]),
    (coach.LlmRequest request) {
      final result = receipt(request, '$prefix-draft');
      if (result['ok'] != true) {
        throw StateError('Fixture draft rejected: $result');
      }
      return batch([
        call('$prefix-show', 'show_plan', {
          'plan_id': result['plan_id'],
          'note': '从容易控制的动作开始，循序渐进。',
        }),
      ]);
    },
  ];

  List<Object> recommendationTurn({
    String prefix = 'recommend',
    List<String> ids = stretching,
    String quote = '拉伸',
  }) => [
    batch([
      call('$prefix-start', 'start_task', {'type': 'recommend'}),
      call('$prefix-params', 'set_params', {
        'fields': {
          'goal': sourced(['purpose.stretch'], quote),
        },
      }),
      for (final id in ids)
        call('$prefix-search-$id', 'search_actions', {
          'tags': <String>[],
          'keywords': catalog[id]!.name.of('en'),
        }),
      call('$prefix-show', 'show_actions', {
        'ids': ids,
        'note': '慢慢进入舒适的拉伸范围。',
      }),
    ]),
  ];

  static Map<String, Object?> sourced(Object value, String quote) => {
    'value': value,
    'source': 'user',
    'quote': quote,
  };
  static coach.LlmToolCall call(String id, String name, Object args) =>
      coach.LlmToolCall(id: id, name: name, arguments: jsonEncode(args));
  static coach.LlmResponse batch(List<coach.LlmToolCall> calls) =>
      coach.LlmResponse(
        content: '',
        toolCalls: calls,
        finishReason: 'tool_calls',
        model: 'fake-model',
      );
  static Map<String, dynamic> receipt(coach.LlmRequest request, String id) =>
      jsonDecode(request.messages.lastWhere((m) => m.toolCallId == id).content)
          as Map<String, dynamic>;
}
