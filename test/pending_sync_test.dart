import 'package:flutter_test/flutter_test.dart';
import 'package:proteinix/models/local/local_pending_sync.dart';

LocalPendingSync entry({int retries = 0, String? error}) => LocalPendingSync(
      id: 'x',
      table: 'daily_logs',
      operation: 'upsert',
      dataJson: '{}',
      createdAt: DateTime(2026, 8, 10),
      retryCount: retries,
      lastError: error,
    );

void main() {
  // Parking is what separates the two counters the sync badge and the drain
  // loop read: the badge counts everything, the loop skips parked entries.
  // Get this boundary wrong and a write either retries forever or vanishes
  // from the queue while still being counted.
  group('parking boundary', () {
    test('a fresh write is not parked', () {
      expect(entry().isParked, isFalse);
    });

    test('stays live right up to the limit', () {
      expect(entry(retries: LocalPendingSync.maxRetries - 1).isParked, isFalse);
    });

    test('parks on reaching the limit', () {
      expect(entry(retries: LocalPendingSync.maxRetries).isParked, isTrue);
    });

    test('stays parked beyond it', () {
      expect(entry(retries: LocalPendingSync.maxRetries + 10).isParked, isTrue);
    });
  });

  // What "Retry now" does: reset the count so the drain loop stops skipping it.
  // Connectivity is the usual cause of parking, so a released entry has to be
  // indistinguishable from a fresh one.
  test('clearing the retry count un-parks an entry', () {
    final e = entry(retries: LocalPendingSync.maxRetries);
    expect(e.isParked, isTrue);

    e.retryCount = 0;
    e.lastError = null;

    expect(e.isParked, isFalse);
    expect(e.lastError, isNull);
  });

  // Logging a meal on a weak connection parked the write, and coming back
  // online then flushed everything *except* it — the drain loop skips parked
  // entries. The badge counted it forever with no way back.
  group('parked by network vs parked by bad data', () {
    const network = [
      'SocketException: Software caused connection abort (OS Error: '
          'Software caused connection abort, errno = 103)',
      'TimeoutException after 0:00:12.000000: Future not completed',
      'ClientException with SocketException: Failed host lookup',
      'HandshakeException: Connection terminated during handshake',
      'SocketException: Connection reset by peer',
    ];

    for (final error in network) {
      test('"${error.split(':').first}" is recoverable', () {
        expect(LocalPendingSync.isNetworkError(error), isTrue);
        expect(entry(retries: 5, error: error).parkedByNetwork, isTrue);
      });
    }

    // These must stay parked however often the app reconnects — retrying a
    // genuinely malformed write forever is exactly what parking prevents.
    const permanent = [
      'PostgrestException(message: column "foo" does not exist, code: 42703)',
      'PostgrestException(message: new row violates row-level security policy)',
      'FormatException: Unexpected character',
    ];

    for (final error in permanent) {
      test('"${error.split('(').first}" stays parked', () {
        expect(LocalPendingSync.isNetworkError(error), isFalse);
        expect(entry(retries: 5, error: error).parkedByNetwork, isFalse);
      });
    }

    test('an entry with no recorded error stays parked', () {
      expect(entry(retries: 5).parkedByNetwork, isFalse);
    });

    test('a live entry is never "parked by network", whatever the error', () {
      expect(entry(retries: 2, error: network.first).parkedByNetwork, isFalse);
    });
  });
}
