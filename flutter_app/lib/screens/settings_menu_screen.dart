import '../widgets/app_version_text.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import 'item_settings_screen.dart';
import 'stock_setting_screen.dart';
import 'container_settings_screen.dart';
import 'tag_printing_screen.dart';
import 'recycle_bin_screen.dart';
import 'account_settings_screen.dart';
import 'manage_users_screen.dart';
import 'action_needed_items_screen.dart';
import 'gst_config_screen.dart';
import 'app_update_settings_screen.dart';
import 'send_notification_screen.dart';
import 'role_permission_manager_screen.dart';

class SettingsMenuScreen extends StatelessWidget {
  const SettingsMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final languageProvider = Provider.of<LanguageProvider>(context);
    final isFullAccess = authProvider.user?.hasFullAccess == true;

    if (!isFullAccess) {
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
      backgroundColor: const Color(0xFFF7F7FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFF7F7FA),
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
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _SettingsSection(
            label: 'Account',
            accentColor: const Color(0xFF0D9488),
            rows: [
              _SettingsRow(
                title: languageProvider.t('account_settings'),
                subtitle: 'Profile, password, fingerprint login',
                icon: Icons.account_circle_outlined,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AccountSettingsScreen()),
                ),
              ),
            ],
          ),

          _SettingsSection(
            label: 'Inventory',
            accentColor: const Color(0xFF2563EB),
            rows: [
              _SettingsRow(
                title: languageProvider.t('item_settings'),
                subtitle: 'Stock types, metals, and purity options',
                icon: Icons.inventory_2_outlined,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ItemSettingsScreen()),
                ),
              ),
              _SettingsRow(
                title: 'Stock Setting',
                subtitle: 'Valuation, wastage, labour, sell, purchase and old metal rules',
                icon: Icons.tune_rounded,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StockSettingScreen()),
                ),
              ),
              _SettingsRow(
                title: languageProvider.t('container_settings'),
                subtitle: 'Container types, weight categories, layouts',
                icon: Icons.inventory_outlined,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ContainerSettingsScreen()),
                ),
              ),
              _SettingsRow(
                title: languageProvider.t('tag_printing'),
                subtitle: 'Print barcode tags and view print history',
                icon: Icons.print_outlined,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TagPrintingScreen()),
                ),
              ),
              _SettingsRow(
                title: 'Action Needed Stock',
                subtitle: 'Review stock added via quick-scan',
                icon: Icons.pending_actions_outlined,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ActionNeededItemsScreen()),
                ),
              ),
              _SettingsRow(
                title: languageProvider.t('recycle_bin'),
                subtitle: 'View and restore deleted stock',
                icon: Icons.delete_outline,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RecycleBinScreen()),
                ),
              ),
            ],
          ),

          _SettingsSection(
            label: 'Store & Billing',
            accentColor: const Color(0xFF059669),
            rows: [
              _SettingsRow(
                title: 'GST Configuration',
                subtitle: 'GSTIN, PAN, HSN code and tax rates',
                icon: Icons.percent_rounded,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GstConfigScreen()),
                ),
              ),
            ],
          ),

          _SettingsSection(
            label: 'Administration',
            accentColor: const Color(0xFF4F46E5),
            rows: [
              _SettingsRow(
                title: languageProvider.t('manage_users'),
                subtitle: 'Add, edit, and manage staff accounts',
                icon: Icons.people_outline,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ManageUsersScreen()),
                ),
              ),
              _SettingsRow(
                title: 'Roles & Permissions',
                subtitle: 'Configure what each role can do',
                icon: Icons.admin_panel_settings_outlined,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const RolePermissionManagerScreen()),
                ),
              ),
            ],
          ),

          _SettingsSection(
            label: 'Notifications & Updates',
            accentColor: const Color(0xFF7C3AED),
            rows: [
              _SettingsRow(
                title: 'Send Notification',
                subtitle: 'Push a message to all users or a specific role',
                icon: Icons.campaign_outlined,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SendNotificationScreen()),
                ),
              ),
              _SettingsRow(
                title: 'App Update Settings',
                subtitle: 'Control the update-available popup users see',
                icon: Icons.system_update_outlined,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AppUpdateSettingsScreen()),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          Text(
            '© Laltu Guinea Palace',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
          const SizedBox(height: 2),
          AppVersionText(
            style: TextStyle(fontSize: 11, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }
}

/// One labeled group of settings rows, rendered as a single flat card so
/// related options read as one unit instead of N separately-styled cards.
class _SettingsSection extends StatelessWidget {
  final String label;
  final Color accentColor;
  final List<_SettingsRow> rows;

  const _SettingsSection({
    required this.label,
    required this.accentColor,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: Colors.grey[500],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.withOpacity(0.12)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                for (int i = 0; i < rows.length; i++) ...[
                  _SettingsTile(row: rows[i], accentColor: accentColor),
                  if (i != rows.length - 1)
                    Divider(
                      height: 1,
                      indent: 60,
                      color: Colors.grey.withOpacity(0.12),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsRow {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _SettingsRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
}

class _SettingsTile extends StatelessWidget {
  final _SettingsRow row;
  final Color accentColor;

  const _SettingsTile({required this.row, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: row.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(row.icon, color: accentColor, size: 19),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      row.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[350], size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
