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
  static const String _groqApiKey = 'your grok api key here';
  static const String _groqUrl =
      'https://api.groq.com/openai/v1/chat/completions';

  // llama-3.1-8b-instant = much faster than 70b, still accurate for simple JSON tasks
  static const String _model = 'llama-3.1-8b-instant';

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

  static const List<String> _politicsKeywords = [
    'election',
    'parliament',
    'minister',
    'president',
    'prime minister',
    'government',
    'senate',
    'congress',
    'vote',
    'party',
    'political',
    'diplomat',
    'treaty',
    'legislation',
    'bill',
    'law',
    'policy',
    'انتخاب',
    'حکومت',
    'وزیر',
    'پارلیمان',
    'سیاست',
    'سياسة',
    'حكومة',
    'انتخابات',
    'وزير',
    'برلمان',
    'siyaset',
    'hükümet',
    'seçim',
    'meclis',
    'bakan',
    'चुनाव',
    'सरकार',
    'संसद',
    'मंत्री',
    'राजनीति',
  ];

  static const List<String> _negativeKeywords = [
    'war',
    'kill',
    'killed',
    'dead',
    'death',
    'deaths',
    'attack',
    'attacked',
    'crash',
    'crisis',
    'flood',
    'fire',
    'murder',
    'bomb',
    'bombing',
    'disaster',
    'protest',
    'riot',
    'arrested',
    'corruption',
    'scandal',
    'explosion',
    'shooting',
    'violence',
    'collapse',
    'ban',
    'sanction',
    'earthquake',
    'hurricane',
    'drought',
    'famine',
    'poverty',
    'conflict',
    'hostage',
    'terror',
    'terrorist',
    'massacre',
    'genocide',
    'coup',
    'قتل',
    'موت',
    'حادثہ',
    'دہشت',
    'سیلاب',
    'آگ',
    'لڑائی',
    'مقتول',
    'ہلاک',
    'تباہی',
    'بم',
    'دھماکہ',
    'احتجاج',
  ];

  static const List<String> _positiveKeywords = [
    'win',
    'won',
    'winner',
    'success',
    'growth',
    'award',
    'launch',
    'record',
    'achieve',
    'achievement',
    'peace',
    'deal',
    'breakthrough',
    'recover',
    'recovery',
    'improve',
    'improvement',
    'rise',
    'gain',
    'celebrate',
    'celebration',
    'relief',
    'rescue',
    'saved',
    'progress',
    'innovation',
    'discovery',
    'cure',
    'vaccine',
    'historic',
    'milestone',
    'کامیاب',
    'ترقی',
    'فتح',
    'کامیابی',
    'انعام',
    'امن',
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
      try {
        final result = await _callGroq(
          entry.title,
          entry.description,
          entry.apiCategory,
          entry.language,
        );
        _cache[entry.cacheKey] = result;
        entry.completer.complete(result);
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('rate_limit_retry') && entry.retries < 2) {
          entry.retries++;
          _queue.insert(0, entry); // retry at front of queue
        } else {
          debugPrint(
            '[GroqMLService] Giving up on "${_short(entry.title)}": $e',
          );
          final result = _smartFallback(
            entry.title,
            entry.description,
            entry.apiCategory,
            entry.language,
          );
          _cache[entry.cacheKey] = result;
          entry.completer.complete(result);
        }
      }
      if (_queue.isNotEmpty) {
        // 700ms between calls — fast enough, within Groq free tier
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

    // Shorter prompt = faster response (fewer tokens to process)
    final prompt = trusted
        ? 'News title: $title\nDesc: $description\n\nRespond ONLY with JSON, no extra text:\n{"sentiment":"positive","score":0.7,"readability":"simple"}\nsentiment=negative/positive/neutral, score=-1.0 to 1.0, readability=simple/moderate/advanced. War/death/crisis=negative. Growth/win/peace=positive.'
        : 'News title: $title\nDesc: $description\n\nRespond ONLY with JSON, no extra text:\n{"sentiment":"positive","score":0.7,"readability":"simple","category":"politics"}\nsentiment=negative/positive/neutral, score=-1.0 to 1.0, readability=simple/moderate/advanced, category=politics/general. War/death/crisis=negative. Growth/win/peace=positive. Detect politics: election/government/minister/parliament/vote.';

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
            'max_tokens': 60, // reduced from 80 — we only need ~50 tokens
            'temperature': 0.1, // lower = more consistent, faster
          }),
        )
        .timeout(const Duration(seconds: 10)); // reduced from 15s

    if (response.statusCode == 429) {
      final body = jsonDecode(response.body);
      final msg = body['error']?['message'] as String? ?? '';
      final match = RegExp(r'([0-9.]+)s').firstMatch(msg);
      final waitMs = ((double.tryParse(match?.group(1) ?? '5') ?? 5.0) * 1000)
          .toInt()
          .clamp(2000, 8000); // wait between 2s and 8s max
      debugPrint('[GroqMLService] Rate limit, waiting ${waitMs}ms');
      await Future.delayed(Duration(milliseconds: waitMs));
      throw Exception('rate_limit_retry');
    }

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final raw =
        (data['choices'] as List?)?.first?['message']?['content'] as String? ??
        '{}';

    final cleaned = _extractJson(raw);

    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Bad JSON: $cleaned');
    }

    // --- Sentiment ---
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

    // --- Category ---
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

    // --- Readability ---
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

  /// Keyword-based fallback — gives real sentiment/category without Groq
  static GroqMLResult _smartFallback(
    String title,
    String description,
    String apiCategory,
    String language,
  ) {
    final combined = '${title.toLowerCase()} ${description.toLowerCase()}';
    final trusted = _trustedApiCategories.contains(apiCategory.toLowerCase());

    // Sentiment via keywords
    final isNegative = _negativeKeywords.any((kw) => combined.contains(kw));
    final isPositive =
        !isNegative && _positiveKeywords.any((kw) => combined.contains(kw));

    final sentiment = isNegative
        ? SentimentResult(
            sentiment: Sentiment.negative,
            score: -0.5,
            label: 'Negative',
            emoji: '😟',
          )
        : isPositive
        ? SentimentResult(
            sentiment: Sentiment.positive,
            score: 0.5,
            label: 'Positive',
            emoji: '😊',
          )
        : SentimentResult(
            sentiment: Sentiment.neutral,
            score: 0.0,
            label: 'Neutral',
            emoji: '😐',
          );

    // Category via keywords
    String cat;
    if (trusted) {
      cat = apiCategory.toLowerCase();
    } else {
      final isPolitics = _politicsKeywords.any(
        (kw) => combined.contains(kw.toLowerCase()),
      );
      cat = isPolitics ? 'politics' : 'general';
    }

    // Readability — vary it by sentiment/content length hint
    final wordCount = combined.split(' ').length;
    final ReadingLevel level;
    if (wordCount < 20) {
      level = ReadingLevel.simple;
    } else if (wordCount > 60) {
      level = ReadingLevel.advanced;
    } else {
      level = ReadingLevel.moderate;
    }

    final avgWords = _avgArticleWords[language] ?? 600;
    final wpm = _langWpm[language] ?? 200;
    final adjWpm = level == ReadingLevel.simple
        ? wpm * 1.0
        : level == ReadingLevel.moderate
        ? wpm * 0.75
        : wpm * 0.55;
    final readSec = ((avgWords / adjWpm) * 60).clamp(60.0, 1800.0).round();

    final (lLabel, lEmoji) = switch (level) {
      ReadingLevel.simple => ('Simple', '🟢'),
      ReadingLevel.advanced => ('Advanced', '🔴'),
      _ => ('Moderate', '🟡'),
    };

    return GroqMLResult(
      sentiment: sentiment,
      category: CategoryResult(
        category: cat,
        emoji: _categoryEmojis[cat] ?? '📰',
        confidence: 0.5,
      ),
      readability: ReadabilityResult(
        level: level,
        label: lLabel,
        emoji: lEmoji,
        readingTimeSeconds: readSec,
        fleschScore: level == ReadingLevel.simple
            ? 75.0
            : level == ReadingLevel.moderate
            ? 45.0
            : 20.0,
      ),
    );
  }

  static String _short(String s) =>
      s.length > 40 ? '${s.substring(0, 40)}…' : s;
}

class _QueueEntry {
  final String title, description, apiCategory, language, cacheKey;
  final completer = Completer<GroqMLResult>();
  int retries = 0;
  _QueueEntry({
    required this.title,
    required this.description,
    required this.apiCategory,
    required this.language,
    required this.cacheKey,
  });
}
