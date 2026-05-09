import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../theme.dart';
import '../utils/nav_back.dart';
import '../widgets/amount_field.dart';
import '../widgets/category_color.dart';
import '../widgets/common.dart';
import '../widgets/format.dart';
import '../widgets/skeleton.dart';

class FixedExpensesScreen extends StatefulWidget {
  const FixedExpensesScreen({super.key});

  @override
  State<FixedExpensesScreen> createState() => _FixedExpensesScreenState();
}

class _FixedExpensesScreenState extends State<FixedExpensesScreen> {
  _FixedData? _data;
  Object? _error;
  // 'expense' | 'income' — 상단 탭으로 전환.
  String _type = 'expense';
  // 결제수단 표시용 — _FixedRow에 전달.
  Map<int, String> _accountsById = const {};
  Map<int, String> _cardsById = const {};
  final ScrollController _scrollCtrl = ScrollController();

  late final Listenable _apiListenable = Listenable.merge([
    Api.instance.fixedVersion,
    Api.instance.majorsVersion,
    Api.instance.categoriesVersion,
  ]);
  bool _reloadScheduled = false;

  @override
  void initState() {
    super.initState();
    _apiListenable.addListener(_onApiChanged);
    _reload();
  }

  @override
  void dispose() {
    _apiListenable.removeListener(_onApiChanged);
    _scrollCtrl.dispose();
    super.dispose();
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
      final now = DateTime.now();
      final ym =
          '${now.year}-${now.month.toString().padLeft(2, '0')}';
      // 자동 적용 먼저 — 도래분 등록 후 status 조회해야 정확한 'registered' 표시.
      // (이 화면 진입은 보통 카탈로그 신규 등록 직후가 많아 트리거 보장 필요)
      await api.applyDueFixedTransactions(ym).catchError((_) => 0);
      final results = await Future.wait([
        api.listFixedExpenses(type: _type),
        api.listCategories(),
        api.listAccounts(),
        api.listCards(),
        api.getFixedStatusForMonth(ym),
      ]);
      Suggestions sug;
      try {
        sug = await api.getSuggestions();
      } catch (_) {
        sug = const Suggestions(merchants: [], cards: []);
      }
      if (!mounted) return;
      final accs = results[2] as List<Account>;
      final cards = results[3] as List<CreditCard>;
      setState(() {
        _data = _FixedData(
          items: results[0] as List<FixedExpense>,
          cats: results[1] as CategoriesData,
          suggestions: sug,
          statusByFixed:
              results[4] as Map<int, FixedStatus>,
        );
        _accountsById = {for (final a in accs) a.id: a.name};
        _cardsById = {for (final c in cards) c.id: c.name};
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<void> _openModal(_FixedData d, [FixedExpense? item]) async {
    final r = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => _FixedModal(
        cats: d.cats,
        suggestions: d.suggestions,
        item: item,
        initialType: _type,
        status: item != null ? d.statusByFixed[item.id] : null,
      ),
    );
    if (r == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.text2),
          onPressed: () => goBackOr(context, '/settings'),
        ),
        title: Text(
          '정기 거래',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        centerTitle: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_fixed',
        onPressed: _data == null ? null : () => _openModal(_data!),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(_type == 'income' ? '정기수입 추가' : '정기지출 추가'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: _FlowHint(
                onTap: () => context.go('/settings/help'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: _typeTabs(),
            ),
            Expanded(child: _content()),
          ],
        ),
      ),
    );
  }

  Widget _typeTabs() {
    Widget tab(String value, String label) {
      final selected = _type == value;
      final isIncomeTab = value == 'income';
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_type == value) return;
            setState(() {
              _type = value;
              _data = null;
            });
            _reload();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected
                  ? (isIncomeTab
                      ? AppColors.incomeBg
                      : AppColors.surface)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? (isIncomeTab
                          ? AppColors.incomeText
                          : AppColors.text)
                      : AppColors.text3,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          tab('expense', '정기지출'),
          tab('income', '정기수입'),
        ],
      ),
    );
  }

  Widget _content() {
    return Builder(
      builder: (context) {
        if (_data == null) {
              if (_error != null) {
                return Center(child: Text(errorMessage(_error!)));
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 90),
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: AppCard(
                      tight: true,
                      padding:
                          const EdgeInsets.fromLTRB(18, 14, 18, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          SkeletonLine(width: 110, height: 11),
                          SizedBox(height: 6),
                          SkeletonLine(width: 140, height: 22),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        for (var i = 0; i < 5; i++) ...[
                          AppCard(
                            padding: const EdgeInsets.fromLTRB(
                                14, 12, 14, 12),
                            child: Row(
                              children: const [
                                Skeleton(
                                    width: 36,
                                    height: 36,
                                    shape: BoxShape.circle),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SkeletonLine(width: 90),
                                      SizedBox(height: 6),
                                      SkeletonLine(
                                          width: 130, height: 10),
                                    ],
                                  ),
                                ),
                                SkeletonLine(width: 70, height: 14),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            }
            final d = _data!;
            final active =
                d.items.where((it) => it.active).toList();
            final inactive =
                d.items.where((it) => !it.active).toList();
            final totalActive =
                active.fold<int>(0, (s, x) => s + x.amount);

            return ListView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 90),
              children: [
                if (d.items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: EmptyCard(
                      icon: Icons.repeat,
                      title: _type == 'income'
                          ? '등록된 정기수입이 없어요'
                          : '등록된 정기지출이 없어요',
                      body: _type == 'income'
                          ? '월급·이자처럼 매달 들어오는 수입을 등록해두면 거래내역에서 한 번에 추가할 수 있어요.'
                          : '월세·구독·통신비를 등록해두면 거래내역에서 한 번에 거래로 추가할 수 있어요.',
                    ),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: AppCard(
                      tight: true,
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('활성 ${active.length}개의 월 합계',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.text3,
                                fontWeight: FontWeight.w500,
                              )),
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(won(totalActive),
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.text,
                                    letterSpacing: -0.01,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  )),
                              const SizedBox(width: 4),
                              Text('원',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.text3,
                                    fontWeight: FontWeight.w600,
                                  )),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        for (final it in active)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _FixedRow(
                              item: it,
                              onTap: () => _openModal(d, it),
                              accountsById: _accountsById,
                              cardsById: _cardsById,
                              status: d.statusByFixed[it.id],
                            ),
                          ),
                        if (inactive.isNotEmpty) ...[
                          Padding(
                            padding: EdgeInsets.fromLTRB(4, 12, 4, 6),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text('비활성',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.text3,
                                  )),
                            ),
                          ),
                          for (final it in inactive)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Opacity(
                                opacity: 0.55,
                                child: _FixedRow(
                                  item: it,
                                  onTap: () => _openModal(d, it),
                                  accountsById: _accountsById,
                                  cardsById: _cardsById,
                                  status: d.statusByFixed[it.id],
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        );
  }
}

/// "2026-05-10" → "5/10" 짧은 라벨.
String _mdLabel(String iso) {
  final parts = iso.split('-');
  if (parts.length != 3) return iso;
  return '${int.parse(parts[1])}/${int.parse(parts[2])}';
}

/// 정기지출 화면 상단 흐름 안내 — 누르면 도움말로 점프.
class _FlowHint extends StatelessWidget {
  const _FlowHint({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 14, color: AppColors.text3),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '도래일이 되면 자동으로 거래로 추가되고 자산에 반영돼요',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.text3,
                  height: 1.4,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.help_outline, size: 14, color: AppColors.text3),
          ],
        ),
      ),
    );
  }
}

/// 신용카드 선택 시 day_of_month 가이드. 잔여할부 등록 시 결제일을 day_of_month로
/// 두면 다음 사이클로 넘어가서 청구에 안 잡히는 함정을 방지.
class _CardCycleHint extends StatelessWidget {
  const _CardCycleHint({required this.card});
  final CreditCard card;

  @override
  Widget build(BuildContext context) {
    final close = card.statementCloseDay;
    final pay = card.paymentDay;
    final msg = close != null
        ? '사용기간 마감일은 매월 $close일이에요. 입력일을 마감일 이전으로 두면 다음 결제 청구에 함께 잡혀요.'
        : '결제일은 매월 $pay일이에요. 잔여할부라면 결제일 며칠 전을 추천해요.';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.primaryWeak,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline,
              size: 16, color: AppColors.primaryStrong),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.text2,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 정기지출 결제수단 토글 — [내 계좌 / 신용카드].
class _PaymentKindToggle extends StatelessWidget {
  const _PaymentKindToggle({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget item(String v, String label, IconData icon) {
      final selected = value == v;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (value != v) onChanged(v);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected ? AppColors.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 15,
                    color: selected ? AppColors.text : AppColors.text3),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected ? AppColors.text : AppColors.text3,
                    )),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          item('account', '내 계좌', Icons.account_balance_wallet_outlined),
          item('card', '신용카드', Icons.credit_card),
        ],
      ),
    );
  }
}

class _FixedRow extends StatelessWidget {
  const _FixedRow({
    required this.item,
    required this.onTap,
    this.accountsById = const {},
    this.cardsById = const {},
    this.status,
  });
  final FixedExpense item;
  final VoidCallback onTap;
  final Map<int, String> accountsById;
  final Map<int, String> cardsById;
  final FixedStatus? status;

  @override
  Widget build(BuildContext context) {
    final isIncome = item.type == 'income';
    final meta = StringBuffer(item.major);
    if (item.sub?.isNotEmpty ?? false) meta.write(' · ${item.sub}');
    meta.write(' · 매월 ${item.dayOfMonth}일');
    // 결제수단 표시 — card_id면 카드 이름, account_id면 계좌 이름. 자유 텍스트는
    // 옛 데이터 fallback (account/card 매핑 안 된 경우만).
    if (item.cardId != null) {
      final cardName = cardsById[item.cardId!];
      if (cardName != null) meta.write(' · $cardName');
    } else if (item.accountId != null) {
      final accName = accountsById[item.accountId!];
      if (accName != null) meta.write(' · $accName');
    } else if (item.card?.isNotEmpty ?? false) {
      meta.write(' · ${item.card}');
    }
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          CategoryDot(item.major, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          )),
                    ),
                    if (isIncome) ...[
                      const SizedBox(width: 6),
                      Pill(
                        label: '수입',
                        color: AppColors.incomeText,
                        bg: AppColors.incomeBg,
                      ),
                    ],
                    if (!item.active) ...[
                      const SizedBox(width: 6),
                      Pill(
                          label: '비활성',
                          color: AppColors.text3,
                          bg: AppColors.surface2),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(meta.toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.text3,
                    )),
                if (status != null && item.active) ...[
                  const SizedBox(height: 4),
                  _StatusLine(status: status!),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text('${won(item.amount)}원',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
                fontFeatures: [FontFeature.tabularFigures()],
              )),
          Icon(Icons.chevron_right,
              color: AppColors.text4, size: 20),
        ],
      ),
    );
  }
}

/// 카탈로그 row의 자동 등록 상태 한 줄 — registered/skipped/dueLater/pending.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status});
  final FixedStatus status;

  @override
  Widget build(BuildContext context) {
    String label;
    Color color;
    IconData icon;
    switch (status.status) {
      case 'registered':
        label =
            '${_mdLabel(status.registeredDate ?? status.dueDate)} 등록됨';
        color = AppColors.success;
        icon = Icons.check_circle_outline;
        break;
      case 'skipped':
        label = '이번 달은 등록 안 함 (직접 삭제)';
        color = AppColors.text3;
        icon = Icons.do_not_disturb_on_outlined;
        break;
      case 'dueLater':
        // 매칭 거래(미래로 옮겨진) 있으면 그 날짜 우선. 없으면 카탈로그 도래일.
        label =
            '${_mdLabel(status.registeredDate ?? status.dueDate)} 등록 예정';
        color = AppColors.text3;
        icon = Icons.schedule;
        break;
      case 'pending':
      default:
        label = '곧 등록';
        color = AppColors.text3;
        icon = Icons.schedule;
        break;
    }
    return Row(
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: color,
                fontWeight: FontWeight.w600,
              )),
        ),
      ],
    );
  }
}

class _FixedModal extends StatefulWidget {
  const _FixedModal({
    required this.cats,
    required this.suggestions,
    this.item,
    this.initialType = 'expense',
    this.status,
  });
  final CategoriesData cats;
  final Suggestions suggestions;
  final FixedExpense? item;
  // 신규 등록 시 default type. 편집(item!=null)이면 item.type 우선.
  final String initialType;
  // 편집 시 그 항목의 이번 달 자동 등록 상태 (있으면 다이얼로그/토스트 분기에 사용).
  final FixedStatus? status;

  @override
  State<_FixedModal> createState() => _FixedModalState();
}

class _FixedModalState extends State<_FixedModal> {
  late final TextEditingController _name;
  late final TextEditingController _day;
  late final TextEditingController _amount;
  late final TextEditingController _card;
  late final TextEditingController _memo;
  late String _major;
  String? _sub;
  late bool _active;
  late String _type; // 'expense' | 'income'
  bool _saving = false;

  // 입금/출금 계좌 dropdown + 신용카드 dropdown용.
  List<Account> _accounts = const [];
  List<CreditCard> _cards = const [];
  int? _accountId;
  int? _cardId;
  // 'account' | 'card' — 지출 모드에서만 의미 (수입은 항상 account).
  String _paymentKind = 'account';

  bool get _editing => widget.item != null;
  bool get _isIncome => _type == 'income';

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    _type = it?.type ?? widget.initialType;
    _name = TextEditingController(text: it?.name ?? '');
    _day = TextEditingController(text: '${it?.dayOfMonth ?? 1}');
    _amount = TextEditingController();
    AmountField.setNumber(_amount, it?.amount);
    _card = TextEditingController(text: it?.card ?? '');
    _memo = TextEditingController(text: it?.memo ?? '');
    final majors = widget.cats.majorsOf(_type);
    _major = it?.major ?? (majors.isNotEmpty ? majors.first : '');
    _sub = it?.sub;
    _active = it?.active ?? true;
    _accountId = it?.accountId;
    _cardId = it?.cardId;
    _paymentKind = (it?.cardId != null) ? 'card' : 'account';
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    try {
      final results = await Future.wait([
        Api.instance.listAccounts(),
        Api.instance.listCards(),
      ]);
      if (!mounted) return;
      final accs = results[0] as List<Account>;
      final cards = results[1] as List<CreditCard>;
      setState(() {
        _accounts = accs;
        _cards = cards;
        _accountId ??= accs.isNotEmpty ? accs.first.id : null;
        _cardId ??= cards.isNotEmpty ? cards.first.id : null;
      });
    } catch (_) {/* 무시 */}
  }

  @override
  void dispose() {
    _name.dispose();
    _day.dispose();
    _amount.dispose();
    _card.dispose();
    _memo.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _major.isEmpty) {
      showToast(context, '이름과 카테고리는 필수예요', error: true);
      return;
    }
    final isCardPayment = !_isIncome && _paymentKind == 'card';
    if (_isIncome && _accountId == null) {
      showToast(context, '입금 계좌를 선택해주세요', error: true);
      return;
    }
    if (!_isIncome && _paymentKind == 'account' && _accountId == null) {
      showToast(context, '출금 계좌를 선택해주세요', error: true);
      return;
    }
    if (isCardPayment && _cardId == null) {
      showToast(context, '신용카드를 선택해주세요', error: true);
      return;
    }
    final amount = AmountField.parse(_amount) ?? 0;
    final day = int.tryParse(_day.text.trim()) ?? 1;

    // 편집 + 이번 달 거래 매칭 있으면 — 같이 수정 여부 다이얼로그.
    // (registered든 dueLater(미래로 옮겨진 거래)든 transactionId 있으면 sync 의미 있음)
    String? syncChoice; // 'sync' | 'noSync' | null(취소)
    final stat = widget.status;
    if (_editing && stat?.transactionId != null) {
      syncChoice = await _askSyncDialog(stat!, day);
      if (syncChoice == null) return; // 사용자 취소
    }

    setState(() => _saving = true);
    try {
      // payment 분기에 맞춰 account_id / card_id 명확히 (한쪽은 null로 비움).
      final saveAccountId = isCardPayment ? null : _accountId;
      final saveCardId = isCardPayment ? _cardId : null;
      if (_editing) {
        await Api.instance.updateFixedExpense(
          widget.item!.id,
          name: name,
          major: _major,
          sub: _sub ?? '',
          amount: amount,
          card: _card.text,
          dayOfMonth: day,
          active: _active,
          memo: _memo.text,
          type: _type,
          accountId: saveAccountId,
          cardId: saveCardId,
          clearAccountId: saveAccountId == null,
          clearCardId: saveCardId == null,
        );
        if (syncChoice == 'sync' && stat?.transactionId != null) {
          // 이번 달 거래도 같이 수정 — 날짜 변경된 경우 거래 date도 새 day로
          // 옮겨서 옛 날짜에 거래 잔존하는 일 없게.
          final ym = stat!.dueDate.substring(0, 7);
          final newDate =
              '$ym-${day.toString().padLeft(2, '0')}';
          await Api.instance.updateTransaction(
            stat.transactionId!,
            date: newDate,
            merchant: name,
            majorCategory: _major,
            subCategory: _sub ?? '',
            amount: amount,
            type: _type,
            accountId: saveAccountId,
            cardId: saveCardId,
          );
        }
      } else {
        await Api.instance.createFixedExpense(
          name: name,
          major: _major,
          sub: (_sub?.isEmpty ?? true) ? null : _sub,
          amount: amount,
          card: _card.text.isEmpty ? null : _card.text,
          accountId: saveAccountId,
          cardId: saveCardId,
          dayOfMonth: day,
          active: _active,
          memo: _memo.text.isEmpty ? null : _memo.text,
          type: _type,
        );
      }
      if (!mounted) return;
      showToast(context, _saveToastMessage(syncChoice, day));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showToast(context, errorMessage(e), error: true);
      setState(() => _saving = false);
    }
  }

  /// 편집 시 이번 달 거래도 같이 수정할지 묻는 다이얼로그.
  /// 헤더 우상단 X로 취소 + 본문 아래 가로 두 버튼 (secondary | primary).
  /// newDay가 미래 일자면 "거래내역에서 도래일까지 안 보임" 사전 안내 추가.
  Future<String?> _askSyncDialog(FixedStatus stat, int newDay) async {
    final mdLabel = _mdLabel(stat.registeredDate ?? stat.dueDate);
    // 새 일자가 today 이후인지 — 그러면 거래가 미래로 옮겨져서 도래일까지 거래내역 미노출.
    final ym = stat.dueDate.substring(0, 7);
    final newDateStr = '$ym-${newDay.toString().padLeft(2, '0')}';
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final movesToFuture = newDateStr.compareTo(todayStr) > 0;
    return showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        backgroundColor: AppColors.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '이번 달 거래도 같이 바꿀까요?',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(null),
                    icon: Icon(Icons.close, color: AppColors.text3),
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '$mdLabel에 이미 등록된 거래가 있어요. 정기 거래만 바꾸면 다음 달부터 새 정보로 등록되고, 이번 달 거래는 그대로 유지돼요.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.text2,
                    height: 1.55,
                  ),
                ),
              ),
              if (movesToFuture) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    padding:
                        const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            size: 14, color: AppColors.text3),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '"이번 달도 같이" 누르면 거래 날짜가 ${now.month}/$newDay로 옮겨져요. 도래일까지 거래내역에 안 보이고 자산에서도 빠지지 않아요.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.text3,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            Navigator.of(ctx).pop('noSync'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          side: BorderSide(color: AppColors.line),
                          foregroundColor: AppColors.text,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: const Text(
                          '다음 달부터만',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(ctx).pop('sync'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: const Text(
                          '이번 달도 같이',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 저장 후 사용자에게 보여줄 토스트 메시지 — 상태에 따라 명확한 안내.
  String _saveToastMessage(String? syncChoice, int newDay) {
    if (!_editing) return '등록했어요';
    // 비활성으로 바꿨으면 자동 등록 안 됨 — 자동 등록 안내문 잘못 노출 방지.
    if (!_active) return '비활성으로 변경됐어요. 자동 등록 안 돼요';
    final stat = widget.status;
    final newDayLabel = '$newDay일';
    switch (stat?.status) {
      case 'registered':
        return syncChoice == 'sync'
            ? '이번 달 거래도 함께 수정됐어요'
            : '다음 달 $newDayLabel부터 새 정보로 등록돼요';
      case 'dueLater':
      case 'pending':
        return '이번 달 $newDayLabel부터 새 정보로 자동 등록돼요';
      case 'skipped':
        return '다음 달 $newDayLabel부터 새 정보로 등록돼요';
      default:
        return '수정했어요';
    }
  }

  Future<void> _delete() async {
    final it = widget.item;
    if (it == null) return;
    final ok = await confirmDialog(
      context,
      title: _isIncome ? '정기수입 삭제' : '정기지출 삭제',
      message: '"${it.name}"을 삭제할까요? (이미 등록된 거래내역은 영향 없음)',
      confirmText: '삭제',
      danger: true,
    );
    if (!ok) return;
    try {
      await Api.instance.deleteFixedExpense(it.id);
      if (!mounted) return;
      showToast(context, '삭제했어요');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showToast(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final subs = widget.cats.byMajor[_major] ?? const [];
    final subValues = ['', ...subs.map((s) => s.sub)];
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.92),
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
                  Text(
                    _editing
                        ? (_isIncome ? '정기수입 수정' : '정기지출 수정')
                        : (_isIncome ? '정기수입 등록' : '정기지출 등록'),
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: AppColors.text3),
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
                    TextField(
                      controller: _name,
                      decoration: InputDecoration(
                          labelText: '이름',
                          hintText: _isIncome ? '예: 월급, 이자' : '예: 월세, 넷플릭스'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _day,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: '매월 며칠'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AmountField(controller: _amount),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: AppDropdown<String>(
                            label: '카테고리',
                            value: widget.cats.majorsOf(_type).contains(_major)
                                ? _major
                                : null,
                            items: [
                              for (final m in widget.cats.majorsOf(_type))
                                AppDropdownItem(value: m, label: m),
                            ],
                            onChanged: (v) => setState(() {
                              _major = v;
                              _sub = null;
                            }),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AppDropdown<String>(
                            label: '태그',
                            value: _sub ?? '',
                            items: [
                              for (final v in subValues)
                                AppDropdownItem(
                                  value: v,
                                  label: v.isEmpty ? '(없음)' : v,
                                ),
                            ],
                            onChanged: (v) =>
                                setState(() => _sub = v.isEmpty ? null : v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_isIncome)
                      AppDropdown<int>(
                        label: '입금 계좌',
                        value: _accounts.any((a) => a.id == _accountId)
                            ? _accountId
                            : null,
                        items: [
                          for (final a in _accounts)
                            AppDropdownItem(value: a.id, label: a.name),
                        ],
                        onChanged: (v) => setState(() => _accountId = v),
                      )
                    else ...[
                      _PaymentKindToggle(
                        value: _paymentKind,
                        onChanged: (v) =>
                            setState(() => _paymentKind = v),
                      ),
                      const SizedBox(height: 10),
                      if (_paymentKind == 'account')
                        AppDropdown<int>(
                          label: '출금 계좌',
                          value: _accounts.any((a) => a.id == _accountId)
                              ? _accountId
                              : null,
                          items: [
                            for (final a in _accounts)
                              AppDropdownItem(value: a.id, label: a.name),
                          ],
                          onChanged: (v) => setState(() => _accountId = v),
                        )
                      else if (_cards.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surface2,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            '신용카드 · 자산 탭에서 카드를 먼저 추가해주세요',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.text3,
                            ),
                          ),
                        )
                      else ...[
                        AppDropdown<int>(
                          label: '신용카드',
                          value: _cards.any((c) => c.id == _cardId)
                              ? _cardId
                              : null,
                          items: [
                            for (final c in _cards)
                              AppDropdownItem(value: c.id, label: c.name),
                          ],
                          onChanged: (v) => setState(() => _cardId = v),
                        ),
                        if (_cardId != null) ...[
                          const SizedBox(height: 8),
                          _CardCycleHint(
                            card: _cards.firstWhere(
                              (c) => c.id == _cardId,
                              orElse: () => _cards.first,
                            ),
                          ),
                        ],
                      ],
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _memo,
                      decoration: const InputDecoration(
                          labelText: '메모', hintText: '선택'),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => setState(() => _active = !_active),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 8),
                        child: Row(
                          children: [
                            Switch(
                              value: _active,
                              onChanged: (v) =>
                                  setState(() => _active = v),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text('활성',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.text)),
                                      const SizedBox(width: 4),
                                      Tooltip(
                                        message: _isIncome
                                            ? '활성 정기수입만 도래일에 자동으로 거래로 추가돼요.'
                                            : '활성 정기지출만 도래일에 자동으로 거래로 추가돼요.',
                                        triggerMode:
                                            TooltipTriggerMode.tap,
                                        showDuration:
                                            const Duration(seconds: 4),
                                        preferBelow: true,
                                        textStyle: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12),
                                        decoration: BoxDecoration(
                                          color: AppColors.text,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        padding: const EdgeInsets
                                            .symmetric(
                                            horizontal: 10,
                                            vertical: 8),
                                        child: Icon(
                                            Icons.info_outline,
                                            size: 16,
                                            color: AppColors.text3),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text('꺼두면 자동 등록에서 제외돼요',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.text3)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_editing) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: EdgeInsets.fromLTRB(12, 10, 12, 10),
                        decoration: BoxDecoration(
                          color: AppColors.primaryWeak,
                          borderRadius:
                              BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline,
                                size: 16, color: AppColors.primaryStrong),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '정기 거래 정보를 바꾸면 *다음 자동 등록부터* 새 정보로 들어가요.\n이미 등록된 거래는 따로 거래내역에서 직접 수정해주세요.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.text2,
                                  height: 1.55,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Divider(color: AppColors.line2, height: 1),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _delete,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          alignment: Alignment.centerLeft,
                        ),
                        child: const Text('이 항목 삭제',
                            style:
                                TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(
                  20, 12, 20, 12 + mq.padding.bottom * 0.4),
              decoration: BoxDecoration(
                border:
                    Border(top: BorderSide(color: AppColors.line2)),
              ),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_editing ? '저장' : '등록'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FixedData {
  final List<FixedExpense> items;
  final CategoriesData cats;
  final Suggestions suggestions;
  final Map<int, FixedStatus> statusByFixed;
  const _FixedData({
    required this.items,
    required this.cats,
    required this.suggestions,
    required this.statusByFixed,
  });
}
