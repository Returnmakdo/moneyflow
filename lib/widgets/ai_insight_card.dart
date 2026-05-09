import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../api/api.dart';
import '../screens/shell_screen.dart';
import '../theme.dart';
import 'common.dart';
import 'spending_insight_pages.dart';

/// 한 달 거래 데이터를 Edge Function 통해 Claude로 보내서 분석받는 카드.
/// 결과를 # 헤드라인 + ## 섹션으로 split해서 PageView로 표시.
/// 각 섹션은 매핑된 시각 위젯(Summary/Pattern/Budget/Suggestion)으로 렌더링.
class AiInsightCard extends StatefulWidget {
  final String month;
  final InsightVisualData? data;
  const AiInsightCard({super.key, required this.month, this.data});

  @override
  State<AiInsightCard> createState() => _AiInsightCardState();
}

class _AiInsightCardState extends State<AiInsightCard> {
  final Map<String, SpendingInsight> _cache = {};
  bool _loading = false;
  bool _checkingCache = true;
  Object? _error;
  final PageController _pageCtrl = PageController();
  int _currentPage = 0;

  SpendingInsight? get _current => _cache[widget.month];

  @override
  void initState() {
    super.initState();
    _loadCached();
    // 분석 탭 다시 누름 → DB 캐시 다시 fetch (옛 in-memory 결과 동기화).
    ShellTabSignals.insightsTab.addListener(_onTabPressed);
    // 거래 변경 → ai_insights 트리거 무효화 → fetch.
    Api.instance.txVersion.addListener(_onTabPressed);
  }

  @override
  void dispose() {
    ShellTabSignals.insightsTab.removeListener(_onTabPressed);
    Api.instance.txVersion.removeListener(_onTabPressed);
    _pageCtrl.dispose();
    super.dispose();
  }

  void _onTabPressed() {
    if (mounted) _loadCached();
  }

  Future<void> _loadCached() async {
    try {
      final cached =
          await Api.instance.getCachedSpendingInsight(widget.month);
      if (!mounted) return;
      setState(() {
        // DB 캐시 hit이면 그 결과로 갱신, miss면 옛 in-memory 결과도 비움
        // (DB가 무효화됐는데 클라이언트가 옛 결과 계속 보여주는 문제 차단).
        if (cached != null) {
          _cache[widget.month] = cached;
        } else {
          _cache.remove(widget.month);
        }
        _checkingCache = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _checkingCache = false);
    }
  }

  Future<void> _analyze({bool force = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result =
          await Api.instance.getSpendingInsight(widget.month, force: force);
      if (!mounted) return;
      setState(() {
        _cache[widget.month] = result;
        _loading = false;
        _currentPage = 0;
      });
      // 새 결과면 첫 페이지로 리셋.
      if (_pageCtrl.hasClients) {
        _pageCtrl.jumpToPage(0);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final has = _current != null;
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (has && !_loading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _resultHeader(_current!),
            ),
          if (_checkingCache)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_loading)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text(
                    '거래 내역을 보고 있어요…',
                    style: TextStyle(color: AppColors.text2, fontSize: 13),
                  ),
                ],
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    errorMessage(_error!),
                    style: TextStyle(
                      color: AppColors.danger,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonal(
                      onPressed: () => _analyze(),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      child: const Text('다시 시도'),
                    ),
                  ),
                ],
              ),
            )
          else if (has)
            _ResultBody(
              insight: _current!,
              data: widget.data,
              pageCtrl: _pageCtrl,
              currentPage: _currentPage,
              onPageChanged: (i) => setState(() => _currentPage = i),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '이번 달 거래를 보고 패턴, 특징, 다음 달 제안을 짚어드려요.',
                    style: TextStyle(
                      color: AppColors.text2,
                      fontSize: 13.5,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => _analyze(),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 44),
                      textStyle: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('이번 달 분석하기'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _resultHeader(SpendingInsight insight) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          if (insight.cached && insight.generatedAt != null)
            Expanded(
              child: Text(
                '이전 분석 · ${_relativeTime(insight.generatedAt!)} 생성',
                style:
                    TextStyle(fontSize: 12, color: AppColors.text3),
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            const Spacer(),
          TextButton(
            onPressed: () => _analyze(force: true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.text2,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('다시 분석'),
          ),
        ],
      ),
    );
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return '방금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${t.year}.${t.month.toString().padLeft(2, '0')}.${t.day.toString().padLeft(2, '0')}';
  }
}

class _ResultBody extends StatelessWidget {
  const _ResultBody({
    required this.insight,
    required this.data,
    required this.pageCtrl,
    required this.currentPage,
    required this.onPageChanged,
  });

  final SpendingInsight insight;
  final InsightVisualData? data;
  final PageController pageCtrl;
  final int currentPage;
  final ValueChanged<int> onPageChanged;


  @override
  Widget build(BuildContext context) {
    final parsed = parseInsight(insight.text);
    final sections = parsed.sections;

    if (sections.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: SpendingOtherPage(
          section: InsightSection(
            key: 'other',
            title: '분석',
            body: insight.text,
          ),
        ),
      );
    }

    final pages = <Widget>[
      for (final s in sections) _pageFor(s),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (parsed.headline != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: _Headline(text: parsed.headline!),
          ),
        ],
        SizedBox(
          height: 340,
          child: ScrollConfiguration(
            // 데스크톱(웹/Windows)에서 마우스 드래그로도 페이지 넘기게 허용.
            behavior: const MaterialScrollBehavior().copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.stylus,
                PointerDeviceKind.trackpad,
              },
            ),
            child: PageView(
              controller: pageCtrl,
              onPageChanged: onPageChanged,
              children: pages,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _NavButton(
              icon: Icons.chevron_left,
              enabled: currentPage > 0,
              onTap: () => pageCtrl.previousPage(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOut,
              ),
            ),
            _PageIndicator(count: pages.length, current: currentPage),
            _NavButton(
              icon: Icons.chevron_right,
              enabled: currentPage < pages.length - 1,
              onTap: () => pageCtrl.nextPage(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOut,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _pageFor(InsightSection section) {
    if (data == null) {
      return SpendingOtherPage(section: section);
    }
    switch (section.key) {
      case 'summary':
        return SpendingSummaryPage(section: section, data: data!);
      case 'pattern':
        return SpendingPatternPage(section: section, data: data!);
      case 'budget':
        return SpendingBudgetPage(section: section, data: data!);
      case 'suggestion':
        return SpendingSuggestionPage(section: section, data: data!);
      default:
        return SpendingOtherPage(section: section);
    }
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.primaryWeak,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 15.5,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryStrong,
          height: 1.4,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 32,
      child: IconButton(
        onPressed: enabled ? onTap : null,
        icon: Icon(icon, size: 22),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          foregroundColor: AppColors.text2,
          disabledForegroundColor: AppColors.line,
        ),
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.count, required this.current});
  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: i == current ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == current ? AppColors.primary : AppColors.line,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ],
      ],
    );
  }
}
