import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/store_provider.dart';
import '../utils/app_colors.dart';
import 'store_tabs/stock_dashboard_tab.dart';
import 'store_tabs/purchase_list_tab.dart';
import 'store_tabs/stock_summary_tab.dart';
import 'store_tabs/reconciliation_tab.dart';

class StoreManagementScreen extends StatefulWidget {
  const StoreManagementScreen({super.key});

  @override
  State<StoreManagementScreen> createState() => _StoreManagementScreenState();
}

class _StoreManagementScreenState extends State<StoreManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentTab = 0;

  static const _tabs = [
    _TabMeta(Icons.inventory_2_outlined, 'Stock',     'Live stock weight'),
    _TabMeta(Icons.receipt_long_outlined,'Purchases', 'All purchase entries'),
    _TabMeta(Icons.bar_chart_rounded,    'Summary',   'Daily in/out ledger'),
    _TabMeta(Icons.balance_outlined,     'Reconcile', 'Balance check'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) return;
        setState(() => _currentTab = _tabController.index);
      });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final store = Provider.of<StoreProvider>(context, listen: false);
      store.fetchStockDashboard();
      store.fetchPurchases();
      store.fetchDailySummary();
      store.fetchReconciliation();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<StoreProvider>(
      builder: (context, store, _) {
        return Scaffold(
          backgroundColor: const Color(0xFFF8F9FC),
          body: NestedScrollView(
            headerSliverBuilder: (context, _) => [
              SliverAppBar(
                pinned: true,
                floating: false,
                expandedHeight: 110,
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1A1A1A),
                elevation: 0,
                shadowColor: Colors.black12,
                surfaceTintColor: Colors.white,
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding:
                      const EdgeInsets.fromLTRB(16, 0, 16, 58),
                  title: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Store Management',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          color: Color(0xFF1A1A1A),
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        _tabs[_currentTab].subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(48),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        bottom: BorderSide(
                            color: Colors.grey.shade100, width: 1),
                      ),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      labelColor: AppColors.primary,
                      unselectedLabelColor: Colors.grey[500],
                      indicatorColor: AppColors.primary,
                      indicatorWeight: 2.5,
                      indicatorSize: TabBarIndicatorSize.label,
                      labelStyle: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700),
                      unselectedLabelStyle: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500),
                      tabs: [
                        for (int i = 0; i < _tabs.length; i++)
                          Tab(
                            icon: i == 3
                                ? _reconcileIcon(store.hasReconcileAlert)
                                : Icon(_tabs[i].icon, size: 18),
                            text: _tabs[i].label,
                            iconMargin: const EdgeInsets.only(bottom: 2),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            body: TabBarView(
              controller: _tabController,
              children: const [
                StockDashboardTab(),
                PurchaseListTab(),
                StockSummaryTab(),
                ReconciliationTab(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _reconcileIcon(bool hasAlert) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(_tabs[3].icon, size: 18),
        if (hasAlert)
          Positioned(
            right: -5,
            top: -3,
            child: Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Colors.red, shape: BoxShape.circle),
            ),
          ),
      ],
    );
  }
}

class _TabMeta {
  final IconData icon;
  final String label;
  final String subtitle;
  const _TabMeta(this.icon, this.label, this.subtitle);
}
