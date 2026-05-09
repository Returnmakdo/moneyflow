import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../api/models.dart';
import '../theme.dart';
import 'category_color.dart';
import 'format.dart';

/// AI 인사이트 마크다운에서 # 헤드라인과 ## 섹션을 분리한 결과.
class ParsedInsight {
  const ParsedInsight({this.headline, required this.sections});
  final String? headline;
  final List<InsightSection> sections;
}

class InsightSection {
  const InsightSection({
    required this.key,
    required this.title,
    required this.body,
  });

  /// 'summary' | 'pattern' | 'budget' | 'suggestion' | 'other'
  final String key;
  final String title;
  final String body;
}

ParsedInsight parseInsight(String markdown) {
  final lines = markdown.split('\n');
  String? headline;
  String? curTitle;
  final curBody = StringBuffer();
  final sections = <InsightSection>[];

  void flush() {
    if (curTitle != null) {
      sections.add(_makeSection(curTitle!, curBody.toString().trim()));
      curBody.clear();
      curTitle = null;
    }
  }

  for (final line in lines) {
    if (line.startsWith('# ')) {
      flush();
      headline = line.substring(2).trim();
    } else if (line.startsWith('## ')) {
      flush();
      curTitle = line.substring(3).trim();
    } else if (curTitle != null) {
      curBody.writeln(line);
    }
  }
  flush();

  return ParsedInsight(headline: headline, sections: sections);
}

/// 마크다운 파서가 한글/구두점 인접 ** 를 단어 경계로 인식 못 해서
/// **xxx** 가 그대로 노출되는 문제 보정. **xxx** 짝을 통째로 잡고,
/// 직전 char가 비공백이면 앞에, 직후 char가 비공백이면 뒤에 공백을 끼워
/// word boundary를 확보.
String _normalizeBold(String s) {
  // ** 양옆에 한글/구두점이 인접하면 공백 강제 삽입 (단어 경계 확보).
  s = s.replaceAllMapped(
    RegExp(r'(\S?)\*\*([^*\n]+?)\*\*(\S?)'),
    (m) {
      final before = m[1] ?? '';
      final inner = m[2]!;
      final after = m[3] ?? '';
      final pre = before.isEmpty ? '' : '$before ';
      final post = after.isEmpty ? '' : ' $after';
      return '$pre**$inner**$post';
    },
  );
  // 1) ~~text~~ 형식 취소선 마크업 제거.
  s = s.replaceAll(RegExp(r'[~～〜]{2,}'), '');
  // 2) 숫자~숫자 같은 단일 tilde 범위 표현 — GFM 파서가 두 개의 단일 ~를
  //    strikethrough 짝으로 매치해서 사이 텍스트를 취소선 처리하는 케이스가
  //    있어 일반 dash로 변환.
  s = s.replaceAllMapped(
    RegExp(r'(\d)\s*[~～〜]\s*(\d)'),
    (m) => '${m[1]}-${m[2]}',
  );
  return s;
}

InsightSection _makeSection(String title, String body) {
  String key;
  if (title.contains('요약')) {
    key = 'summary';
  } else if (title.contains('패턴')) {
    key = 'pattern';
  } else if (title.contains('예산')) {
    key = 'budget';
  } else if (title.contains('제안')) {
    key = 'suggestion';
  } else {
    key = 'other';
  }
  return InsightSection(key: key, title: title, body: body);
}

/// 페이지 시각화에 필요한 데이터 묶음. 화면이 fetch해서 카드에 주입.
class InsightVisualData {
  const InsightVisualData({
    required this.dashboard,
    required this.monthTxs,
    required this.budgets,
  });
  final Dashboard dashboard;
  final List<Tx> monthTxs;
  final List<Budget> budgets;
}

// ── 페이지 위젯들 ──────────────────────────────────────────

class SpendingSummaryPage extends StatelessWidget {
  const SpendingSummaryPage({
    super.key,
    required this.section,
    required this.data,
  });
  final InsightSection section;
  final InsightVisualData data;

  @override
  Widget build(BuildContext context) {
    final d = data.dashboard;
    final delta = d.thisMonthTotal - d.prevMonthTotal;
    final pct = d.prevMonthTotal > 0
        ? (delta / d.prevMonthTotal * 100).round()
        : null;
    final hasPrev = d.prevMonthTotal > 0;
    final deltaColor = !hasPrev
        ? AppColors.text3
        : (delta < 0 ? AppColors.success : AppColors.danger);
    final deltaText = !hasPrev
        ? '지난달 데이터 없음'
        : '전월 대비 ${delta >= 0 ? '+' : ''}${smartWon(delta)}원${pct != null ? ' (${pct >= 0 ? '+' : ''}$pct%)' : ''}';

    // 차트는 선택한 월과 그 직전 월만 표시 — trend에 미래 월(현재시간 기준 더
    // 최근 거래)이 섞이는 걸 방지.
    final prevYm = shiftYm(d.month, -1);
    final twoMonthTrend = [
      TrendPoint(
        ym: prevYm,
        expenseTotal: d.prevMonthTotal,
        incomeTotal: d.prevIncomeTotal,
      ),
      TrendPoint(
        ym: d.month,
        expenseTotal: d.thisMonthTotal,
        incomeTotal: d.incomeTotal,
      ),
    ];

    return _FadingScroll(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(title: section.title),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                smartWon(d.thisMonthTotal),
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                  fontFeatures: [FontFeature.tabularFigures()],
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '원',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            deltaText,
            style: TextStyle(
              fontSize: 12.5,
              color: deltaColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 90,
            child: _MiniTrendBar(
              trend: twoMonthTrend,
              currentMonth: d.month,
            ),
          ),
          const SizedBox(height: 14),
          _PageBody(body: section.body),
        ],
      ),
    );
  }
}

class SpendingPatternPage extends StatelessWidget {
  const SpendingPatternPage({
    super.key,
    required this.section,
    required this.data,
  });
  final InsightSection section;
  final InsightVisualData data;

  @override
  Widget build(BuildContext context) {
    final byMerchant = <String, _MerchantAgg>{};
    for (final t in data.monthTxs) {
      // 분석은 지출 기준 — 입금/이체/카드결제 거래는 제외.
      if (t.type != 'expense') continue;
      if (t.isFixed) continue;
      final m = t.merchant;
      if (m == null || m.isEmpty) continue;
      final r = byMerchant.putIfAbsent(m, () => _MerchantAgg(major: t.majorCategory));
      r.total += t.amount;
      r.count += 1;
    }
    final top = byMerchant.entries.toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));
    final maxTotal = top.isEmpty ? 1 : top.first.value.total;
    final topShown = top.take(5).toList();

    return _FadingScroll(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(title: section.title),
          const SizedBox(height: 12),
          if (topShown.isNotEmpty) ...[
            Text(
              '자주 간 가맹점',
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.text3,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            for (final e in topShown) ...[
              _MerchantBar(
                name: e.key,
                total: e.value.total,
                count: e.value.count,
                major: e.value.major,
                ratio: e.value.total / maxTotal,
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 6),
          ],
          _PageBody(body: section.body),
        ],
      ),
    );
  }
}

class SpendingBudgetPage extends StatelessWidget {
  const SpendingBudgetPage({
    super.key,
    required this.section,
    required this.data,
  });
  final InsightSection section;
  final InsightVisualData data;

  @override
  Widget build(BuildContext context) {
    final budgetMap = {for (final b in data.budgets) b.major: b.monthlyAmount};
    final entries = data.dashboard.categories
        .where((c) => (budgetMap[c.major] ?? 0) > 0)
        .map((c) {
      final budget = budgetMap[c.major] ?? 0;
      final spent = c.variableSpent;
      final pct = budget > 0 ? (spent / budget * 100).round() : 0;
      return _BudgetEntry(
        major: c.major,
        spent: spent,
        budget: budget,
        pct: pct,
      );
    }).toList()
      ..sort((a, b) => b.pct.compareTo(a.pct));
    final shown = entries.take(5).toList();

    return _FadingScroll(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(title: section.title),
          const SizedBox(height: 12),
          if (shown.isNotEmpty) ...[
            for (final e in shown) ...[
              _BudgetRow(entry: e),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
          ],
          _PageBody(body: section.body),
        ],
      ),
    );
  }
}

class SpendingSuggestionPage extends StatelessWidget {
  const SpendingSuggestionPage({
    super.key,
    required this.section,
    required this.data,
  });
  final InsightSection section;
  final InsightVisualData data;

  @override
  Widget build(BuildContext context) {
    // 이번 달 변동비 top 3 카테고리 — "다음 달 점검 후보" 라는 뉘앙스로
    // 박스 아래에 작은 칩으로 표시.
    final variableMajors = data.dashboard.categories
        .where((c) => c.variableSpent > 0)
        .toList()
      ..sort((a, b) => b.variableSpent.compareTo(a.variableSpent));
    final topMajors = variableMajors.take(3).toList();

    return _FadingScroll(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(title: section.title),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primaryWeak,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lightbulb_outline,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _PageBody(body: section.body)),
              ],
            ),
          ),
          if (topMajors.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              '함께 살펴볼 변동비 카테고리',
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.text3,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in topMajors) _CategoryChip(
                  major: c.major,
                  amount: c.variableSpent,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.major, required this.amount});
  final String major;
  final int amount;
  @override
  Widget build(BuildContext context) {
    final c = categoryColor(major);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            major,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: c.fg,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${smartWon(amount)}원',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: c.fg.withValues(alpha: 0.85),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 매핑 안 된 ## 섹션의 fallback — 헤더 + 본문만.
class SpendingOtherPage extends StatelessWidget {
  const SpendingOtherPage({super.key, required this.section});
  final InsightSection section;
  @override
  Widget build(BuildContext context) {
    return _FadingScroll(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(title: section.title),
          const SizedBox(height: 12),
          _PageBody(body: section.body),
        ],
      ),
    );
  }
}

/// 콘텐츠가 길 때 하단에 fade gradient를 깔아 "더 있어요" 신호를 주고,
/// 스크롤이 끝에 도달하면 fade가 부드럽게 사라짐.
class _FadingScroll extends StatefulWidget {
  const _FadingScroll({required this.padding, required this.child});
  final EdgeInsetsGeometry padding;
  final Widget child;
  @override
  State<_FadingScroll> createState() => _FadingScrollState();
}

class _FadingScrollState extends State<_FadingScroll> {
  final _ctrl = ScrollController();
  bool _showFade = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_update);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void dispose() {
    _ctrl.removeListener(_update);
    _ctrl.dispose();
    super.dispose();
  }

  void _update() {
    if (!_ctrl.hasClients || !mounted) return;
    final pos = _ctrl.position;
    final canScrollDown = pos.maxScrollExtent - pos.pixels > 1.0;
    if (canScrollDown != _showFade) {
      setState(() => _showFade = canScrollDown);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SingleChildScrollView(
          controller: _ctrl,
          padding: widget.padding,
          child: widget.child,
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 28,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _showFade ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      AppColors.surface,
                      AppColors.surface.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── 내부 위젯 ───────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
      ],
    );
  }
}

class _PageBody extends StatelessWidget {
  const _PageBody({required this.body});
  final String body;
  @override
  Widget build(BuildContext context) {
    if (body.isEmpty) return const SizedBox.shrink();
    return MarkdownBody(
      data: _normalizeBold(body),
      softLineBreak: true,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 13.5,
          height: 1.6,
          color: AppColors.text,
        ),
        strong: TextStyle(
          fontFamily: 'Pretendard',
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
        listBullet: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 13.5,
          height: 1.6,
          color: AppColors.text,
        ),
        blockSpacing: 6,
        listIndent: 16,
      ),
    );
  }
}

class _MiniTrendBar extends StatelessWidget {
  const _MiniTrendBar({required this.trend, required this.currentMonth});
  final List<TrendPoint> trend;
  final String currentMonth;

  @override
  Widget build(BuildContext context) {
    final maxV = trend.fold<int>(1, (m, t) => t.total > m ? t.total : m);
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxV * 1.2,
        minY: 0,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: false),
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
              reservedSize: 18,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= trend.length) return const SizedBox.shrink();
                final m = int.parse(trend[i].ym.substring(5, 7));
                final isCur = trend[i].ym == currentMonth;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '$m월',
                    style: TextStyle(
                      fontSize: 10,
                      color: isCur ? AppColors.primary : AppColors.text3,
                      fontWeight:
                          isCur ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < trend.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: trend[i].total.toDouble(),
                width: 14,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4)),
                color: trend[i].ym == currentMonth
                    ? AppColors.primary
                    : AppColors.line,
              ),
            ]),
        ],
      ),
    );
  }
}

class _MerchantAgg {
  _MerchantAgg({required this.major});
  final String major;
  int total = 0;
  int count = 0;
}

class _MerchantBar extends StatelessWidget {
  const _MerchantBar({
    required this.name,
    required this.total,
    required this.count,
    required this.major,
    required this.ratio,
  });
  final String name;
  final int total;
  final int count;
  final String major;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(major).fg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${smartWon(total)}원',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.text2,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '· $count건',
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.text3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 14),
          child: LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            return Stack(children: [
              Container(
                width: w,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line2,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Container(
                width: w * ratio.clamp(0.0, 1.0),
                height: 4,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ]);
          }),
        ),
      ],
    );
  }
}

class _BudgetEntry {
  const _BudgetEntry({
    required this.major,
    required this.spent,
    required this.budget,
    required this.pct,
  });
  final String major;
  final int spent;
  final int budget;
  final int pct;
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({required this.entry});
  final _BudgetEntry entry;
  @override
  Widget build(BuildContext context) {
    final over = entry.pct >= 100;
    final near = entry.pct >= 80 && entry.pct < 100;
    final color = over
        ? AppColors.danger
        : (near ? AppColors.warning : AppColors.primary);
    final ratio = (entry.pct / 100).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: categoryColor(entry.major).fg,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                entry.major,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
            Text(
              '${entry.pct}%',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 14),
          child: LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            return Stack(children: [
              Container(
                width: w,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.line2,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Container(
                width: w * ratio,
                height: 5,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ]);
          }),
        ),
        const SizedBox(height: 3),
        Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Text(
            '${smartWon(entry.spent)}원 / ${smartWon(entry.budget)}원',
            style: TextStyle(
              fontSize: 11.5,
              color: AppColors.text3,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
