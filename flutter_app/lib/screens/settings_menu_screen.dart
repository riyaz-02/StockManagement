import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../utils/app_colors.dart';
import 'item_settings_screen.dart';
import 'container_settings_screen.dart';
import 'tag_printing_screen.dart';
import 'recycle_bin_screen.dart';
import 'account_settings_screen.dart';
import 'manage_users_screen.dart';

class SettingsMenuScreen extends StatelessWidget {
  const SettingsMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final languageProvider = Provider.of<LanguageProvider>(context);
    
    // Check if user is admin
    if (authProvider.user?.role != 'admin') {
      return Scaffold(
        appBar: AppBar(title: Text(languageProvider.t('settings'))),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Admin Access Required',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Only administrators can access settings',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.maybePop(context);
            }
          },
        ),
        title: Text(
          languageProvider.t('settings'),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Account Settings (All Users)
          _buildSettingCard(
            context,
            languageProvider: languageProvider,
            title: languageProvider.t('account_settings'),
            icon: Icons.account_circle_outlined,
            color: Colors.teal,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AccountSettingsScreen()),
              );
            },
          ),
          const SizedBox(height: 12),
          
          // Manage Users (Admin Only)
          if (authProvider.user?.role == 'admin')
            _buildSettingCard(
              context,
              languageProvider: languageProvider,
              title: languageProvider.t('manage_users'),
              icon: Icons.people_outline,
              color: Colors.indigo,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ManageUsersScreen()),
                );
              },
            ),
          if (authProvider.user?.role == 'admin')
            const SizedBox(height: 12),
          
          _buildSettingCard(
            context,
            languageProvider: languageProvider,
            title: languageProvider.t('item_settings'),
            subtitle: 'Manage item types, metals, and purity options',
            icon: Icons.inventory,
            color: Colors.blue,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ItemSettingsScreen()),
              );
            },
          ),
          const SizedBox(height: 12), // Reduced from 16
          _buildSettingCard(
            context,
            languageProvider: languageProvider,
            title: languageProvider.t('container_settings'),
            subtitle: 'Manage container types, weight categories, and layouts',
            icon: Icons.inventory_2,
            color: Colors.green,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ContainerSettingsScreen()),
              );
            },
          ),
          const SizedBox(height: 12), // Reduced from 16
          _buildSettingCard(
            context,
            languageProvider: languageProvider,
            title: languageProvider.t('tag_printing'),
            subtitle: 'Print barcode tags and view print history',
            icon: Icons.print,
            color: Colors.pink,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TagPrintingScreen()),
              );
            },
          ),
          const SizedBox(height: 12), // Reduced from 16
          _buildSettingCard(
            context,
            languageProvider: languageProvider,
            title: languageProvider.t('recycle_bin'),
            subtitle: 'View and restore deleted items', // Modified subtitle
            icon: Icons.delete_outline,
            color: Colors.orange, // Modified color
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RecycleBinScreen()),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildSettingCard(
            context,
            languageProvider: languageProvider,
            title: languageProvider.t('system_settings'),
            subtitle: 'Configure system preferences and defaults',
            icon: Icons.settings,
            color: Colors.purple,
            onTap: () {
              // TODO: Navigate to system settings
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Coming soon!')),
              );
            },
          ),
          const SizedBox(height: 24),
          // Copyright footer
          Text(
            '© Laltu Guinea Palace',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
          const SizedBox(height: 2),
          Text(
            'Version 1.2.0',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey[400]),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSettingCard(
    BuildContext context, {
    required LanguageProvider languageProvider,
    required String title,
    String? subtitle, // Made optional but not used
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.7),
                Colors.white.withOpacity(0.3),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(10), // Reduced from 12
                child: Row(
                  children: [
                    Container(
                      width: 40, // Reduced from 48
                      height: 40, // Reduced from 48
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: color, size: 22), // Reduced from 24
                    ),
                    const SizedBox(width: 12), // Reduced from 16
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15, // Reduced from 16
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
