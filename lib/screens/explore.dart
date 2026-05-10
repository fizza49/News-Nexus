import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:new_nexus/provider/location_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/article_model.dart';
import '../ml/readability_scorer.dart';
import '../ml/category_classifier.dart';
import '../ml/sentiment_analyzer.dart';
import '../services/news_service.dart';
import '../services/bookmark_service.dart';
import 'package:provider/provider.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final NewsService _newsService = NewsService();
  final BookmarkService _bookmarkService = BookmarkService();

  List<ArticleModel> _articles = [];
  bool _isLoading = true;

  String _currentCategory = 'top';
  String? _lastLoadedCountry;
  String? _lastLoadedLanguage;

  ReadingLevel? _readabilityFilter;
  bool _politicsFilter = false;

  // How many articles have finished LLM enrichment
  int _enrichedCount = 0;

  String get _currentCountry => context.read<LocationProvider>().countryCode;
  String get _currentLanguage =>
      context.read<LocationProvider>().selectedLanguage;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.watch<LocationProvider>();
    final newCountry = provider.countryCode;
    final newLang = provider.selectedLanguage;
    if (_lastLoadedCountry == null ||
        _lastLoadedCountry != newCountry ||
        _lastLoadedLanguage != newLang) {
      _loadNews(country: newCountry, language: newLang);
    }
  }

  Future<void> _loadNews({
    String? category,
    String? country,
    String? language,
  }) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _enrichedCount = 0;
    });

    try {
      final cat = category ?? _currentCategory;
      final cou = country ?? _currentCountry;
      final lang = language ?? _currentLanguage;

      final data = await _newsService.fetchByCategory(
        category: cat,
        country: cou,
        lang: lang,
      );

      if (mounted) {
        setState(() {
          _articles = data;
          _currentCategory = cat;
          _lastLoadedCountry = cou;
          _lastLoadedLanguage = lang;
          _isLoading = false;
        });
        _enrichArticles(data);
      }
    } catch (e) {
      debugPrint('ExploreScreen ERROR: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _enrichArticles(List<ArticleModel> articles) {
    // Process up to 10 articles, one at a time via GroqMLService queue
    final batch = articles.length > 10 ? articles.sublist(0, 5) : articles;
    for (final article in batch) {
      if (!article.isEnriched) {
        article.enrichAsync(
          onDone: () {
            if (mounted) {
              setState(() {
                _enrichedCount++;
              });
            }
          },
        );
      } else {
        _enrichedCount++;
      }
    }
  }

  // ── Filtered articles ────────────────────────────────────────────────────
  // For readability and politics filters, ONLY include articles that have
  // actually been enriched by LLM (not default-fallback ones).
  // This prevents "Simple" filter showing 0 results when enrichment hasn't run.
  // Political keywords for fallback matching (same list as GroqMLService)
  static const List<String> _politicsKeywords = [
    'election', 'parliament', 'minister', 'president', 'prime minister',
    'government', 'senate', 'congress', 'vote', 'party', 'political',
    'diplomat', 'treaty', 'legislation', 'bill', 'policy',
    'انتخاب', 'حکومت', 'وزیر', 'پارلیمان', 'سیاست',
    'سياسة', 'حكومة', 'انتخابات', 'وزير', 'برلمان',
    'siyaset', 'hükümet', 'seçim', 'meclis', 'bakan',
    'चुनाव', 'सरकार', 'संसद', 'मंत्री', 'राजनीति',
  ];

  bool _isPoliticsArticle(ArticleModel a) {
    // LLM classified it as politics
    if (a.isEnriched && a.mlCategory.category == 'politics') return true;
    // Fallback: keyword matching on title + description
    final combined = '${a.title.toLowerCase()} ${a.description.toLowerCase()}';
    return _politicsKeywords.any((kw) => combined.contains(kw.toLowerCase()));
  }

  List<ArticleModel> get _filteredArticles {
    var list = _articles;

    if (_politicsFilter) {
      // Use LLM result OR keyword fallback — don't require enrichment
      list = list.where(_isPoliticsArticle).toList();
    } else if (_readabilityFilter != null) {
      // Only enriched articles have real readability data
      list = list
          .where((a) => a.isEnriched && a.readability.level == _readabilityFilter)
          .toList();
    }

    return list;
  }

  bool get _isFiltering => _politicsFilter || _readabilityFilter != null;

  // How many of the batch are still being enriched
  int get _pendingCount {
    final batchSize = _articles.length > 10 ? 10 : _articles.length;
    return (batchSize - _enrichedCount).clamp(0, batchSize);
  }

  // ── Country Picker ───────────────────────────────────────────────────────
  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (_, controller) => Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Select Country',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  controller: controller,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.my_location, color: Color(0xFF2563EB)),
                      title: const Text('Detect my location'),
                      onTap: () async {
                        Navigator.pop(context);
                        await context.read<LocationProvider>().detectLocation();
                      },
                    ),
                    const Divider(height: 1),
                    ...NewsService.supportedCountries.entries.map((entry) {
                      final countryName = entry.value['name'] as String;
                      final isSelected = entry.key == _currentCountry;
                      return ListTile(
                        title: Text(countryName),
                        trailing: isSelected
                            ? const Icon(Icons.check, color: Color(0xFF2563EB))
                            : null,
                        tileColor: isSelected
                            ? const Color(0xFF2563EB).withValues(alpha: 0.06)
                            : null,
                        onTap: () async {
                          Navigator.pop(context);
                          await context.read<LocationProvider>().changeCountry(entry.key);
                        },
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Search Dialog ────────────────────────────────────────────────────────
  void _openSearchDialog() {
    String selectedCategory = _currentCategory;
    String query = '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search News'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(hintText: 'Keyword'),
              onChanged: (value) => query = value,
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: selectedCategory,
              items: NewsService.examCategories
                  .map((cat) => DropdownMenuItem(
                        value: cat,
                        child: Text(_categoryLabel(cat)),
                      ))
                  .toList(),
              onChanged: (value) => selectedCategory = value!,
              decoration: const InputDecoration(labelText: 'Category'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _isLoading = true);
              if (query.isNotEmpty) {
                _newsService
                    .searchArticles(query,
                        country: _currentCountry, lang: _currentLanguage)
                    .then((results) {
                  if (mounted) {
                    setState(() {
                      _articles = results;
                      _isLoading = false;
                      _enrichedCount = 0;
                    });
                    _enrichArticles(results);
                  }
                }).catchError((e) {
                  if (mounted) setState(() => _isLoading = false);
                });
              } else {
                _loadNews(category: selectedCategory);
              }
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }

  Widget _buildImage(String? url) {
    if (url == null || url.isEmpty || !url.startsWith('http')) {
      return Container(
        color: Colors.grey.shade200,
        child: const Icon(Icons.article_outlined, size: 40, color: Colors.grey),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      httpHeaders: const {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
      },
      placeholder: (context, url) => Container(
        color: Colors.grey.shade100,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      errorWidget: (context, url, error) => Container(
        color: Colors.grey.shade200,
        child: const Icon(Icons.article_outlined, size: 40, color: Colors.grey),
      ),
    );
  }

  String _categoryLabel(String cat) {
    if (cat == 'top') return 'General';
    return cat[0].toUpperCase() + cat.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final locationProvider = context.watch<LocationProvider>();
    final country = locationProvider.countryCode;
    final countryName = NewsService.getCountryName(country) ?? country.toUpperCase();
    final countryLabel = countryName.split(' ').first;
    final filtered = _filteredArticles;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: const Text('Explore',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          GestureDetector(
            onTap: _showCountryPicker,
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(countryLabel, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 4),
                  Text(
                    country.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down,
                      size: 16, color: Color(0xFF2563EB)),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Search Bar ──────────────────────────────────────────────────
          GestureDetector(
            onTap: _openSearchDialog,
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 5)],
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Colors.grey),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Search in ${_categoryLabel(_currentCategory)}...',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _categoryLabel(_currentCategory),
                      style: const TextStyle(
                        color: Color(0xFF2563EB),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Category Chips ──────────────────────────────────────────────
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: NewsService.examCategories.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                // Last chip = Politics (LLM client-side filter)
                if (index == NewsService.examCategories.length) {
                  final isSelected = _politicsFilter;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _politicsFilter = !_politicsFilter;
                        _readabilityFilter = null;
                      });
                      // Load 'top' to get a wide pool if not already there
                      if (!_politicsFilter == false &&
                          _currentCategory != 'top') {
                        _loadNews(category: 'top');
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF7C3AED)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF7C3AED)
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Text(
                        '🏛️ Politics',
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.grey[700],
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                }

                final cat = NewsService.examCategories[index];
                final isSelected = cat == _currentCategory && !_politicsFilter;
                return GestureDetector(
                  onTap: () {
                    setState(() => _politicsFilter = false);
                    _loadNews(category: cat);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF2563EB)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF2563EB)
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Text(
                      _categoryLabel(cat),
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey[700],
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 10),

          // ── AI Readability Filter ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.psychology,
                        size: 13, color: Color(0xFF2563EB)),
                    const SizedBox(width: 4),
                    const Text(
                      'AI Difficulty Filter',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                    // Show how many articles are still being analysed
                    if (_pendingCount > 0) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Colors.grey[400],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Analysing $_pendingCount...',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _ReadabilityChip(
                        label: '📰 All',
                        selected: _readabilityFilter == null && !_politicsFilter,
                        color: Colors.blueGrey,
                        onTap: () => setState(() {
                          _readabilityFilter = null;
                          _politicsFilter = false;
                        }),
                      ),
                      const SizedBox(width: 8),
                      _ReadabilityChip(
                        label: '🟢 Simple',
                        selected: _readabilityFilter == ReadingLevel.simple,
                        color: Colors.green,
                        onTap: () => setState(() {
                          _politicsFilter = false;
                          _readabilityFilter =
                              _readabilityFilter == ReadingLevel.simple
                                  ? null
                                  : ReadingLevel.simple;
                        }),
                      ),
                      const SizedBox(width: 8),
                      _ReadabilityChip(
                        label: '🟡 Moderate',
                        selected: _readabilityFilter == ReadingLevel.moderate,
                        color: Colors.orange,
                        onTap: () => setState(() {
                          _politicsFilter = false;
                          _readabilityFilter =
                              _readabilityFilter == ReadingLevel.moderate
                                  ? null
                                  : ReadingLevel.moderate;
                        }),
                      ),
                      const SizedBox(width: 8),
                      _ReadabilityChip(
                        label: '🔴 Advanced',
                        selected: _readabilityFilter == ReadingLevel.advanced,
                        color: Colors.red,
                        onTap: () => setState(() {
                          _politicsFilter = false;
                          _readabilityFilter =
                              _readabilityFilter == ReadingLevel.advanced
                                  ? null
                                  : ReadingLevel.advanced;
                        }),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // ── Articles List ───────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildArticleList(filtered),
          ),
        ],
      ),
    );
  }

  Widget _buildArticleList(List<ArticleModel> filtered) {
    // When a filter is active and enrichment is still running, show progress
    if (_isFiltering && filtered.isEmpty) {
      final batchSize = _articles.length > 10 ? 10 : _articles.length;
      final done = _enrichedCount;
      // For politics: keyword matching is instant, no need to wait for LLM
      // For readability: we do need LLM enrichment
      final isStillAnalysing = !_politicsFilter && done < batchSize;

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isStillAnalysing) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Analysing articles ($done/$batchSize)...',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Text(
                'Filtering by ${_readabilityFilter?.name ?? ""} difficulty',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ] else ...[
              const Icon(Icons.search_off, size: 60, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                _politicsFilter
                    ? 'No politics articles found.\nTry switching category to Top or refreshing.'
                    : 'No ${_readabilityFilter?.name ?? ""} articles found.\nTry a different difficulty.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() {
                  _politicsFilter = false;
                  _readabilityFilter = null;
                }),
                child: const Text('Show all articles'),
              ),
            ],
          ],
        ),
      );
    }

    if (_articles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.article_outlined, size: 60, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('No articles found', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    // When no filter active, show all articles (including not-yet-enriched)
    final displayList = _isFiltering ? filtered : _articles;

    return RefreshIndicator(
      onRefresh: () async {
        NewsService.clearCache();
        await _loadNews();
      },
      child: ListView.builder(
        itemCount: displayList.length,
        itemBuilder: (context, index) {
          return _ArticleCard(
            article: displayList[index],
            bookmarkService: _bookmarkService,
            buildImage: _buildImage,
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// READABILITY CHIP
// ─────────────────────────────────────────────────────────────────────────────

class _ReadabilityChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _ReadabilityChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color, width: 1.4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : color,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ARTICLE CARD
// ─────────────────────────────────────────────────────────────────────────────

class _ArticleCard extends StatefulWidget {
  final ArticleModel article;
  final BookmarkService bookmarkService;
  final Widget Function(String?) buildImage;

  const _ArticleCard({
    required this.article,
    required this.bookmarkService,
    required this.buildImage,
  });

  @override
  State<_ArticleCard> createState() => _ArticleCardState();
}

class _ArticleCardState extends State<_ArticleCard> {
  bool _isBookmarked = false;
  bool _bookmarkLoading = false;

  @override
  void initState() {
    super.initState();
    _checkBookmark();
  }

  Future<void> _checkBookmark() async {
    final val = await widget.bookmarkService.isBookmarked(widget.article.url);
    if (mounted) setState(() => _isBookmarked = val);
  }

  Future<void> _toggleBookmark() async {
    if (_bookmarkLoading) return;
    setState(() => _bookmarkLoading = true);
    try {
      if (_isBookmarked) {
        await widget.bookmarkService.removeBookmark(widget.article.url);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Removed from bookmarks'),
              duration: Duration(seconds: 1),
            ),
          );
          setState(() => _isBookmarked = false);
        }
      } else {
        await widget.bookmarkService.addBookmark(widget.article);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Saved to bookmarks ✓'),
              duration: Duration(seconds: 1),
              backgroundColor: Color(0xFF2563EB),
            ),
          );
          setState(() => _isBookmarked = true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _bookmarkLoading = false);
    }
  }

  Future<void> _openArticle(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open article')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final article = widget.article;
    final enriched = article.isEnriched;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => _openArticle(article.url),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            SizedBox(
              height: 180,
              width: double.infinity,
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(15)),
                child: widget.buildImage(
                  article.urlToImage.isNotEmpty ? article.urlToImage : null,
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    article.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 6),

                  // Description
                  if (article.description.isNotEmpty)
                    Text(
                      article.description,
                      style:
                          TextStyle(color: Colors.grey[600], fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                  const SizedBox(height: 8),

                  // ── ML Badges — use Wrap to prevent overflow ───────────
                  if (!enriched)
                    // Show shimmer/loading state while LLM is working
                    Row(
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Colors.grey[400],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Analysing...',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[400]),
                        ),
                      ],
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _badge(
                          '${article.sentiment.emoji} ${article.sentiment.label}',
                          _sentimentColor(article.sentiment.sentiment),
                        ),
                        _badge(
                          '${article.mlCategory.emoji} '
                          '${CategoryClassifier.capitalize(article.mlCategory.category)}',
                          Colors.grey.shade100,
                        ),
                        _badge(
                          '${article.readability.emoji} ${article.readability.label}',
                          Colors.grey.shade100,
                        ),
                        _badge(
                          '⏱ ${article.readability.readingTimeLabel}',
                          Colors.grey.shade100,
                        ),
                      ],
                    ),

                  const SizedBox(height: 8),

                  // Source + date + bookmark
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          article.source,
                          style: const TextStyle(
                              fontWeight: FontWeight.w500, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            article.publishedAt.length >= 10
                                ? article.publishedAt.substring(0, 10)
                                : article.publishedAt,
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 11),
                          ),
                          _bookmarkLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: Padding(
                                    padding: EdgeInsets.all(4),
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                )
                              : IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: Icon(
                                    _isBookmarked
                                        ? Icons.bookmark
                                        : Icons.bookmark_border,
                                    color: _isBookmarked
                                        ? const Color(0xFF2563EB)
                                        : Colors.grey,
                                    size: 20,
                                  ),
                                  onPressed: _toggleBookmark,
                                ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _sentimentColor(Sentiment s) {
    return switch (s) {
      Sentiment.positive => Colors.green.shade50,
      Sentiment.negative => Colors.red.shade50,
      _ => Colors.grey.shade100,
    };
  }

  Widget _badge(String text, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11)),
    );
  }
}