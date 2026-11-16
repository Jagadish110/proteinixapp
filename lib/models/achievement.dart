class AiMessage {
  final String? id;
  final String userId;
  final String role; // 'user' | 'assistant'
  final String content;
  final DateTime createdAt;

  AiMessage({
    this.id,
    required this.userId,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  factory AiMessage.fromJson(Map<String, dynamic> j) => AiMessage(
        id: j['id'] as String?,
        userId: j['user_id'] as String,
        role: j['role'] as String,
        content: j['content'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

class WeightLog {
  final String? id;
  final String userId;
  final double weightKg;
  final DateTime date;

  WeightLog({
    this.id,
    required this.userId,
    required this.weightKg,
    required this.date,
  });

  factory WeightLog.fromJson(Map<String, dynamic> j) => WeightLog(
        id: j['id'] as String?,
        userId: j['user_id'] as String,
        weightKg: (j['weight_kg'] as num).toDouble(),
        date: DateTime.parse(j['date'] as String),
      );
}

class Achievement {
  final String? id;
  final String userId;
  final String type;
  final DateTime achievedAt;

  Achievement({
    this.id,
    required this.userId,
    required this.type,
    required this.achievedAt,
  });

  factory Achievement.fromJson(Map<String, dynamic> j) => Achievement(
        id: j['id'] as String?,
        userId: j['user_id'] as String,
        type: j['achievement_type'] as String,
        achievedAt: DateTime.parse(j['achieved_at'] as String),
      );
}
