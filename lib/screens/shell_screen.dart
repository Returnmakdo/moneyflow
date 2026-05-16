import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../auth.dart';
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

  // 분석 탭(index 4)은 AI 베타. 베타 사용자에만 NavigationBar에 노출. 라우트
  // (/insights)는 살아있어서 직접 URL 입력 시 진입 가능.
  static const _allTabs = [
    _Tab('대시보드', Icons.dashboard_outlined, Icons.dashboard),
    _Tab('거래내역', Icons.receipt_long_outlined, Icons.receipt_long),
    _Tab('예산', Icons.savings_outlined, Icons.savings),
    _Tab('자산', Icons.account_balance_wallet_outlined,
        Icons.account_balance_wallet),
    _Tab('분석', Icons.insights_outlined, Icons.insights),
  ];

  @override
  Widget build(BuildContext context) {
    final visibleTabs = AuthService.aiBetaEnabled
        ? _allTabs
        : _allTabs.sublist(0, 4);
    // currentIndex가 visible 범위 밖이면(베타 X 사용자가 URL로 /insights 들어옴)
    // NavigationBar 선택 표시 안 보이게 -1 처리 — NavigationBar는 -1 미지원이라
    // 0으로 clamp하되 indicator 숨김을 위해 별도 처리 필요. 단순화: clamp만.
    final selected = navigationShell.currentIndex < visibleTabs.length
        ? navigationShell.currentIndex
        : 0;
    return Scaffold(
      body: SafeArea(bottom: false, child: navigationShell),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        height: 64,
        indicatorColor: AppColors.primaryWeak,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: selected,
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
          for (final t in visibleTabs)
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
