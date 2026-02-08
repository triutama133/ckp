import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';

class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;

  bool get isListening => _isListening;
  bool get isInitialized => _isInitialized;

  /// Initialize speech recognition
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      // Request microphone permission
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        print('Microphone permission denied');
        return false;
      }

      // Initialize speech to text
      _isInitialized = await _speech.initialize(
        onError: (error) => print('Speech recognition error: $error'),
        onStatus: (status) => print('Speech recognition status: $status'),
      );

      return _isInitialized;
    } catch (e) {
      print('Error initializing speech recognition: $e');
      return false;
    }
  }

  /// Start listening for voice input
  Future<void> startListening({
    required Function(String) onResult,
    Function(String)? onPartialResult,
  }) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        throw Exception('Failed to initialize speech recognition');
      }
    }

    if (_isListening) {
      print('Already listening');
      return;
    }

    try {
      await _speech.listen(
        onResult: (result) {
          if (result.finalResult) {
            onResult(result.recognizedWords);
            _isListening = false;
          } else if (onPartialResult != null) {
            onPartialResult(result.recognizedWords);
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        localeId: 'id_ID', // Indonesian locale
        onSoundLevelChange: null,
        listenOptions: stt.SpeechListenOptions(
          partialResults: onPartialResult != null,
          cancelOnError: true,
          listenMode: stt.ListenMode.confirmation,
        ),
      );

      _isListening = true;
    } catch (e) {
      print('Error starting speech recognition: $e');
      _isListening = false;
      rethrow;
    }
  }

  /// Stop listening
  Future<void> stopListening() async {
    if (!_isListening) return;

    try {
      await _speech.stop();
      _isListening = false;
    } catch (e) {
      print('Error stopping speech recognition: $e');
    }
  }

  /// Cancel listening
  Future<void> cancelListening() async {
    if (!_isListening) return;

    try {
      await _speech.cancel();
      _isListening = false;
    } catch (e) {
      print('Error canceling speech recognition: $e');
    }
  }

  /// Quick voice to text conversion
  Future<String?> listenOnce({Duration timeout = const Duration(seconds: 10)}) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) return null;
    }

    String? result;
    final completer = Future<String?>(() async {
      await startListening(
        onResult: (text) {
          result = text;
        },
      );

      // Wait for result or timeout
      final startTime = DateTime.now();
      while (result == null && DateTime.now().difference(startTime) < timeout) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (!_isListening) break;
      }

      if (result == null) {
        await stopListening();
      }

      return result;
    });

    return await completer;
  }

  /// Get available locales
  Future<List<stt.LocaleName>> getAvailableLocales() async {
    if (!_isInitialized) {
      await initialize();
    }

    return await _speech.locales();
  }

  /// Check if speech recognition is available
  Future<bool> isAvailable() async {
    return await _speech.initialize();
  }

  /// Dispose resources
  void dispose() {
    if (_isListening) {
      _speech.stop();
    }
  }
}
