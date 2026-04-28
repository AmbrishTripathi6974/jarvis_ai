import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  static const String appTitle = 'JARVIS';
  static const String geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta';

  static const Duration minimumUiOperationDuration = Duration(milliseconds: 650);
  static const Duration assistantWordRevealDelay = Duration(milliseconds: 60);
  static const Duration assistantStreamStallTimeout = Duration(seconds: 8);
  static const int assistantInitialRevealWordBuffer = 3;

  static const Duration connectTimeout = Duration(seconds: 20);
  static const Duration receiveTimeout = Duration(minutes: 2);
  static const Duration sendTimeout = Duration(seconds: 20);

  static const String _defaultGeminiModel = 'gemini-2.5-flash';
  static const List<String> _defaultFallbackGeminiModels = [
    // Order matters: try higher capacity next, then cheaper/lighter.
    'gemini-2.5-pro',
    'gemini-2.0-flash-lite',
  ];

  static String get geminiModel {
    final configured = dotenv.env['GEMINI_MODEL']?.trim();
    if (configured == null || configured.isEmpty) {
      return _defaultGeminiModel;
    }

    // Accept both `models/<id>` and `<id>`.
    if (configured.startsWith('models/')) {
      return configured.substring('models/'.length);
    }
    return configured;
  }

  static List<String> get geminiModelFailoverChain {
    final primary = geminiModel;
    final configuredFallbacks = _fallbackModelsFromEnv();
    final chain = <String>[primary];
    for (final model in configuredFallbacks) {
      if (model != primary) {
        chain.add(model);
      }
    }
    return chain;
  }

  static List<String> _fallbackModelsFromEnv() {
    final raw = dotenv.env['GEMINI_MODEL_FALLBACKS']?.trim();
    if (raw == null || raw.isEmpty) {
      return _defaultFallbackGeminiModels;
    }

    final models = raw
        .split(',')
        .map((m) => m.trim())
        .where((m) => m.isNotEmpty)
        .map((m) => m.startsWith('models/') ? m.substring('models/'.length) : m)
        .toList();

    return models.isEmpty ? _defaultFallbackGeminiModels : models;
  }

  static String get geminiApiKey => dotenv.env['GEMINI_API_KEY']?.trim() ?? '';

  static Uri geminiStreamUri({String? model}) => Uri.parse(
        '$geminiBaseUrl/models/${model ?? geminiModel}:streamGenerateContent?alt=sse',
      );
}
