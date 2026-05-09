import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/models.dart';
import '../theme.dart';
import 'category_color.dart';
import 'format.dart';

/// 카테고리별 지출 비율 리스트 — 색깔 dot + 이름 + % + 금액 + 진행률 바.
/// 고정비 포함/제외 토글 가능. (도형 차트 없이 progress bar로만 표현)
/// 카테고리 row 탭 시 거래내역 화면으로 필터된 상태로 이동.
class CategoryShare extends StatefulWidget {
  const CategoryShare({
    super.key,
    required this.categories,
    required this.month,
  });
  final List<CategoryStats> categories;
  final String month;

  @override
  State<CategoryShare> createState() => _CategoryShareState();
}

class _CategoryShareState extends State<CategoryShare> {
  bool _includeFixed = true;

  int _amountOf(CategoryStats c) =>
      _includeFixed ? c.spent : c.variableSpent;

  void _goToFiltered(String major) {
    final params = <String, String>{
      'month': widget.month,
      'major': major,
      if (!_includeFixed) 'fixed': 'false',
    };
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    context.go('/transactions?$query');
  }

  @override
  Widget build(BuildContext context) {
    final spent = [...widget.categories]
      ..removeWhere((c) => _amountOf(c) <= 0)
      ..sort((a, b) => _amountOf(b).compareTo(_amountOf(a)));
    final total = spent.fold<int>(0, (s, c) => s + _amountOf(c));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: smartWon(total)),
                  TextSpan(
                    text: '원',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.text3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
                letterSpacing: -0.3,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const Spacer(),
            _IncludeFixedToggle(
              includeFixed: _includeFixed,
              onChanged: (v) => setState(() => _includeFixed = v),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (spent.isEmpty)
          SizedBox(
            height: 80,
            child: Center(
              child: Text('이번 달 지출이 없어요',
                  style: TextStyle(color: AppColors.text3, fontSize: 13)),
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < spent.length; i++)
                _ShareRow(
                  color: categoryColor(spent[i].major).fg,
                  label: spent[i].major,
                  amount: _amountOf(spent[i]),
                  pct: total == 0 ? 0 : _amountOf(spent[i]) / total,
                  onTap: () => _goToFiltered(spent[i].major),
                ),
            ],
          ),
      ],
    );
  }
}

class _IncludeFixedToggle extends StatelessWidget {
  const _IncludeFixedToggle({
    required this.includeFixed,
    required this.onChanged,
  });
  final bool includeFixed;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SegItem(
            label: '전체',
            selected: includeFixed,
            onTap: () => onChanged(true),
          ),
          _SegItem(
            label: '고정비 제외',
            selected: !includeFixed,
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }
}

class _SegItem extends StatelessWidget {
  const _SegItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryWeak : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm - 2),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.primaryStrong : AppColors.text3,
            )),
      ),
    );
  }
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({
    required this.color,
    required this.label,
    required this.amount,
    required this.pct,
    this.onTap,
  });
  final Color color;
  final String label;
  final int amount;
  final double pct;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: AppColors.text,
                        fontWeight: FontWeight.w600,
                      )),
                ),
                const SizedBox(width: 8),
                Text(smartWon(amount),
                    style: TextStyle(
                      fontSize: 13.5,
                      color: AppColors.text,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    )),
                Text('원',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.text3)),
                if (onTap != null) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right,
                      size: 16, color: AppColors.text4),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(width: 20),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: pct.clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: AppColors.line2,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${(pct * 100).round()}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.text3,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 최근 N개월 추이 — 지출(검정 강조) + 수입(파랑) 그룹 막대.
/// 수입이 모든 달에 0이면 단일 막대처럼 보여서 자연스러움.
class MonthlyTrendBar extends StatelessWidget {
  const MonthlyTrendBar({
    super.key,
    required this.trend,
    required this.currentMonth,
  });
  final List<TrendPoint> trend;
  final String currentMonth;

  static const _expenseColor = Color(0xFF111827); // 거의 검정 (지출 강조)
  static const _expenseDim = Color(0xFFD1D5DB); // 회색 (이번 달 외)
  static const _incomeColor = Color(0xFF1D4ED8); // 파랑
  static const _incomeDim = Color(0xFFBFDBFE);

  bool get _hasIncome => trend.any((t) => t.incomeTotal > 0);

  @override
  Widget build(BuildContext context) {
    if (trend.isEmpty) return const SizedBox.shrink();
    final maxV = trend.fold<int>(1, (m, t) {
      final v = t.expenseTotal > t.incomeTotal ? t.expenseTotal : t.incomeTotal;
      return v > m ? v : m;
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_hasIncome) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: [
                _LegendDot(color: _expenseColor, label: '지출'),
                const SizedBox(width: 14),
                _LegendDot(color: _incomeColor, label: '수입'),
              ],
            ),
          ),
        ],
        SizedBox(
          height: 180,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxV * 1.2,
              minY: 0,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => const Color(0xFF191F28),
                  tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  tooltipMargin: 6,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItem: (group, gx, rod, ry) {
                    final t = trend[group.x];
                    final mLabel = '${int.parse(t.ym.substring(5, 7))}월';
                    final lines = <TextSpan>[
                      TextSpan(
                        text: '지출 ${won(t.expenseTotal)}원',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ];
                    if (t.incomeTotal > 0) {
                      lines.add(TextSpan(
                        text: '\n수입 ${won(t.incomeTotal)}원',
                        style: const TextStyle(
                          color: Color(0xFFBFDBFE),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ));
                    }
                    return BarTooltipItem(
                      '$mLabel\n',
                      const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      children: lines,
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    reservedSize: 26,
                    getTitlesWidget: (value, meta) {
                      if ((value - value.roundToDouble()).abs() > 0.001) {
                        return const SizedBox();
                      }
                      final i = value.toInt();
                      if (i < 0 || i >= trend.length) return const SizedBox();
                      final t = trend[i];
                      final isCurrent = t.ym == currentMonth;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${int.parse(t.ym.substring(5, 7))}월',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: isCurrent
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isCurrent
                                ? AppColors.primary
                                : AppColors.text3,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < trend.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 4,
                    barRods: [
                      BarChartRodData(
                        toY: trend[i].expenseTotal.toDouble(),
                        width: _hasIncome ? 10 : 18,
                        color: trend[i].ym == currentMonth
                            ? _expenseColor
                            : _expenseDim,
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                      if (_hasIncome)
                        BarChartRodData(
                          toY: trend[i].incomeTotal.toDouble(),
                          width: 10,
                          color: trend[i].ym == currentMonth
                              ? _incomeColor
                              : _incomeDim,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
              fontSize: 11.5,
              color: AppColors.text3,
              fontWeight: FontWeight.w600,
            )),
      ],
    );
  }
}
