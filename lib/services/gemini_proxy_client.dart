import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/errors/ai_quota_exceeded_exception.dart';
import 'supabase_service.dart';

/// Calls the `gemini-proxy` Supabase Edge Function instead of the Gemini API
/// directly.
///
/// The Gemini key lives only in the edge function's secrets — never in the
/// app bundle — and every call is authenticated as the current Supabase user
/// and metered server-side against their daily quota, so neither can be
/// bypassed by a patched client.
class GeminiProxyClient {
  static Future<String> generate({
    required String
        kind, // 'text' or 'vision' — matches the proxy's quota buckets
    required List<Map<String, dynamic>> contents,
    Map<String, dynamic> generationConfig = const {},
    String model = 'gemini-flash-latest',
  }) async {
    final FunctionResponse res;
    try {
      res = await SupabaseService.client.functions.invoke(
        'gemini-proxy',
        body: {
          'kind': kind,
          'model': model,
          'contents': contents,
          'generationConfig': generationConfig,
        },
      );
    } on FunctionException catch (e) {
      final details = e.details;
      final errorCode = details is Map ? details['error'] : null;
      final serverMessage =
          details is Map ? details['message'] as String? : null;

      if (e.status == 429 || errorCode == 'quota_exceeded') {
        throw AiQuotaExceededException(
          serverMessage ??
              "You've reached today's AI limit. Try again tomorrow.",
        );
      }
      throw Exception(serverMessage ?? 'AI request failed (${e.status}).');
    }

    final data = res.data;
    if (data is Map && data['text'] is String) {
      return data['text'] as String;
    }
    throw Exception('AI request returned an unexpected response.');
  }
}
