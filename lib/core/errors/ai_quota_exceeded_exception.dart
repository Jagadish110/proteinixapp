/// Thrown when the server-side daily AI quota (enforced by the
/// `gemini-proxy` edge function) has been used up for the current user.
///
/// Kept distinct from a generic network failure so screens can show
/// "you're out of AI calls for today" instead of "check your connection".
class AiQuotaExceededException implements Exception {
  final String message;
  AiQuotaExceededException(this.message);

  @override
  String toString() => message;
}
