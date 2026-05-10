import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/article_model.dart';

class NewsService {
  static const String _apiKey =
      'get your api key from newsdata.io and put it here';
  static const String _baseUrl = 'https://newsdata.io/api/1';

  // Cache
  static List<ArticleModel>? _cachedHeadlines;
  static String? _cachedHeadlinesKey;
  static final Map<String, List<ArticleModel>> _categoryCache = {};
  static final Map<String, List<ArticleModel>> _searchCache = {};
  static DateTime? _lastFetched;

  static final Map<String, Future<List<ArticleModel>>> _pendingRequests = {};

  static const Duration _cacheDuration = Duration(minutes: 30);

  bool get _cacheExpired =>
      _lastFetched == null ||
      DateTime.now().difference(_lastFetched!) > _cacheDuration;

  static void clearCache() {
    _cachedHeadlines = null;
    _cachedHeadlinesKey = null;
    _categoryCache.clear();
    _searchCache.clear();
    _lastFetched = null;
    _pendingRequests.clear();
  }

  // NewsData.io supported categories
  static const List<String> examCategories = [
    'top',
    'science',
    'technology',
    'health',
    'business',
    'sports',
    'entertainment',
  ];

  // Supported Countries with Flags and Default Language
  static const Map<String, Map<String, String>> supportedCountries = {
    'us': {'name': '🇺🇸 United States', 'defaultLang': 'en'},
    'gb': {'name': '🇬🇧 United Kingdom', 'defaultLang': 'en'},
    'in': {'name': '🇮🇳 India', 'defaultLang': 'en'},
    'pk': {'name': '🇵🇰 Pakistan', 'defaultLang': 'ur'},
    'au': {'name': '🇦🇺 Australia', 'defaultLang': 'en'},
    'ca': {'name': '🇨🇦 Canada', 'defaultLang': 'en'},
    'ae': {'name': '🇦🇪 UAE', 'defaultLang': 'ar'},
    'sg': {'name': '🇸🇬 Singapore', 'defaultLang': 'en'},
    'za': {'name': '🇿🇦 South Africa', 'defaultLang': 'en'},
    'ng': {'name': '🇳🇬 Nigeria', 'defaultLang': 'en'},
    'de': {'name': '🇩🇪 Germany', 'defaultLang': 'de'},
    'fr': {'name': '🇫🇷 France', 'defaultLang': 'fr'},
    'jp': {'name': '🇯🇵 Japan', 'defaultLang': 'ja'},
    'br': {'name': '🇧🇷 Brazil', 'defaultLang': 'pt'},
    'mx': {'name': '🇲🇽 Mexico', 'defaultLang': 'es'},
    'eg': {'name': '🇪🇬 Egypt', 'defaultLang': 'ar'},
    'tr': {'name': '🇹🇷 Turkey', 'defaultLang': 'tr'},
    'my': {'name': '🇲🇾 Malaysia', 'defaultLang': 'ms'},
    'ph': {'name': '🇵🇭 Philippines', 'defaultLang': 'en'},
    'id': {'name': '🇮🇩 Indonesia', 'defaultLang': 'id'},
  };

  // All languages supported by NewsData.io
  static const Map<String, String> supportedLanguages = {
    'en': '🇬🇧 English',
    'de': '🇩🇪 German',
    'fr': '🇫🇷 French',
    'es': '🇪🇸 Spanish',
    'it': '🇮🇹 Italian',
    'pt': '🇵🇹 Portuguese',
    'nl': '🇳🇱 Dutch',
    'pl': '🇵🇱 Polish',
    'ru': '🇷🇺 Russian',
    'uk': '🇺🇦 Ukrainian',
    'sv': '🇸🇪 Swedish',
    'no': '🇳🇴 Norwegian',
    'da': '🇩🇰 Danish',
    'fi': '🇫🇮 Finnish',
    'cs': '🇨🇿 Czech',
    'sk': '🇸🇰 Slovak',
    'hu': '🇭🇺 Hungarian',
    'ro': '🇷🇴 Romanian',
    'bg': '🇧🇬 Bulgarian',
    'hr': '🇭🇷 Croatian',
    'sr': '🇷🇸 Serbian',
    'el': '🇬🇷 Greek',
    'tr': '🇹🇷 Turkish',
    'ar': '🇸🇦 Arabic',
    'fa': '🇮🇷 Persian/Farsi',
    'ur': '🇵🇰 Urdu',
    'hi': '🇮🇳 Hindi',
    'bn': '🇧🇩 Bengali',
    'pa': '🇮🇳 Punjabi',
    'ta': '🇮🇳 Tamil',
    'te': '🇮🇳 Telugu',
    'ml': '🇮🇳 Malayalam',
    'kn': '🇮🇳 Kannada',
    'gu': '🇮🇳 Gujarati',
    'mr': '🇮🇳 Marathi',
    'as': '🇮🇳 Assamese',
    'or': '🇮🇳 Odia',
    'zh': '🇨🇳 Chinese (Simplified)',
    'zh-hans': '🇨🇳 Chinese (Simplified)',
    'zh-hant': '🇹🇼 Chinese (Traditional)',
    'ja': '🇯🇵 Japanese',
    'ko': '🇰🇷 Korean',
    'th': '🇹🇭 Thai',
    'vi': '🇻🇳 Vietnamese',
    'id': '🇮🇩 Indonesian',
    'ms': '🇲🇾 Malay',
    'tl': '🇵🇭 Filipino/Tagalog',
    'my': '🇲🇲 Burmese',
    'km': '🇰🇭 Khmer',
    'lo': '🇱🇦 Lao',
    'he': '🇮🇱 Hebrew',
    'sq': '🇦🇱 Albanian',
    'sw': '🇹🇿 Swahili',
    'af': '🇿🇦 Afrikaans',
    'am': '🇪🇹 Amharic',
    'ha': '🇳🇬 Hausa',
    'yo': '🇳🇬 Yoruba',
    'zu': '🇿🇦 Zulu',
    'xh': '🇿🇦 Xhosa',
    'ig': '🇳🇬 Igbo',
    'es-mx': '🇲🇽 Spanish (Mexico)',
    'pt-br': '🇧🇷 Portuguese (Brazil)',
    'lt': '🇱🇹 Lithuanian',
    'lv': '🇱🇻 Latvian',
    'et': '🇪🇪 Estonian',
    'sl': '🇸🇮 Slovenian',
    'ca': '🇪🇸 Catalan',
    'is': '🇮🇸 Icelandic',
    'mt': '🇲🇹 Maltese',
    'kk': '🇰🇿 Kazakh',
    'uz': '🇺🇿 Uzbek',
    'ne': '🇳🇵 Nepali',
    'si': '🇱🇰 Sinhala',
    'hy': '🇦🇲 Armenian',
    'az': '🇦🇿 Azerbaijani',
    'ka': '🇬🇪 Georgian',
  };

  static const Map<String, List<String>> languagesByCountry = {
    'us': ['en'],
    'gb': ['en'],
    'in': [
      'en',
      'hi',
      'bn',
      'pa',
      'ta',
      'te',
      'ml',
      'kn',
      'gu',
      'mr',
      'as',
      'or',
    ],
    'pk': ['en', 'ur', 'pa'],
    'au': ['en'],
    'ca': ['en', 'fr'],
    'ae': ['ar', 'en', 'ur'],
    'sg': ['en', 'zh', 'ta', 'ms'],
    'za': ['en', 'af', 'zu', 'xh'],
    'ng': ['en', 'ha', 'yo', 'ig'],
    'de': ['de', 'en'],
    'fr': ['fr', 'en'],
    'jp': ['ja', 'en'],
    'br': ['pt-br', 'en'],
    'mx': ['es-mx', 'en'],
    'eg': ['ar', 'en'],
    'tr': ['tr', 'en'],
    'my': ['ms', 'en', 'zh'],
    'ph': ['tl', 'en'],
    'id': ['id', 'en'],
  };

  static String? getCountryName(String countryCode) =>
      supportedCountries[countryCode]?['name'];

  static String? getLanguageName(String languageCode) =>
      supportedLanguages[languageCode];

  static String getDefaultLanguageForCountry(String countryCode) =>
      supportedCountries[countryCode]?['defaultLang'] ?? 'en';

  static List<String> getLanguagesForCountry(String countryCode) =>
      languagesByCountry[countryCode] ?? ['en'];

  /// Fetch top headlines with request deduplication
  /// Returns cached headlines if available and not expired
  /// Prevents multiple simultaneous API calls for the same parameters
  Future<List<ArticleModel>> fetchTopHeadlines({
    String country = 'us',
    String lang = 'en',
  }) async {
    final cacheKey = '${country}_$lang';

    // Check cache first
    if (_cachedHeadlines != null &&
        !_cacheExpired &&
        _cachedHeadlinesKey == cacheKey) {
      print('DEBUG: Returning cached headlines for $cacheKey');
      return _cachedHeadlines!;
    }
    final requestKey = 'headlines_$cacheKey';
    if (_pendingRequests.containsKey(requestKey)) {
      print('DEBUG: Returning pending request for $requestKey');
      return _pendingRequests[requestKey]!;
    }

    final future = _fetchTopHeadlinesInternal(country, lang);
    _pendingRequests[requestKey] = future;

    try {
      final result = await future;
      return result;
    } finally {
      _pendingRequests.remove(requestKey);
    }
  }

  /// Internal method for fetching top headlines
  Future<List<ArticleModel>> _fetchTopHeadlinesInternal(
    String country,
    String lang,
  ) async {
    final url = Uri.parse(
      '$_baseUrl/latest?apikey=$_apiKey&country=$country&language=$lang',
    );

    final response = await http.get(url).timeout(const Duration(seconds: 15));
    final data = json.decode(response.body);

    if (response.statusCode == 200 && data['status'] == 'success') {
      final List results = data['results'] ?? [];
      final result = results
          .where(
            (a) =>
                a['title'] != null && (a['title'] as String).trim().isNotEmpty,
          )
          .map((a) => ArticleModel.fromJson(a, language: lang))
          .toList();

      _cachedHeadlines = result;
      _cachedHeadlinesKey = '${country}_$lang';
      _lastFetched = DateTime.now();
      return result;
    } else {
      final msg =
          data['results']?['message'] ??
          data['message'] ??
          'Failed to load news (${response.statusCode})';
      throw Exception(msg);
    }
  }

  /// Fetch articles by category with request deduplication
  /// Returns cached articles if available and not expired
  /// Prevents multiple simultaneous API calls for the same parameters
  Future<List<ArticleModel>> fetchByCategory({
    String category = 'top',
    String country = 'us',
    String lang = 'en',
  }) async {
    final cacheKey = '${country}_${category}_$lang';

    // Check cache first
    if (!_cacheExpired && _categoryCache.containsKey(cacheKey)) {
      print('DEBUG: Returning cached $cacheKey');
      return _categoryCache[cacheKey]!;
    }

    // FIX: If a request is already pending for this key, return that future
    final requestKey = 'category_$cacheKey';
    if (_pendingRequests.containsKey(requestKey)) {
      print('DEBUG: Returning pending request for $requestKey');
      return _pendingRequests[requestKey]!;
    }

    print('DEBUG: Fetching $category for country=$country, language=$lang');

    final future = _fetchByCategoryInternal(category, country, lang);
    _pendingRequests[requestKey] = future;

    try {
      final result = await future;
      return result;
    } finally {
      _pendingRequests.remove(requestKey);
    }
  }

  /// Internal method for fetching by category
  Future<List<ArticleModel>> _fetchByCategoryInternal(
    String category,
    String country,
    String lang,
  ) async {
    final url = Uri.parse(
      '$_baseUrl/latest?apikey=$_apiKey&category=$category&country=$country&language=$lang',
    );

    final response = await http.get(url).timeout(const Duration(seconds: 15));
    final data = json.decode(response.body);

    if (response.statusCode == 200 && data['status'] == 'success') {
      final List results = data['results'] ?? [];
      final result = results
          .where(
            (a) =>
                a['title'] != null && (a['title'] as String).trim().isNotEmpty,
          )
          .map(
            (a) => ArticleModel.fromJson(a, category: category, language: lang),
          )
          .toList();

      _enrichInBackground(result);

      _categoryCache['${country}_${category}_$lang'] = result;
      _lastFetched = DateTime.now();
      return result;
    } else {
      final msg =
          data['results']?['message'] ??
          data['message'] ??
          'Category fetch failed (${response.statusCode})';
      throw Exception(msg);
    }
  }

  Future<List<ArticleModel>> searchArticles(
    String query, {
    String lang = 'en',
    String? country,
  }) async {
    final cacheKey = '${country ?? ''}_${query.toLowerCase().trim()}_$lang';

    if (_searchCache.containsKey(cacheKey)) {
      return _searchCache[cacheKey]!;
    }

    // FIX: Add request deduplication for search as well
    final requestKey = 'search_$cacheKey';
    if (_pendingRequests.containsKey(requestKey)) {
      print('DEBUG: Returning pending search request for $requestKey');
      return _pendingRequests[requestKey]!;
    }

    final future = _searchArticlesInternal(query, lang, country, cacheKey);
    _pendingRequests[requestKey] = future;

    try {
      final result = await future;
      return result;
    } finally {
      _pendingRequests.remove(requestKey);
    }
  }

  /// Internal method for searching articles
  Future<List<ArticleModel>> _searchArticlesInternal(
    String query,
    String lang,
    String? country,
    String cacheKey,
  ) async {
    String urlStr =
        '$_baseUrl/latest?apikey=$_apiKey&q=${Uri.encodeComponent(query)}&language=$lang';
    if (country != null && country.isNotEmpty) {
      urlStr += '&country=$country';
    }

    final response = await http
        .get(Uri.parse(urlStr))
        .timeout(const Duration(seconds: 15));
    final data = json.decode(response.body);

    if (response.statusCode == 200 && data['status'] == 'success') {
      final List results = data['results'] ?? [];
      final result = results
          .where(
            (a) =>
                a['title'] != null && (a['title'] as String).trim().isNotEmpty,
          )
          .map((a) => ArticleModel.fromJson(a, language: lang))
          .toList();

      _searchCache[cacheKey] = result;
      return result;
    } else {
      throw Exception(
        'Search failed: ${data['results']?['message'] ?? data['message']}',
      );
    }
  }

  static bool isLanguageSupported(String languageCode) =>
      supportedLanguages.containsKey(languageCode);

  static bool isCountrySupported(String countryCode) =>
      supportedCountries.containsKey(countryCode);

  static List<String> getAllCountryCodes() => supportedCountries.keys.toList();

  static List<String> getAllLanguageCodes() => supportedLanguages.keys.toList();

  static void _enrichInBackground(List<ArticleModel> articles) {
    // Limit to first 5 articles for enrichment
    final maxArticles = articles.length > 5 ? 5 : articles.length;
    final batch = articles.sublist(0, maxArticles);

    for (final article in batch) {
      article.enrichAsync();
    }
  }
}
