import '../ml/sentiment_analyzer.dart';
import '../ml/category_classifier.dart';
import '../ml/readability_scorer.dart';
import '../ml/groq_ml_service.dart';

class ArticleModel {
  final String title;
  final String description;
  final String url;
  final String urlToImage;
  final String publishedAt;
  final String source;
  final String category; // raw API category
  final String language;
  bool isBookmarked;

  SentimentResult? _sentiment;
  CategoryResult? _mlCategory;
  ReadabilityResult? _readability;

  bool _enrichAttempted = false;
  bool _enriching = false;

  bool get isEnriched => _enrichAttempted;
  bool get isEnriching => _enriching;

  // Whether LLM actually returned results (vs defaults)
  bool get hasLLMResults =>
      _sentiment != null && _mlCategory != null && _readability != null;

  SentimentResult get sentiment =>
      _sentiment ??
      const SentimentResult(
        sentiment: Sentiment.neutral,
        score: 0.0,
        label: 'Neutral',
        emoji: '😐',
      );

  CategoryResult get mlCategory =>
      _mlCategory ??
      CategoryResult(
        category: _normaliseApiCategory(category),
        emoji: _categoryEmoji(_normaliseApiCategory(category)),
        confidence: 0.5,
      );

  ReadabilityResult get readability =>
      _readability ??
      ReadabilityResult(
        level: ReadingLevel.moderate,
        label: 'Moderate',
        emoji: '🟡',
        readingTimeSeconds: _defaultReadTime(language),
        fleschScore: 50.0,
      );

  ArticleModel({
    required this.title,
    required this.description,
    required this.url,
    required this.urlToImage,
    required this.publishedAt,
    required this.source,
    this.category = 'general',
    this.language = 'en',
    this.isBookmarked = false,
  });

  /// Enqueue this article for LLM enrichment.
  /// [onDone] is called once results are ready — use it to call setState.
  Future<void> enrichAsync({void Function()? onDone}) async {
    if (_enrichAttempted || _enriching) {
      onDone?.call();
      return;
    }

    _enriching = true;
    try {
      final result = await GroqMLService.analyze(
        title,
        description,
        apiCategory: category,
        language: language,
      );
      _sentiment = result.sentiment;
      _mlCategory = result.category;
      _readability = result.readability;
    } catch (e) {
      // Leave nulls — getters return sensible defaults
      print('ArticleModel enrichment error: $e');
    }
    _enrichAttempted = true;
    _enriching = false;
    onDone?.call();
  }

  factory ArticleModel.fromJson(
    Map<String, dynamic> json, {
    String category = 'general',
    String language = 'en',
  }) {
    return ArticleModel(
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      url: json['link'] ?? json['url'] ?? '',
      urlToImage: json['image_url'] ?? json['urlToImage'] ?? '',
      publishedAt: json['pubDate'] ?? json['publishedAt'] ?? '',
      source:
          json['source_name'] ??
          (json['source'] is Map ? json['source']['name'] : json['source']) ??
          '',
      category: category,
      language: language,
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'url': url,
    'urlToImage': urlToImage,
    'publishedAt': publishedAt,
    'source': source,
    'category': category,
    'language': language,
  };

  static String _normaliseApiCategory(String cat) {
    const valid = {
      'politics',
      'technology',
      'health',
      'business',
      'sports',
      'science',
      'entertainment',
      'general',
    };
    return valid.contains(cat.toLowerCase()) ? cat.toLowerCase() : 'general';
  }

  static String _categoryEmoji(String cat) {
    const map = {
      'politics': '🏛️',
      'technology': '💻',
      'health': '🏥',
      'business': '📈',
      'sports': '⚽',
      'science': '🔬',
      'entertainment': '🎬',
      'general': '📰',
    };
    return map[cat] ?? '📰';
  }

  static int _defaultReadTime(String lang) {
    const wpm = {
      'ar': 150,
      'ur': 150,
      'hi': 160,
      'ja': 400,
      'zh': 260,
      'zh-hans': 260,
      'zh-hant': 260,
      'ko': 200,
      'th': 120,
    };
    const words = {
      'ar': 500,
      'ur': 450,
      'hi': 480,
      'ja': 1200,
      'zh': 800,
      'zh-hans': 800,
      'zh-hant': 800,
    };
    final w = (wpm[lang] ?? 238).toDouble();
    final n = (words[lang] ?? 600).toDouble();
    return ((n / w) * 60).clamp(60.0, 1800.0).round();
  }
}
