import 'package:ugk_coach/ugk_coach.dart' as coach;

/// The proxy app key is supplied only at build time, never from App storage.
class AiCoachConfig {
  const AiCoachConfig({this.token = ''});
  const AiCoachConfig.fromEnvironment()
    : token = const String.fromEnvironment('SMARTFIT_AI_TOKEN');

  final String token;
  bool get enabled => token.trim().isNotEmpty;

  static const baseUrl = 'https://api.uuugk.win/v1';
  static const model = 'deepseek-v4-flash-0731';

  coach.OpenAiCompatibleClient createClient({required String deviceId}) =>
      coach.OpenAiCompatibleClient(
        // Retry individual steps in CoachAgent, without transport retries.
        config: coach.LlmConfig.ugkWorker.copyWith(maxRetries: 0),
        auth: coach.UgkWorkerAuth(
          appKey: token.trim(),
          deviceId: () async => deviceId,
        ),
      );
}
