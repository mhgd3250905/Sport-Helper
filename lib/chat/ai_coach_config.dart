import 'package:ugk_coach/ugk_coach.dart' as coach;

/// The proxy app key is supplied only at build time, never from App storage.
class AiCoachConfig {
  const AiCoachConfig({this.token = '', this.baseUrl = ''});
  const AiCoachConfig.fromEnvironment()
    : token = const String.fromEnvironment('SMARTFIT_AI_TOKEN'),
      baseUrl = const String.fromEnvironment('SMARTFIT_AI_BASE_URL');

  final String token;
  final String baseUrl;
  bool get enabled {
    if (token.trim().isEmpty) return false;
    final uri = Uri.tryParse(baseUrl.trim());
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }

  static const model = 'deepseek-v4-flash-0731';

  coach.OpenAiCompatibleClient createClient({required String deviceId}) {
    if (!enabled) {
      throw StateError('AI requires an explicit key and HTTPS service address');
    }
    return coach.OpenAiCompatibleClient(
      // Retry individual steps in CoachAgent, without transport retries.
      config: coach.LlmConfig(
        baseUrl: baseUrl.trim(),
        model: model,
        maxTokens: 6000,
        timeout: const Duration(seconds: 120),
        maxRetries: 0,
      ),
      auth: coach.UgkWorkerAuth(
        appKey: token.trim(),
        deviceId: () async => deviceId,
      ),
    );
  }
}
