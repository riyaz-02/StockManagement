import 'package:flutter/material.dart';
import 'package:jewellery_stock_app/screens/home_screen.dart';
import 'package:jewellery_stock_app/screens/item_list_screen.dart';
import 'package:jewellery_stock_app/screens/general_scan_screen.dart';
import 'package:jewellery_stock_app/screens/settings_menu_screen.dart';
import 'package:jewellery_stock_app/screens/booking_list_screen.dart';
import 'package:jewellery_stock_app/widgets/custom_bottom_nav.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({Key? key}) : super(key: key);

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  // Screens for each navigation item
  final List<Widget> _screens = [
    const HomeScreen(),
    const ItemListScreen(),
    const GeneralScanScreen(),
    const BookingListScreen(), // Actual booking screen
    const SettingsMenuScreen(),
  ];

  void _onNavTap(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  Future<bool> _onWillPop() async {
    // If not on home screen, navigate to home
    if (_currentIndex != 0) {
      setState(() {
        _currentIndex = 0;
      });
      return false; // Don't exit app
    }
    return true; // Exit app if already on home
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: _screens,
        ),
        bottomNavigationBar: CustomBottomNav(
          currentIndex: _currentIndex,
          onTap: _onNavTap,
        ),
      ),
    );
  }
}
