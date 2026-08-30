import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../services/api_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_toast.dart';
import 'edit_profile_screen.dart';
import 'change_password_screen.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final ApiService _apiService = ApiService();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isUploadingImage = false;

  Future<void> _uploadProfileImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() => _isUploadingImage = true);

      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // Upload to Cloudinary with 'users' folder
      final result = await _apiService.uploadImage(image, folder: 'users');

      if (result['success'] == true) {
        final imageUrl = result['data']['url'];

        // Update user profile with new image
        final updateResult = await _apiService.updateUser(
          authProvider.user!.id,
          {'profileImage': imageUrl},
        );

        if (updateResult['success'] == true) {
          // Update local user data
          final refreshed = await authProvider.refreshUser();

          if (mounted) {
            if (refreshed) {
              ScaffoldMessenger.of(context).showMaterialBanner(
                MaterialBanner(
                  content: const Text('Profile image updated successfully'),
                  backgroundColor: Colors.green.shade100,
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  actions: [
                    TextButton(
                      onPressed: () => ScaffoldMessenger.of(context)
                          .hideCurrentMaterialBanner(),
                      child: const Text('DISMISS'),
                    ),
                  ],
                ),
              );
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) {
                  ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                }
              });
            } else {
              showAppSnackBar(
                context,
                const SnackBar(
                  content: Text(
                      'Image saved, but failed to refresh your profile — pull to refresh or re-open this screen'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          }
        } else if (mounted) {
          showAppSnackBar(
            context,
            SnackBar(
              content: Text(
                  updateResult['message'] ?? 'Failed to save profile image'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else if (mounted) {
        showAppSnackBar(
          context,
          SnackBar(
            content: Text(result['message'] ?? 'Failed to upload image'),
            backgroundColor: Colors.red,
          ),
        );
      }

      setState(() => _isUploadingImage = false);
    } catch (e) {
      setState(() => _isUploadingImage = false);
      if (mounted) {
        showAppSnackBar(
          context,
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final languageProvider = Provider.of<LanguageProvider>(context);
    final user = authProvider.user;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text(languageProvider.t('account_settings'))),
        body: const Center(child: Text('No user data available')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        title: Text(
          languageProvider.t('account_settings'),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Profile Image Section
            Center(
              child: Stack(
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.primary, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: user.profileImage != null &&
                              user.profileImage!.isNotEmpty
                          ? Image.network(
                              user.profileImage!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: Colors.grey[200],
                                child: Icon(Icons.person,
                                    size: 60, color: Colors.grey[400]),
                              ),
                            )
                          : Container(
                              color: AppColors.primary.withOpacity(0.1),
                              child: Icon(Icons.person,
                                  size: 60, color: AppColors.primary),
                            ),
                    ),
                  ),
                  if (_isUploadingImage)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black54,
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _isUploadingImage ? null : _uploadProfileImage,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.camera_alt,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // User Info Card
            _buildInfoCard(
              languageProvider: languageProvider,
              title: 'Personal Information',
              children: [
                _buildInfoRow(Icons.person_outline, languageProvider.t('name'),
                    user.name),
                const Divider(height: 24),
                _buildInfoRow(Icons.phone_outlined, 'Mobile', user.mobile),
                const Divider(height: 24),
                _buildInfoRow(Icons.badge_outlined, languageProvider.t('role'),
                    user.role.toUpperCase()),
                const Divider(height: 24),
                _buildInfoRow(
                  Icons.calendar_today_outlined,
                  'Member Since',
                  _formatDate(user.createdAt),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Actions Card
            _buildInfoCard(
              languageProvider: languageProvider,
              title: 'Actions',
              children: [
                _buildActionButton(
                  icon: Icons.edit_outlined,
                  label: languageProvider.t('edit_profile'),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const EditProfileScreen()),
                    );
                  },
                ),
                const Divider(height: 16),
                _buildActionButton(
                  icon: Icons.lock_outline,
                  label: languageProvider.t('change_password'),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ChangePasswordScreen()),
                    );
                  },
                ),
                const Divider(height: 16),
                _buildActionButton(
                  icon: Icons.logout,
                  label: languageProvider.t('logout'),
                  color: Colors.red,
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(languageProvider.t('logout')),
                        content: Text(languageProvider.t('are_you_sure')),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.red),
                            child: Text(languageProvider.t('logout')),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true && mounted) {
                      await authProvider.logout();
                      if (mounted) {
                        Navigator.of(context).pushNamedAndRemoveUntil(
                            '/login', (route) => false);
                      }
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(
      {required LanguageProvider languageProvider,
      required String title,
      required List<Widget> children}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: Colors.grey[700]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final actionColor = color ?? AppColors.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: actionColor, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: actionColor,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
