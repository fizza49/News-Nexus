library;

/// ML Model 1: Sentiment Analyzer
/// LLM-powered via Groq API — works for ALL languages.
/// Logs errors instead of silently swallowing them.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum Sentiment { positive, neutral, negative }

class SentimentResult {
  final Sentiment sentiment;
  final double score; // -1.0 to +1.0
  final String label;
  final String emoji;

  const SentimentResult({
    required this.sentiment,
    required this.score,
    required this.label,
    required this.emoji,
  });
}

class SentimentAnalyzer {
  static const String _groqApiKey =
      'your Groq API key here  get one at https://www.groq.com  ';
  static const String _groqUrl =
      'https://api.groq.com/openai/v1/chat/completions';
  static const String _model = 'llama-3.3-70b-versatile';

  static final Map<String, SentimentResult> _cache = {};

  static Future<SentimentResult> analyzeArticle(
    String title,
    String description, {
    String language = 'en',
  }) async {
    final cacheKey = '${title.hashCode}_${description.hashCode}';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

    try {
      final result = await _callGroq(title, description, language);
      _cache[cacheKey] = result;
      return result;
    } catch (e) {
      debugPrint('[SentimentAnalyzer] ERROR: $e');
      const fallback = SentimentResult(
        sentiment: Sentiment.neutral,
        score: 0.0,
        label: 'Neutral',
        emoji: '😐',
      );
      _cache[cacheKey] = fallback;
      return fallback;
    }
  }

  static Future<SentimentResult> _callGroq(
    String title,
    String description,
    String language,
  ) async {
    final prompt =
        '''Analyze the sentiment of this news article. Language: $language.
Title: $title
Description: $description
Reply ONLY with JSON (no markdown): {"sentiment":"positive"|"neutral"|"negative","score":<-1.0 to 1.0>}''';

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

    final sentStr = (parsed['sentiment'] as String? ?? 'neutral')
        .toLowerCase()
        .trim();
    final score = (parsed['score'] as num?)?.toDouble().clamp(-1.0, 1.0) ?? 0.0;

    return switch (sentStr) {
      'positive' => SentimentResult(
        sentiment: Sentiment.positive,
        score: score,
        label: 'Positive',
        emoji: '😊',
      ),
      'negative' => SentimentResult(
        sentiment: Sentiment.negative,
        score: score,
        label: 'Negative',
        emoji: '😟',
      ),
      _ => SentimentResult(
        sentiment: Sentiment.neutral,
        score: score,
        label: 'Neutral',
        emoji: '😐',
      ),
    };
  }
}
