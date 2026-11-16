/// A scored night, as the sleep screen and `daily_logs` see it.
///
/// Distinct from `SleepNight` in `sleep_tracking_service.dart`, which is the
/// raw native reading and carries diagnostics the UI has no use for. This is
/// the domain object: a night that has been measured, scored, and is ready to
/// store or draw.
class SleepResult {
  SleepResult({
    required this.sleepHours,
    required this.interruptions,
    required this.phonePickups,
    required this.date,
    this.sleepStart,
    this.sleepEnd,
  }) : sleepScore = _calculateScore(sleepHours, interruptions);

  /// Total time asleep — the dark stretches summed, not time in bed.
  final double sleepHours;

  /// Wake-ups the user returned to sleep from.
  final int interruptions;

  /// Times the screen was found on during the window. A floor: sampling every
  /// 15 minutes cannot see a phone picked up and put down between two checks.
  final int phonePickups;

  /// The day the night is credited to — the day the user woke.
  final DateTime date;

  /// When sleep was observed to start and end, as opposed to the window the
  /// user set. Null on nights recorded before these were tracked.
  final DateTime? sleepStart;
  final DateTime? sleepEnd;

  /// 0–100. See [_calculateScore] for what it does and does not mean.
  final int sleepScore;

  /// Duration out of 70, interruptions out of 30.
  ///
  /// The weighting is deliberate rather than derived: how long someone slept is
  /// the thing this app can measure most reliably, and interruptions are
  /// inferred from 15-minute samples that miss short wakes entirely. Scoring
  /// them evenly would put half the number on the shakier half of the data.
  ///
  /// Note that 9+ hours scores below 7–9 rather than above it. Oversleeping is
  /// not better than sleeping well, and a score that rose forever would tell
  /// someone sleeping eleven hours that they were doing great.
  static int _calculateScore(double hours, int interruptions) {
    final duration = switch (hours) {
      >= 7 && <= 9 => 70,
      >= 6 && < 7 => 55,
      > 9 => 60,
      >= 5 && < 6 => 40,
      _ => 25,
    };

    final rest = switch (interruptions) {
      0 => 30,
      1 => 25,
      2 => 18,
      3 => 10,
      _ => 5,
    };

    return (duration + rest).clamp(0, 100);
  }

  /// "7h 12m".
  String get durationLabel {
    final total = (sleepHours * 60).round();
    return '${total ~/ 60}h ${(total % 60).toString().padLeft(2, '0')}m';
  }

  /// How the score reads in words, for the badge under it.
  String get scoreLabel => switch (sleepScore) {
        >= 85 => 'Excellent',
        >= 70 => 'Good',
        >= 55 => 'Fair',
        _ => 'Poor',
      };

  /// Roughly how long was spent awake between stretches of sleep.
  ///
  /// Derived from the observed span rather than counted directly — the sampler
  /// records when sleep started and ended and how much of that was dark, so
  /// what is left over is the time awake in between. Null when the span is
  /// unknown, which is every night recorded before those timestamps existed.
  Duration? get timeAwake {
    final from = sleepStart;
    final to = sleepEnd;
    if (from == null || to == null) return null;
    final span = to.difference(from);
    final asleep = Duration(minutes: (sleepHours * 60).round());
    final awake = span - asleep;
    return awake.isNegative ? Duration.zero : awake;
  }

  factory SleepResult.fromMap(Map<dynamic, dynamic> map) {
    DateTime? at(String key) {
      final raw = map[key];
      if (raw == null) return null;
      if (raw is num) {
        return raw == 0
            ? null
            : DateTime.fromMillisecondsSinceEpoch(raw.toInt());
      }
      return DateTime.tryParse(raw.toString());
    }

    return SleepResult(
      sleepHours: (map['sleep_hours'] as num?)?.toDouble() ?? 0,
      interruptions: (map['interruptions'] as num?)?.toInt() ?? 0,
      phonePickups: (map['phone_pickups'] as num?)?.toInt() ?? 0,
      date: DateTime.tryParse(map['date']?.toString() ?? '') ?? DateTime.now(),
      sleepStart: at('sleep_start'),
      sleepEnd: at('sleep_end'),
    );
  }

  Map<String, dynamic> toMap() => {
        'sleep_hours': sleepHours,
        'sleep_interruptions': interruptions,
        'phone_pickups': phonePickups,
        'sleep_score': sleepScore,
        'sleep_start': sleepStart?.toIso8601String(),
        'sleep_end': sleepEnd?.toIso8601String(),
        'date': date.toIso8601String(),
      };
}
