library;

/// Unified Groq ML Service
/// ONE API call per article (combines sentiment + category + readability).
/// Sequential queue with staggered delay → stays within free tier TPM limits.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'sentiment_analyzer.dart';
import 'category_classifier.dart';
import 'readability_scorer.dart';

class GroqMLResult {
  final SentimentResult sentiment;
  final CategoryResult category;
  final ReadabilityResult readability;
  const GroqMLResult({
    required this.sentiment,
    required this.category,
    required this.readability,
  });
}

class GroqMLService {
  static const String _groqApiKey =
      'put your Groq API key here (e.g. sk-xxxx) - get one at https://www.groq.com';
  static const String _groqUrl =
      'Put your Groq endpoint URL here (e.g. https://api.groq.com/v1/endpoint/your-endpoint-id/completions) ';

  // FIX: llama-3.3-70b-versatile follows strict JSON far better than gemma2-9b-it
  static const String _model = 'llama-3.3-70b-versatile';

  static final Map<String, GroqMLResult> _cache = {};

  static final _queue = <_QueueEntry>[];
  static bool _draining = false;

  static const Map<String, int> _avgArticleWords = {
    'en': 600,
    'de': 550,
    'fr': 580,
    'es': 570,
    'it': 560,
    'pt': 570,
    'ar': 500,
    'ur': 450,
    'hi': 480,
    'fa': 480,
    'zh': 800,
    'zh-hans': 800,
    'zh-hant': 800,
    'ja': 1200,
    'ko': 550,
    'ru': 520,
    'uk': 500,
    'tr': 520,
    'id': 500,
    'ms': 500,
  };
  static const Map<String, double> _langWpm = {
    'en': 238,
    'de': 220,
    'fr': 250,
    'es': 250,
    'it': 240,
    'pt': 240,
    'ar': 150,
    'fa': 150,
    'ur': 150,
    'he': 160,
    'hi': 160,
    'bn': 160,
    'ta': 140,
    'zh': 260,
    'zh-hans': 260,
    'zh-hant': 260,
    'ja': 400,
    'ko': 200,
    'th': 120,
    'vi': 180,
    'id': 200,
    'ms': 200,
    'tr': 180,
  };
  static const Map<String, String> _categoryEmojis = {
    'politics': '🏛️',
    'technology': '💻',
    'health': '🏥',
    'business': '📈',
    'sports': '⚽',
    'science': '🔬',
    'entertainment': '🎬',
    'general': '📰',
  };
  static const Set<String> _trustedApiCategories = {
    'science',
    'technology',
    'health',
    'business',
    'sports',
    'entertainment',
  };

  // Political keywords for fallback detection when LLM is unavailable
  static const List<String> _politicsKeywords = [
    'election', 'parliament', 'minister', 'president', 'prime minister',
    'government', 'senate', 'congress', 'vote', 'party', 'political',
    'diplomat', 'treaty', 'legislation', 'bill', 'law', 'policy',
    'انتخاب', 'حکومت', 'وزیر', 'پارلیمان', 'سیاست', // Urdu
    'سياسة', 'حكومة', 'انتخابات', 'وزير', 'برلمان', // Arabic
    'siyaset', 'hükümet', 'seçim', 'meclis', 'bakan', // Turkish
    'चुनाव', 'सरकार', 'संसद', 'मंत्री', 'राजनीति', // Hindi
  ];

  static Future<GroqMLResult> analyze(
    String title,
    String description, {
    String apiCategory = 'top',
    String language = 'en',
  }) {
    final key = '${title.hashCode}_${description.hashCode}_$apiCategory';
    if (_cache.containsKey(key)) return Future.value(_cache[key]);

    final entry = _QueueEntry(
      title: title,
      description: description,
      apiCategory: apiCategory,
      language: language,
      cacheKey: key,
    );
    _queue.add(entry);
    _drain();
    return entry.completer.future;
  }

  static void _drain() async {
    if (_draining) return;
    _draining = true;
    while (_queue.isNotEmpty) {
      final entry = _queue.removeAt(0);
      GroqMLResult result;
      try {
        result = await _callGroq(
          entry.title,
          entry.description,
          entry.apiCategory,
          entry.language,
        );
        _cache[entry.cacheKey] = result;
        entry.completer.complete(result);
      } on _RateLimitException catch (e) {
        // Re-insert at front and pause the whole drain loop for the
        // duration Groq requested.  Previously each call retried itself
        // recursively, so N articles in-flight produced N independent
        // back-off loops that all fired simultaneously → another 429 wave.
        debugPrint('[GroqMLService] Rate limit, waiting ${e.waitMs}ms');
        _queue.insert(0, entry);
        await Future.delayed(Duration(milliseconds: e.waitMs));
        continue;
      } catch (e) {
        debugPrint('[GroqMLService] "${_short(entry.title)}": $e');
        result = _smartFallback(
          entry.title,
          entry.description,
          entry.apiCategory,
          entry.language,
        );
        _cache[entry.cacheKey] = result;
        entry.completer.complete(result);
      }
      if (_queue.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 700));
      }
    }
    _draining = false;
  }

  static Future<GroqMLResult> _callGroq(
    String title,
    String description,
    String apiCategory,
    String language,
  ) async {
    final trusted = _trustedApiCategories.contains(apiCategory.toLowerCase());

    final prompt =
        '''Analyze this news article. Language code: $language.
Title: $title
Description: $description

Reply with ONLY a JSON object (no markdown, no text before or after):
{"sentiment":"positive","score":0.7,"readability":"simple"${trusted ? '' : ',"category":"politics"'}}

Strict rules:
- sentiment: "negative"=war/crisis/disaster/death/scandal/corruption/protest, "positive"=achievement/growth/award/peace/breakthrough/success, "neutral"=routine/informational/factual
- score: number from -1.0 to +1.0. Negative sentiment MUST have negative score (e.g. -0.6). Positive MUST have positive score (e.g. +0.7). Neutral near 0.
- readability: "simple"=everyday language most people understand easily, "advanced"=technical/legal/scientific vocabulary, "moderate"=some specialized terms but generally accessible
${trusted ? '' : '- category: "politics" for elections/voting/government/parliament/ministers/president/prime minister/foreign policy/diplomacy/coup/legislation — IMPORTANT: news API never tags these as politics, you must detect it\n'}
Important: Most news is NOT neutral — war is negative, economic growth is positive, elections can be either. Be decisive.''';

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
            'max_tokens': 80,
            'temperature': 0.15,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 429) {
      final body = jsonDecode(response.body);
      final msg = body['error']?['message'] as String? ?? '';
      final match = RegExp(r'([0-9.]+)s').firstMatch(msg);
      final waitMs =
          ((double.tryParse(match?.group(1) ?? '3') ?? 3.0) * 1000 + 500)
              .toInt();
      // Throw a typed exception so _drain can back off globally,
      // instead of each request retrying independently (which causes the
      // cascade of repeated 429s you see in the logs).
      throw _RateLimitException(waitMs);
    }

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final raw =
        (data['choices'] as List?)?.first?['message']?['content'] as String? ??
        '{}';

    // FIX: Extract JSON by finding first { to last } — handles any surrounding text
    final cleaned = _extractJson(raw);

    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Bad JSON: $cleaned');
    }

    final sentStr = (parsed['sentiment'] as String? ?? 'neutral')
        .toLowerCase()
        .trim();
    final score = (parsed['score'] as num?)?.toDouble().clamp(-1.0, 1.0) ?? 0.0;

    final SentimentResult sentiment;
    if (sentStr == 'positive' || (sentStr == 'neutral' && score > 0.25)) {
      sentiment = SentimentResult(
        sentiment: Sentiment.positive,
        score: score > 0 ? score : score.abs(),
        label: 'Positive',
        emoji: '😊',
      );
    } else if (sentStr == 'negative' ||
        (sentStr == 'neutral' && score < -0.25)) {
      sentiment = SentimentResult(
        sentiment: Sentiment.negative,
        score: score < 0 ? score : -score.abs(),
        label: 'Negative',
        emoji: '😟',
      );
    } else {
      sentiment = SentimentResult(
        sentiment: Sentiment.neutral,
        score: score,
        label: 'Neutral',
        emoji: '😐',
      );
    }

    // Category
    String cat = trusted
        ? apiCategory.toLowerCase()
        : (parsed['category'] as String? ?? 'general').toLowerCase().trim();
    if (!_categoryEmojis.containsKey(cat)) cat = 'general';
    final category = CategoryResult(
      category: cat,
      emoji: _categoryEmojis[cat]!,
      confidence: 0.85,
      fromLLM: !trusted,
    );

    // FIX: Readability with meaningfully different reading times per level
    final levelStr = (parsed['readability'] as String? ?? 'moderate')
        .toLowerCase()
        .trim();
    final (level, lLabel, lEmoji) = switch (levelStr) {
      'simple' => (ReadingLevel.simple, 'Simple', '🟢'),
      'advanced' => (ReadingLevel.advanced, 'Advanced', '🔴'),
      _ => (ReadingLevel.moderate, 'Moderate', '🟡'),
    };
    final avgWords = _avgArticleWords[language] ?? 600;
    final wpm = _langWpm[language] ?? 200;
    // Different multipliers give visibly different times:
    // simple=fast reader speed, moderate=0.75x, advanced=0.55x
    final adjWpm = level == ReadingLevel.simple
        ? wpm * 1.0
        : level == ReadingLevel.moderate
        ? wpm * 0.75
        : wpm * 0.55;
    final readSec = ((avgWords / adjWpm) * 60).clamp(60.0, 1800.0).round();
    final readability = ReadabilityResult(
      level: level,
      label: lLabel,
      emoji: lEmoji,
      readingTimeSeconds: readSec,
      fleschScore: level == ReadingLevel.simple
          ? 75.0
          : level == ReadingLevel.moderate
          ? 45.0
          : 20.0,
    );

    return GroqMLResult(
      sentiment: sentiment,
      category: category,
      readability: readability,
    );
  }

  static String _extractJson(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      return raw.substring(start, end + 1);
    }
    return raw.replaceAll(RegExp(r'```[a-z]*\n?|```'), '').trim();
  }

  /// Smart fallback: use keyword matching for politics detection
  /// so the politics filter still works even when Groq fails.
  static GroqMLResult _smartFallback(
    String title,
    String description,
    String apiCategory,
    String language,
  ) {
    final combined = '${title.toLowerCase()} ${description.toLowerCase()}';
    final trusted = _trustedApiCategories.contains(apiCategory.toLowerCase());

    String cat;
    if (trusted) {
      cat = apiCategory.toLowerCase();
    } else {
      // Check for political keywords
      final isPolitics = _politicsKeywords.any(
        (kw) => combined.contains(kw.toLowerCase()),
      );
      cat = isPolitics ? 'politics' : 'general';
    }

    final avgWords = _avgArticleWords[language] ?? 600;
    final wpm = _langWpm[language] ?? 200;
    final readSec = ((avgWords / wpm) * 60).clamp(60.0, 1800.0).round();

    return GroqMLResult(
      sentiment: const SentimentResult(
        sentiment: Sentiment.neutral,
        score: 0.0,
        label: 'Neutral',
        emoji: '😐',
      ),
      category: CategoryResult(
        category: cat,
        emoji: _categoryEmojis[cat] ?? '📰',
        confidence: 0.5,
      ),
      readability: ReadabilityResult(
        level: ReadingLevel.moderate,
        label: 'Moderate',
        emoji: '🟡',
        readingTimeSeconds: readSec,
        fleschScore: 50.0,
      ),
    );
  }

  static String _short(String s) =>
      s.length > 40 ? '${s.substring(0, 40)}…' : s;
}

class _QueueEntry {
  final String title, description, apiCategory, language, cacheKey;
  final completer = Completer<GroqMLResult>();
  _QueueEntry({
    required this.title,
    required this.description,
    required this.apiCategory,
    required this.language,
    required this.cacheKey,
  });
}

/// Thrown by [GroqMLService._callGroq] on HTTP 429 so that [_drain] can
/// pause the entire queue for the correct duration rather than each in-flight
/// request retrying independently (which was the source of the retry cascade).
class _RateLimitException implements Exception {
  final int waitMs;
  const _RateLimitException(this.waitMs);
}
