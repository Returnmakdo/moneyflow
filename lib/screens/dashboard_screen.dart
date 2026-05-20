import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../auth.dart';
import '../state/selected_month.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/format.dart';
import '../widgets/ko_date_picker.dart';
import '../widgets/kpi_card.dart';
import '../widgets/merchant_item.dart';
import '../widgets/skeleton.dart';
import 'shell_screen.dart' show ShellTabSignals;

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  _DashData? _data;
  Object? _error;
  final ScrollController _scrollCtrl = ScrollController();

  String get _month => SelectedMonth.value.value;

  late final Listenable _apiListenable = Listenable.merge([
    Api.instance.txVersion,
    Api.instance.majorsVersion,
    Api.instance.budgetsVersion,
  ]);
  bool _reloadScheduled = false;

  @override
  void initState() {
    super.initState();
    _apiListenable.addListener(_onApiChanged);
    SelectedMonth.value.addListener(_onMonthChanged);
    AuthService.userVersion.addListener(_onUserChanged);
    ShellTabSignals.dashboardTab.addListener(_onTabPressed);
    _reload();
  }

  @override
  void dispose() {
    _apiListenable.removeListener(_onApiChanged);
    SelectedMonth.value.removeListener(_onMonthChanged);
    AuthService.userVersion.removeListener(_onUserChanged);
    ShellTabSignals.dashboardTab.removeListener(_onTabPressed);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onTabPressed() {
    if (!mounted || !_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _onMonthChanged() {
    if (mounted) {
      setState(() {});
      _reload();
    }
  }

  void _onUserChanged() {
    // 닉네임 변경 등 사용자 정보 갱신 시 인사말 즉시 반영.
    if (mounted) setState(() {});
  }

  void _onApiChanged() {
    if (_reloadScheduled || !mounted) return;
    _reloadScheduled = true;
    scheduleMicrotask(() {
      _reloadScheduled = false;
      if (mounted) _reload();
    });
  }

  Future<void> _reload() async {
    try {
      final api = Api.instance;
      // 지난달 ym 계산 (지출 속도 비교용).
      final parts = _month.split('-').map(int.parse).toList();
      final prevDt = DateTime(parts[0], parts[1] - 1, 1);
      final prevYm =
          '${prevDt.year}-${prevDt.month.toString().padLeft(2, '0')}';
      final results = await Future.wait([
        api.getDashboard(_month),
        api.hasAnyTransactions(),
        api.listTransactions(month: _month, type: 'expense'),
        api.listTransactions(month: prevYm, type: 'expense'),
      ]);
      if (!mounted) return;
      setState(() {
        _data = _DashData(
          data: results[0] as Dashboard,
          isFirstUser: !(results[1] as bool),
          currentTxs: results[2] as List<Tx>,
          prevTxs: results[3] as List<Tx>,
        );
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  void _shift(int delta) {
    SelectedMonth.value.value = shiftYm(_month, delta);
  }

  Future<void> _pickMonth() async {
    final picked = await showKoMonthPicker(
      context: context,
      initialYm: _month,
    );
    if (picked != null && picked != _month) {
      SelectedMonth.value.value = picked;
    }
  }

  Future<void> _refresh() async {
    Api.instance.invalidateAllCaches();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: Builder(
        builder: (context) {
          if (_data == null) {
            if (_error != null) {
              return ListView(children: [
                const SizedBox(height: 80),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(errorMessage(_error!),
                        style: TextStyle(color: AppColors.danger)),
                  ),
                ),
              ]);
            }
            return _dashboardSkeleton();
          }
          final d = _data!;
          return ListView(
            controller: _scrollCtrl,
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 28),
            children: [
              PageHeader(
                title: '${AuthService.displayName()}님 어서오세요',
                subtitle: '한눈에 보는 이번 달 흐름',
                actions: [
                  MonthSwitcher(
                    label: MediaQuery.sizeOf(context).width >= 700
                        ? ymLabel(_month)
                        : ymLabelShort(_month),
                    onPrev: () => _shift(-1),
                    onNext: () => _shift(1),
                    onTapLabel: _pickMonth,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _kpiGrid(d.data),
              ),
              const SizedBox(height: 18),
              _section(
                title: '카테고리별 지출',
                child: AppCard(
                  child: CategoryShare(
                    categories: d.data.categories,
                    month: _month,
                  ),
                ),
              ),
              _section(
                title: '지출 속도',
                child: d.currentTxs.isEmpty && d.prevTxs.isEmpty
                    ? _subList(const []) // 빈 상태 (첫 사용자 CTA 그대로)
                    : AppCard(
                        // 차트가 좌우 풀폭 가깝게 — Y축 라벨/차트 line 영역 확보.
                        padding:
                            const EdgeInsets.fromLTRB(10, 18, 14, 18),
                        child: SpendingPaceChart(
                          currentTxs: d.currentTxs,
                          prevTxs: d.prevTxs,
                          month: _month,
                        ),
                      ),
              ),
              _section(
                title: '최근 6개월',
                child: _trend(d.data),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _dashboardSkeleton() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 28),
      children: [
        const PageHeader(title: '...', subtitle: ''),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 700;
              if (wide) {
                return Row(
                  children: const [
                    Expanded(child: SkeletonCard(height: 110)),
                    SizedBox(width: 10),
                    Expanded(child: SkeletonCard(height: 110)),
                    SizedBox(width: 10),
                    Expanded(child: SkeletonCard(height: 110)),
                    SizedBox(width: 10),
                    Expanded(child: SkeletonCard(height: 110)),
                  ],
                );
              }
              return Column(
                children: const [
                  Row(children: [
                    Expanded(child: SkeletonCard(height: 110)),
                    SizedBox(width: 10),
                    Expanded(child: SkeletonCard(height: 110)),
                  ]),
                  SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: SkeletonCard(height: 110)),
                    SizedBox(width: 10),
                    Expanded(child: SkeletonCard(height: 110)),
                  ]),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: const [
                    SkeletonLine(width: 120, height: 22),
                    Spacer(),
                    Skeleton(width: 130, height: 32, radius: 8),
                  ],
                ),
                const SizedBox(height: 18),
                for (var i = 0; i < 4; i++) ...[
                  Row(
                    children: const [
                      Skeleton(
                          width: 10, height: 10, shape: BoxShape.circle),
                      SizedBox(width: 10),
                      Expanded(child: SkeletonLine(width: 80)),
                      SizedBox(width: 10),
                      SkeletonLine(width: 60, height: 13),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: const [
                      SizedBox(width: 20),
                      Expanded(child: Skeleton(height: 4, radius: 99)),
                      SizedBox(width: 8),
                      SkeletonLine(width: 28, height: 11),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _section({
    required String title,
    String? meta,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(title: title, meta: meta),
          child,
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _kpiGrid(Dashboard d) {
    // 지출 전월 대비
    final expDelta = d.thisMonthTotal - d.prevMonthTotal;
    final expDeltaText = d.prevMonthTotal == 0
        ? '전달 데이터 없음'
        : '전달 대비 ${expDelta >= 0 ? '+' : ''}${smartWon(expDelta)}원';
    final fixedText =
        '고정 ${smartWon(d.fixedTotal)}원 · 변동 ${smartWon(d.variableTotal)}원';

    // 수입 전월 대비
    final incDelta = d.incomeTotal - d.prevIncomeTotal;
    final incDeltaText = d.prevIncomeTotal == 0
        ? (d.incomeTotal == 0 ? '아직 수입 없음' : '전달 데이터 없음')
        : '전달 대비 ${incDelta >= 0 ? '+' : ''}${smartWon(incDelta)}원';

    // 순 이익 = 수입 - 지출
    final net = d.netSaving;
    final netLabel = net >= 0 ? '순 이익' : '적자';
    final netAccent = d.incomeTotal == 0 && d.thisMonthTotal == 0
        ? KpiAccent.neutral
        : (net >= 0 ? KpiAccent.good : KpiAccent.bad);
    final netDelta = d.incomeTotal == 0
        ? '수입을 등록하면 흑자가 보여요'
        : (net >= 0
            ? '수입 ${smartWon(d.incomeTotal)}원 − 지출 ${smartWon(d.thisMonthTotal)}원'
            : '지출이 수입보다 ${smartWon(net.abs())}원 많아요');

    final cards = [
      KpiCard(
        label: '이번 달 지출',
        value: smartWon(d.thisMonthTotal),
        accent: KpiAccent.expense,
        delta: expDeltaText,
        deltaExtra: fixedText,
      ),
      KpiCard(
        label: '이번 달 수입',
        value: smartWon(d.incomeTotal),
        accent: KpiAccent.income,
        delta: incDeltaText,
      ),
      KpiCard(
        label: netLabel,
        value: smartWon(net.abs()),
        accent: netAccent,
        delta: netDelta,
      ),
      KpiCard(
        label: '일평균 지출',
        value: smartWon(d.dailyAvg),
        accent: KpiAccent.neutral,
        delta: '고정지출 제외',
      ),
    ];

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 700;
      if (wide) {
        return Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: cards[i]),
            ],
          ],
        );
      }
      // 2x2
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 10),
              Expanded(child: cards[1]),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: cards[2]),
              const SizedBox(width: 10),
              Expanded(child: cards[3]),
            ],
          ),
        ],
      );
    });
  }

  Widget _subList(List<SubCategoryStat> rows) {
    if (rows.isEmpty) {
      // AI 명세서 import는 베타 — 일반 사용자엔 빈 상태 CTA를 *직접 입력*으로.
      final firstUser =
          (_data?.isFirstUser ?? false) && AuthService.aiBetaEnabled;
      return EmptyCard(
        icon: firstUser ? Icons.auto_awesome : Icons.receipt_long_outlined,
        title: firstUser
            ? '카드 이용내역으로 한 번에 시작해보세요'
            : '이번 달 거래가 없어요',
        body: firstUser
            ? 'AI가 카드 명세서를 정리해서 거래·카테고리까지 자동으로 등록해드려요.'
            : '거래를 추가하면 패턴을 짚어드릴게요.',
        actionLabel: firstUser ? '명세서로 한 번에 가져오기' : '거래 추가',
        onAction: firstUser
            ? () => context.go('/settings/import/ai')
            : () => context.go('/transactions'),
        secondaryActionLabel: firstUser ? '직접 입력' : null,
        onSecondaryAction:
            firstUser ? () => context.go('/transactions') : null,
      );
    }
    return AppCard(
      tight: true,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            MerchantItem(
              rank: i + 1,
              major: rows[i].major,
              title: rows[i].sub,
              subtitle: rows[i].major,
              amount: rows[i].total,
              count: rows[i].count,
              onTap: () {
                // '(태그 없음)'은 placeholder — DB에 그런 sub_category 없음.
                // sub_category IS NULL 필터로 보내야 거래내역에서 정확히 매칭.
                final isNullSub = rows[i].sub == '(태그 없음)';
                final base = '/transactions'
                    '?month=${Uri.encodeComponent(_month)}'
                    '&major=${Uri.encodeComponent(rows[i].major)}';
                final url = isNullSub
                    ? '$base&subnull=1'
                    : '$base&sub=${Uri.encodeComponent(rows[i].sub)}';
                context.go(url);
              },
            ),
        ],
      ),
    );
  }

  Widget _trend(Dashboard d) {
    if (d.trend.isEmpty) {
      return EmptyCard(
        icon: Icons.show_chart,
        title: '아직 거래가 없어요',
        body: '거래를 추가하면 6개월 추이가 보여요.',
        actionLabel: '거래 추가',
        onAction: () => context.go('/transactions'),
      );
    }
    return AppCard(
      child: MonthlyTrendBar(
        trend: d.trend,
        currentMonth: d.month,
      ),
    );
  }
}

class _DashData {
  final Dashboard data;
  final bool isFirstUser;
  // 지출 속도 차트용 — 이번 달/지난달 expense 거래 list.
  final List<Tx> currentTxs;
  final List<Tx> prevTxs;
  const _DashData({
    required this.data,
    required this.isFirstUser,
    required this.currentTxs,
    required this.prevTxs,
  });
}
