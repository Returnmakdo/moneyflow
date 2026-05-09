import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme.dart';

/// 하단 탭 버튼 클릭을 화면에 신호로 전달.
/// 같은 탭을 다시 누를 때만 bump되어, 화면이 listen해서 상단 스크롤·필터 reset 등 처리.
class ShellTabSignals {
  ShellTabSignals._();
  static final dashboardTab = ValueNotifier<int>(0);
  static final transactionsTab = ValueNotifier<int>(0);
  static final budgetsTab = ValueNotifier<int>(0);
  static final accountsTab = ValueNotifier<int>(0);
  static final insightsTab = ValueNotifier<int>(0);

  static void bump(int index) {
    switch (index) {
      case 0:
        dashboardTab.value++;
      case 1:
        transactionsTab.value++;
      case 2:
        budgetsTab.value++;
      case 3:
        accountsTab.value++;
      case 4:
        insightsTab.value++;
    }
  }
}

class ShellScreen extends StatelessWidget {
  const ShellScreen({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  static const tabs = [
    _Tab('대시보드', Icons.dashboard_outlined, Icons.dashboard),
    _Tab('거래내역', Icons.receipt_long_outlined, Icons.receipt_long),
    _Tab('예산', Icons.savings_outlined, Icons.savings),
    _Tab('자산', Icons.account_balance_wallet_outlined,
        Icons.account_balance_wallet),
    _Tab('분석', Icons.insights_outlined, Icons.insights),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(bottom: false, child: navigationShell),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        height: 64,
        indicatorColor: AppColors.primaryWeak,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (i) {
          // 같은 탭을 다시 누를 때만 신호 bump — 화면이 listen해서 상단 스크롤·
          // 필터 reset 등 처리.
          if (i == navigationShell.currentIndex) {
            ShellTabSignals.bump(i);
          }
          navigationShell.goBranch(
            i,
            initialLocation: i == navigationShell.currentIndex,
          );
        },
        destinations: [
          for (final t in tabs)
            NavigationDestination(
              icon: Icon(t.icon, color: AppColors.text3),
              selectedIcon: Icon(t.activeIcon, color: AppColors.primary),
              label: t.label,
            ),
        ],
      ),
    );
  }
}

class _Tab {
  const _Tab(this.label, this.icon, this.activeIcon);
  final String label;
  final IconData icon;
  final IconData activeIcon;
}
