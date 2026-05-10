import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:new_nexus/provider/location_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';

import '../models/article_model.dart';
import '../services/news_service.dart';

import 'notification_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final NewsService _newsService = NewsService();

  List<ArticleModel> _articles = [];
  bool _isLoading = true;
  String _currentCategory = 'top';

  // Track last loaded values to detect real changes
  String? _lastLoadedCountry;
  String? _lastLoadedLanguage;

  // ── Convenience getters from provider ─────────────────────────────────
  String get _currentCountry => context.read<LocationProvider>().countryCode;
  String get _currentLanguage =>
      context.read<LocationProvider>().selectedLanguage;

  @override
  void initState() {
    super.initState();
    // Initial load handled in didChangeDependencies
  }

  // ── Auto reload on first load, country change, or language change ─────
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
    String? country,
    String? language,
    String? category,
  }) async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      final cou = country ?? _currentCountry;
      final lang = language ?? _currentLanguage;
      final cat = category ?? _currentCategory;

      List<ArticleModel> data;

      if (cat == 'top') {
        data = await _newsService.fetchTopHeadlines(country: cou, lang: lang);
      } else {
        data = await _newsService.fetchByCategory(
          category: cat,
          country: cou,
          lang: lang,
        );
      }

      if (mounted) {
        setState(() {
          _articles = data;
          _currentCategory = cat;
          _lastLoadedCountry = cou;
          _lastLoadedLanguage = lang;
          _isLoading = false;
        });

        if (data.isNotEmpty) {
          await NotificationScreen.addNotification(
            title: 'Breaking News',
            subtitle: data.first.title,
            type: NotificationType.breakingNews,
            actionUrl: data.first.url,
          );
        }
      }
    } catch (e) {
      debugPrint('HOME ERROR: $e');

      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // COUNTRY PICKER
  // ───────────────────────────────────────────────────────────────────────

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
                      leading: const Icon(
                        Icons.my_location,
                        color: Color(0xFF2563EB),
                      ),
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

                          await context.read<LocationProvider>().changeCountry(
                            entry.key,
                          );
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

  // ───────────────────────────────────────────────────────────────────────
  // LANGUAGE PICKER
  // ───────────────────────────────────────────────────────────────────────

  void _showLanguagePicker() {
    final availableLanguages = NewsService.getLanguagesForCountry(
      _currentCountry,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        // Capture provider reference from the *outer* context before the sheet
        // closes so we avoid using a disposed BuildContext after Navigator.pop.
        final locationProvider = context.read<LocationProvider>();

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
                'Select Language',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),

              const Divider(),

              Expanded(
                child: ListView(
                  controller: controller,
                  children: availableLanguages.map((langCode) {
                    final langName =
                        NewsService.getLanguageName(langCode) ?? langCode;

                    final isSelected =
                        langCode == locationProvider.selectedLanguage;

                    return ListTile(
                      title: Text(langName),

                      trailing: isSelected
                          ? const Icon(Icons.check, color: Color(0xFF2563EB))
                          : null,

                      tileColor: isSelected
                          ? const Color(0xFF2563EB).withValues(alpha: 0.06)
                          : null,

                      onTap: () {
                        Navigator.pop(sheetContext);
                        // Update provider — didChangeDependencies will
                        // automatically trigger _loadNews.
                        locationProvider.changeLanguage(langCode);
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // SEARCH
  // ───────────────────────────────────────────────────────────────────────

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
                  .map(
                    (cat) => DropdownMenuItem(
                      value: cat,
                      child: Text(cat[0].toUpperCase() + cat.substring(1)),
                    ),
                  )
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
                    .searchArticles(
                      query,
                      country: _currentCountry,
                      lang: _currentLanguage,
                    )
                    .then((results) {
                      if (mounted) {
                        setState(() {
                          _articles = results;
                          _isLoading = false;
                        });
                      }
                    })
                    .catchError((e) {
                      if (mounted) {
                        setState(() => _isLoading = false);
                      }
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

  // ───────────────────────────────────────────────────────────────────────
  // IMAGE BUILDER
  // ───────────────────────────────────────────────────────────────────────

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

  // ───────────────────────────────────────────────────────────────────────
  // OPEN ARTICLE
  // ───────────────────────────────────────────────────────────────────────

  Future<void> _openArticle(String url) async {
    if (url.isEmpty) return;

    final uri = Uri.parse(url);

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open article')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final locationProvider = context.watch<LocationProvider>();

    final country = locationProvider.countryCode;
    final selectedLanguage = locationProvider.selectedLanguage;

    final countryName =
        NewsService.getCountryName(country) ?? country.toUpperCase();

    final countryLabel = countryName.split(' ').first;

    return Scaffold(
      backgroundColor: Colors.grey[100],

      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,

        title: const Text(
          'NewsNexus',
          style: TextStyle(
            color: Color(0xFF2563EB),
            fontWeight: FontWeight.bold,
          ),
        ),

        actions: [
          // Language button
          GestureDetector(
            onTap: _showLanguagePicker,

            child: Container(
              margin: const EdgeInsets.only(right: 8, left: 8),

              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),

              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),

                borderRadius: BorderRadius.circular(20),

                border: Border.all(color: Colors.orange, width: 1),
              ),

              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.language, size: 14, color: Colors.orange),

                  const SizedBox(width: 4),

                  Text(
                    selectedLanguage.toUpperCase(),

                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Country button
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

                  const Icon(
                    Icons.arrow_drop_down,
                    size: 16,
                    color: Color(0xFF2563EB),
                  ),
                ],
              ),
            ),
          ),

          // Notifications
          IconButton(
            icon: const Icon(Icons.notifications_none, color: Colors.black),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationScreen()),
              );
            },
          ),
        ],
      ),

      body: Column(
        children: [
          // Search
          GestureDetector(
            onTap: _openSearchDialog,

            child: Container(
              margin: const EdgeInsets.all(16),

              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),

              decoration: BoxDecoration(
                color: Colors.white,

                borderRadius: BorderRadius.circular(30),

                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 5),
                ],
              ),

              child: const Row(
                children: [
                  Icon(Icons.search, color: Colors.grey),

                  SizedBox(width: 10),

                  Text('Search news...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ),

          // Categories
          SizedBox(
            height: 40,

            child: ListView.separated(
              scrollDirection: Axis.horizontal,

              padding: const EdgeInsets.symmetric(horizontal: 16),

              itemCount: NewsService.examCategories.length,

              separatorBuilder: (_, __) => const SizedBox(width: 8),

              itemBuilder: (context, index) {
                final cat = NewsService.examCategories[index];

                final isSelected = cat == _currentCategory;

                return GestureDetector(
                  onTap: () => _loadNews(category: cat),

                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),

                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),

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
                      cat[0].toUpperCase() + cat.substring(1),

                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey[700],

                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _articles.isEmpty
                ? const Center(child: Text('No articles found'))
                : RefreshIndicator(
                    onRefresh: () async {
                      NewsService.clearCache();
                      await _loadNews();
                    },
                    child: ListView.builder(
                      itemCount: _articles.length,
                      itemBuilder: (context, index) {
                        final article = _articles[index];

                        return _ArticleCard(
                          article: article,
                          buildImage: _buildImage,
                          onTap: () => _openArticle(article.url),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ARTICLE CARD

class _ArticleCard extends StatelessWidget {
  final ArticleModel article;
  final Widget Function(String?) buildImage;
  final VoidCallback onTap;

  const _ArticleCard({
    required this.article,
    required this.buildImage,
    required this.onTap,
  });

  Widget _badge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),

      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),

      child: Text(text, style: const TextStyle(fontSize: 11)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),

      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),

      elevation: 3,

      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            SizedBox(
              height: 180,
              width: double.infinity,

              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(15),
                ),

                child: buildImage(
                  article.urlToImage.isNotEmpty ? article.urlToImage : null,
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(12),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
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

                  if (article.description.isNotEmpty)
                    Text(
                      article.description,

                      style: TextStyle(color: Colors.grey[600], fontSize: 13),

                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                  const SizedBox(height: 8),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,

                    children: [
                      Expanded(
                        child: Text(
                          article.source,

                          overflow: TextOverflow.ellipsis,

                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ),

                      Text(
                        article.publishedAt.length >= 10
                            ? article.publishedAt.substring(0, 10)
                            : article.publishedAt,

                        style: TextStyle(color: Colors.grey[500], fontSize: 11),
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
}
