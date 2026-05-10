import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/article_model.dart';
import '../ml/sentiment_analyzer.dart';
import '../ml/readability_scorer.dart';
import '../services/bookmark_service.dart';

class ArticleCard extends StatefulWidget {
  final ArticleModel article;
  final BookmarkService bookmarkService;

  const ArticleCard({
    super.key,
    required this.article,
    required this.bookmarkService,
  });

  @override
  State<ArticleCard> createState() => _ArticleCardState();
}

class _ArticleCardState extends State<ArticleCard> {
  bool _isBookmarked = false;

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
    if (_isBookmarked) {
      await widget.bookmarkService.removeBookmark(widget.article.url);
    } else {
      await widget.bookmarkService.addBookmark(widget.article);
    }
    if (mounted) setState(() => _isBookmarked = !_isBookmarked);
  }

  Color _sentimentColor(Sentiment s) {
    switch (s) {
      case Sentiment.positive:
        return Colors.green;
      case Sentiment.negative:
        return Colors.red;
      case Sentiment.neutral:
        return Colors.orange;
    }
  }

  Color _readabilityColor(ReadingLevel l) {
    switch (l) {
      case ReadingLevel.simple:
        return Colors.green;
      case ReadingLevel.moderate:
        return Colors.orange;
      case ReadingLevel.advanced:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.article;
    final sColor = _sentimentColor(a.sentiment.sentiment);
    final rColor = _readabilityColor(a.readability.level);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final uri = Uri.parse(a.url);
          if (await canLaunchUrl(uri)) launchUrl(uri);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Thumbnail ─────────────────────────
            if (a.urlToImage.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: CachedNetworkImage(
                  imageUrl: a.urlToImage,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    height: 180,
                    color: Colors.grey[300],
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (context, url, error) => Container(
                    height: 100,
                    color: Colors.grey[200],
                    child: const Icon(Icons.broken_image, size: 40),
                  ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── ML Badges ─────────────────────────
                  Wrap(
                    spacing: 1,
                    runSpacing: 1,
                    children: [
                      _MLBadge(
                        text:
                            '${a.mlCategory.emoji} ${_cap(a.mlCategory.category)}',
                        color: const Color(0xFF2563EB),
                      ),
                      _MLBadge(
                        text: '${a.sentiment.emoji} ${a.sentiment.label}',
                        color: sColor,
                      ),
                      _MLBadge(
                        text: '${a.readability.emoji} ${a.readability.label}',
                        color: rColor,
                      ),
                      _MLBadge(
                        text: '⏱ ${a.readability.readingTimeLabel}',
                        color: Colors.blueGrey,
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // ── Title ─────────────────────────
                  Text(
                    a.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 4),

                  // ── Description ───────────────────
                  Text(
                    a.description,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          a.source,
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      if (a.publishedAt.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            a.publishedAt.split('T').first,
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 11,
                            ),
                          ),
                        ),

                      IconButton(
                        icon: Icon(
                          _isBookmarked
                              ? Icons.bookmark
                              : Icons.bookmark_border,
                          color: _isBookmarked
                              ? const Color(0xFF2563EB)
                              : Colors.grey,
                        ),
                        onPressed: _toggleBookmark,
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

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ── Compact ML Badge ─────────────────────────
class _MLBadge extends StatelessWidget {
  final String text;
  final Color color;

  const _MLBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 3,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
