import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../utils/app_colors.dart';
import 'scan_item_screen.dart';
import 'add_edit_item_screen.dart';
import 'item_list_screen.dart';
import 'container_list_screen.dart';
import 'tally_screen.dart';
import 'repair_screen.dart';
import 'booking_list_screen.dart';
import 'reports_screen.dart';
import 'settings_menu_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final languageProvider = Provider.of<LanguageProvider>(context);
    final user = authProvider.user;

    return Scaffold(
      appBar: AppBar(
        title: Text(languageProvider.translate('home')),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await authProvider.logout();
              if (context.mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: AppColors.primary,
                      child: Text(
                        user?.name.substring(0, 1).toUpperCase() ?? 'U',
                        style: const TextStyle(
                          fontSize: 24,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Welcome, ${user?.name ?? 'User'}!',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user?.role.toUpperCase() ?? '',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Main Actions Grid
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.1,
              children: [
                _MenuCard(
                  icon: Icons.qr_code_scanner,
                  title: languageProvider.translate('scan_item'),
                  color: AppColors.primary,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ScanItemScreen()),
                  ),
                ),
                _MenuCard(
                  icon: Icons.inventory,
                  title: languageProvider.translate('items'),
                  color: AppColors.success,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ItemListScreen()),
                  ),
                ),
                _MenuCard(
                  icon: Icons.inventory_2,
                  title: languageProvider.translate('containers'),
                  color: AppColors.info,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ContainerListScreen()),
                  ),
                ),
                _MenuCard(
                  icon: Icons.checklist,
                  title: languageProvider.translate('start_tally'),
                  color: AppColors.warning,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TallyScreen()),
                  ),
                ),
                _MenuCard(
                  icon: Icons.build,
                  title: languageProvider.translate('repair_items'),
                  color: AppColors.secondary,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RepairScreen()),
                  ),
                ),
                _MenuCard(
                  icon: Icons.bookmark,
                  title: languageProvider.translate('bookings'),
                  color: Colors.orange,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BookingListScreen()),
                  ),
                ),
                _MenuCard(
                  icon: Icons.assessment,
                  title: languageProvider.translate('reports'),
                  color: Colors.purple,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ReportsScreen()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Settings Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.settings),
                label: Text(languageProvider.translate('settings')),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsMenuScreen()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 40,
                  color: color,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
