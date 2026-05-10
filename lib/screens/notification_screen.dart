import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

enum NotificationType { breakingNews, bookmark, account }

class NotificationItem {
  final String id;
  final String title;
  final String subtitle;
  final NotificationType type;
  final String? actionUrl; // for news articles
  final DateTime timestamp;
  bool isRead;

  NotificationItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
    this.actionUrl,
    required this.timestamp,
    this.isRead = false,
  });

  factory NotificationItem.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return NotificationItem(
      id: doc.id,
      title: d['title'] ?? '',
      subtitle: d['subtitle'] ?? '',
      type: NotificationType.values.firstWhere(
        (e) => e.name == (d['type'] ?? 'breakingNews'),
        orElse: () => NotificationType.breakingNews,
      ),
      actionUrl: d['actionUrl'],
      timestamp: (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isRead: d['isRead'] ?? false,
    );
  }
}

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  // ── Firestore collection for current user ──────────────────────────────────
  static CollectionReference? _notificationsCol() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications');
  }

  // ── Add a notification (call this from anywhere in the app) ───────────────
  static Future<void> addNotification({
    required String title,
    required String subtitle,
    required NotificationType type,
    String? actionUrl,
  }) async {
    final col = _notificationsCol();
    if (col == null) return;
    await col.add({
      'title': title,
      'subtitle': subtitle,
      'type': type.name,
      'actionUrl': actionUrl,
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
    });
  }

  // ── Mark all as read ───────────────────────────────────────────────────────
  Future<void> _markAllRead() async {
    final col = _notificationsCol();
    if (col == null) return;
    final unread = await col.where('isRead', isEqualTo: false).get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  // ── Delete a notification ──────────────────────────────────────────────────
  Future<void> _delete(String id) async {
    final col = _notificationsCol();
    if (col == null) return;
    await col.doc(id).delete();
  }

  // ── Handle tap ────────────────────────────────────────────────────────────
  Future<void> _handleTap(BuildContext context, NotificationItem item) async {
    // Mark as read first
    final col = _notificationsCol();
    if (col != null) {
      await col.doc(item.id).update({'isRead': true});
    }

    if (!context.mounted) return;

    if (item.type == NotificationType.breakingNews &&
        item.actionUrl != null &&
        item.actionUrl!.isNotEmpty) {
      // ✅ FIXED: open article with externalApplication mode + proper error handling
      final uri = Uri.parse(item.actionUrl!);
      try {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (!launched && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open article')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error opening article: $e')));
        }
      }
    } else if (item.type == NotificationType.bookmark) {
      // ✅ FIXED: navigates to /home with arguments: 2 which BottomNavBar
      // now reads via initialIndex — opens Bookmark tab directly
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/home',
        (route) => false,
        arguments: 2, // index 2 = Bookmark tab
      );
    }
    // Account notifications — just mark read, no navigation needed
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${time.day}/${time.month}/${time.year}';
  }

  IconData _iconForType(NotificationType type) {
    switch (type) {
      case NotificationType.breakingNews:
        return Icons.newspaper;
      case NotificationType.bookmark:
        return Icons.bookmark;
      case NotificationType.account:
        return Icons.person;
    }
  }

  Color _colorForType(NotificationType type) {
    switch (type) {
      case NotificationType.breakingNews:
        return Colors.red;
      case NotificationType.bookmark:
        return const Color(0xFF2563EB);
      case NotificationType.account:
        return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: _markAllRead,
            child: const Text(
              'Mark all read',
              style: TextStyle(color: Color(0xFF2563EB)),
            ),
          ),
        ],
      ),
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, authSnap) {
          if (authSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!authSnap.hasData) {
            return const Center(
              child: Text('Please log in to see notifications'),
            );
          }

          return StreamBuilder<QuerySnapshot>(
            stream: _notificationsCol()
                ?.orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snap.data?.docs ?? [];

              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.notifications_none,
                        size: 80,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No notifications yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                );
              }

              final items = docs
                  .map((d) => NotificationItem.fromFirestore(d))
                  .toList();

              return ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 72),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Dismissible(
                    key: Key(item.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 16),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) => _delete(item.id),
                    child: InkWell(
                      onTap: () => _handleTap(context, item),
                      child: Container(
                        color: item.isRead
                            ? Colors.transparent
                            : const Color(0xFF2563EB).withValues(alpha: 0.05),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Icon circle
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: _colorForType(
                                  item.type,
                                ).withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _iconForType(item.type),
                                color: _colorForType(item.type),
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Text content
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.title,
                                          style: TextStyle(
                                            fontWeight: item.isRead
                                                ? FontWeight.normal
                                                : FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      // Unread blue dot
                                      if (!item.isRead)
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF2563EB),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.subtitle,
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _timeAgo(item.timestamp),
                                    style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
