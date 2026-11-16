import 'supabase_service.dart';
import 'local_db_service.dart';

/// Where a user stands with the free trial of the AI features.
class TrialState {
  const TrialState({
    required this.active,
    required this.daysLeft,
    required this.known,
  });

  /// The AI features are usable without a subscription right now.
  final bool active;

  /// Whole days remaining, rounded up, so the last partial day still reads as
  /// "1 day left" rather than "0". Zero once the trial has ended.
  final int daysLeft;

  /// Whether the account's creation date was actually available. False means
  /// the answer is a guess — see [TrialService.state] for which way it guesses.
  final bool known;

  /// The trial has run out, as opposed to never having been established.
  bool get expired => known && !active;

  static const unknown =
      TrialState(active: true, daysLeft: TrialService.trialDays, known: false);
}

/// The three-day free run at the AI features — food scanning, text and voice
/// logging, and the AI Coach. Everything else in the app is free forever and
/// is never gated by this.
///
/// Anchored to `profiles.created_at`, which the server writes once and the
/// client never sends back. That is what stops the obvious attack: clearing
/// app data or reinstalling restores the same account with the same creation
/// date, so the three days cannot be restarted.
///
/// This is deliberately *not* a Google Play free trial. A Play trial requires
/// a payment method before the user has seen the food scanner work on their
/// own plate, which is the single thing most likely to sell the app.
class TrialService {
  const TrialService._();

  static const trialDays = 3;

  /// Reads the cached profile only — no network, so this is safe to call on
  /// every gated tap without adding latency to the thing the user just pressed.
  ///
  /// Fails **open**. If the creation date isn't known — a fresh install that
  /// hasn't pulled the profile yet, a signed-out session, Hive not ready — the
  /// trial reads as active. Wrongly paywalling someone who is entitled is a
  /// worse failure than briefly letting an expired user through, and the date
  /// arrives with the next sync anyway.
  static TrialState state() {
    try {
      final uid = SupabaseService.currentUserId;
      if (uid == null || !LocalDBService.isReady) return TrialState.unknown;

      final createdAt = LocalDBService.getProfile(uid)?.createdAt;
      if (createdAt == null) return TrialState.unknown;

      final ends = createdAt.add(const Duration(days: trialDays));
      final left = ends.difference(DateTime.now());
      // `<=`, not `isNegative`. At the exact expiry instant the remainder is
      // zero, which is not negative — so the trial reported itself active with
      // zero days left, the one contradictory state this is supposed to avoid.
      if (left <= Duration.zero) {
        return const TrialState(active: false, daysLeft: 0, known: true);
      }
      // Rounded up: 25 hours left is "2 days", 1 minute left is still "1 day".
      // Rounding down would tell someone mid-trial that they had none left.
      final days = (left.inMinutes / (24 * 60)).ceil();
      return TrialState(active: true, daysLeft: days, known: true);
    } catch (_) {
      return TrialState.unknown;
    }
  }
}
