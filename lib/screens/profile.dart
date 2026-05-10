import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:new_nexus/provider/location_provider.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/news_service.dart';

import 'login_screen.dart';
import 'edit_profile_screen.dart';
import 'notification_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  final LocationService _locationService = LocationService();

  Map<String, dynamic>? _userData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  // ───────────────────────── USER DATA ─────────────────────────
  Future<void> _loadUserData() async {
    User? user = FirebaseAuth.instance.currentUser;

    user ??= await FirebaseAuth.instance
        .authStateChanges()
        .where((u) => u != null)
        .first;

    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (mounted) {
        setState(() {
          _userData = doc.data();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Profile load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ───────────────────────── SIGN OUT ─────────────────────────
  Future<void> _signOut() async {
    await _authService.signOut();
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  // ───────────────────────── COUNTRY PICKER ─────────────────────────
  void _showCountryPicker() {
    final provider = context.read<LocationProvider>();

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
                'Change Location',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  'News on Home & Explore will update automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
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
                        await provider.detectLocation();
                      },
                    ),

                    const Divider(height: 1),

                    ...NewsService.supportedCountries.entries.map((entry) {
                      final countryName = entry.value['name'] as String;
                      final current = context
                          .watch<LocationProvider>()
                          .countryCode;

                      final isSelected = entry.key == current;

                      return ListTile(
                        title: Text(countryName),
                        trailing: isSelected
                            ? const Icon(Icons.check, color: Color(0xFF2563EB))
                            : null,
                        tileColor: isSelected
                            ? const Color(0xFF2563EB).withOpacity(0.08)
                            : null,
                        onTap: () async {
                          Navigator.pop(context);
                          await provider.changeCountry(entry.key);
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

  // ───────────────────────── LANGUAGE PICKER ─────────────────────────
  void _showLanguagePicker() {
    final provider = context.read<LocationProvider>();
    final country = provider.countryCode;
    final availableLanguages = NewsService.getLanguagesForCountry(country);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
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
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  'News on Home will update to your chosen language.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  controller: controller,
                  children: availableLanguages.map((langCode) {
                    final langName =
                        NewsService.getLanguageName(langCode) ?? langCode;
                    final current = provider.selectedLanguage;
                    final isSelected = langCode == current;

                    return ListTile(
                      title: Text(langName),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: Color(0xFF2563EB))
                          : null,
                      tileColor: isSelected
                          ? const Color(0xFF2563EB).withOpacity(0.08)
                          : null,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        provider.changeLanguage(langCode);
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

  // ───────────────────────── PASSWORD RESET ─────────────────────────
  Future<void> _changePassword() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email == null) return;

    await FirebaseAuth.instance.sendPasswordResetEmail(email: user!.email!);

    await NotificationScreen.addNotification(
      title: 'Password Reset',
      subtitle: 'Email sent to ${user.email}',
      type: NotificationType.account,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Password reset email sent')));
  }

  // ───────────────────────── UI ─────────────────────────
  @override
  Widget build(BuildContext context) {
    final locationProvider = context.watch<LocationProvider>();
    final country = locationProvider.countryCode;
    final selectedLanguage = locationProvider.selectedLanguage;

    final user = FirebaseAuth.instance.currentUser;

    // ✅ FIXED: Get full country name from the helper method
    final countryName =
        NewsService.getCountryName(country) ?? country.toUpperCase();
    final languageName =
        NewsService.getLanguageName(selectedLanguage) ??
        selectedLanguage.toUpperCase();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Profile',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _signOut),
        ],
      ),

      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const SizedBox(height: 20),

                  CircleAvatar(
                    radius: 50,
                    backgroundColor: const Color(0xFF2563EB),
                    child: Text(
                      (_userData?['name'] ?? 'U')[0].toUpperCase(),
                      style: const TextStyle(fontSize: 40, color: Colors.white),
                    ),
                  ),

                  const SizedBox(height: 16),

                  Text(
                    _userData?['name'] ?? 'User',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  Text(
                    user?.email ?? user?.phoneNumber ?? '',
                    style: TextStyle(color: Colors.grey[600]),
                  ),

                  const SizedBox(height: 8),

                  // COUNTRY & LANGUAGE CHIPS
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    alignment: WrapAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: _showCountryPicker,
                        child: Chip(
                          avatar: const Icon(
                            Icons.location_on,
                            size: 16,
                            color: Color(0xFF2563EB),
                          ),
                          label: Text(countryName),
                          backgroundColor: const Color(
                            0xFF2563EB,
                          ).withOpacity(0.08),
                          side: const BorderSide(color: Color(0xFF2563EB)),
                        ),
                      ),
                      GestureDetector(
                        onTap: _showLanguagePicker,
                        child: Chip(
                          avatar: const Icon(
                            Icons.language,
                            size: 16,
                            color: Colors.orange,
                          ),
                          label: Text(languageName),
                          backgroundColor: Colors.orange.withOpacity(0.08),
                          side: const BorderSide(color: Colors.orange),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 30),
                  const Divider(),

                  _ProfileTile(
                    icon: Icons.person_outline,
                    title: 'Edit Profile',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const EditProfileScreen(),
                        ),
                      ).then((_) => _loadUserData());
                    },
                  ),

                  _ProfileTile(
                    icon: Icons.location_on_outlined,
                    title: 'Change Location',
                    subtitle: countryName,
                    onTap: _showCountryPicker,
                  ),

                  _ProfileTile(
                    icon: Icons.language,
                    title: 'News Language',
                    subtitle: languageName,
                    onTap: _showLanguagePicker,
                  ),

                  _ProfileTile(
                    icon: Icons.notifications_outlined,
                    title: 'Notifications',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NotificationScreen(),
                        ),
                      );
                    },
                  ),

                  _ProfileTile(
                    icon: Icons.lock_outline,
                    title: 'Change Password',
                    onTap: _changePassword,
                  ),

                  _ProfileTile(
                    icon: Icons.info_outline,
                    title: 'About App',
                    onTap: () {
                      showAboutDialog(
                        context: context,
                        applicationName: 'News Nexus',
                        applicationVersion: '1.0.0',
                        applicationLegalese: '© 2026',
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _signOut,
                      icon: const Icon(Icons.logout),
                      label: const Text('Sign Out'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ───────────────────────── TILE ─────────────────────────
class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF2563EB)),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
