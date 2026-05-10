import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_screen.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  bool _isSaving = false;
  bool _isLoadingName = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentName();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // ── Load existing name from cache instantly ──────────────────────────────
  Future<void> _loadCurrentName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoadingName = false);
      return;
    }

    try {
      // Try cache first — instant, no network needed
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.cache));

      if (mounted && doc.exists) {
        _nameController.text = doc.data()?['name'] ?? '';
      }
    } catch (_) {
      // Cache miss — try server
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 5));

        if (mounted && doc.exists) {
          _nameController.text = doc.data()?['name'] ?? '';
        }
      } catch (e) {
        print('Load name error: $e');
        // Leave field empty — user can type their name
      }
    }

    if (mounted) setState(() => _isLoadingName = false);
  }

  // Save name
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isSaving = false);
      return;
    }

    final name = _nameController.text.trim();

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({'name': name}, SetOptions(merge: true))
          .timeout(const Duration(seconds: 5));

      await NotificationScreen.addNotification(
        title: 'Profile Updated',
        subtitle: 'Your name was changed to $name',
        type: NotificationType.account,
      );
    } catch (e) {
      print('Save profile error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save. Try again.')),
        );
      }
    }

    if (!mounted) return;
    setState(() => _isSaving = false);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Edit Profile")),
      body: _isLoadingName
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: "Name"),
                      validator: (value) => value == null || value.isEmpty
                          ? "Enter your name"
                          : null,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text("Save"),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
