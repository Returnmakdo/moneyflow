import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../theme.dart';
import '../utils/nav_back.dart';
import '../widgets/amount_field.dart';
import '../widgets/common.dart';
import '../widgets/format.dart';

/// 외부(거래 모달 등)에서 새 템플릿을 만들거나 편집할 때 사용.
/// 저장 성공 시 새/수정된 TransactionTemplate 반환, 취소 시 null.
/// 카테고리/계좌/카드 fetch가 끝나야 시트를 띄울 수 있어서 wrapper 형태.
Future<TransactionTemplate?> showTemplateEditor(
  BuildContext context, {
  required String initialType,
  TransactionTemplate? template,
}) async {
  CategoriesData cats;
  List<Account> accounts;
  List<CreditCard> cards;
  try {
    final results = await Future.wait([
      Api.instance.listCategories(),
      Api.instance.listAccounts(),
      Api.instance.listCards(),
    ]);
    cats = results[0] as CategoriesData;
    accounts = results[1] as List<Account>;
    cards = results[2] as List<CreditCard>;
  } catch (e) {
    if (context.mounted) showToast(context, errorMessage(e), error: true);
    return null;
  }
  if (!context.mounted) return null;
  return showModalBottomSheet<TransactionTemplate>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (_) => _TemplateEditor(
      cats: cats,
      accounts: accounts,
      cards: cards,
      template: template,
      initialType: initialType,
    ),
  );
}

class TransactionTemplatesScreen extends StatefulWidget {
  const TransactionTemplatesScreen({super.key});

  @override
  State<TransactionTemplatesScreen> createState() =>
      _TransactionTemplatesScreenState();
}

class _TransactionTemplatesScreenState
    extends State<TransactionTemplatesScreen> {
  String _type = 'expense';
  List<TransactionTemplate>? _templates;
  CategoriesData? _cats;
  List<Account> _accounts = const [];
  List<CreditCard> _cards = const [];
  Object? _error;

  late final Listenable _apiListenable = Listenable.merge([
    Api.instance.templatesVersion,
    Api.instance.majorsVersion,
    Api.instance.categoriesVersion,
    Api.instance.accountsVersion,
    Api.instance.cardsVersion,
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
      final results = await Future.wait([
        Api.instance.listTemplates(type: _type),
        Api.instance.listCategories(),
        Api.instance.listAccounts(),
        Api.instance.listCards(),
      ]);
      if (!mounted) return;
      setState(() {
        _templates = results[0] as List<TransactionTemplate>;
        _cats = results[1] as CategoriesData;
        _accounts = results[2] as List<Account>;
        _cards = results[3] as List<CreditCard>;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<void> _openEditor([TransactionTemplate? tpl]) async {
    final cats = _cats;
    if (cats == null) return;
    final r = await showModalBottomSheet<TransactionTemplate>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => _TemplateEditor(
        cats: cats,
        accounts: _accounts,
        cards: _cards,
        template: tpl,
        initialType: _type,
      ),
    );
    if (r != null) _reload();
  }

  Future<void> _delete(TransactionTemplate tpl) async {
    final ok = await confirmDialog(
      context,
      title: '템플릿 삭제',
      message: '"${tpl.name}" 템플릿을 삭제할까요?',
      confirmText: '삭제',
      danger: true,
    );
    if (!ok) return;
    try {
      await Api.instance.deleteTemplate(tpl.id);
      if (!mounted) return;
      showToast(context, '삭제했어요');
    } catch (e) {
      if (!mounted) return;
      showToast(context, errorMessage(e), error: true);
    }
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
          '거래 템플릿',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        centerTitle: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_templates',
        onPressed: _cats == null ? null : () => _openEditor(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(_type == 'income' ? '수입 템플릿 추가' : '지출 템플릿 추가'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: _typeTabs(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                '거래 등록 시 모달에서 "템플릿" 버튼으로 불러올 수 있어요.',
                style: TextStyle(fontSize: 12.5, color: AppColors.text3),
              ),
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
              _templates = null;
            });
            _reload();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected
                  ? (isIncomeTab ? AppColors.incomeBg : AppColors.surface)
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
          tab('expense', '지출 템플릿'),
          tab('income', '수입 템플릿'),
        ],
      ),
    );
  }

  Widget _content() {
    if (_templates == null) {
      if (_error != null) {
        return Center(child: Text(errorMessage(_error!)));
      }
      return const Center(child: CircularProgressIndicator());
    }
    final items = _templates!;
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
        child: EmptyCard(
          icon: Icons.bookmark_border,
          title: _type == 'income'
              ? '등록된 수입 템플릿이 없어요'
              : '등록된 지출 템플릿이 없어요',
          body:
              '자주 입력하는 거래를 미리 저장해두면 거래 등록 시 한 번에 불러와서 수정할 수 있어요.',
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) => _TemplateRow(
        item: items[i],
        accountsById: {for (final a in _accounts) a.id: a.name},
        cardsById: {for (final c in _cards) c.id: c.name},
        onTap: () => _openEditor(items[i]),
        onDelete: () => _delete(items[i]),
      ),
    );
  }
}

class _TemplateRow extends StatelessWidget {
  const _TemplateRow({
    required this.item,
    required this.accountsById,
    required this.cardsById,
    required this.onTap,
    required this.onDelete,
  });
  final TransactionTemplate item;
  final Map<int, String> accountsById;
  final Map<int, String> cardsById;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      tight: true,
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        )),
                    if (_metaLine() != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        _metaLine()!,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.text3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (item.amount > 0)
                Text(
                  won(item.amount),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: item.type == 'income'
                        ? AppColors.success
                        : AppColors.text,
                  ),
                ),
              IconButton(
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline,
                    size: 20, color: AppColors.text3),
                tooltip: '삭제',
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _metaLine() {
    final parts = <String>[];
    if (item.major != null && item.major!.isNotEmpty) parts.add(item.major!);
    if (item.sub != null && item.sub!.isNotEmpty) parts.add(item.sub!);
    if (item.merchant != null && item.merchant!.isNotEmpty) {
      parts.add(item.merchant!);
    }
    final accName = item.accountId != null ? accountsById[item.accountId!] : null;
    final cardName = item.cardId != null ? cardsById[item.cardId!] : null;
    if (cardName != null) {
      parts.add('💳 $cardName');
    } else if (accName != null) {
      parts.add('🏦 $accName');
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

class _TemplateEditor extends StatefulWidget {
  const _TemplateEditor({
    required this.cats,
    required this.accounts,
    required this.cards,
    required this.initialType,
    this.template,
  });
  final CategoriesData cats;
  final List<Account> accounts;
  final List<CreditCard> cards;
  final String initialType;
  final TransactionTemplate? template;

  @override
  State<_TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<_TemplateEditor> {
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _merchant;
  late final TextEditingController _memo;
  late String _type;
  String? _major;
  String? _sub;
  int? _accountId;
  int? _cardId;
  String _paymentKind = 'account'; // expense 전용
  bool _saving = false;

  bool get _editing => widget.template != null;
  bool get _isIncome => _type == 'income';

  @override
  void initState() {
    super.initState();
    final t = widget.template;
    _type = t?.type ?? widget.initialType;
    _name = TextEditingController(text: t?.name ?? '');
    _amount = TextEditingController();
    AmountField.setNumber(_amount, t?.amount);
    _merchant = TextEditingController(text: t?.merchant ?? '');
    _memo = TextEditingController(text: t?.memo ?? '');
    _major = t?.major;
    _sub = t?.sub;
    _accountId = t?.accountId;
    _cardId = t?.cardId;
    if (_isIncome) {
      _paymentKind = 'account';
      _accountId ??= widget.accounts.isNotEmpty ? widget.accounts.first.id : null;
    } else {
      if (_cardId != null) {
        _paymentKind = 'card';
      } else if (_accountId != null) {
        _paymentKind = 'account';
      } else {
        _paymentKind = 'account';
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _merchant.dispose();
    _memo.dispose();
    super.dispose();
  }

  List<String> _typedMajors() => widget.cats.majorsOf(_type);

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final name = _name.text.trim();
    if (name.isEmpty) {
      showToast(context, '템플릿 이름을 입력해주세요', error: true);
      return;
    }
    final amount = AmountField.parse(_amount) ?? 0;
    if (amount <= 0) {
      showToast(context, '금액을 입력해주세요', error: true);
      return;
    }
    if (_major == null || _major!.isEmpty) {
      showToast(context, '카테고리를 선택해주세요', error: true);
      return;
    }
    final useCard = !_isIncome && _paymentKind == 'card';
    setState(() => _saving = true);
    try {
      final TransactionTemplate result;
      if (_editing) {
        result = await Api.instance.updateTemplate(
          widget.template!.id,
          name: name,
          type: _type,
          amount: amount,
          major: _major,
          sub: _sub,
          merchant: _merchant.text,
          memo: _memo.text,
          accountId: useCard ? null : _accountId,
          cardId: useCard ? _cardId : null,
          clearAccount: useCard,
          clearCard: !useCard,
          clearSub: _sub == null || _sub!.isEmpty,
          clearMerchant: _merchant.text.trim().isEmpty,
          clearMemo: _memo.text.trim().isEmpty,
        );
      } else {
        result = await Api.instance.createTemplate(
          name: name,
          type: _type,
          amount: amount,
          major: _major,
          sub: _sub,
          merchant: _merchant.text,
          memo: _memo.text,
          accountId: useCard ? null : _accountId,
          cardId: useCard ? _cardId : null,
        );
      }
      if (!mounted) return;
      showToast(context, _editing ? '수정했어요' : '추가했어요');
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      showToast(context, errorMessage(e), error: true);
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final majors = _typedMajors();
    final List<Category> subs = (_major != null)
        ? (widget.cats.byMajor[_major!] ?? const <Category>[])
        : const <Category>[];
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
                    _editing ? '템플릿 수정' : '새 템플릿',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
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
                    if (!_editing) ...[
                      _typeToggle(),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: '템플릿 이름',
                        hintText: '예: 점심 회사앞 김밥',
                      ),
                    ),
                    const SizedBox(height: 12),
                    AmountField(controller: _amount),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _majorDropdown(majors)),
                        const SizedBox(width: 10),
                        Expanded(child: _subDropdown(subs)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _merchant,
                      decoration: InputDecoration(
                        labelText: _isIncome ? '받은 곳' : '가맹점',
                        hintText: '선택',
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_isIncome)
                      _accountDropdown(
                        label: '입금 계좌',
                        value: _accountId,
                        onChanged: (v) => setState(() => _accountId = v),
                      )
                    else ...[
                      _paymentToggle(),
                      const SizedBox(height: 10),
                      if (_paymentKind == 'account')
                        _accountDropdown(
                          label: '출금 계좌',
                          value: _accountId,
                          onChanged: (v) => setState(() => _accountId = v),
                        )
                      else
                        _cardDropdown(),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _memo,
                      decoration: const InputDecoration(
                          labelText: '메모', hintText: '선택'),
                    ),
                    const SizedBox(height: 8),
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
                onPressed: _saving ? null : _save,
                child: Text(_editing ? '저장' : '추가'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeToggle() {
    Widget item(String value, String label) {
      final selected = _type == value;
      final isIncomeTab = value == 'income';
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_type == value) return;
            setState(() {
              _type = value;
              _major = null;
              _sub = null;
              if (_isIncome) {
                _paymentKind = 'account';
                _cardId = null;
                _accountId ??= widget.accounts.isNotEmpty
                    ? widget.accounts.first.id
                    : null;
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected
                  ? (isIncomeTab ? AppColors.incomeBg : AppColors.surface)
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
                      ? (isIncomeTab ? AppColors.incomeText : AppColors.text)
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
          item('expense', '지출 템플릿'),
          item('income', '수입 템플릿'),
        ],
      ),
    );
  }

  Widget _paymentToggle() {
    Widget item(String value, String label, IconData icon) {
      final selected = _paymentKind == value;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_paymentKind == value) return;
            setState(() => _paymentKind = value);
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

  Widget _majorDropdown(List<String> majors) {
    return AppDropdown<String>(
      label: '카테고리',
      value: (_major != null && majors.contains(_major)) ? _major : '',
      items: [
        const AppDropdownItem(value: '', label: '(선택 안 함)'),
        for (final m in majors) AppDropdownItem(value: m, label: m),
      ],
      onChanged: (v) {
        setState(() {
          _major = v.isEmpty ? null : v;
          _sub = null;
        });
      },
    );
  }

  Widget _subDropdown(List<Category> subs) {
    return AppDropdown<String>(
      label: '태그',
      value: _sub ?? '',
      items: [
        const AppDropdownItem(value: '', label: '(없음)'),
        for (final s in subs) AppDropdownItem(value: s.sub, label: s.sub),
      ],
      onChanged: (v) {
        setState(() => _sub = v.isEmpty ? null : v);
      },
    );
  }

  Widget _accountDropdown({
    required String label,
    required int? value,
    required ValueChanged<int?> onChanged,
  }) {
    if (widget.accounts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          '$label · 자산 탭에서 계좌를 먼저 추가해주세요',
          style: TextStyle(fontSize: 12.5, color: AppColors.text3),
        ),
      );
    }
    return AppDropdown<int>(
      label: label,
      value: widget.accounts.any((a) => a.id == value) ? value : null,
      items: [
        const AppDropdownItem(value: -1, label: '(선택 안 함)'),
        for (final a in widget.accounts)
          AppDropdownItem(value: a.id, label: a.name),
      ],
      onChanged: (v) => onChanged(v == -1 ? null : v),
    );
  }

  Widget _cardDropdown() {
    if (widget.cards.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          '신용카드 · 자산 탭에서 카드를 먼저 추가해주세요',
          style: TextStyle(fontSize: 12.5, color: AppColors.text3),
        ),
      );
    }
    return AppDropdown<int>(
      label: '신용카드',
      value: widget.cards.any((c) => c.id == _cardId) ? _cardId : null,
      items: [
        const AppDropdownItem(value: -1, label: '(선택 안 함)'),
        for (final c in widget.cards)
          AppDropdownItem(value: c.id, label: c.name),
      ],
      onChanged: (v) => setState(() => _cardId = v == -1 ? null : v),
    );
  }
}
