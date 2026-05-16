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
  // 디폴트는 *고정비 제외* — 일평균·태그 통계 등 다른 변동비 기준 지표와 일관.
  // 사용자가 토글로 '전체' 보기 가능.
  bool _includeFixed = false;

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
          // 디폴트(고정비 제외)가 왼쪽 — 사용자가 처음 보는 위치.
          _SegItem(
            label: '고정비 제외',
            selected: !includeFixed,
            onTap: () => onChanged(false),
          ),
          _SegItem(
            label: '전체',
            selected: includeFixed,
            onTap: () => onChanged(true),
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

/// 태그(=서브카테고리)별 지출 — CategoryShare와 동일 룩으로 통일.
/// 디폴트는 *고정비 제외*, 토글로 전체 보기.
class SubCategoryShare extends StatefulWidget {
  const SubCategoryShare({
    super.key,
    required this.variable,
    required this.all,
    required this.month,
  });
  final List<SubCategoryStat> variable;
  final List<SubCategoryStat> all;
  final String month;

  @override
  State<SubCategoryShare> createState() => _SubCategoryShareState();
}

class _SubCategoryShareState extends State<SubCategoryShare> {
  bool _includeFixed = false;

  List<SubCategoryStat> get _data =>
      _includeFixed ? widget.all : widget.variable;

  void _goToFiltered(SubCategoryStat s) {
    final params = <String, String>{
      'month': widget.month,
      'major': s.major,
      if (s.sub == '(태그 없음)') 'subnull': '1' else 'sub': s.sub,
      if (!_includeFixed) 'fixed': 'false',
    };
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    context.go('/transactions?$query');
  }

  @override
  Widget build(BuildContext context) {
    final rows = [..._data]
      ..removeWhere((s) => s.total <= 0)
      ..sort((a, b) => b.total.compareTo(a.total));
    final total = rows.fold<int>(0, (s, r) => s + r.total);
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
        if (rows.isEmpty)
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
              for (var i = 0; i < rows.length; i++)
                _ShareRow(
                  color: categoryColor(rows[i].major).fg,
                  label: '${rows[i].sub} · ${rows[i].major}',
                  amount: rows[i].total,
                  pct: total == 0 ? 0 : rows[i].total / total,
                  onTap: () => _goToFiltered(rows[i]),
                ),
            ],
          ),
      ],
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

/// 일별 누적 지출 라인 차트 — 이번 달 vs 지난달 비교 (지출 속도).
/// 변동비 디폴트 + 토글로 전체 전환. 미래 일자는 라인 끊김.
class SpendingPaceChart extends StatefulWidget {
  const SpendingPaceChart({
    super.key,
    required this.currentTxs,
    required this.prevTxs,
    required this.month,
  });
  final List<Tx> currentTxs;
  final List<Tx> prevTxs;
  final String month; // 'YYYY-MM'

  @override
  State<SpendingPaceChart> createState() => _SpendingPaceChartState();
}

class _SpendingPaceChartState extends State<SpendingPaceChart> {
  bool _includeFixed = false;

  List<int> _cumulative(List<Tx> txs, int days) {
    final daily = List<int>.filled(days, 0);
    for (final t in txs) {
      if (!_includeFixed && t.isFixed) continue;
      if (t.date.length < 10) continue;
      final day = int.tryParse(t.date.substring(8, 10)) ?? 0;
      if (day < 1 || day > days) continue;
      daily[day - 1] += t.amount;
    }
    final cum = <int>[];
    var sum = 0;
    for (final d in daily) {
      sum += d;
      cum.add(sum);
    }
    return cum;
  }

  @override
  Widget build(BuildContext context) {
    final parts = widget.month.split('-').map(int.parse).toList();
    final daysInMonth = DateTime(parts[0], parts[1] + 1, 0).day;
    final daysInPrev = DateTime(parts[0], parts[1], 0).day;
    final today = DateTime.now();
    final isCurrentMonth =
        today.year == parts[0] && today.month == parts[1];
    final isPastMonth = !isCurrentMonth &&
        (today.year > parts[0] ||
            (today.year == parts[0] && today.month > parts[1]));
    int todayCutoff;
    if (isCurrentMonth) {
      todayCutoff = today.day;
    } else if (isPastMonth) {
      todayCutoff = daysInMonth;
    } else {
      todayCutoff = 0;
    }

    final curCum = _cumulative(widget.currentTxs, daysInMonth);
    final prevCum = _cumulative(widget.prevTxs, daysInPrev);

    final curSpots = <FlSpot>[
      const FlSpot(0, 0),
      for (var i = 0; i < todayCutoff; i++)
        FlSpot((i + 1).toDouble(), curCum[i].toDouble()),
    ];
    final prevSpots = <FlSpot>[
      const FlSpot(0, 0),
      for (var i = 0; i < daysInPrev; i++)
        FlSpot((i + 1).toDouble(), prevCum[i].toDouble()),
    ];

    final currentTotalAtCutoff =
        todayCutoff > 0 ? curCum[todayCutoff - 1] : 0;
    final prevAtSameDay = (todayCutoff > 0 && todayCutoff <= prevCum.length)
        ? prevCum[todayCutoff - 1]
        : (prevCum.isNotEmpty ? prevCum.last : 0);
    final prevTotal = prevCum.isNotEmpty ? prevCum.last : 0;
    final diff = currentTotalAtCutoff - prevAtSameDay;
    final hasComparison = prevCum.isNotEmpty;

    final maxY = [
      ...curSpots.map((s) => s.y),
      ...prevSpots.map((s) => s.y),
    ].fold<double>(0, (m, y) => y > m ? y : m);
    // 50만원 step으로 ceil — Y축 라벨이 깔끔한 정수.
    final niceMax = maxY <= 0
        ? 500000.0
        : ((maxY * 1.1) / 500000).ceil() * 500000.0;
    final yInterval = niceMax / 5; // 5분할 → 4개 라벨
    // Y축 라벨 reservedSize — 자릿수에 따라 동적. 100만원 단위면 4자리(예: 1000),
    // 1억대면 5자리. 자릿수 × 약 8px + 우측 padding 8px.
    final maxLabelLen = (niceMax / 10000).round().toString().length;
    final yReservedSize = (maxLabelLen * 8.0 + 10).clamp(22.0, 56.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 상단: 토글만 우측에.
        Row(
          children: [
            const Spacer(),
            _IncludeFixedToggle(
              includeFixed: _includeFixed,
              onChanged: (v) => setState(() => _includeFixed = v),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // 차트 위: (만원) 좌측, 범례 우측
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '(만원)',
              style: TextStyle(
                fontSize: 10.5,
                color: AppColors.text4,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            _PaceLegend(color: AppColors.primaryStrong, label: '이번 달 지출'),
            const SizedBox(width: 12),
            _PaceLegend(color: AppColors.text3, label: '지난달 지출'),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: niceMax,
              minX: 0,
              maxX: daysInMonth.toDouble(),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: yInterval,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: AppColors.line2,
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: yReservedSize,
                    interval: yInterval,
                    getTitlesWidget: (v, _) {
                      if (v < 0) return const SizedBox();
                      final manwon = (v / 10000).round();
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          '$manwon',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: AppColors.text4,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: 1,
                    getTitlesWidget: (v, _) {
                      final day = v.toInt();
                      String? label;
                      if (day == 1) {
                        label = '1일';
                      } else if (day == daysInMonth) {
                        label = '$daysInMonth일';
                      } else if (todayCutoff > 0 && day == todayCutoff) {
                        label = '오늘';
                      } else {
                        return const SizedBox();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: day == todayCutoff
                                ? AppColors.text2
                                : AppColors.text4,
                            fontWeight: day == todayCutoff
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              extraLinesData: ExtraLinesData(
                verticalLines: [
                  if (todayCutoff > 0)
                    VerticalLine(
                      x: todayCutoff.toDouble(),
                      color: AppColors.line,
                      strokeWidth: 1,
                    ),
                ],
              ),
              lineTouchData: LineTouchData(
                handleBuiltInTouches: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) =>
                      AppColors.text.withValues(alpha: 0.92),
                  tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  getTooltipItems: (spots) {
                    return spots.map((s) {
                      final isCurrent =
                          s.barIndex == (prevSpots.length > 1 ? 1 : 0);
                      final label = isCurrent ? '이번 달' : '지난달';
                      return LineTooltipItem(
                        '${s.x.toInt()}일 · $label\n${smartWon(s.y.round())}원',
                        TextStyle(
                          color: AppColors.surface,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      );
                    }).toList();
                  },
                ),
              ),
              lineBarsData: [
                if (prevSpots.length > 1)
                  LineChartBarData(
                    spots: prevSpots,
                    isCurved: false,
                    color: AppColors.text3,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                  ),
                if (curSpots.length > 1)
                  LineChartBarData(
                    spots: curSpots,
                    isCurved: false,
                    color: AppColors.primaryStrong,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: true,
                      checkToShowDot: (spot, _) =>
                          spot.x.toInt() == todayCutoff,
                      getDotPainter: (spot, xPct, bar, idx) =>
                          FlDotCirclePainter(
                        radius: 5,
                        color: AppColors.primaryStrong,
                        strokeWidth: 2,
                        strokeColor: AppColors.surface,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        _PaceSummaryRow(
          label: '이번 달 지출',
          amount: currentTotalAtCutoff,
          color: AppColors.primaryStrong,
        ),
        const SizedBox(height: 8),
        _PaceSummaryRow(
          label: '지난달 총 지출',
          amount: prevTotal,
          color: AppColors.text3,
        ),
        if (hasComparison && todayCutoff > 0) ...[
          const SizedBox(height: 14),
          _PaceMessageBox(diff: diff),
        ],
      ],
    );
  }
}

class _PaceSummaryRow extends StatelessWidget {
  const _PaceSummaryRow({
    required this.label,
    required this.amount,
    required this.color,
  });
  final String label;
  final int amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            color: AppColors.text2,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Text(
          '${smartWon(amount)}원',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _PaceMessageBox extends StatelessWidget {
  const _PaceMessageBox({required this.diff});
  final int diff;

  @override
  Widget build(BuildContext context) {
    final more = diff > 0;
    final less = diff < 0;
    final iconColor = more ? AppColors.danger : AppColors.success;
    final iconData =
        more ? Icons.trending_up : (less ? Icons.trending_down : Icons.remove);
    final text = more
        ? '지난달 이때보다 ${smartWon(diff)}원 더 쓰는 중'
        : (less
            ? '지난달 이때보다 ${smartWon(diff.abs())}원 덜 쓰는 중'
            : '지난달 이때와 동일');
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(iconData, size: 16, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaceLegend extends StatelessWidget {
  const _PaceLegend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
              fontSize: 11.5,
              color: AppColors.text3,
              fontWeight: FontWeight.w500,
            )),
      ],
    );
  }
}
