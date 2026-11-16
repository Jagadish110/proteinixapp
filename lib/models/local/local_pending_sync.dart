import 'package:hive/hive.dart';

part 'local_pending_sync.g.dart';

/// One queued write waiting to reach Supabase — the app's outbox.
///
/// Every mutation lands in Hive first and drops an entry here; [SyncService]
/// drains the queue in creation order whenever the device is online. Ordering
/// matters: a meal insert has to reach the server before the delete that
/// removes it, or the delete no-ops and the meal reappears on the next pull.
@HiveType(typeId: 4)
class LocalPendingSync extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String table;

  @HiveField(2)
  String operation; // insert | upsert | delete

  @HiveField(3)
  String dataJson;

  @HiveField(4)
  DateTime createdAt;

  @HiveField(5)
  int retryCount;

  /// Identifies the row this entry targets, e.g. `daily_logs|<uid>|2026-08-02`.
  ///
  /// Entries sharing a key are collapsed to the newest one. Without this,
  /// tapping "+250ml" ten times offline queues ten full-state upserts of the
  /// same row, and only the last one could ever matter.
  @HiveField(6)
  String? dedupeKey;

  /// Last error seen, kept for Profile → Diagnostics rather than thrown away.
  @HiveField(7)
  String? lastError;

  LocalPendingSync({
    required this.id,
    required this.table,
    required this.operation,
    required this.dataJson,
    required this.createdAt,
    this.retryCount = 0,
    this.dedupeKey,
    this.lastError,
  });

  /// Entries that have failed this many times are parked: skipped by the
  /// drain loop so one poison record can't block the queue, but kept on disk
  /// so the user's data is never silently discarded.
  static const maxRetries = 5;

  bool get isParked => retryCount >= maxRetries;

  /// Errors that mean "there was no network", not "this write is bad".
  ///
  /// The distinction is what makes parking safe to undo. A poison row must
  /// stay parked however many times it is offered; a row that failed because
  /// the signal dropped will succeed the moment there is one, and leaving it
  /// parked strands it — the drain loop skips parked entries, so a reconnect
  /// flushes everything *except* the rows the outage broke.
  static final _networkError = RegExp(
    r'SocketException|TimeoutException|ClientException|HandshakeException|'
    r'Failed host lookup|connection abort|Connection closed|Connection reset|'
    r'Network is unreachable|No address associated',
    caseSensitive: false,
  );

  static bool isNetworkError(String? error) =>
      error != null && _networkError.hasMatch(error);

  /// Parked, but only because the connection was down — safe to retry once the
  /// app is online again.
  bool get parkedByNetwork => isParked && isNetworkError(lastError);
}
