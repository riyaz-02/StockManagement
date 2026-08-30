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
import 'store_management_screen.dart';
import 'invoice_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Timer? _timer;
  DateTime _currentTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimer();
      setState(() => _currentTime = DateTime.now());
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    // Update every minute instead of every second for battery optimization
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
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
                          final logoHeight =
                              constraints.maxWidth > 600 ? 70.0 : 60.0;
                          final days = [
                            'Sunday',
                            'Monday',
                            'Tuesday',
                            'Wednesday',
                            'Thursday',
                            'Friday',
                            'Saturday'
                          ];
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
                                  filter:
                                      ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 10),
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
                                        color: const Color(0xFFE94560)
                                            .withOpacity(0.3),
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
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        // Gradient Icon
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [
                                                Color(0xFFE94560),
                                                Color(0xFFFF6B9D)
                                              ],
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFFE94560)
                                                    .withOpacity(0.3),
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
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Consumer<LanguageProvider>(
                                                builder: (context,
                                                        languageProvider,
                                                        child) =>
                                                    Text(
                                                  '${languageProvider.t('welcome_back')} ${user?.name ?? 'User'}',
                                                  style: const TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w700,
                                                    color: Color(0xFF1A1A1A),
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  maxLines: 1,
                                                ),
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
                icon: const Icon(Icons.logout,
                    color: Color(0xFFE94560), size: 24),
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

                  // Feature Cards Grid - Auto-sizing based on content
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      SizedBox(
                        width: (MediaQuery.of(context).size.width - 56) /
                            2, // Half width minus padding
                        child: Consumer<LanguageProvider>(
                          builder: (context, languageProvider, child) =>
                              _ElegantCard(
                            icon: Icons.qr_code_scanner,
                            title: languageProvider.t('scan_item'),
                            description: languageProvider.t('scan_barcode'),
                            primaryColor: const Color(0xFFFF6B9D),
                            secondaryColor: const Color(0xFFFF6B9D),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const GeneralScanScreen()),
                              );
                            },
                          ),
                        ),
                      ),
                      SizedBox(
                        width: (MediaQuery.of(context).size.width - 56) / 2,
                        child: Consumer<LanguageProvider>(
                          builder: (context, languageProvider, child) =>
                              _ElegantCard(
                            icon: Icons.inventory_2_rounded,
                            title: languageProvider.t('items'),
                            description: languageProvider.t('view_all_items'),
                            primaryColor: const Color(0xFF11998E),
                            secondaryColor: const Color(0xFF38EF7D),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const ItemListScreen()),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: (MediaQuery.of(context).size.width - 56) / 2,
                        child: Consumer<LanguageProvider>(
                          builder: (context, languageProvider, child) =>
                              _ElegantCard(
                            icon: Icons.widgets_rounded,
                            title: languageProvider.t('containers'),
                            description: languageProvider.t('manage_storage'),
                            primaryColor: const Color(0xFF8E2DE2),
                            secondaryColor: const Color(0xFF4A00E0),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const ContainerListScreen()),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: (MediaQuery.of(context).size.width - 56) / 2,
                        child: Consumer<LanguageProvider>(
                          builder: (context, languageProvider, child) =>
                              _ElegantCard(
                            icon: Icons.assessment_rounded,
                            title: languageProvider.t('start_tally'),
                            description: languageProvider.t('verify_inventory'),
                            primaryColor: const Color(0xFFFF6B6B),
                            secondaryColor: const Color(0xFFEE5A6F),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const TallyListScreen()),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: (MediaQuery.of(context).size.width - 56) / 2,
                        child: Consumer<LanguageProvider>(
                          builder: (context, languageProvider, child) =>
                              _ElegantCard(
                            icon: Icons.receipt_long_rounded,
                            title: languageProvider.t('bookings'),
                            description: languageProvider.t('customer_orders'),
                            primaryColor: const Color(0xFF00C9FF),
                            secondaryColor: const Color(0xFF92FE9D),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const BookingListScreen()),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: (MediaQuery.of(context).size.width - 56) / 2,
                        child: _ElegantCard(
                          icon: Icons.analytics_rounded,
                          title: 'Reports',
                          description: 'Analytics & insights',
                          primaryColor: const Color(0xFFF093FB),
                          secondaryColor: const Color(0xFFF5576C),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const ReportsScreen()),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: (MediaQuery.of(context).size.width - 56) / 2,
                        child: _ElegantCard(
                          icon: Icons.store_rounded,
                          title: 'Store',
                          description: 'Stock, GST & purchases',
                          primaryColor: const Color(0xFF059669),
                          secondaryColor: const Color(0xFF34D399),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const StoreManagementScreen()),
                          ),
                        ),
                      ),
                      // ── GST Invoice card ───────────────────────────────
                      SizedBox(
                        width: (MediaQuery.of(context).size.width - 56) / 2,
                        child: _ElegantCard(
                          icon: Icons.receipt_outlined,
                          title: 'GST Invoice',
                          description: 'Sales billing',
                          primaryColor: const Color(0xFFD97706),
                          secondaryColor: const Color(0xFFF59E0B),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const InvoiceScreen()),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Bottom padding for navigation bar
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 70),
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

class _ElegantCardState extends State<_ElegantCard>
    with SingleTickerProviderStateMixin {
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
                LayoutBuilder(
                  builder: (context, constraints) {
                    // Calculate responsive sizes based on card width
                    final cardWidth = constraints.maxWidth;
                    final isSmallScreen = cardWidth < 170;

                    // Responsive sizes - more aggressive reduction for small screens
                    final padding = isSmallScreen ? 8.0 : 14.0;
                    final iconSize = isSmallScreen ? 36.0 : 46.0;
                    final iconRadius = isSmallScreen ? 9.0 : 12.0;
                    final iconInnerSize = isSmallScreen ? 18.0 : 24.0;
                    final spacingAfterIcon = isSmallScreen ? 6.0 : 10.0;
                    final titleFontSize = isSmallScreen ? 13.0 : 15.5;
                    final spacingAfterTitle = isSmallScreen ? 2.0 : 3.0;
                    final descriptionFontSize = isSmallScreen ? 9.5 : 11.0;

                    return Padding(
                      padding: EdgeInsets.fromLTRB(
                        padding + 4, // Extra left padding
                        padding,
                        padding,
                        padding,
                      ),
                      child: LayoutBuilder(
                        builder: (context, innerConstraints) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              // Icon with gradient
                              Container(
                                width: iconSize,
                                height: iconSize,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      widget.primaryColor,
                                      widget.secondaryColor
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius:
                                      BorderRadius.circular(iconRadius),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          widget.primaryColor.withOpacity(0.3),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  widget.icon,
                                  color: Colors.white,
                                  size: iconInnerSize,
                                ),
                              ),
                              SizedBox(height: spacingAfterIcon),

                              // Title - flexible to prevent overflow
                              Flexible(
                                child: Text(
                                  widget.title,
                                  style: TextStyle(
                                    fontSize: titleFontSize,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF1A1A1A),
                                    letterSpacing: -0.3,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SizedBox(height: spacingAfterTitle),

                              // Description - flexible to prevent overflow
                              Flexible(
                                child: Text(
                                  widget.description,
                                  style: TextStyle(
                                    fontSize: descriptionFontSize,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                    height: 1.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
