import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/amount_field.dart';
import '../widgets/common.dart';
import '../widgets/format.dart';
import '../widgets/skeleton.dart';
import 'shell_screen.dart' show ShellTabSignals;

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  _BudgetsData? _data;
  Object? _error;
  final Map<String, TextEditingController> _ctrls = {};
  // 서버에서 마지막으로 받은 값. 사용자가 input을 안 건드렸으면(현재 ctrl 값과
  // 일치) reload 시 새 값으로 동기화하고, 건드렸으면 그대로 둠 (typing clobber 방지).
  final Map<String, int> _lastLoaded = {};
  bool _saving = false;
  final ScrollController _scrollCtrl = ScrollController();

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
    ShellTabSignals.budgetsTab.addListener(_onTabPressed);
    _reload();
  }

  @override
  void dispose() {
    _apiListenable.removeListener(_onApiChanged);
    ShellTabSignals.budgetsTab.removeListener(_onTabPressed);
    for (final c in _ctrls.values) {
      c.dispose();
    }
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
      final results = await Future.wait([
        api.listBudgets(),
        api.getDashboard(todayYm()),
      ]);
      final budgets = results[0] as List<Budget>;
      final dash = results[1] as Dashboard;
      final variable = {
        for (final c in dash.categories) c.major: c.variableSpent,
      };

      // 컨트롤러 동기화: 새 카테고리는 추가, 사라진 건 정리, 사용자가 안 건드린
      // 입력만 서버 값으로 갱신.
      final keep = <String>{};
      for (final b in budgets) {
        keep.add(b.major);
        final ctrl = _ctrls.putIfAbsent(b.major, () => TextEditingController());
        final last = _lastLoaded[b.major];
        final isNew = last == null;
        final untouched = last != null && AmountField.parse(ctrl) == last;
        if (isNew || untouched) {
          AmountField.setNumber(ctrl, b.monthlyAmount);
        }
        _lastLoaded[b.major] = b.monthlyAmount;
      }
      final toRemove =
          _ctrls.keys.where((k) => !keep.contains(k)).toList();
      for (final k in toRemove) {
        _ctrls.remove(k)?.dispose();
        _lastLoaded.remove(k);
      }
      if (!mounted) return;
      setState(() {
        _data = _BudgetsData(budgets: budgets, variable: variable);
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<void> _save() async {
    if (_saving || _data == null) return;
    setState(() => _saving = true);
    try {
      final updated = <Budget>[];
      for (final b in _data!.budgets) {
        final amt = AmountField.parse(_ctrls[b.major]!) ?? 0;
        updated.add(Budget(major: b.major, monthlyAmount: amt));
      }
      await Api.instance.saveBudgets(updated);
      if (!mounted) return;
      showToast(context, '예산을 저장했어요');
      await _reload();
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _budgetsSkeleton() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 90),
      children: [
        const PageHeader(title: '예산 설정', subtitle: ''),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              for (var i = 0; i < 5; i++) ...[
                AppCard(
                  padding:
                      const EdgeInsets.fromLTRB(18, 16, 18, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      SkeletonLine(width: 80, height: 14),
                      SizedBox(height: 8),
                      SkeletonLine(width: 120, height: 13),
                      SizedBox(height: 12),
                      Skeleton(height: 8, radius: 99),
                      SizedBox(height: 16),
                      Skeleton(height: 44, radius: 10),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_budgets',
        onPressed: (_saving || _data == null) ? null : _save,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.check),
        label: Text(_saving ? '저장 중...' : '저장'),
      ),
      body: SafeArea(
        child: Builder(
          builder: (context) {
            if (_data == null) {
              if (_error != null) {
                return Center(child: Text(errorMessage(_error!)));
              }
              return _budgetsSkeleton();
            }
            final d = _data!;
            // PageHeader는 0번, 그 이후는 카테고리 row.
            return ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 90),
              itemCount: 1 + d.budgets.length,
              itemBuilder: (ctx, i) {
                if (i == 0) {
                  return const PageHeader(
                    title: '예산 설정',
                    subtitle: '고정비는 예산에서 제외돼요.',
                  );
                }
                final b = d.budgets[i - 1];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: _BudgetEditCard(
                    major: b.major,
                    spent: d.variable[b.major] ?? 0,
                    budget: b.monthlyAmount,
                    controller: _ctrls[b.major]!,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _BudgetEditCard extends StatelessWidget {
  const _BudgetEditCard({
    required this.major,
    required this.spent,
    required this.budget,
    required this.controller,
  });
  final String major;
  final int spent;
  final int budget;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final pct = budget > 0 ? (spent / budget).clamp(0.0, 999.0) : 0.0;
    final pctClamped = pct > 1.0 ? 1.0 : pct;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(major,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text)),
              ),
              Text('${(pct * 100).round()}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: pct >= 1.0
                        ? AppColors.danger
                        : pct >= 0.8
                            ? AppColors.warning
                            : AppColors.text2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ],
          ),
          const SizedBox(height: 6),
          RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 13.5),
              children: [
                TextSpan(
                    text: '${won(spent)}원',
                    style: TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    )),
                TextSpan(
                    text: ' 사용',
                    style: TextStyle(color: AppColors.text2)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ProgressTrack(percent: pctClamped),
          const SizedBox(height: 14),
          AmountField(
              controller: controller, label: '이번 달 예산 (원)'),
        ],
      ),
    );
  }
}

class _BudgetsData {
  final List<Budget> budgets;
  final Map<String, int> variable;
  const _BudgetsData({
    required this.budgets,
    required this.variable,
  });
}
