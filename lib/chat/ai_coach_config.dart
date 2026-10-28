import 'package:ugk_coach/ugk_coach.dart' as coach;

/// Internal API credentials are supplied at build time, never from App storage.
class AiCoachConfig {
  const AiCoachConfig({this.token = ''});
  const AiCoachConfig.fromEnvironment()
    : token = const String.fromEnvironment('SMARTFIT_AI_TOKEN');

  final String token;
  bool get enabled => token.trim().isNotEmpty;

  static const baseUrl = 'https://ai.uuugk.win/v1';
  static const model = 'deepseek-flash';

  coach.OpenAiCompatibleClient createClient({required String deviceId}) =>
      coach.OpenAiCompatibleClient(
        // Retry individual steps in CoachAgent, without transport retries.
        config: coach.LlmConfig.ugkWorker.copyWith(
          baseUrl: baseUrl,
          model: model,
          maxRetries: 0,
        ),
        auth: coach.ApiKeyAuth(token.trim()),
      );
}
