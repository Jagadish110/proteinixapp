import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:proteinix/services/onboarding_draft_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The draft is the only thing standing between an interrupted sign-up and a
/// re-typed form, and every one of these rules is a way it could quietly hand
/// back the wrong answers instead.
void main() {
  const uid = 'user-1';

  OnboardingDraft draft({
    int step = 1,
    String name = 'Jagadish',
    String? weightUnit,
    DateTime? savedAt,
  }) =>
      OnboardingDraft(
        step: step,
        name: name,
        age: '21',
        weight: '63',
        height: '170',
        weightUnit: weightUnit,
        gender: 'Male',
        goal: 'Gain Weight',
        savedAt: savedAt,
      );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('round-trips the step and the answers', () async {
    await OnboardingDraftService.save(draft(step: 2), uid: uid);
    final back = await OnboardingDraftService.load(uid: uid);

    expect(back, isNotNull);
    expect(back!.step, 2);
    expect(back.name, 'Jagadish');
    expect(back.goal, 'Gain Weight');
    expect(back.weight, '63');
  });

  test('keeps the unit the numbers were typed in', () async {
    // Restoring "63" as kilograms for someone who entered pounds is a silent
    // 39kg error that then recalculates every macro target.
    await OnboardingDraftService.save(draft(weightUnit: 'lbs'), uid: uid);
    expect((await OnboardingDraftService.load(uid: uid))!.weightUnit, 'lbs');
  });

  test('nothing is stored until there is something to resume', () async {
    // An untouched first step is not an abandoned session.
    expect(const OnboardingDraft(step: 0).isEmpty, isTrue);
    expect(const OnboardingDraft(step: 0, name: '  ').isEmpty, isTrue);
    expect(const OnboardingDraft(step: 1).isEmpty, isFalse);
    expect(const OnboardingDraft(step: 0, goal: 'Lose Weight').isEmpty, isFalse);
  });

  test('an empty draft is not handed back', () async {
    SharedPreferences.setMockInitialValues({
      'onboarding_draft': jsonEncode(const OnboardingDraft(step: 0).toJson()),
    });
    expect(await OnboardingDraftService.load(uid: uid), isNull);
  });

  test('clear removes it', () async {
    await OnboardingDraftService.save(draft(), uid: uid);
    await OnboardingDraftService.clear();
    expect(await OnboardingDraftService.load(uid: uid), isNull);
  });

  test("another account's draft is dropped, not inherited", () async {
    await OnboardingDraftService.save(draft(), uid: 'someone-else');
    expect(await OnboardingDraftService.load(uid: uid), isNull);

    // And dropped for good, so it cannot resurface for its original owner
    // either — a shared phone should not replay a stranger's half-typed form.
    expect(await OnboardingDraftService.load(uid: 'someone-else'), isNull);
  });

  test('a stale draft is discarded rather than replayed', () async {
    await OnboardingDraftService.save(
      draft(savedAt: DateTime.now().subtract(const Duration(days: 31))),
      uid: uid,
    );
    expect(await OnboardingDraftService.load(uid: uid), isNull);
  });

  test('a recent draft survives', () async {
    await OnboardingDraftService.save(
      draft(savedAt: DateTime.now().subtract(const Duration(days: 29))),
      uid: uid,
    );
    expect(await OnboardingDraftService.load(uid: uid), isNotNull);
  });

  test('corrupt json is survivable', () async {
    SharedPreferences.setMockInitialValues({'onboarding_draft': 'not json'});
    expect(await OnboardingDraftService.load(uid: uid), isNull);
  });

  test('a signed-out save is still restorable on the same device', () async {
    // uid is null before the session resolves; the draft should not be lost
    // just because ownership could not be stamped.
    await OnboardingDraftService.save(draft(), uid: null);
    expect(await OnboardingDraftService.load(uid: uid), isNotNull);
  });
}
