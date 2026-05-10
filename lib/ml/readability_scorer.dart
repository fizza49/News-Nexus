library;

/// ML Model 3: Readability Scorer
/// LLM-powered via Groq — language-aware for ALL languages.
/// Reading time uses a realistic full-article word count estimate
/// since we only have title+description (not full body text).

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum ReadingLevel { simple, moderate, advanced }

class ReadabilityResult {
  final ReadingLevel level;
  final String label;
  final String emoji;
  final int readingTimeSeconds;
  final double fleschScore; // 0–100, higher = easier

  const ReadabilityResult({
    required this.level,
    required this.label,
    required this.emoji,
    required this.readingTimeSeconds,
    required this.fleschScore,
  });

  String get readingTimeLabel {
    if (readingTimeSeconds < 60) return '<1m';
    final minutes = (readingTimeSeconds / 60).round();
    return '$minutes m read';
  }
}

class ReadabilityScorer {
  static const String _groqApiKey =
      'your Groq API key here (e.g. sk-xxxx) - get one at https://www.groq.com  ';
  static const String _groqUrl =
      'https://api.groq.com/openai/v1/chat/completions';
  static const String _model = 'llama-3.3-70b-versatile';

  // Typical reading speeds (words per minute) by language
  static const Map<String, double> _langWpm = {
    'en': 238,
    'de': 220,
    'fr': 250,
    'es': 250,
    'it': 240,
    'pt': 240,
    'nl': 220,
    'pl': 200,
    'ru': 180,
    'uk': 180,
    'sv': 220,
    'no': 220,
    'da': 220,
    'fi': 180,
    'cs': 180,
    'sk': 180,
    'hu': 180,
    'ro': 200,
    'ar': 150,
    'fa': 150,
    'ur': 150,
    'he': 160,
    'hi': 160,
    'bn': 160,
    'pa': 160,
    'ta': 140,
    'te': 140,
    'ml': 140,
    'kn': 140,
    'gu': 160,
    'mr': 160,
    'zh': 260,
    'zh-hans': 260,
    'zh-hant': 260,
    'ja': 400,
    'ko': 200,
    'th': 120,
    'vi': 180,
    'id': 200,
    'ms': 200,
    'tl': 200,
    'tr': 180,
  };

  // Average news article length by language (words/chars)
  // Used to estimate realistic reading time when only preview is available
  static const Map<String, int> _avgArticleWords = {
    'en': 600, 'de': 550, 'fr': 580, 'es': 570, 'it': 560, 'pt': 570,
    'ar': 500, 'ur': 450, 'hi': 480, 'fa': 480,
    'zh': 800, 'zh-hans': 800, 'zh-hant': 800, // chars
    'ja': 1200, // chars
    'ko': 550,
    'ru': 520, 'uk': 500,
    'tr': 520, 'id': 500, 'ms': 500,
  };

  static final Map<String, ReadabilityResult> _cache = {};

  static Future<ReadabilityResult> score(
    String title,
    String description, {
    String content = '',
    String language = 'en',
  }) async {
    final text = [
      title,
      description,
      content,
    ].where((s) => s.isNotEmpty).join(' ');

    final cacheKey = '${text.hashCode}_$language';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

    try {
      final result = await _callGroq(title, description, language);
      _cache[cacheKey] = result;
      return result;
    } catch (e) {
      debugPrint('[ReadabilityScorer] ERROR: $e');
      final fallback = _heuristicScore(text, language);
      _cache[cacheKey] = fallback;
      return fallback;
    }
  }

  static Future<ReadabilityResult> _callGroq(
    String title,
    String description,
    String language,
  ) async {
    final prompt =
        '''Assess the reading difficulty of this news article for a native speaker. Language: $language.
Title: $title
Description: $description
Reply ONLY with JSON (no markdown): {"level":"simple"|"moderate"|"advanced","flesch_equivalent":<0-100>}
simple=everyday words, short sentences (flesch 60-100)
moderate=some jargon, average sentences (flesch 30-59)
advanced=technical/specialized, complex grammar (flesch 0-29)''';

    final response = await http
        .post(
          Uri.parse(_groqUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_groqApiKey',
          },
          body: jsonEncode({
            'model': _model,
            'messages': [
              {'role': 'user', 'content': prompt},
            ],
            'max_tokens': 60,
            'temperature': 0.1,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Groq HTTP ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final raw =
        (data['choices'] as List?)?.first?['message']?['content'] as String? ??
        '{}';
    final cleaned = raw.replaceAll(RegExp(r'```[a-z]*\n?|```'), '').trim();
    final parsed = jsonDecode(cleaned) as Map<String, dynamic>;

    final levelStr = (parsed['level'] as String? ?? 'moderate')
        .toLowerCase()
        .trim();
    final flesch =
        (parsed['flesch_equivalent'] as num?)?.toDouble().clamp(0.0, 100.0) ??
        50.0;

    ReadingLevel level;
    String label;
    String emoji;
    switch (levelStr) {
      case 'simple':
        level = ReadingLevel.simple;
        label = 'Simple';
        emoji = '🟢';
        break;
      case 'advanced':
        level = ReadingLevel.advanced;
        label = 'Advanced';
        emoji = '🔴';
        break;
      default:
        level = ReadingLevel.moderate;
        label = 'Moderate';
        emoji = '🟡';
    }

    // Reading Time Estimation:
    // We only have title+description (~30-60 words).
    // Use the average full article length for this language instead
    final avgWords = _avgArticleWords[language] ?? 600;
    final wpm = _langWpm[language] ?? 200;
    final adjustedWpm = level == ReadingLevel.simple
        ? wpm
        : level == ReadingLevel.moderate
        ? wpm * 0.8
        : wpm * 0.65;
    final readingTimeSec = ((avgWords / adjustedWpm) * 60)
        .clamp(60.0, 1800.0)
        .round();

    return ReadabilityResult(
      level: level,
      label: label,
      emoji: emoji,
      readingTimeSeconds: readingTimeSec,
      fleschScore: flesch,
    );
  }

  static ReadabilityResult _heuristicScore(String text, String language) {
    final sentences = text
        .split(RegExp(r'[.!?。！？]+'))
        .where((s) => s.trim().isNotEmpty)
        .length
        .clamp(1, 999);
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final avgLen = words / sentences;

    ReadingLevel level;
    String label;
    String emoji;
    double flesch;
    if (avgLen < 15) {
      level = ReadingLevel.simple;
      label = 'Simple';
      emoji = '🟢';
      flesch = 70;
    } else if (avgLen < 25) {
      level = ReadingLevel.moderate;
      label = 'Moderate';
      emoji = '🟡';
      flesch = 45;
    } else {
      level = ReadingLevel.advanced;
      label = 'Advanced';
      emoji = '🔴';
      flesch = 20;
    }

    final avgWords = _avgArticleWords[language] ?? 600;
    final wpm = _langWpm[language] ?? 200;
    final adjustedWpm = level == ReadingLevel.simple
        ? wpm
        : level == ReadingLevel.moderate
        ? wpm * 0.8
        : wpm * 0.65;
    final readingTimeSec = ((avgWords / adjustedWpm) * 60)
        .clamp(60.0, 1800.0)
        .round();

    return ReadabilityResult(
      level: level,
      label: label,
      emoji: emoji,
      readingTimeSeconds: readingTimeSec,
      fleschScore: flesch,
    );
  }
}
