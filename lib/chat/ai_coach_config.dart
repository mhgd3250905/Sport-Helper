import 'package:ugk_coach/ugk_coach.dart' as coach;

/// Internal API credentials are supplied at build time, never from App storage.
class AiCoachConfig {
  const AiCoachConfig({
    this.token = '',
    this.endpoint = baseUrl,
    this.modelName = model,
    this.authMode = 'bearer',
  });
  const AiCoachConfig.fromEnvironment()
    : token = const String.fromEnvironment('SMARTFIT_AI_TOKEN'),
      endpoint = const String.fromEnvironment(
        'SMARTFIT_AI_BASE_URL',
        defaultValue: baseUrl,
      ),
      modelName = const String.fromEnvironment(
        'SMARTFIT_AI_MODEL',
        defaultValue: model,
      ),
      authMode = const String.fromEnvironment(
        'SMARTFIT_AI_AUTH',
        defaultValue: 'bearer',
      );

  final String token;
  final String endpoint;
  final String modelName;
  final String authMode;
  bool get enabled => token.trim().isNotEmpty;

  static const baseUrl = 'https://ai.uuugk.win/v1';
  static const model = 'deepseek-flash';

  coach.OpenAiCompatibleClient createClient({required String deviceId}) =>
      coach.OpenAiCompatibleClient(
        // Retry individual steps in CoachAgent, without transport retries.
        config: coach.LlmConfig.ugkWorker.copyWith(
          baseUrl: endpoint,
          model: modelName,
          maxRetries: 0,
        ),
        auth: switch (authMode) {
          'bearer' => coach.ApiKeyAuth(token.trim()),
          'worker' => coach.UgkWorkerAuth(
            appKey: token.trim(),
            deviceId: () async => deviceId,
          ),
          _ => throw ArgumentError.value(authMode, 'SMARTFIT_AI_AUTH'),
        },
      );
}
