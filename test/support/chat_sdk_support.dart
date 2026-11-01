import 'package:smartfit/app/coach_chat.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_chat/ugk_coach_chat.dart';

import '../support.dart';
import 'coach_v2_fixtures.dart';

AppServices sdkChatServices(AppStore store, CoachV2Fixtures fixture) =>
    AppServices(
      library: fixture.library,
      catalog: loadCatalog(),
      store: store,
      coachCatalog: fixture.catalog,
      coachProfile: fixture.profile,
      poseHubCatalog: fixture.poseHub,
      voiceLibrary: VoiceLibrary.empty,
      voiceOutput: const MutedVoiceOutput(),
      chatReplyDelay: Duration.zero,
    );

CoachChatController fakeHostChat(
  AppServices services,
  coach.LlmClient client, {
  DateTime Function()? clock,
}) => createSmartfitChat(
  services,
  gateway: CoachGatewayBinding.shared(client),
  clock: clock,
);
