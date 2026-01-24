import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';

class CustomBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const CustomBottomNav({
    Key? key,
    required this.currentIndex,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    
    return Material(
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.3),
      child: Container(
        height: 55,
        decoration: const BoxDecoration(
          color: Colors.white,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            // Background container with notch
            Positioned.fill(
              child: CustomPaint(
                painter: BottomNavPainter(),
              ),
            ),
            // Navigation items
            SizedBox(
              height: 55,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildNavItem(
                      context: context,
                      icon: Icons.home_rounded,
                      label: languageProvider.t('home'),
                      index: 0,
                    ),
                    _buildNavItem(
                      context: context,
                      icon: Icons.inventory_2_rounded,
                      label: languageProvider.t('items'),
                      index: 1,
                    ),
                    // Center scan button - smaller and inside the bar
                    _buildCenterButton(),
                    _buildNavItem(
                      context: context,
                      icon: Icons.bookmark_rounded,
                      label: languageProvider.t('bookings'),
                      index: 3,
                    ),
                    _buildNavItem(
                      context: context,
                      icon: Icons.settings_rounded,
                      label: languageProvider.t('settings'),
                      index: 4,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required int index,
  }) {
    final isActive = currentIndex == index;
    
    return InkWell(
      onTap: () => onTap(index),
      borderRadius: BorderRadius.circular(16),
      splashColor: const Color(0xFFE94560).withOpacity(0.1),
      highlightColor: const Color(0xFFE94560).withOpacity(0.05),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                gradient: isActive
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFFE94560).withOpacity(0.15),
                          const Color(0xFFD32F2F).withOpacity(0.1),
                        ],
                      )
                    : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 20,
                color: isActive 
                    ? const Color(0xFFE94560) 
                    : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                fontSize: 8,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive 
                    ? const Color(0xFFE94560) 
                    : Colors.grey.shade600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterButton() {
    final isActive = currentIndex == 2;
    
    return Container(
      margin: const EdgeInsets.only(left: 5),
      child: Transform.translate(
        offset: const Offset(0, -12),
        child: GestureDetector(
          onTap: () => onTap(2),
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFE94560),
                  Color(0xFFD32F2F),
                  Color(0xFFC62828),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE94560).withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              Icons.qr_code_scanner_rounded,
              color: Colors.white,
              size: 35,
            ),
          ),
        ),
      ),
    );
  }
}

// Custom painter for bottom nav with notch
class BottomNavPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Draw gradient shadow background first
    final shadowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.grey.shade200.withOpacity(0.3),
          Colors.grey.shade100.withOpacity(0.1),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    
    final shadowPath = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    
    canvas.drawPath(shadowPath, shadowPaint);
    
    // Main white background with smooth circular notch
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final path = Path();
    
    // Start from top left
    path.moveTo(0, 24);
    
    // Top left corner curve
    path.quadraticBezierTo(0, 0, 24, 0);
    
    // Button is 70px diameter, positioned -12px up
    // Create a shallow circular notch (not full semicircle)
    final center = size.width / 2;
    final notchWidth = 36.0; // Width of the notch opening
    final notchRadius = 40.0; // Large radius for shallow arc
    
    // Line to start of circular arc
    path.lineTo(center - notchWidth, 0);
    
    // Create shallow circular arc using arcToPoint
    path.arcToPoint(
      Offset(center + notchWidth, 0),
      radius: Radius.circular(notchRadius),
      clockwise: true, // Arc goes upward
    );
    
    // Line to top right corner
    path.lineTo(size.width - 24, 0);
    
    // Top right corner curve
    path.quadraticBezierTo(size.width, 0, size.width, 24);
    
    // Right edge
    path.lineTo(size.width, size.height);
    
    // Bottom edge
    path.lineTo(0, size.height);
    
    // Close path
    path.close();
    
    // Draw multiple shadow layers for smooth shadow effect on curved notch
    for (int i = 5; i >= 1; i--) {
      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.02 * i)
        ..style = PaintingStyle.stroke
        ..strokeWidth = i * 2.0
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, i * 1.5);
      
      canvas.drawPath(path, shadowPaint);
    }
    
    // Draw the main white path
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
