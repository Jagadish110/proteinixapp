import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records uncaught errors to disk so a crash that happens away from a laptop
/// can still be read back later, from Profile → Diagnostics.
///
/// Release builds strip most console logging, so without this an unexplained
/// close leaves nothing behind to diagnose.
class CrashLog {
  const CrashLog._();

  static const _key = 'crash_log_entries';
  static const _maxEntries = 20;

  /// Installs handlers for both Flutter framework errors and raw Dart errors.
  static void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      unawaited(record(
        '${details.exceptionAsString()}\n${details.library ?? ''}'
        '${_context(details)}',
        details.stack,
      ));
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(record(error.toString(), stack));
      // Returning true marks it handled so the isolate isn't torn down.
      return true;
    };
  }

  /// Pulls the widget that caused a framework error out of [details].
  ///
  /// Layout errors — RenderFlex overflows above all — carry no stack trace, so
  /// without this a Diagnostics entry reads "A RenderFlex overflowed by 1.00
  /// pixels on the bottom / rendering library / no stack" and names neither the
  /// screen nor the widget. Everything needed to identify it is already on
  /// [details]; it just lives on `context`/`informationCollector` rather than
  /// in `exceptionAsString()`.
  ///
  /// `debugCreator` only carries the creation location in debug builds, which
  /// is where these get diagnosed anyway — in release this degrades to the
  /// context line alone rather than throwing.
  static String _context(FlutterErrorDetails details) {
    final parts = <String>[];

    final context = details.context?.toDescription();
    if (context != null && context.isNotEmpty && context != 'null') {
      parts.add('while $context');
    }

    // DiagnosticsNode for the offending element — includes the widget type and,
    // in debug, the file:line it was created at.
    for (final node
        in details.informationCollector?.call() ?? const <DiagnosticsNode>[]) {
      final line = node.toDescription().trim();
      if (line.isEmpty) continue;
      parts.add(line);
      if (parts.length >= 4) break; // Keep entries readable in the UI.
    }

    return parts.isEmpty ? '' : '\n${parts.join('\n')}';
  }

  static Future<void> record(String message, StackTrace? stack) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries = prefs.getStringList(_key) ?? <String>[];
      final trace =
          stack?.toString().split('\n').take(8).join('\n') ?? 'no stack';
      entries.insert(
          0, '${DateTime.now().toIso8601String()}\n$message\n$trace');
      await prefs.setStringList(
        _key,
        entries.take(_maxEntries).toList(),
      );
    } catch (_) {
      // Never let the crash reporter itself throw.
    }
  }

  static Future<List<String>> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? const [];
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
