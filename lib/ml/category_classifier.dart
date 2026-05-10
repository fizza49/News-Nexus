library;

/// ML Model 2: Article Category Classifier
/// LLM-powered via Groq + API category fusion.
/// Works for ALL languages. Adds "politics" which the API doesn't have.
///
/// Fusion strategy:
///   - API category is trusted for: science, technology, health, business,
///     sports, entertainment  (these are reliable)
///   - API "top" / "general" → use LLM to determine real category
///   - LLM adds "politics" which the API never returns
///   - If LLM and API disagree on a specific category → prefer API
///     unless LLM says "politics" (since API can't detect it)

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class CategoryResult {
  final String category;
  final String emoji;
  final double confidence; // 0.0 to 1.0
  final bool fromLLM; // true = LLM classified, false = API-provided

  const CategoryResult({
    required this.category,
    required this.emoji,
    required this.confidence,
    this.fromLLM = false,
  });
}

class CategoryClassifier {
  static const String _groqApiKey = 'your grok api key here';
  static const String _groqUrl =
      'https://api.groq.com/openai/v1/chat/completions';
  static const String _model = 'llama-3.3-70b-versatile';

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

  // API categories that are reliable — trust them directly
  static const Set<String> _trustedApiCategories = {
    'science',
    'technology',
    'health',
    'business',
    'sports',
    'entertainment',
  };

  // In-memory cache
  static final Map<String, CategoryResult> _cache = {};

  /// Classify an article, fusing API category with LLM intelligence.
  ///
  /// [apiCategory] is the raw category string from NewsData.io (e.g. "top", "business")
  /// [language] is the article language code (e.g. "ur", "fr", "ar")
  static Future<CategoryResult> classify(
    String title,
    String description, {
    String apiCategory = 'top',
    String language = 'en',
  }) async {
    final cacheKey = '${title.hashCode}_${description.hashCode}_$apiCategory';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

    final normalised = apiCategory.toLowerCase().trim();

    // If the API gave us a trusted specific category, return it directly
    // (no LLM call needed — saves quota)
    if (_trustedApiCategories.contains(normalised)) {
      final result = CategoryResult(
        category: normalised,
        emoji: _categoryEmojis[normalised] ?? '📰',
        confidence: 0.95,
        fromLLM: false,
      );
      _cache[cacheKey] = result;
      return result;
    }

    // For "top", "general", or unknown → ask LLM (it can also detect politics)
    try {
      final llmResult = await _callGroq(
        title,
        description,
        language,
        normalised,
      );
      _cache[cacheKey] = llmResult;
      return llmResult;
    } catch (e) {
      debugPrint('[CategoryClassifier] ERROR: $e');
      // Fallback
      final fallbackCat = normalised == 'top'
          ? 'general'
          : (normalised.isEmpty ? 'general' : normalised);
      final fallback = CategoryResult(
        category: fallbackCat,
        emoji: _categoryEmojis[fallbackCat] ?? '📰',
        confidence: 0.5,
        fromLLM: false,
      );
      _cache[cacheKey] = fallback;
      return fallback;
    }
  }

  static Future<CategoryResult> _callGroq(
    String title,
    String description,
    String language,
    String apiCategory,
  ) async {
    final prompt =
        '''
You are a multilingual news article category classifier.

Language code: $language
Title: $title
Description: $description
API-provided category hint: $apiCategory

Choose the SINGLE best category from this list:
- politics (government, elections, parliament, diplomacy, political leaders, coups, legislation)
- technology (AI, software, gadgets, internet, startups, chips, apps)
- health (medicine, disease, hospitals, vaccines, mental health, fitness)
- business (economy, markets, finance, companies, trade, GDP, stocks)
- sports (cricket, football, tennis, basketball, Olympics, tournaments)
- science (research, space, environment, biology, physics, climate)
- entertainment (movies, music, celebrities, TV shows, awards)
- general (anything that doesn't fit above)

Important:
- If the API hint is a specific category (not "top"/"general"), strongly prefer it
  UNLESS the content clearly belongs to "politics" — the API never returns politics
- Respond ONLY with valid JSON (no markdown):
{"category": "<one of the 8 above>", "confidence": <float 0.0 to 1.0>}
''';

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
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw Exception('Groq HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final raw =
        (data['choices'] as List?)?.first?['message']?['content'] as String? ??
        '{}';

    final cleaned = raw.replaceAll(RegExp(r'```[a-z]*\n?|```'), '').trim();
    final parsed = jsonDecode(cleaned) as Map<String, dynamic>;

    String cat = (parsed['category'] as String? ?? 'general')
        .toLowerCase()
        .trim();
    final confidence =
        (parsed['confidence'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 0.7;

    // Safety: if LLM returns something outside our valid set, fall back
    if (!_categoryEmojis.containsKey(cat)) cat = 'general';

    return CategoryResult(
      category: cat,
      emoji: _categoryEmojis[cat]!,
      confidence: confidence,
      fromLLM: true,
    );
  }

  static String capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
