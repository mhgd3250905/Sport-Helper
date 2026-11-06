import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_chat/ugk_coach_chat.dart';
import 'package:ugk_trainer/ugk_trainer.dart' show SessionResult;

import '../diagnostics/runtime_log.dart';
import '../diagnostics/coach_chat_diagnostics.dart';
import '../data/app_store.dart';
import '../domain/exercise.dart';
import '../domain/plan.dart';
import '../domain/saved_plan.dart';
import '../domain/session.dart' as session;
import '../ui/about_page.dart';
import '../ui/chat/saved_plans_page.dart';
import '../ui/chat/coach_chat_visuals.dart';
import '../ui/custom_plan_page.dart';
import '../ui/library_page.dart';
import '../ui/open_training.dart';
import '../ui/theme.dart';
import 'coach_chat_storage.dart';
import 'services.dart';
import 'training_transition_activity.dart';

const smartfitCoachChatNamespace = 'smartfit.chat.v1';

CoachAppProfile smartfitCoachAppProfile(AppServices services) {
  final catalog = services.coachCatalog;
  final profile = services.coachProfile;
  if (catalog == null || profile == null) {
    throw StateError(
      'SmartFit chat requires its loaded catalog and coach profile.',
    );
  }
  final master = services.poseHubCatalog?.raw ?? catalog.toJson();
  final ids =
      services.poseHubCatalog?.allActions.map((action) => action.id).toSet() ??
      catalog.drills.map((drill) => drill.id).toSet();
  return CoachAppProfile(
    appId: profile.id,
    scopeManifest: coach.CoachActionScopeManifest.fromCatalogBytes(
      appId: profile.id,
      catalogBytes: utf8.encode(jsonEncode(master)),
      // SmartFit selects the whole catalogue in use (profile `select: {}`);
      // the SDK drops not_recommended/retired from coach suggestions.
      allowedActionIds: ids,
    ),
    coachProfile: profile,
    agentMode: services.agentMode,
    aiTags: services.appAiTags,
    conversationPolicy: coach.CoachScopeConversationPolicy(
      specialty: '通用健身与拉伸',
      suggestions: const ['来一套 5 分钟拉伸', '推荐几个动作', '今天练什么'],
    ),
    executionTiming: session.SessionBuilder(services.library).executionTiming,
    visual: smartfitCoachChatVisuals(services.library),
  );
}

/// The same production profile and host stores serve the App and observed clients.
/// Supplying a gateway changes its lease only, never scope or validation.
CoachChatController createSmartfitChat(
  AppServices services, {
  CoachChatBindings? bindings,
  CoachGatewayBinding? gateway,
  DateTime Function()? clock,
}) {
  final diagnostics = CoachChatDiagnostics();
  late final CoachChatController controller;
  controller = CoachChatController(
    profile: smartfitCoachAppProfile(services),
    catalog: services.coachCatalog!,
    bindings:
        bindings ??
        smartfitCoachChatBindings(
          services,
          gateway: diagnostics.observeGateway(
            gateway ?? smartfitCoachGateway(services),
          ),
          controller: () => controller,
          observer: diagnostics.observe,
          beforeNewConversation: diagnostics.archiveConversation,
        ),
    replyDelay: services.chatReplyDelay,
    prepareReply: services.media == null
        ? null
        : () async {
            await services.media!.canDownload();
          },
    clock: clock,
  );
  diagnostics.attach(controller);
  return controller;
}

CoachChatBindings smartfitCoachChatBindings(
  AppServices services, {
  CoachGatewayBinding? gateway,
  CoachChatController Function()? controller,
  CoachChatObserver? observer,
  Future<void> Function(CoachChatSnapshot snapshot)? beforeNewConversation,
}) => CoachChatBindings(
  storageNamespace: smartfitCoachChatNamespace,
  gateway: gateway ?? smartfitCoachGateway(services),
  plans: SmartfitCoachPlanStore(services.store),
  history: SmartfitCoachChatHistoryStore(services.store),
  preferences: SmartfitCoachChatPreferenceStore(services.store),
  memory: services.userMemoryStore,
  actions: smartfitCoachChatActions(services, controller: controller),
  beforeNewConversation: beforeNewConversation,
  observer:
      observer ??
      (event, detail) => RuntimeLog.instance.record(
        'coach_chat.$event',
        fields: {
          if (detail != null) 'detailType': detail.runtimeType.toString(),
        },
      ),
);

CoachGatewayBinding smartfitCoachGateway(AppServices services) =>
    CoachGatewayBinding(
      create: () {
        if (!services.aiConfig.enabled || services.deviceId == null) {
          return const CoachClientLease.shared(_UnavailableCoachClient());
        }
        final client = services.aiConfig.createClient(
          deviceId: services.deviceId!,
        );
        return CoachClientLease.owned(client, release: client.close);
      },
    );

CoachChatHostActions smartfitCoachChatActions(
  AppServices services, {
  CoachChatController Function()? controller,
}) {
  CoachChatController chat() => controller?.call() ?? services.chat;
  return CoachChatHostActions(
    onStartTraining: _startTraining,
    onOpenLibrary: (context, request) => _push(
      context,
      LibraryPage(
        initial: request.initialCategoryId == null
            ? null
            : ExerciseCategory.byName(request.initialCategoryId!),
      ),
      'library',
    ),
    onOpenAction: (context, request) async {
      final exercise = services.library.tryGet(request.actionId);
      if (exercise != null) await showExerciseDetails(context, exercise);
    },
    onOpenSavedPlans: (context) => _push(
      context,
      SavedPlansPage(
        store: services.store,
        library: services.library,
        onShow: (saved) {
          Navigator.of(context).pop();
          unawaited(
            chat().sendPlanToConversation(
              SmartfitCoachPlanStore(services.store).snapshot(saved),
            ),
          );
        },
        onStart: (saved, sourceContext) => unawaited(
          chat().startTraining(
            sourceContext,
            ChatMessage(
              id: 'saved-${saved.id}',
              role: ChatRole.assistant,
              at: saved.savedAt,
              plan: session.trainerPlan(saved.plan),
              savedExternalId: saved.id,
              storageRevision: AppStore.savedPlanStorageRevision(saved),
              request: requestForPlan(session.trainerPlan(saved.plan)),
            ),
            sourceEntry: 'saved_plan',
          ),
        ),
        onCompose: () {
          Navigator.of(context).pop();
          chat().requestCompose();
        },
        onDetails: (saved, sourceContext) =>
            _openSavedDetails(sourceContext, chat(), services.store, saved),
      ),
      'saved_plans',
    ),
    onOpenCustomPlan: (context) =>
        _push(context, const CustomPlanPage(), 'custom_plan'),
    onOpenSettings: (context) => _push(context, const AboutPage(), 'settings'),
  );
}

Future<void> _push(BuildContext context, Widget page, String name) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      settings: RouteSettings(name: name),
      builder: (_) => page,
    ),
  );
}

Future<void> _openSavedDetails(
  BuildContext context,
  CoachChatController controller,
  AppStore store,
  SavedPlan saved,
) async {
  await controller.start();
  if (!context.mounted) return;
  final original = SmartfitCoachPlanStore(store).snapshot(saved);
  final selection = CoachSavedPlanSnapshot(
    externalId: original.externalId,
    title: original.title,
    plan: const coach.PlanCodec().decode({
      ...original.plan.toJson(),
      'title': saved.name,
    }),
    storageRevision: original.storageRevision,
    sdkVersion: original.sdkVersion,
    updatedAt: original.updatedAt,
  );
  final prepared = controller.prepareSavedPlanDetails(selection);
  if (!prepared.ok) {
    showSfToast(context, '计划不符合当前动作范围或训练条件。已保存计划仍保留。');
    return;
  }
  await _push(
    context,
    CoachChatPlanDetailsPage(controller: controller, plan: prepared.reference!),
    'plan',
  );
}

Future<SessionResult?> _startTraining(
  BuildContext context,
  CoachChatTrainingRequest request,
) async {
  // The existing route owns poster readiness, startGate, media teardown and
  // save-failure/replay holds. Mirror only its short entry/exit activity into
  // the SDK source viewport; never hold the complete workout.
  final activity = TrainingTransitionActivity.instance;
  VoidCallback? release = request.holdTransition();
  void synchronize() {
    if (activity.active) {
      release ??= request.holdTransition();
    } else {
      release?.call();
      release = null;
    }
  }

  activity.addListener(synchronize);
  try {
    return await openTraining(
      context,
      plan: TrainingPlan.fromJson(request.plan.plan.toJson()),
      sourceEntry: request.sourceEntry,
      onStarting: request.onStarting,
    );
  } finally {
    activity.removeListener(synchronize);
    release?.call();
  }
}

class _UnavailableCoachClient implements coach.LlmClient {
  const _UnavailableCoachClient();
  @override
  String get model => 'unconfigured';
  @override
  coach.Pricing? get pricing => null;
  @override
  Future<coach.LlmResponse> complete(
    coach.LlmRequest request, {
    coach.CancelToken? cancel,
  }) async => throw StateError('AI gateway is not configured.');
}
