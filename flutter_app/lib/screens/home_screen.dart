import 'dart:ui';
import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../utils/app_colors.dart';
import 'general_scan_screen.dart';
import 'item_list_screen.dart';
import 'container_list_screen.dart';
import 'tally_list_screen.dart';
import 'booking_list_screen.dart';
import 'reports_screen.dart';
import 'settings_menu_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _timer;
  DateTime _currentTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          // Elegant Header with Logo and Glassmorphism Welcome
          SliverAppBar(
            expandedHeight: 180,
            floating: false,
            pinned: true,
            elevation: 0,
            backgroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                children: [
                  // White base
                  Container(
                    color: Colors.white,
                  ),
                  // Decorative circles (larger size)
                  Positioned(
                    right: -100,
                    top: -100,
                    child: Container(
                      width: 280,
                      height: 280,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFE94560).withOpacity(0.12),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 5,
                    top: 5,
                    child: Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFFF6B9D).withOpacity(0.1),
                      ),
                    ),
                  ),
                  // Content
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final logoHeight = constraints.maxWidth > 600 ? 70.0 : 60.0;
                          final days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
                          final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                          
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Shop Logo
                              Image.asset(
                                'assets/images/lgp_logo_red.png',
                                height: logoHeight,
                                errorBuilder: (context, error, stackTrace) {
                                  return Icon(
                                    Icons.diamond,
                                    color: const Color(0xFFE94560),
                                    size: logoHeight,
                                  );
                                },
                              ),
                              const Spacer(),
                              // Glassmorphism Welcome Card
                              ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.white.withOpacity(0.4),
                                          Colors.white.withOpacity(0.25),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: const Color(0xFFE94560).withOpacity(0.3),
                                        width: 1.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        // Gradient Icon
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [Color(0xFFE94560), Color(0xFFFF6B9D)],
                                            ),
                                            borderRadius: BorderRadius.circular(10),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFFE94560).withOpacity(0.3),
                                                blurRadius: 8,
                                                offset: const Offset(0, 3),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.waving_hand,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // Text Content
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'Welcome ${user?.name ?? 'User'}',
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF1A1A1A),
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                              ),
                                              const SizedBox(height: 1),
                                              FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  '${days[_currentTime.weekday % 7]}, ${_currentTime.day} ${months[_currentTime.month - 1]} • ${_currentTime.hour.toString().padLeft(2, '0')}:${_currentTime.minute.toString().padLeft(2, '0')}:${_currentTime.second.toString().padLeft(2, '0')}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w500,
                                                    color: Colors.grey[700],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.settings_outlined, color: Colors.grey[700], size: 24),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsMenuScreen()),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: Color(0xFFE94560), size: 24),
                onPressed: () async {
                  await authProvider.logout();
                  if (context.mounted) {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  }
                },
              ),
              const SizedBox(width: 8),
            ],
          ),

          // Content Section
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Feature Cards Grid (removed section header)
                  const SizedBox(height: 0),
                  const Text(
                        '',
                        style: TextStyle(
                          fontSize: 0,
                        ),
                      ),

                  // Feature Cards Grid
                  LayoutBuilder(
                    builder: (context, constraints) {
                      // Adjust aspect ratio based on screen width
                      final aspectRatio = constraints.maxWidth < 340 ? 0.95 : 1.1;
                      return GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: aspectRatio,
                    children: [
                      _ElegantCard(
                        icon: Icons.qr_code_scanner,
                        title: 'Scan',
                        description: 'Scan Barcode',
                        primaryColor: const Color(0xFFFF6B9D),
                        secondaryColor: const Color(0xFFFF6B9D), // Assuming a single color for now, or adjust as needed
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const GeneralScanScreen()),
                          );
                        },
                      ),
                      _ElegantCard(
                        icon: Icons.inventory_2_rounded,
                        title: 'Inventory',
                        description: 'View all items',
                        primaryColor: const Color(0xFF11998E),
                        secondaryColor: const Color(0xFF38EF7D),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ItemListScreen()),
                        ),
                      ),
                      _ElegantCard(
                        icon: Icons.widgets_rounded,
                        title: 'Containers',
                        description: 'Manage storage',
                        primaryColor: const Color(0xFFEE0979),
                        secondaryColor: const Color(0xFFFF6A00),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ContainerListScreen()),
                        ),
                      ),
                      _ElegantCard(
                        icon: Icons.fact_check_rounded,
                        title: 'Stock Tally',
                        description: 'Verify inventory',
                        primaryColor: const Color(0xFFF093FB),
                        secondaryColor: const Color(0xFFF5576C),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const TallyListScreen()),
                        ),
                      ),
                      _ElegantCard(
                        icon: Icons.event_note_rounded,
                        title: 'Bookings',
                        description: 'Customer orders',
                        primaryColor: const Color(0xFF4FACFE),
                        secondaryColor: const Color(0xFF00F2FE),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const BookingListScreen()),
                        ),
                      ),
                      _ElegantCard(
                        icon: Icons.analytics_rounded,
                        title: 'Reports',
                        description: 'Analytics & insights',
                        primaryColor: const Color(0xFF43E97B),
                        secondaryColor: const Color(0xFF38F9D7),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ReportsScreen()),
                        ),
                      ),
                    ],
                  );
                },
              ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ElegantCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color primaryColor;
  final Color secondaryColor;
  final VoidCallback onTap;

  const _ElegantCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.primaryColor,
    required this.secondaryColor,
    required this.onTap,
  });

  @override
  State<_ElegantCard> createState() => _ElegantCardState();
}

class _ElegantCardState extends State<_ElegantCard> with SingleTickerProviderStateMixin {
  bool _isPressed = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
        _controller.forward();
      },
      onTapUp: (_) {
        setState(() => _isPressed = false);
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
        _controller.reverse();
      },
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: widget.primaryColor.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                // Gradient Background (subtle)
                Positioned(
                  right: -20,
                  top: -20,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          widget.primaryColor.withOpacity(0.1),
                          widget.secondaryColor.withOpacity(0.05),
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                
                // Content
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Icon with gradient
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [widget.primaryColor, widget.secondaryColor],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: widget.primaryColor.withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          widget.icon,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(height: 14),
                      
                      // Title
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A1A),
                          letterSpacing: -0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      
                      // Description
                      Text(
                        widget.description,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
