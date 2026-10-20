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
        config: const coach.LlmConfig(
          baseUrl: baseUrl,
          model: model,
          maxTokens: 6000,
          timeout: Duration(seconds: 45),
          maxRetries: 0,
        ),
        auth: _ProxyAuth(appKey: token.trim(), deviceId: deviceId),
      );
}

class _ProxyAuth implements coach.AuthProvider {
  const _ProxyAuth({required this.appKey, required this.deviceId});

  final String appKey;
  final String deviceId;

  @override
  Future<Map<String, String>> headers() async => {
    'X-App-Key': appKey,
    'X-Device-Id': deviceId,
  };
}
