import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/article_model.dart';

class BookmarkService {
  static const String _localKey = 'bookmarks';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ── Wait for authenticated user ──────────────────────────────────────────────
  Future<User?> _getUser() async {
    // If already available, return immediately
    if (_auth.currentUser != null) return _auth.currentUser;

    // Otherwise wait up to 5 seconds for auth to restore (Flutter Web timing)
    try {
      return await _auth
          .authStateChanges()
          .where((u) => u != null)
          .first
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      return null; // timed out — user not logged in
    }
  }

  // ── Firestore path ───────────────────────────────────────────────────────────
  CollectionReference _bookmarksCol(String uid) =>
      _firestore.collection('users').doc(uid).collection('bookmarks');

  // ── Add Bookmark ─────────────────────────────────────────────────────────────
  Future<void> addBookmark(ArticleModel article) async {
    await _saveLocal(article);

    try {
      final user = await _getUser();
      print('DEBUG ADD BOOKMARK UID: ${user?.uid}');
      if (user == null) return;

      final docId = _urlToDocId(article.url);
      await _bookmarksCol(user.uid).doc(docId).set({
        'title': article.title,
        'description': article.description,
        'url': article.url,
        'urlToImage': article.urlToImage,
        'source': article.source,
        'publishedAt': article.publishedAt,
        'category': article.category,
        'savedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Firestore bookmark add error: $e');
    }
  }

  // ── Remove Bookmark ──────────────────────────────────────────────────────────
  Future<void> removeBookmark(String url) async {
    await _removeLocal(url);

    try {
      final user = await _getUser();
      if (user == null) return;
      await _bookmarksCol(user.uid).doc(_urlToDocId(url)).delete();
    } catch (e) {
      print('Firestore bookmark remove error: $e');
    }
  }

  // ── Is Bookmarked ────────────────────────────────────────────────────────────
  Future<bool> isBookmarked(String url) async {
    final bookmarks = await getBookmarks();
    return bookmarks.any((a) => a.url == url);
  }

  // ── Get All Bookmarks ────────────────────────────────────────────────────────
  Future<List<ArticleModel>> getBookmarks() async {
    try {
      final user = await _getUser();
      print('DEBUG GET BOOKMARKS UID: ${user?.uid}');
      if (user == null) return _getLocal();

      final snapshot = await _bookmarksCol(
        user.uid,
      ).orderBy('savedAt', descending: true).get();

      if (snapshot.docs.isNotEmpty) {
        final articles = snapshot.docs.map((doc) {
          final d = doc.data() as Map<String, dynamic>;
          return ArticleModel(
            title: d['title'] ?? '',
            description: d['description'] ?? '',
            url: d['url'] ?? '',
            urlToImage: d['urlToImage'] ?? '',
            source: d['source'] ?? '',
            publishedAt: d['publishedAt'] ?? '',
            category: d['category'] ?? '',
          );
        }).toList();

        await _overwriteLocal(articles);
        return articles;
      }
    } catch (e) {
      print('Firestore getBookmarks error: $e');
    }

    return _getLocal();
  }

  // Realtime Stream
  Stream<List<ArticleModel>> bookmarksStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value([]);

    return _bookmarksCol(uid)
        .orderBy('savedAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) {
            final d = doc.data() as Map<String, dynamic>;
            return ArticleModel(
              title: d['title'] ?? '',
              description: d['description'] ?? '',
              url: d['url'] ?? '',
              urlToImage: d['urlToImage'] ?? '',
              source: d['source'] ?? '',
              publishedAt: d['publishedAt'] ?? '',
              category: d['category'] ?? '',
            );
          }).toList(),
        );
  }

  // ── Local Helpers ────────────────────────────────────────────────────────────
  Future<List<ArticleModel>> _getLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_localKey) ?? [];
    return raw.map((s) {
      final map = json.decode(s) as Map<String, dynamic>;
      return ArticleModel(
        title: map['title'] ?? '',
        description: map['description'] ?? '',
        url: map['url'] ?? '',
        urlToImage: map['urlToImage'] ?? '',
        source: map['source'] ?? '',
        publishedAt: map['publishedAt'] ?? '',
        category: map['category'] ?? '',
      );
    }).toList();
  }

  Future<void> _saveLocal(ArticleModel article) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_localKey) ?? [];

    final existing = raw.map((s) {
      final m = json.decode(s) as Map<String, dynamic>;
      return m['url'] as String? ?? '';
    }).toList();

    if (!existing.contains(article.url)) {
      raw.insert(
        0,
        json.encode({
          'title': article.title,
          'description': article.description,
          'url': article.url,
          'urlToImage': article.urlToImage,
          'source': article.source,
          'publishedAt': article.publishedAt,
          'category': article.category,
        }),
      );
      await prefs.setStringList(_localKey, raw);
    }
  }

  Future<void> _removeLocal(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_localKey) ?? [];
    raw.removeWhere((s) {
      final m = json.decode(s) as Map<String, dynamic>;
      return m['url'] == url;
    });
    await prefs.setStringList(_localKey, raw);
  }

  Future<void> _overwriteLocal(List<ArticleModel> articles) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = articles
        .map(
          (a) => json.encode({
            'title': a.title,
            'description': a.description,
            'url': a.url,
            'urlToImage': a.urlToImage,
            'source': a.source,
            'publishedAt': a.publishedAt,
            'category': a.category,
          }),
        )
        .toList();
    await prefs.setStringList(_localKey, raw);
  }

  String _urlToDocId(String url) => url
      .replaceAll(RegExp(r'[^\w]'), '_')
      .substring(0, url.length > 100 ? 100 : url.length);
}
