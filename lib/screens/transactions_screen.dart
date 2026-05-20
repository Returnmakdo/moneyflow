import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../auth.dart';
import '../state/selected_month.dart';
import '../theme.dart';
import '../widgets/amount_field.dart';
import '../widgets/common.dart';
import '../widgets/format.dart';
import '../widgets/ko_date_picker.dart';
import '../widgets/skeleton.dart';
import '../widgets/tx_row.dart';
import 'shell_screen.dart' show ShellTabSignals;
import 'tx_modal.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({
    super.key,
    this.initialMonth,
    this.initialMajor,
    this.initialSub,
    this.initialSubIsNull = false,
    this.initialQ,
    this.initialFixed,
    this.initialDateFrom,
    this.initialDateTo,
    this.initialCardId,
    this.initialCardName,
  });

  final String? initialMonth;
  final String? initialMajor;
  final String? initialSub;
  final bool initialSubIsNull;
  final String? initialQ;
  final String? initialFixed; // '', 'true', 'false'
  final String? initialDateFrom; // YYYY-MM-DD
  final String? initialDateTo;
  final int? initialCardId;
  final String? initialCardName; // 배지 표시용 (필수 아님)

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

enum _TxSort {
  dateDesc('날짜 (최신순)'),
  dateAsc('날짜 (오래된순)'),
  amountDesc('금액 (높은순)'),
  amountAsc('금액 (낮은순)');

  const _TxSort(this.label);
  final String label;
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  String _major = '';
  String _sub = '';
  bool _subIsNull = false;
  String _q = '';
  String _fixed = ''; // '', 'true', 'false'
  String _type = ''; // '', 'expense', 'income'
  // 임의 기간/카드/계좌 필터 — 활성 시 SelectedMonth 무시(기간만).
  String? _dateFrom;
  String? _dateTo;
  int? _cardFilterId;
  String? _cardFilterName;
  int? _accountFilterId;
  String? _accountFilterName;

  String get _month => SelectedMonth.value.value;
  int? _minAmount;
  int? _maxAmount;
  _TxSort _sort = _TxSort.dateDesc;

  CategoriesData? _cats;
  Suggestions? _suggestions;
  Set<String> _recurringKeys = const {};
  Map<int, String> _accountsById = const {};
  Map<int, String> _cardsById = const {};
  List<Tx>? _txs;
  Object? _txError;
  bool _isFirstUser = false;
  final ScrollController _scrollCtrl = ScrollController();

  Timer? _qDebounce;
  late final TextEditingController _qCtrl;

  late final Listenable _apiListenable = Listenable.merge([
    Api.instance.txVersion,
    Api.instance.majorsVersion,
    Api.instance.categoriesVersion,
    Api.instance.fixedVersion,
    Api.instance.accountsVersion,
    Api.instance.cardsVersion,
  ]);
  bool _reloadScheduled = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialMonth != null && widget.initialMonth!.isNotEmpty) {
      SelectedMonth.value.value = widget.initialMonth!;
    }
    _major = widget.initialMajor ?? '';
    _sub = widget.initialSub ?? '';
    _subIsNull = widget.initialSubIsNull;
    _q = widget.initialQ ?? '';
    _fixed = widget.initialFixed ?? '';
    _dateFrom = widget.initialDateFrom;
    _dateTo = widget.initialDateTo;
    _cardFilterId = widget.initialCardId;
    _cardFilterName = widget.initialCardName;
    _qCtrl = TextEditingController(text: _q);
    _apiListenable.addListener(_onApiChanged);
    SelectedMonth.value.addListener(_onMonthChanged);
    ShellTabSignals.transactionsTab.addListener(_onTabPressed);
    _bootstrap();
  }

  void _onMonthChanged() {
    if (mounted) {
      setState(() {});
      _reload();
    }
  }

  void _onTabPressed() {
    // 같은 탭을 다시 누른 경우 — 스크롤만 상단으로. 필터는 보존.
    if (!mounted || !_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  bool get _hasFilter =>
      _major.isNotEmpty ||
      _sub.isNotEmpty ||
      _subIsNull ||
      _q.isNotEmpty ||
      _fixed.isNotEmpty ||
      _minAmount != null ||
      _maxAmount != null ||
      _dateFrom != null ||
      _dateTo != null ||
      _cardFilterId != null ||
      _accountFilterId != null ||
      _sort != _TxSort.dateDesc;

  bool get _hasRangeOrCard =>
      _dateFrom != null ||
      _dateTo != null ||
      _cardFilterId != null ||
      _accountFilterId != null;

  @override
  void didUpdateWidget(TransactionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 대시보드 등 다른 화면에서 쿼리 파라미터를 바꿔 들어오면
    // StatefulShellRoute가 같은 State를 유지하므로 여기서 동기화한다.
    final changed = widget.initialMonth != oldWidget.initialMonth ||
        widget.initialMajor != oldWidget.initialMajor ||
        widget.initialSub != oldWidget.initialSub ||
        widget.initialSubIsNull != oldWidget.initialSubIsNull ||
        widget.initialQ != oldWidget.initialQ ||
        widget.initialFixed != oldWidget.initialFixed ||
        widget.initialDateFrom != oldWidget.initialDateFrom ||
        widget.initialDateTo != oldWidget.initialDateTo ||
        widget.initialCardId != oldWidget.initialCardId;
    if (!changed) return;
    if (widget.initialMonth != null && widget.initialMonth!.isNotEmpty) {
      SelectedMonth.value.value = widget.initialMonth!;
    }
    setState(() {
      _major = widget.initialMajor ?? '';
      _sub = widget.initialSub ?? '';
      _subIsNull = widget.initialSubIsNull;
      _q = widget.initialQ ?? '';
      _fixed = widget.initialFixed ?? '';
      _dateFrom = widget.initialDateFrom;
      _dateTo = widget.initialDateTo;
      _cardFilterId = widget.initialCardId;
      _cardFilterName = widget.initialCardName;
      _qCtrl.text = _q;
    });
    _qDebounce?.cancel();
    _reload();
  }

  @override
  void dispose() {
    _apiListenable.removeListener(_onApiChanged);
    SelectedMonth.value.removeListener(_onMonthChanged);
    ShellTabSignals.transactionsTab.removeListener(_onTabPressed);
    _qDebounce?.cancel();
    _qCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onApiChanged() {
    if (_reloadScheduled || !mounted) return;
    _reloadScheduled = true;
    scheduleMicrotask(() {
      _reloadScheduled = false;
      if (mounted) _bootstrap();
    });
  }

  Future<void> _bootstrap() async {
    try {
      final cats = await Api.instance.listCategories();
      Suggestions? sug;
      try {
        sug = await Api.instance.getSuggestions();
      } catch (_) {
        sug = const Suggestions(merchants: [], cards: []);
      }
      Set<String> recurring = const {};
      try {
        final list = await Api.instance.listFixedExpenses();
        recurring = {
          for (final f in list)
            if (f.active) '${f.name}|${f.major}',
        };
      } catch (_) {/* 무시 */}
      bool firstUser = false;
      try {
        firstUser = !(await Api.instance.hasAnyTransactions());
      } catch (_) {/* 무시 — 노출 안 함 */}
      Map<int, String> accountsById = const {};
      Map<int, String> cardsById = const {};
      try {
        final accList = await Api.instance.listAccounts();
        accountsById = {for (final a in accList) a.id: a.name};
      } catch (_) {/* 무시 */}
      try {
        final cardList = await Api.instance.listCards();
        cardsById = {for (final c in cardList) c.id: c.name};
      } catch (_) {/* 무시 */}
      if (!mounted) return;
      setState(() {
        _cats = cats;
        _suggestions = sug;
        _recurringKeys = recurring;
        _isFirstUser = firstUser;
        _accountsById = accountsById;
        _cardsById = cardsById;
      });
      _reload();
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e), error: true);
    }
  }

  Future<void> _reload() async {
    _autoApplyDueFixed();
    try {
      // 임의 기간/카드 필터가 있으면 month는 무시.
      final hasRange = _dateFrom != null || _dateTo != null;
      final txs = await Api.instance.listTransactions(
        month: hasRange ? null : _month,
        major: _major.isEmpty ? null : _major,
        sub: _subIsNull ? null : (_sub.isEmpty ? null : _sub),
        subIsNull: _subIsNull,
        q: _q.isEmpty ? null : _q,
        fixed: _fixed == 'true'
            ? true
            : _fixed == 'false'
                ? false
                : null,
        type: _type.isEmpty ? null : _type,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        cardId: _cardFilterId,
        accountId: _accountFilterId,
      );
      if (!mounted) return;
      setState(() {
        _txs = txs;
        _txError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _txError = e);
    }
  }

  /// 그 월의 도래한 정기 거래를 자동으로 등록 (fire-and-forget, dedupe).
  /// 미래 월은 처리 X. 등록되면 invalidateTx로 화면이 자동 reload 됨.
  void _autoApplyDueFixed() {
    Api.instance.applyDueFixedTransactions(_month).catchError((_) => 0);
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

  void _onQChanged(String v) {
    _qDebounce?.cancel();
    _qDebounce = Timer(const Duration(milliseconds: 250), () {
      _q = v;
      _reload();
    });
  }

  /// FAB 누르면 [지출 추가][수입 추가][명세서 가져오기] 세 옵션 시트.
  Future<void> _showAddSheet() async {
    if (_cats == null) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => _AddSheet(),
    );
    if (!mounted || action == null) return;
    if (action == 'expense') {
      await _openModal(initialType: 'expense');
    } else if (action == 'income') {
      await _openModal(initialType: 'income');
    } else if (action == 'transfer') {
      await _openModal(initialType: 'transfer');
    } else if (action == 'import') {
      context.go('/settings/import/ai');
    }
  }

  Future<void> _openModal({Tx? tx, String initialType = 'expense'}) async {
    if (_cats == null) return;
    final result = await showTxModal(
      context,
      cats: _cats!,
      suggestions: _suggestions ?? const Suggestions(merchants: [], cards: []),
      tx: tx,
      initialType: initialType,
    );
    if (result == TxModalResult.changed && mounted) {
      _suggestions = null;
      // 자동완성 재로드 (백그라운드)
      Api.instance.getSuggestions().then((s) {
        if (mounted) setState(() => _suggestions = s);
      }).catchError((_) {});
      _reload();
    }
  }

  String _headerSub() {
    final parts = <String>[];
    if (_major.isNotEmpty) parts.add(_major);
    if (_sub.isNotEmpty) parts.add(_sub);
    if (_subIsNull) parts.add('태그 없음');
    if (_fixed == 'true') parts.add('고정비');
    if (_fixed == 'false') parts.add('변동비');
    final kindLabel = _type == 'income'
        ? '수입'
        : (_type == 'expense' ? '지출' : '거래');
    return parts.isEmpty
        ? '${ymLabel(_month)} $kindLabel'
        : '${ymLabel(_month)} $kindLabel · ${parts.join(' · ')}';
  }

  void _clearFilters() {
    setState(() {
      _major = '';
      _sub = '';
      _subIsNull = false;
      _q = '';
      _fixed = '';
      _minAmount = null;
      _maxAmount = null;
      _sort = _TxSort.dateDesc;
      _dateFrom = null;
      _dateTo = null;
      _cardFilterId = null;
      _cardFilterName = null;
      _accountFilterId = null;
      _accountFilterName = null;
      _qCtrl.text = '';
    });
    _reload();
  }

  void _clearRangeAndCard() {
    setState(() {
      _dateFrom = null;
      _dateTo = null;
      _cardFilterId = null;
      _cardFilterName = null;
      _accountFilterId = null;
      _accountFilterName = null;
    });
    _reload();
  }

  /// 서버에서 받은 거래에 client-side 추가 필터(금액 범위) + 정렬 적용.
  List<Tx> _applyExtraFilters(List<Tx> rows) {
    var filtered = rows;
    // 미래 일자 거래는 거래내역에 안 보임 — 도래일에 자동 노출.
    // 거래내역 = 발생 거래 일관성 + 자산 today filter와 통일된 동작.
    // 정기 거래를 미래 일자로 옮긴 케이스는 카탈로그 row 상태("X/Y 등록 예정")로 표시됨.
    if (_month == todayYm()) {
      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      filtered =
          filtered.where((t) => t.date.compareTo(today) <= 0).toList();
    }
    if (_minAmount != null) {
      filtered = filtered.where((t) => t.amount >= _minAmount!).toList();
    }
    if (_maxAmount != null) {
      filtered = filtered.where((t) => t.amount <= _maxAmount!).toList();
    }
    final sorted = [...filtered];
    switch (_sort) {
      case _TxSort.dateDesc:
        sorted.sort((a, b) {
          final c = b.date.compareTo(a.date);
          return c != 0 ? c : b.id.compareTo(a.id);
        });
        break;
      case _TxSort.dateAsc:
        sorted.sort((a, b) {
          final c = a.date.compareTo(b.date);
          return c != 0 ? c : a.id.compareTo(b.id);
        });
        break;
      case _TxSort.amountDesc:
        sorted.sort((a, b) => b.amount.compareTo(a.amount));
        break;
      case _TxSort.amountAsc:
        sorted.sort((a, b) => a.amount.compareTo(b.amount));
        break;
    }
    return sorted;
  }

  String _amountRangeLabel() {
    if (_minAmount != null && _maxAmount != null) {
      return '${won(_minAmount!)} ~ ${won(_maxAmount!)}원';
    }
    if (_minAmount != null) return '${won(_minAmount!)}원 이상';
    if (_maxAmount != null) return '${won(_maxAmount!)}원 이하';
    return '';
  }

  Future<void> _openFilterSheet() async {
    final result = await showModalBottomSheet<_FilterResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => _FilterSheet(
        initialMin: _minAmount,
        initialMax: _maxAmount,
        initialSort: _sort,
        initialCardId: _cardFilterId,
        initialAccountId: _accountFilterId,
        initialDateFrom: _dateFrom,
        initialDateTo: _dateTo,
        cards: [
          for (final e in _cardsById.entries) MapEntry(e.key, e.value),
        ],
        accounts: [
          for (final e in _accountsById.entries) MapEntry(e.key, e.value),
        ],
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _minAmount = result.minAmount;
      _maxAmount = result.maxAmount;
      _sort = result.sort;
      _cardFilterId = result.cardId;
      _cardFilterName = result.cardName;
      _accountFilterId = result.accountId;
      _accountFilterName = result.accountName;
      _dateFrom = result.dateFrom;
      _dateTo = result.dateTo;
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final cats = _cats;
    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_transactions',
        onPressed: _showAddSheet,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('거래 추가'),
      ),
      body: SafeArea(
        child: cats == null
            ? _txSkeleton()
            : RefreshIndicator(
                onRefresh: () async {
                  Api.instance.invalidateAllCaches();
                  await _reload();
                },
                child: _buildVirtualizedList(cats),
              ),
      ),
    );
  }

  Widget _txSkeleton() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 90),
      children: [
        const PageHeader(title: '거래내역', subtitle: ''),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(
            children: const [
              Skeleton(height: 44, radius: 10),
              SizedBox(height: 8),
              Row(children: [
                Expanded(child: Skeleton(height: 44, radius: 10)),
                SizedBox(width: 8),
                Skeleton(width: 130, height: 44, radius: 10),
                SizedBox(width: 6),
                Skeleton(width: 40, height: 40, radius: 10),
              ]),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _txListSkeleton(),
        ),
      ],
    );
  }

  Widget _txListSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              SkeletonLine(width: 90, height: 11),
              SizedBox(height: 8),
              SkeletonLine(width: 160, height: 24),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          tight: true,
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            children: [
              for (var i = 0; i < 5; i++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: const [
                      Skeleton(
                          width: 36, height: 36, shape: BoxShape.circle),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonLine(width: 110),
                            SizedBox(height: 6),
                            SkeletonLine(width: 60, height: 10),
                          ],
                        ),
                      ),
                      SkeletonLine(width: 70, height: 14),
                    ],
                  ),
                ),
                if (i < 4) Divider(color: AppColors.line2, height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _toolbar(CategoriesData cats) {
    // _type에 맞는 majors만 노출. type=''면 모든 majors.
    final filteredMajors = _type.isEmpty
        ? cats.majors
        : cats.majorsOf(_type);
    final majors = ['', ...filteredMajors];
    // 선택된 major의 태그 옵션. major 선택 X면 빈 리스트 → sub 드랍다운 숨김.
    final subsForMajor = _major.isEmpty
        ? const <String>[]
        : (cats.byMajor[_major]?.map((c) => c.sub).toList() ?? const []);
    // 현재 sub dropdown 값 (3가지 케이스: 전체 '', 태그 없음 sentinel, sub name)
    const nullSentinel = '__null__';
    final subValue = _subIsNull
        ? nullSentinel
        : (subsForMajor.contains(_sub) ? _sub : '');
    return Column(
      children: [
        TextField(
          controller: _qCtrl,
          onChanged: _onQChanged,
          decoration: InputDecoration(
            hintText: '가맹점/메모 검색',
            prefixIcon: Icon(Icons.search,
                color: AppColors.text3, size: 20),
          ),
        ),
        const SizedBox(height: 8),
        // 수입/지출 필터 chips
        Row(
          children: [
            _TypeChip(
              label: '전체',
              selected: _type.isEmpty,
              onTap: () {
                if (_type.isEmpty) return;
                setState(() {
                  _type = '';
                  // major가 다른 type 카테고리면 reset.
                });
                _reload();
              },
            ),
            const SizedBox(width: 6),
            _TypeChip(
              label: '지출',
              selected: _type == 'expense',
              onTap: () {
                if (_type == 'expense') return;
                setState(() {
                  _type = 'expense';
                  if (_major.isNotEmpty &&
                      cats.typeOf(_major) != 'expense') {
                    _major = '';
                    _sub = '';
                    _subIsNull = false;
                  }
                });
                _reload();
              },
            ),
            const SizedBox(width: 6),
            _TypeChip(
              label: '수입',
              selected: _type == 'income',
              accent: AppColors.incomeText,
              accentBg: AppColors.incomeBg,
              onTap: () {
                if (_type == 'income') return;
                setState(() {
                  _type = 'income';
                  if (_major.isNotEmpty &&
                      cats.typeOf(_major) != 'income') {
                    _major = '';
                    _sub = '';
                    _subIsNull = false;
                  }
                });
                _reload();
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: AppDropdown<String>(
                value: _major,
                items: [
                  for (final m in majors)
                    AppDropdownItem(
                      value: m,
                      label: m.isEmpty ? '전체 카테고리' : m,
                    ),
                ],
                onChanged: (v) {
                  setState(() {
                    _major = v;
                    _sub = '';
                    _subIsNull = false;
                  });
                  _reload();
                },
              ),
            ),
            const SizedBox(width: 8),
            _SegBtn(
              options: const [
                _SegOpt('', '전체'),
                _SegOpt('true', '고정'),
                _SegOpt('false', '변동'),
              ],
              value: _fixed,
              onChanged: (v) {
                setState(() => _fixed = v);
                _reload();
              },
            ),
            const SizedBox(width: 6),
            _FilterIconBtn(
              active: _minAmount != null ||
                  _maxAmount != null ||
                  _sort != _TxSort.dateDesc,
              onTap: _openFilterSheet,
            ),
          ],
        ),
        if (_major.isNotEmpty && subsForMajor.isNotEmpty) ...[
          const SizedBox(height: 8),
          AppDropdown<String>(
            value: subValue,
            items: [
              const AppDropdownItem(value: '', label: '전체 태그'),
              const AppDropdownItem(
                  value: nullSentinel, label: '(태그 없음)'),
              for (final s in subsForMajor)
                AppDropdownItem(value: s, label: s),
            ],
            onChanged: (v) {
              setState(() {
                if (v == nullSentinel) {
                  _subIsNull = true;
                  _sub = '';
                } else {
                  _subIsNull = false;
                  _sub = v;
                }
              });
              _reload();
            },
          ),
        ],
      ],
    );
  }

  /// ListView.builder 기반 가상화 — header/toolbar는 SliverToBoxAdapter처럼
  /// 한 줄씩 차지하고, row 영역은 일별 그룹 단위로 itemBuilder가 호출돼서
  /// 화면 밖 항목은 빌드 안 됨. "올해" 같은 큰 결과셋도 즉시 스크롤.
  Widget _buildVirtualizedList(CategoriesData cats) {
    // 1) 고정 헤더 영역 — 항상 위에 노출되는 것들.
    final fixed = <Widget Function(BuildContext)>[];
    fixed.add((_) => PageHeader(
          title: '거래내역',
          subtitle: _headerSub(),
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
        ));
    if (_hasRangeOrCard) {
      fixed.add((_) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: _RangeFilterBanner(
              cardName: _cardFilterName,
              accountName: _accountFilterName,
              dateFrom: _dateFrom,
              dateTo: _dateTo,
              onClear: _clearRangeAndCard,
            ),
          ));
    }
    fixed.add((_) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: _toolbar(cats),
        ));
    final showActiveChips = _sub.isNotEmpty ||
        _subIsNull ||
        _q.isNotEmpty ||
        _minAmount != null ||
        _maxAmount != null ||
        _sort != _TxSort.dateDesc;
    if (showActiveChips) {
      fixed.add((_) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (_sub.isNotEmpty)
                  _Chip(label: '세부: $_sub', onClear: _clearFilters),
                if (_subIsNull)
                  _Chip(label: '태그 없음', onClear: _clearFilters),
                if (_q.isNotEmpty)
                  _Chip(label: '검색: $_q', onClear: _clearFilters),
                if (_minAmount != null || _maxAmount != null)
                  _Chip(
                    label: _amountRangeLabel(),
                    onClear: () {
                      setState(() {
                        _minAmount = null;
                        _maxAmount = null;
                      });
                    },
                  ),
                if (_sort != _TxSort.dateDesc)
                  _Chip(
                    label: '정렬: ${_sort.label}',
                    onClear: () =>
                        setState(() => _sort = _TxSort.dateDesc),
                  ),
              ],
            ),
          ));
    }

    // 2) 거래 데이터 처리 — 에러/로딩/빈 상태/일별 그룹.
    if (_txs == null) {
      fixed.add((_) {
        if (_txError != null) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(errorMessage(_txError!),
                style: TextStyle(color: AppColors.danger)),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _txListSkeleton(),
        );
      });
      return ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 90),
        itemCount: fixed.length,
        itemBuilder: (ctx, i) => fixed[i](ctx),
      );
    }

    final rows = _applyExtraFilters(_txs!);
    final hasFilter = _hasFilter;
    // type='all'에서는 expense+income 단순 합산이 회계적으로 무의미해서
    // 지출/수입을 분리 표시. type 필터가 하나로 한정된 경우엔 단일 합계.
    final showSplit = _type.isEmpty;
    final expenseTotal = rows
        .where((r) => r.type == 'expense')
        .fold<int>(0, (s, r) => s + r.amount);
    final incomeTotal = rows
        .where((r) => r.type == 'income')
        .fold<int>(0, (s, r) => s + r.amount);

    // Summary
    fixed.add((_) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _Summary(
            label: hasFilter
                ? '필터된 합계 · ${ymLabel(_month)}'
                : '${ymLabel(_month)} ${_type == 'income' ? '수입' : (_type == 'expense' ? '지출' : '거래')}',
            total: showSplit ? null : (expenseTotal + incomeTotal),
            expenseTotal: showSplit ? expenseTotal : null,
            incomeTotal: showSplit ? incomeTotal : null,
            count: rows.length,
            filtered: hasFilter,
          ),
        ));
    fixed.add((_) => const SizedBox(height: 10));

    // 빈 상태 — AI 명세서 베타는 베타 사용자에만 노출.
    final showAiCta = _isFirstUser && AuthService.aiBetaEnabled;
    if (rows.isEmpty) {
      fixed.add((_) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: EmptyCard(
              icon: hasFilter
                  ? Icons.filter_alt_off_outlined
                  : (showAiCta
                      ? Icons.auto_awesome
                      : Icons.receipt_long_outlined),
              title: hasFilter
                  ? '조건에 맞는 거래가 없어요'
                  : (showAiCta
                      ? '카드 이용내역으로 한 번에 시작해보세요'
                      : '이번 달에 등록된 거래가 없어요'),
              body: hasFilter
                  ? null
                  : (showAiCta
                      ? 'AI가 카드 명세서를 정리해서 거래·카테고리까지 자동으로 등록해드려요.'
                      : '오른쪽 아래 + 추가 버튼으로 거래를 등록할 수 있어요.'),
              actionLabel:
                  (!hasFilter && showAiCta) ? '명세서로 한 번에 가져오기' : null,
              onAction: (!hasFilter && showAiCta)
                  ? () => context.go('/settings/import/ai')
                  : null,
              secondaryActionLabel:
                  (!hasFilter && showAiCta) ? '직접 입력' : null,
              onSecondaryAction:
                  (!hasFilter && showAiCta) ? _openModal : null,
            ),
          ));
      return ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 90),
        itemCount: fixed.length,
        itemBuilder: (ctx, i) => fixed[i](ctx),
      );
    }

    // 일별 그룹화 — 각 그룹이 ListView.builder의 한 항목.
    final byDate = <String, List<Tx>>{};
    for (final r in rows) {
      byDate.putIfAbsent(r.date, () => []).add(r);
    }
    final groups = byDate.entries.toList();

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 90),
      itemCount: fixed.length + groups.length,
      itemBuilder: (ctx, i) {
        if (i < fixed.length) return fixed[i](ctx);
        final entry = groups[i - fixed.length];
        final dayTxs = entry.value;
        final sum = dayTxs
            .where((t) => t.type == 'expense' || t.type == 'income')
            .fold<int>(0, (s, t) => s + t.amount);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: AppCard(
            tight: true,
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 4),
            child: Column(
              children: [
                TxDayHeader(date: entry.key, total: sum),
                for (final tx in dayTxs)
                  TxRow(
                    tx: tx,
                    isRecurring: _recurringKeys
                        .contains('${tx.merchant}|${tx.majorCategory}'),
                    accountsById: _accountsById,
                    cardsById: _cardsById,
                    onTap: () => _openModal(tx: tx),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.label,
    required this.count,
    required this.filtered,
    this.total,
    this.expenseTotal,
    this.incomeTotal,
  });
  final String label;
  // 단일 모드: total 표시, 분리 모드: expense/income 두 줄 표시.
  final int? total;
  final int? expenseTotal;
  final int? incomeTotal;
  final int count;
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final isSplit = expenseTotal != null && incomeTotal != null;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: filtered ? AppColors.primary : AppColors.text3,
                    )),
              ),
              Text('$count건',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.text3,
                  )),
            ],
          ),
          const SizedBox(height: 8),
          if (isSplit) ...[
            _SplitRow(
              label: '지출',
              amount: expenseTotal!,
              color: AppColors.danger,
            ),
            const SizedBox(height: 4),
            _SplitRow(
              label: '수입',
              amount: incomeTotal!,
              color: AppColors.success,
            ),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(won(total ?? 0),
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                      letterSpacing: -0.02,
                      fontFeatures: [FontFeature.tabularFigures()],
                    )),
                const SizedBox(width: 4),
                Text('원',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.text3,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
        ],
      ),
    );
  }
}

class _SplitRow extends StatelessWidget {
  const _SplitRow({
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
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            )),
        const Spacer(),
        Text(won(amount),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
              letterSpacing: -0.02,
              fontFeatures: [FontFeature.tabularFigures()],
            )),
        const SizedBox(width: 3),
        Text('원',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.text3,
              fontWeight: FontWeight.w600,
            )),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onClear});
  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onClear,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.text2,
                    fontWeight: FontWeight.w500)),
            const SizedBox(width: 6),
            Icon(Icons.close, size: 14, color: AppColors.text3),
          ],
        ),
      ),
    );
  }
}

class _SegOpt {
  final String value;
  final String label;
  const _SegOpt(this.value, this.label);
}

class _FilterIconBtn extends StatelessWidget {
  const _FilterIconBtn({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppColors.primaryWeak : AppColors.surface2,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: Icon(
            Icons.tune,
            size: 18,
            color: active ? AppColors.primary : AppColors.text2,
          ),
        ),
      ),
    );
  }
}

class _FilterResult {
  final int? minAmount;
  final int? maxAmount;
  final _TxSort sort;
  final int? cardId;
  final String? cardName;
  final int? accountId;
  final String? accountName;
  final String? dateFrom;
  final String? dateTo;
  const _FilterResult({
    required this.minAmount,
    required this.maxAmount,
    required this.sort,
    required this.cardId,
    required this.cardName,
    required this.accountId,
    required this.accountName,
    required this.dateFrom,
    required this.dateTo,
  });
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.initialMin,
    required this.initialMax,
    required this.initialSort,
    required this.initialCardId,
    required this.initialAccountId,
    required this.initialDateFrom,
    required this.initialDateTo,
    required this.cards,
    required this.accounts,
  });
  final int? initialMin;
  final int? initialMax;
  final _TxSort initialSort;
  final int? initialCardId;
  final int? initialAccountId;
  final String? initialDateFrom;
  final String? initialDateTo;
  /// (id, name) 리스트 — sort_order 적용된 채로 들어옴.
  final List<MapEntry<int, String>> cards;
  final List<MapEntry<int, String>> accounts;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final TextEditingController _minCtrl;
  late final TextEditingController _maxCtrl;
  late _TxSort _sort;
  // 0 = 전체 (드롭다운 sentinel), 그 외 = 실제 id.
  late int _cardId;
  late int _accountId;
  String? _dateFrom;
  String? _dateTo;

  @override
  void initState() {
    super.initState();
    _minCtrl = TextEditingController();
    _maxCtrl = TextEditingController();
    if (widget.initialMin != null) {
      AmountField.setNumber(_minCtrl, widget.initialMin);
    }
    if (widget.initialMax != null) {
      AmountField.setNumber(_maxCtrl, widget.initialMax);
    }
    _sort = widget.initialSort;
    _cardId = widget.initialCardId ?? 0;
    _accountId = widget.initialAccountId ?? 0;
    _dateFrom = widget.initialDateFrom;
    _dateTo = widget.initialDateTo;
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final initialStart = _dateFrom != null
        ? DateTime.tryParse(_dateFrom!) ?? DateTime(now.year, now.month, 1)
        : DateTime(now.year, now.month, 1);
    final initialEnd =
        _dateTo != null ? DateTime.tryParse(_dateTo!) ?? now : now;
    final picked = await showModalBottomSheet<DateTimeRange>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => _RangePickerSheet(
        initialStart: initialStart,
        initialEnd: initialEnd,
      ),
    );
    if (picked == null) return;
    setState(() {
      _dateFrom = _fmtIso(picked.start);
      _dateTo = _fmtIso(picked.end);
    });
  }

  String _shortMD(String iso) {
    final p = iso.split('-');
    if (p.length != 3) return iso;
    return '${int.parse(p[1])}.${int.parse(p[2])}';
  }

  String _fmtIso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 프리셋 정의 — (라벨, [from, to]) 페어. now를 기준으로 매번 계산.
  List<MapEntry<String, DateTimeRange>> _presets() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstOfMonth = DateTime(now.year, now.month, 1);
    final lastMonthFirst = DateTime(now.year, now.month - 1, 1);
    final lastMonthLast = DateTime(now.year, now.month, 0); // 전월 마지막 날
    final firstOfYear = DateTime(now.year, 1, 1);
    return [
      MapEntry('이번 달', DateTimeRange(start: firstOfMonth, end: today)),
      MapEntry('지난 달',
          DateTimeRange(start: lastMonthFirst, end: lastMonthLast)),
      MapEntry('최근 7일',
          DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today)),
      MapEntry('최근 30일',
          DateTimeRange(start: today.subtract(const Duration(days: 29)), end: today)),
      MapEntry('올해', DateTimeRange(start: firstOfYear, end: today)),
    ];
  }

  bool _isPresetActive(DateTimeRange r) {
    if (_dateFrom == null || _dateTo == null) return false;
    return _dateFrom == _fmtIso(r.start) && _dateTo == _fmtIso(r.end);
  }

  Widget _buildPresetChips() {
    final presets = _presets();
    final isCustom = _dateFrom != null &&
        _dateTo != null &&
        !presets.any((e) => _isPresetActive(e.value));
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in presets)
          _DateChip(
            label: p.key,
            selected: _isPresetActive(p.value),
            onTap: () => setState(() {
              _dateFrom = _fmtIso(p.value.start);
              _dateTo = _fmtIso(p.value.end);
            }),
          ),
        _DateChip(
          label: isCustom
              ? '${_shortMD(_dateFrom!)} ~ ${_shortMD(_dateTo!)}'
              : '직접 선택',
          icon: Icons.date_range,
          selected: isCustom,
          onTap: _pickRange,
        ),
        if (_dateFrom != null || _dateTo != null)
          _DateChip(
            label: '해제',
            icon: Icons.close,
            selected: false,
            onTap: () => setState(() {
              _dateFrom = null;
              _dateTo = null;
            }),
          ),
      ],
    );
  }

  void _apply() {
    final cardName = _cardId == 0
        ? null
        : widget.cards
            .firstWhere((e) => e.key == _cardId,
                orElse: () => const MapEntry(0, ''))
            .value;
    final accountName = _accountId == 0
        ? null
        : widget.accounts
            .firstWhere((e) => e.key == _accountId,
                orElse: () => const MapEntry(0, ''))
            .value;
    Navigator.of(context).pop(_FilterResult(
      minAmount: AmountField.parse(_minCtrl),
      maxAmount: AmountField.parse(_maxCtrl),
      sort: _sort,
      cardId: _cardId == 0 ? null : _cardId,
      cardName: (cardName != null && cardName.isEmpty) ? null : cardName,
      accountId: _accountId == 0 ? null : _accountId,
      accountName:
          (accountName != null && accountName.isEmpty) ? null : accountName,
      dateFrom: _dateFrom,
      dateTo: _dateTo,
    ));
  }

  void _reset() {
    setState(() {
      _minCtrl.clear();
      _maxCtrl.clear();
      _sort = _TxSort.dateDesc;
      _cardId = 0;
      _accountId = 0;
      _dateFrom = null;
      _dateTo = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.line,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Row(
                children: [
                  const Text('필터·정렬',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(
                    onPressed: _reset,
                    child: Text('초기화',
                        style: TextStyle(
                            color: AppColors.text3, fontSize: 13)),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('기간',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text2)),
                    const SizedBox(height: 8),
                    _buildPresetChips(),
                    if (_dateFrom != null && _dateTo != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.event,
                              size: 14, color: AppColors.text3),
                          const SizedBox(width: 6),
                          Text(
                            '${_shortMD(_dateFrom!)} ~ ${_shortMD(_dateTo!)}',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text2,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 18),
                    if (widget.cards.isNotEmpty) ...[
                      Text('신용카드',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text2)),
                      const SizedBox(height: 8),
                      AppDropdown<int>(
                        value: _cardId,
                        items: [
                          const AppDropdownItem(value: 0, label: '전체'),
                          for (final e in widget.cards)
                            AppDropdownItem(value: e.key, label: e.value),
                        ],
                        onChanged: (v) => setState(() => _cardId = v),
                      ),
                      const SizedBox(height: 18),
                    ],
                    if (widget.accounts.isNotEmpty) ...[
                      Text('계좌',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text2)),
                      const SizedBox(height: 8),
                      AppDropdown<int>(
                        value: _accountId,
                        items: [
                          const AppDropdownItem(value: 0, label: '전체'),
                          for (final e in widget.accounts)
                            AppDropdownItem(value: e.key, label: e.value),
                        ],
                        onChanged: (v) => setState(() => _accountId = v),
                      ),
                      const SizedBox(height: 18),
                    ],
                    Text('금액 범위',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text2)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: AmountField(
                            controller: _minCtrl,
                            label: '최소',
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Text('~',
                              style: TextStyle(
                                  fontSize: 16, color: AppColors.text3)),
                        ),
                        Expanded(
                          child: AmountField(
                            controller: _maxCtrl,
                            label: '최대',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text('정렬',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text2)),
                    const SizedBox(height: 8),
                    Column(
                      children: [
                        for (final s in _TxSort.values)
                          InkWell(
                            onTap: () => setState(() => _sort = s),
                            borderRadius:
                                BorderRadius.circular(AppRadius.sm),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 10),
                              child: Row(
                                children: [
                                  Icon(
                                    _sort == s
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    size: 18,
                                    color: _sort == s
                                        ? AppColors.primary
                                        : AppColors.text4,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(s.label,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: _sort == s
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                        color: _sort == s
                                            ? AppColors.text
                                            : AppColors.text2,
                                      )),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(
                  20, 12, 20, 12 + mq.padding.bottom * 0.4),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line2)),
              ),
              child: FilledButton(
                onPressed: _apply,
                child: const Text('적용'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegBtn extends StatelessWidget {
  const _SegBtn({
    required this.options,
    required this.value,
    required this.onChanged,
  });
  final List<_SegOpt> options;
  final String value;
  final ValueChanged<String> onChanged;

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
          for (final o in options)
            GestureDetector(
              onTap: () => onChanged(o.value),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: value == o.value
                      ? AppColors.primaryWeak
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.sm - 2),
                ),
                child: Text(o.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: value == o.value
                          ? AppColors.primaryStrong
                          : AppColors.text3,
                    )),
              ),
            ),
        ],
      ),
    );
  }
}

/// 자산 탭에서 진입했을 때 활성 기간/카드 필터 배지.
class _RangeFilterBanner extends StatelessWidget {
  const _RangeFilterBanner({
    required this.cardName,
    required this.accountName,
    required this.dateFrom,
    required this.dateTo,
    required this.onClear,
  });
  final String? cardName;
  final String? accountName;
  final String? dateFrom;
  final String? dateTo;
  final VoidCallback onClear;

  String _shortMD(String iso) {
    final p = iso.split('-');
    if (p.length != 3) return iso;
    return '${int.parse(p[1])}.${int.parse(p[2])}';
  }

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (cardName != null) parts.add(cardName!);
    if (accountName != null) parts.add(accountName!);
    if (dateFrom != null && dateTo != null) {
      parts.add('${_shortMD(dateFrom!)} ~ ${_shortMD(dateTo!)}');
    } else if (dateFrom != null) {
      parts.add('${_shortMD(dateFrom!)} 이후');
    } else if (dateTo != null) {
      parts.add('${_shortMD(dateTo!)} 이전');
    }
    return Material(
      color: AppColors.expenseBg,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.filter_alt_outlined,
                size: 16, color: AppColors.expenseText),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                parts.join(' · '),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.expenseText,
                ),
              ),
            ),
            InkWell(
              onTap: onClear,
              borderRadius: BorderRadius.circular(99),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close,
                    size: 16, color: AppColors.expenseText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 수입/지출 필터 칩.
class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent,
    this.accentBg,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? accent;
  final Color? accentBg;

  @override
  Widget build(BuildContext context) {
    final fg = selected
        ? (accent ?? AppColors.primaryStrong)
        : AppColors.text3;
    final bg = selected
        ? (accentBg ?? AppColors.primaryWeak)
        : AppColors.surface2;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

/// FAB 누르면 뜨는 진입 시트 — 지출/수입 큰 버튼 + 명세서 가져오기.
class _AddSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.line,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
              child: Row(
                children: [
                  Expanded(
                    child: _BigKindButton(
                      icon: Icons.shopping_cart_outlined,
                      label: '지출',
                      fg: AppColors.expenseText,
                      bg: AppColors.expenseBg,
                      borderColor: AppColors.expenseBorder,
                      onTap: () => Navigator.of(context).pop('expense'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _BigKindButton(
                      icon: Icons.savings_outlined,
                      label: '수입',
                      fg: AppColors.incomeText,
                      bg: AppColors.incomeBg,
                      borderColor: AppColors.incomeBorder,
                      onTap: () => Navigator.of(context).pop('income'),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
              child: Divider(height: 1, color: AppColors.line2),
            ),
            _option(
              context,
              icon: Icons.swap_horiz,
              title: '내 계좌로 송금',
              subtitle: '계좌 사이 이체 — 자산에서 빠지지 않아요',
              value: 'transfer',
            ),
            if (AuthService.aiBetaEnabled) ...[
              Divider(
                height: 1,
                color: AppColors.line2,
                indent: 20,
                endIndent: 20,
              ),
              _option(
                context,
                icon: Icons.auto_awesome,
                title: '명세서로 한 번에 가져오기',
                subtitle: 'AI가 카드 이용내역을 자동으로 정리',
                value: 'import',
                accent: true,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _option(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
    bool accent = false,
  }) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(value),
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent ? AppColors.primary : AppColors.primaryWeak,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 20,
                color: accent ? Colors.white : AppColors.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.text3,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: AppColors.text4),
          ],
        ),
      ),
    );
  }
}

class _BigKindButton extends StatelessWidget {
  const _BigKindButton({
    required this.icon,
    required this.label,
    required this.fg,
    required this.bg,
    required this.borderColor,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color fg;
  final Color bg;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: fg),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 필터 시트의 기간 프리셋 칩.
class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.primaryStrong : AppColors.text2;
    final bg = selected ? AppColors.primaryWeak : AppColors.surface2;
    final border = selected ? AppColors.primary : AppColors.line;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: border,
              width: selected ? 1.2 : 1,
            ),
            borderRadius: BorderRadius.circular(99),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 직접 선택용 커스텀 캘린더 — 토스/뱅샐 스타일.
/// 첫 탭 = 시작, 두 번째 탭 = 끝 (시작보다 이전이면 swap), 세 번째 탭 = 새 시작.
class _RangePickerSheet extends StatefulWidget {
  const _RangePickerSheet({
    required this.initialStart,
    required this.initialEnd,
  });
  final DateTime initialStart;
  final DateTime initialEnd;

  @override
  State<_RangePickerSheet> createState() => _RangePickerSheetState();
}

class _RangePickerSheetState extends State<_RangePickerSheet> {
  late DateTime _viewMonth;
  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    _start = _dateOnly(widget.initialStart);
    _end = _dateOnly(widget.initialEnd);
    _viewMonth = DateTime(widget.initialEnd.year, widget.initialEnd.month, 1);
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  void _onTapDay(DateTime d) {
    setState(() {
      if (_start == null || (_start != null && _end != null)) {
        _start = d;
        _end = null;
      } else {
        if (d.isBefore(_start!)) {
          _end = _start;
          _start = d;
        } else {
          _end = d;
        }
      }
    });
  }

  void _shiftMonth(int delta) {
    setState(() {
      _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + delta, 1);
    });
  }

  String _ymLabel() =>
      '${_viewMonth.year}.${_viewMonth.month.toString().padLeft(2, '0')}';

  bool _isInRange(DateTime d) {
    if (_start == null || _end == null) return false;
    return !d.isBefore(_start!) && !d.isAfter(_end!);
  }

  bool _isStart(DateTime d) =>
      _start != null && d.isAtSameMomentAs(_start!);
  bool _isEnd(DateTime d) => _end != null && d.isAtSameMomentAs(_end!);

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Row(
                  children: [
                    const Text('기간 선택',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(() {
                        _start = null;
                        _end = null;
                      }),
                      child: Text('초기화',
                          style: TextStyle(
                              color: AppColors.text3, fontSize: 13)),
                    ),
                  ],
                ),
              ),
              _buildMonthNav(),
              const SizedBox(height: 4),
              _buildWeekdays(),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _buildGrid(),
              ),
              const SizedBox(height: 12),
              _buildFooter(),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthNav() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _shiftMonth(-1),
            icon: Icon(Icons.chevron_left,
                color: AppColors.text2, size: 22),
            splashRadius: 20,
          ),
          Expanded(
            child: Center(
              child: Text(
                _ymLabel(),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          IconButton(
            onPressed: () => _shiftMonth(1),
            icon: Icon(Icons.chevron_right,
                color: AppColors.text2, size: 22),
            splashRadius: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildWeekdays() {
    const days = ['일', '월', '화', '수', '목', '금', '토'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (int i = 0; i < 7; i++)
            Expanded(
              child: Center(
                child: Text(
                  days[i],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: i == 0
                        ? AppColors.expenseText
                        : (i == 6
                            ? AppColors.incomeText
                            : AppColors.text3),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    // weekday: Mon=1..Sun=7; %7 → Sun=0,Mon=1...Sat=6 (일요일 시작 정렬)
    final firstDow =
        DateTime(_viewMonth.year, _viewMonth.month, 1).weekday % 7;
    final daysInMonth =
        DateTime(_viewMonth.year, _viewMonth.month + 1, 0).day;
    final cells = <Widget>[];
    for (int i = 0; i < firstDow; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(_viewMonth.year, _viewMonth.month, d);
      cells.add(_buildDayCell(date));
    }
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox.shrink());
    }

    final rows = <Widget>[];
    for (int i = 0; i < cells.length; i += 7) {
      rows.add(Row(
        children: [
          for (int j = 0; j < 7; j++)
            Expanded(child: AspectRatio(aspectRatio: 1, child: cells[i + j])),
        ],
      ));
    }
    return Column(children: rows);
  }

  Widget _buildDayCell(DateTime date) {
    final inRange = _isInRange(date);
    final isStart = _isStart(date);
    final isEnd = _isEnd(date);
    final isEdge = isStart || isEnd;
    final isSingleDay = isStart && isEnd;
    final today = _dateOnly(DateTime.now());
    final isToday = date.isAtSameMomentAs(today);
    final dow = date.weekday % 7;

    Color textColor;
    if (isEdge) {
      textColor = Colors.white;
    } else if (inRange) {
      textColor = AppColors.primaryStrong;
    } else if (dow == 0) {
      textColor = AppColors.expenseText;
    } else if (dow == 6) {
      textColor = AppColors.incomeText;
    } else {
      textColor = AppColors.text;
    }

    return GestureDetector(
      onTap: () => _onTapDay(date),
      behavior: HitTestBehavior.opaque,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (inRange && !isSingleDay)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (_, c) {
                  // 원 직경(36)에 정확히 맞춰 띠 높이 = 36, 위아래 균등 패딩.
                  final pad = ((c.maxHeight - 36) / 2).clamp(0.0, 40.0);
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: pad),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            color: isStart
                                ? Colors.transparent
                                : AppColors.primaryWeak,
                          ),
                        ),
                        Expanded(
                          child: Container(
                            color: isEnd
                                ? Colors.transparent
                                : AppColors.primaryWeak,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          if (isEdge)
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
          Text(
            '${date.day}',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: isEdge || isToday
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: textColor,
            ),
          ),
          if (isToday && !isEdge)
            Positioned(
              bottom: 6,
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _shortMD(DateTime d) => '${d.month}.${d.day}';

  Widget _buildFooter() {
    final canApply = _start != null && _end != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              canApply
                  ? '${_shortMD(_start!)} ~ ${_shortMD(_end!)}'
                  : (_start != null
                      ? '시작 ${_shortMD(_start!)} · 끝 선택'
                      : '날짜를 선택해주세요'),
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: canApply ? AppColors.text : AppColors.text3,
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: canApply
                ? () => Navigator.of(context).pop(
                      DateTimeRange(start: _start!, end: _end!),
                    )
                : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size(80, 40),
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
}
