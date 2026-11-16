import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/api_keys.dart';
import 'supabase_service.dart';

/// Raised when Google sign-in fails for a reason worth showing the user.
class GoogleAuthException implements Exception {
  const GoogleAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Google sign-in through the native Android account picker.
///
/// The previous flow called `signInWithOAuth`, which hands off to a Custom Tab:
/// browser chrome, a Google consent page, then a deep link back into the app.
/// That works, but it looks like leaving the app, and the round trip through
/// `io.supabase.proteinix://login-callback/` is a moving part that breaks quietly
/// whenever the scheme or the redirect allow-list drifts.
///
/// Here the platform shows the account sheet the user already knows, hands back
/// an ID token, and that token is exchanged with Supabase directly. No browser,
/// no deep link, no redirect configuration.
class GoogleAuthService {
  const GoogleAuthService._();

  /// `serverClientId` must be the **web** client ID, not the Android one, even
  /// though this only ever runs on Android: it sets the `aud` claim on the ID
  /// token, and Supabase validates that against the client IDs configured on
  /// its Google provider. Passing the Android client ID here yields a token
  /// Supabase rejects with a confusing audience-mismatch error.
  ///
  /// The Android client ID is never referenced in app code at all — it exists
  /// only so Google can match this build by package name and signing SHA-1.
  static final GoogleSignIn _google =
      GoogleSignIn(serverClientId: ApiKeys.googleWebClientId);

  /// Opens the account picker and signs the resulting user into Supabase.
  ///
  /// Returns false when the user dismissed the picker — a cancellation is a
  /// normal outcome, not an error, and showing a red banner for it is wrong.
  static Future<bool> signIn() async {
    if (ApiKeys.googleWebClientId.isEmpty) {
      throw const GoogleAuthException(
          'Google sign-in is not configured for this build.');
    }

    final GoogleSignInAccount? account;
    try {
      // Sign out first so the picker always appears. Without this a second
      // sign-in silently reuses the cached account, which is wrong on a shared
      // phone and makes "wrong account" unrecoverable without clearing data.
      await _google.signOut();
      account = await _google.signIn();
    } on PlatformException catch (e) {
      throw GoogleAuthException(_explain(e));
    }

    // Null means dismissed, which the plugin reports separately from a failure.
    if (account == null) return false;

    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) {
      throw const GoogleAuthException(
          'Google did not return an ID token. Check that the web client ID is '
          'a "Web application" credential.');
    }

    await SupabaseService.client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: auth.accessToken,
    );
    return true;
  }

  /// Turns the plugin's wrapped `ApiException` into something actionable.
  ///
  /// The status code is the only part that identifies the fault, and it arrives
  /// buried in a message like
  /// `com.google.android.gms.common.api.ApiException: 10: `. Status 10 is
  /// DEVELOPER_ERROR and is by far the most common — it means Google has no
  /// Android OAuth client matching this build's package name *and* signing
  /// certificate, which is invisible from inside the app.
  static String _explain(PlatformException e) {
    final detail = '${e.message ?? ''} ${e.details ?? ''}';

    if (detail.contains(': 10') || detail.contains('DEVELOPER_ERROR')) {
      return "This build isn't registered with Google (error 10). The Android "
          'OAuth client needs package com.proteinix and this build\'s SHA-1.';
    }
    if (detail.contains(': 7') || detail.contains('NETWORK_ERROR')) {
      return 'No connection to Google. Check your network and try again.';
    }
    if (detail.contains(': 12500') || detail.contains('SIGN_IN_FAILED')) {
      return 'Google sign-in failed. Check the OAuth consent screen is '
          'configured and your account is a test user if it is in Testing mode.';
    }
    return 'Google sign-in failed: ${e.message ?? e.code}';
  }

  /// Clears the Google session alongside the Supabase one.
  ///
  /// Without this the picker silently reuses the last account on the next sign
  /// in, so "sign out" wouldn't let a second user get in on a shared phone.
  /// Never throws — sign-out has to work offline and with Google unreachable.
  static Future<void> signOut() async {
    try {
      await _google.signOut();
    } catch (_) {}
  }
}
