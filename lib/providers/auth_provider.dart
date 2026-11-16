import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/crash_log.dart';
import '../models/local/local_profile.dart';
import '../models/user_profile.dart';
import '../services/connectivity_service.dart';
import '../services/google_auth_service.dart';
import '../services/local_db_service.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../services/sync_service.dart';

/// Watches Supabase auth state.
///
/// The session itself is persisted locally by supabase_flutter, so this keeps
/// reporting a signed-in user with no network — which is the whole reason the
/// app can open offline.
final authStateProvider =
    StreamProvider((ref) => SupabaseService.client.auth.onAuthStateChange);

/// Current user profile, served from the local database.
final profileProvider =
    StateNotifierProvider<ProfileNotifier, AsyncValue<UserProfile?>>(
        (ref) => ProfileNotifier());

class ProfileNotifier extends StateNotifier<AsyncValue<UserProfile?>> {
  /// Seeds from the cache *synchronously*, so a returning user's first frame
  /// already shows their name and goals. Starting at `AsyncValue.loading()` and
  /// filling in a moment later is what made the dashboard flash a spinner on
  /// every open, even though the data was sitting in Hive the whole time.
  ProfileNotifier() : super(_seed()) {
    load();
  }

  static AsyncValue<UserProfile?> _seed() {
    try {
      final uid = SupabaseService.currentUserId;
      if (uid != null && LocalDBService.isReady) {
        final cached = LocalDBService.getProfile(uid);
        if (cached != null) return AsyncValue.data(cached.toDomain());
      }
    } catch (_) {}
    return const AsyncValue.loading();
  }

  /// Loads from Hive immediately, then refreshes from Supabase in the
  /// background when there's a connection.
  ///
  /// This never surfaces an error state for a network failure: a cached profile
  /// is a perfectly good profile, and the previous version's `AsyncValue.error`
  /// on a dropped connection is what pushed the whole UI into its error branch
  /// offline.
  Future<void> load() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) {
      state = const AsyncValue.data(null);
      return;
    }

    // Reading the cache is best-effort. A bad box must not be the reason the
    // user can't see their profile — we can always fall back to the network.
    UserProfile? cached;
    try {
      if (LocalDBService.isReady) {
        cached = LocalDBService.getProfile(uid)?.toDomain();
      }
    } catch (e, s) {
      await CrashLog.record('Profile cache read failed: $e', s);
    }
    if (cached != null) state = AsyncValue.data(cached);

    if (!ConnectivityService.isOnline) {
      // Nothing cached and no network: hand back null rather than an error so
      // callers show an empty profile instead of a failure screen.
      if (cached == null) state = const AsyncValue.data(null);
      return;
    }

    try {
      final row = await SupabaseService.client
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle()
          .timeout(SyncService.timeout);
      if (row == null) {
        if (cached == null) state = const AsyncValue.data(null);
        return;
      }
      final fresh = LocalProfile.fromRow(row);

      // Publish before caching, and never let the cache write fail the load.
      // Having successfully fetched the profile and then showing "Could not
      // load your profile" because a local write threw is exactly backwards —
      // the cache is an optimisation, not the source of truth.
      state = AsyncValue.data(fresh.toDomain());
      try {
        await LocalDBService.putProfileLocal(fresh);
      } catch (e, s) {
        await CrashLog.record('Profile cache write failed: $e', s);
      }
    } catch (e, st) {
      // Keep whatever was cached; only report an error if we have nothing.
      if (cached == null) state = AsyncValue.error(e, st);
    }
  }

  /// Saves locally and queues the upload. Succeeds offline.
  Future<void> update(UserProfile p) async {
    final previous = state.value;
    await LocalDBService.saveProfile(LocalProfile.fromDomain(p));
    state = AsyncValue.data(p);
    SyncService.syncPendingData();

    // Reminder bodies quote the user's water and step targets, and those
    // strings are handed to the OS when the alarm is registered — the alarm
    // fires with no Dart running, so nothing can re-read the profile at
    // delivery time. A changed target is therefore stale in the shade until the
    // alarms are rewritten against it.
    //
    // Hooked here rather than on the Profile tiles because this is the one
    // place every goal edit passes through: the tiles, "Edit all", and the
    // weight check-in that proposes new targets all land on this method. Wiring
    // it per-caller is how the water tile ended up the only one that refreshed.
    //
    // Only these two goals are scheduled ahead. Protein and calorie alerts are
    // built by [GoalAlerts] at the moment they fire, so they are never stale.
    if (previous == null ||
        previous.waterGoalMl != p.waterGoalMl ||
        previous.stepsGoal != p.stepsGoal) {
      unawaited(NotificationService.refreshGoalReminders());
    }
  }

  Future<void> signOut() async {
    // Flush the outbox *first*, while the session that owns it is still
    // active. `syncPendingData` requires a signed-in user, so this has to run
    // before Supabase signs out below — and it has to run before the cache
    // clear too, because a step count or meal edit logged minutes ago can
    // still be sitting unpushed. Bounded so a hung network can't turn "sign
    // out" into a spinner that never resolves; whatever doesn't make it in
    // time is not lost, only deferred — see LocalDBService.clearAll for why.
    try {
      await SyncService.syncPendingData().timeout(SyncService.timeout);
    } catch (e, s) {
      await CrashLog.record('Outbox flush before sign-out failed: $e', s);
    }

    // Clear the display cache: the boxes hold this account's data, and leaving
    // it behind would show one user's meals to whoever signs in next. The
    // outbox itself is untouched by this — see the comment on clearAll.
    await LocalDBService.clearAll();
    // Also drop the Google session, or the native picker silently reuses the
    // last account and a second user can never sign in on a shared phone.
    await GoogleAuthService.signOut();
    try {
      await SupabaseService.client.auth.signOut().timeout(SyncService.timeout);
    } catch (_) {
      // Offline sign-out still has to work — the local session is cleared by
      // the call above regardless of whether the server was reachable.
    }
    state = const AsyncValue.data(null);
  }

  /// Permanently deletes the account and every row it owns.
  ///
  /// Required by Play Store policy for any app that supports account
  /// creation. Runs through the `delete-account` edge function because
  /// removing the `auth.users` row — and the avatar files that don't cascade
  /// from it — needs the service role key, which must never reach the
  /// client. Throws on failure so the caller's dialog can show an error
  /// instead of silently signing the user out of an account that still
  /// exists.
  Future<void> deleteAccount() async {
    await SupabaseService.client.functions.invoke('delete-account');

    // The account is already gone server-side at this point; everything
    // below is local cleanup, unlike signOut there is nothing left to flush.
    await LocalDBService.clearAll();
    await GoogleAuthService.signOut();
    try {
      await SupabaseService.client.auth.signOut().timeout(SyncService.timeout);
    } catch (_) {
      // The session is invalid either way now — this only clears local state.
    }
    state = const AsyncValue.data(null);
  }
}
