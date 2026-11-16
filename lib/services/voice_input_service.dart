import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Thin wrapper around on-device speech recognition for meal logging.
///
/// Keeps a single recogniser instance alive for the app and normalises the
/// permission dance so screens only deal with `start` / `stop` / callbacks.
class VoiceInputService {
  VoiceInputService._();
  static final VoiceInputService instance = VoiceInputService._();

  final SpeechToText _speech = SpeechToText();
  bool _available = false;

  bool get isListening => _speech.isListening;
  bool get isAvailable => _available;

  /// Returns null on success, or a human-readable reason it can't listen.
  Future<String?> prepare() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      return status.isPermanentlyDenied
          ? 'Microphone access is blocked. Enable it in system settings to log by voice.'
          : 'Microphone permission is needed to log by voice.';
    }

    try {
      _available = await _speech.initialize(
        onError: (_) {},
        onStatus: (_) {},
        debugLogging: false,
      );
    } catch (_) {
      _available = false;
    }

    return _available
        ? null
        : 'Speech recognition is not available on this device.';
  }

  /// Begins listening. [onResult] fires repeatedly with the running transcript;
  /// [onFinalResult] fires once when the recogniser settles.
  Future<void> start({
    required void Function(String transcript) onResult,
    required void Function(String transcript) onFinalResult,
    void Function(double level)? onSoundLevel,
    void Function(String message)? onError,
    String localeId = 'en_IN',
  }) async {
    if (!_available) {
      final reason = await prepare();
      if (reason != null) {
        onError?.call(reason);
        return;
      }
    }

    // Fall back to the device default if the preferred locale is unsupported.
    String? resolved;
    try {
      final locales = await _speech.locales();
      resolved = locales.any((l) => l.localeId == localeId)
          ? localeId
          : (await _speech.systemLocale())?.localeId;
    } catch (_) {
      resolved = null;
    }

    await _speech.listen(
      onResult: (r) {
        onResult(r.recognizedWords);
        if (r.finalResult) onFinalResult(r.recognizedWords);
      },
      onSoundLevelChange: onSoundLevel,
      listenOptions: SpeechListenOptions(
        localeId: resolved,
        partialResults: true,
        cancelOnError: false,
        listenMode: ListenMode.dictation,
        // Meals take a moment to describe — don't cut the user off mid-sentence.
        listenFor: const Duration(seconds: 45),
        pauseFor: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> stop() => _speech.stop();

  Future<void> cancel() => _speech.cancel();
}
