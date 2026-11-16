import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Everything the onboarding wizard needs to pick up where it was abandoned.
///
/// Deliberately a flat bag of strings rather than a [UserProfile]: half of
/// these are partially typed, in whichever unit the user had selected, and one
/// of them is "which step were you on". None of that is a profile yet, and
/// modelling it as one would mean inventing values for fields nobody has
/// filled in.
class OnboardingDraft {
  const OnboardingDraft({
    required this.step,
    this.name,
    this.age,
    this.weight,
    this.height,
    this.targetWeight,
    this.weightUnit,
    this.heightUnit,
    this.gender,
    this.goal,
    this.activity,
    this.avatarUrl,
    this.savedAt,
  });

  factory OnboardingDraft.fromJson(Map<String, dynamic> j) => OnboardingDraft(
        step: (j['step'] as num?)?.toInt() ?? 0,
        name: j['name'] as String?,
        age: j['age'] as String?,
        weight: j['weight'] as String?,
        height: j['height'] as String?,
        targetWeight: j['targetWeight'] as String?,
        weightUnit: j['weightUnit'] as String?,
        heightUnit: j['heightUnit'] as String?,
        gender: j['gender'] as String?,
        goal: j['goal'] as String?,
        activity: j['activity'] as String?,
        avatarUrl: j['avatarUrl'] as String?,
        savedAt: DateTime.tryParse(j['savedAt'] as String? ?? ''),
      );

  /// Which page the wizard was on, so returning lands on the question the user
  /// walked away from rather than back at their name.
  final int step;

  /// Raw field text, not parsed numbers — a half-typed "7" is worth keeping,
  /// and parsing it here would either round it to something the user never
  /// entered or throw it away.
  final String? name;
  final String? age;
  final String? weight;
  final String? height;
  final String? targetWeight;

  /// Which unit those numbers were entered in. Without these, "70" comes back
  /// as kilograms for someone who typed pounds.
  final String? weightUnit;
  final String? heightUnit;

  final String? gender;
  final String? goal;
  final String? activity;

  /// An avatar already uploaded to storage. The upload survives the abandoned
  /// session, so re-asking for the photo would be asking twice for something
  /// already done.
  final String? avatarUrl;

  final DateTime? savedAt;

  Map<String, dynamic> toJson() => {
        'step': step,
        'name': name,
        'age': age,
        'weight': weight,
        'height': height,
        'targetWeight': targetWeight,
        'weightUnit': weightUnit,
        'heightUnit': heightUnit,
        'gender': gender,
        'goal': goal,
        'activity': activity,
        'avatarUrl': avatarUrl,
        'savedAt': (savedAt ?? DateTime.now()).toIso8601String(),
      };

  /// Nothing worth restoring — an untouched first step.
  bool get isEmpty =>
      step == 0 &&
      (name == null || name!.trim().isEmpty) &&
      goal == null &&
      activity == null;
}

/// Keeps a half-finished onboarding run so leaving the app doesn't cost it.
///
/// ## When this writes
///
/// Only when the user actually leaves mid-way — the screen saves on
/// `AppLifecycleState.paused` and on backing out, never on every keystroke.
/// Someone who fills the three steps in one sitting therefore never touches
/// local storage at all, which is the intended behaviour: there is nothing to
/// resume, so there is nothing to keep.
///
/// ## When it clears
///
/// The moment the profile upsert succeeds. A draft outliving its own
/// completion is how a finished user gets dropped back into step 2 on their
/// next launch, so [clear] runs before the wizard routes onward.
///
/// Scoped to a user id, because a shared phone signing into a second account
/// must not inherit the first one's half-typed answers.
class OnboardingDraftService {
  const OnboardingDraftService._();

  static const _keyDraft = 'onboarding_draft';
  static const _keyOwner = 'onboarding_draft_uid';

  /// Past this, a draft is someone's abandoned experiment rather than a
  /// session they mean to resume, and silently re-filling a month-old weight
  /// is worse than asking again.
  static const _maxAge = Duration(days: 30);

  static Future<void> save(OnboardingDraft draft, {required String? uid}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyDraft, jsonEncode(draft.toJson()));
      if (uid != null) await prefs.setString(_keyOwner, uid);
    } catch (_) {
      // A draft that fails to save costs a re-typed form, never the flow.
    }
  }

  /// The stored draft, or null when there is none, it belongs to someone else,
  /// or it has gone stale.
  static Future<OnboardingDraft?> load({required String? uid}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyDraft);
      if (raw == null) return null;

      final owner = prefs.getString(_keyOwner);
      if (owner != null && uid != null && owner != uid) {
        // A different account's draft. Drop it rather than carry it forward.
        await clear();
        return null;
      }

      final draft = OnboardingDraft.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);

      final at = draft.savedAt;
      if (at != null && DateTime.now().difference(at) > _maxAge) {
        await clear();
        return null;
      }
      return draft.isEmpty ? null : draft;
    } catch (_) {
      // Corrupt or from an older shape. Not worth blocking onboarding over.
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyDraft);
      await prefs.remove(_keyOwner);
    } catch (_) {
      // Best effort; a stale draft is bounded by [_maxAge] regardless.
    }
  }
}
