import 'package:flutter/material.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/amount_field.dart';
import '../widgets/common.dart';
import '../widgets/format.dart';
import '../widgets/ko_date_picker.dart';
import 'transaction_templates_screen.dart' show showTemplateEditor;

enum TxModalResult { changed, none }

Future<TxModalResult> showTxModal(
  BuildContext context, {
  required CategoriesData cats,
  required Suggestions suggestions,
  Tx? tx,
  // 신규 거래 등록 시 초기 type. 편집(tx!=null)이면 거래의 기존 type 사용.
  String initialType = 'expense',
}) async {
  final r = await showModalBottomSheet<TxModalResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (ctx) => _TxModal(
      cats: cats,
      suggestions: suggestions,
      tx: tx,
      initialType: initialType,
    ),
  );
  return r ?? TxModalResult.none;
}

class _TxModal extends StatefulWidget {
  const _TxModal({
    required this.cats,
    required this.suggestions,
    this.tx,
    this.initialType = 'expense',
  });
  final CategoriesData cats;
  final Suggestions suggestions;
  final Tx? tx;
  final String initialType;

  @override
  State<_TxModal> createState() => _TxModalState();
}

class _TxModalState extends State<_TxModal> {
  late final TextEditingController _date;
  late final TextEditingController _amount;
  late final TextEditingController _merchant;
  late final TextEditingController _card;
  late final TextEditingController _memo;
  late String _major;
  String? _sub;
  late bool _isFixed;
  // 'expense' | 'income'. transfer는 다음 plan에서 추가.
  late String _type;
  bool _saving = false;

  // 모달 안에서 카테고리/태그를 즉석 생성하면 cats가 갱신돼야 dropdown에 표시됨.
  // props는 immutable이라 state에 mutable 복사본을 둠.
  // 모든 type(지출+수입) 카테고리를 보유하고 화면 노출 시 _type으로 필터.
  late CategoriesData _cats;

  bool get _editing => widget.tx != null;
  bool get _isIncome => _type == 'income';
  bool get _isTransfer => _type == 'transfer';

  List<String> _typedMajors() => _cats.majorsOf(_type);

  // 사용자 등록 계좌 — 수입의 입금 계좌 dropdown + 이체 모드의 from/to dropdown.
  // listAccounts 비동기 fetch 후 setState로 채움.
  List<Account> _accounts = const [];
  // 등록된 신용카드 — 지출 모드 신용카드 결제 시 dropdown.
  List<CreditCard> _cards = const [];
  int? _selectedCardId;

  // 이체 모드 출금/입금 계좌 ID. transfer일 때만 의미.
  int? _fromAccountId;
  int? _toAccountId;

  // 수입 모드의 입금 계좌 ID. 자산 흐름에 정확히 반영되도록 명시 매핑.
  int? _incomeAccountId;

  // 지출 모드의 출금 계좌 ID + 결제수단 종류.
  // _expensePaymentKind = 'account': 내 계좌(체크카드·현금·이체) — 출금 계좌 dropdown
  // _expensePaymentKind = 'card':    신용카드 — 카드 자유 텍스트 (B4 정식 시스템 전 임시)
  int? _expenseAccountId;
  String _expensePaymentKind = 'account';

  @override
  void initState() {
    super.initState();
    final tx = widget.tx;
    _cats = widget.cats;
    // 기존 거래 수정 시 그 거래의 type 사용, 신규는 호출자가 넘긴 initialType.
    _type = tx?.type ?? widget.initialType;
    final firstMajor = _typedMajors();
    _major = tx?.majorCategory ??
        (_isTransfer
            ? '이체'
            : (firstMajor.isNotEmpty ? firstMajor.first : ''));
    _sub = tx?.subCategory;
    _date = TextEditingController(text: tx?.date ?? todayIso());
    _amount = TextEditingController();
    AmountField.setNumber(_amount, tx?.amount);
    _merchant = TextEditingController(text: tx?.merchant ?? '');
    _card = TextEditingController(text: tx?.card ?? '');
    _memo = TextEditingController(text: tx?.memo ?? '');
    // 수입 거래는 고정비 토글 없음.
    _isFixed = _isIncome ? false : (tx?.isFixed ?? false);
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    try {
      final results = await Future.wait([
        Api.instance.listAccounts(),
        Api.instance.listCards(),
      ]);
      if (!mounted) return;
      final accountList = results[0] as List<Account>;
      final cardList = results[1] as List<CreditCard>;
      setState(() {
        _accounts = accountList;
        _cards = cardList;
        final tx = widget.tx;
        if (tx?.type == 'transfer') {
          _fromAccountId = tx?.fromAccountId;
          _toAccountId = tx?.toAccountId;
        } else {
          _fromAccountId ??= accountList.isNotEmpty ? accountList.first.id : null;
          _toAccountId ??= accountList.length >= 2 ? accountList[1].id : null;
        }
        if (tx?.type == 'income') {
          _incomeAccountId = tx?.accountId;
        } else {
          _incomeAccountId ??= accountList.isNotEmpty ? accountList.first.id : null;
        }
        if (tx?.type == 'expense' && tx?.cardId == null) {
          _expenseAccountId = tx?.accountId;
        } else {
          _expenseAccountId ??= accountList.isNotEmpty ? accountList.first.id : null;
        }
        // 지출 카드 모드: 편집 시 거래의 card_id, 신규는 첫 카드.
        if (tx?.type == 'expense' && tx?.cardId != null) {
          _selectedCardId = tx?.cardId;
          _expensePaymentKind = 'card';
        } else {
          _selectedCardId ??= cardList.isNotEmpty ? cardList.first.id : null;
        }
      });
    } catch (_) {/* 무시 */}
  }

  @override
  void dispose() {
    _date.dispose();
    _amount.dispose();
    _merchant.dispose();
    _card.dispose();
    _memo.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    // 일반 거래는 *발생한 거래 입력*이 본질 — 미래 일자 차단.
    // 정기 반복은 설정 → 정기 거래에서 등록하면 도래일에 자동 추가됨.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var initial = DateTime.tryParse(_date.text) ?? today;
    if (initial.isAfter(today)) initial = today;
    final picked = await showKoDatePicker(
      context: context,
      initial: initial,
      firstDate: DateTime(2000),
      lastDate: today,
    );
    if (picked != null) {
      _date.text =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() {});
    }
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final amount = AmountField.parse(_amount);
    if (_date.text.isEmpty || amount == null || amount <= 0) {
      showToast(
          context,
          (amount != null && amount < 0)
              ? '금액은 양수여야 해요'
              : '날짜와 금액은 필수예요',
          error: true);
      return;
    }
    if (_isTransfer) {
      if (_fromAccountId == null || _toAccountId == null) {
        showToast(context, '출금·입금 계좌를 선택해주세요', error: true);
        return;
      }
      if (_fromAccountId == _toAccountId) {
        showToast(context, '같은 계좌끼리는 송금할 수 없어요', error: true);
        return;
      }
    } else if (_major.isEmpty) {
      showToast(context, '카테고리는 필수예요', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isTransfer) {
        // transfer는 카테고리/가맹점/카드/고정비 없이 from/to만.
        // major_category는 NOT NULL이라 시스템 라벨 '이체' 하드코드.
        if (_editing) {
          await Api.instance.updateTransaction(
            widget.tx!.id,
            date: _date.text,
            amount: amount,
            majorCategory: '이체',
            memo: _memo.text,
            type: 'transfer',
            fromAccountId: _fromAccountId,
            toAccountId: _toAccountId,
          );
        } else {
          await Api.instance.createTransaction(
            date: _date.text,
            amount: amount,
            majorCategory: '이체',
            memo: _memo.text.isEmpty ? null : _memo.text,
            type: 'transfer',
            fromAccountId: _fromAccountId,
            toAccountId: _toAccountId,
          );
        }
      } else {
        // 지출 카드 모드 검증.
        if (_type == 'expense' && _expensePaymentKind == 'card') {
          if (_selectedCardId == null) {
            showToast(context, '신용카드를 먼저 추가하거나 선택해주세요',
                error: true);
            setState(() => _saving = false);
            return;
          }
        }
        final accountId = _isIncome
            ? _incomeAccountId
            : (_expensePaymentKind == 'account' ? _expenseAccountId : null);
        final cardId = (_type == 'expense' && _expensePaymentKind == 'card')
            ? _selectedCardId
            : null;
        if (_editing) {
          await Api.instance.updateTransaction(
            widget.tx!.id,
            date: _date.text,
            card: _card.text,
            merchant: _merchant.text,
            amount: amount,
            majorCategory: _major,
            subCategory: _sub ?? '',
            memo: _memo.text,
            isFixed: _isFixed,
            type: _type,
            accountId: accountId,
            cardId: cardId,
          );
        } else {
          await Api.instance.createTransaction(
            date: _date.text,
            card: _card.text.isEmpty ? null : _card.text,
            merchant: _merchant.text.isEmpty ? null : _merchant.text,
            amount: amount,
            majorCategory: _major,
            subCategory: (_sub?.isEmpty ?? true) ? null : _sub,
            memo: _memo.text.isEmpty ? null : _memo.text,
            isFixed: _isFixed,
            type: _type,
            accountId: accountId,
            cardId: cardId,
          );
        }
      }
      // 변동비 expense 신규 거래에 한해 그 카테고리 예산 임계(80%/100%) 통과 시
      // 토스트. 수정·삭제는 차감 계산 복잡 + 빈도 낮아 신규만 처리.
      String? thresholdMsg;
      bool thresholdDanger = false;
      if (!_isTransfer &&
          _type == 'expense' &&
          !_isFixed &&
          !_editing &&
          _major.isNotEmpty) {
        final t = await _evaluateBudgetThreshold(_major, amount);
        thresholdMsg = t?.message;
        thresholdDanger = t?.over ?? false;
      }
      if (!mounted) return;
      showToast(
        context,
        thresholdMsg ?? (_editing ? '수정했어요' : '추가했어요'),
        error: thresholdDanger,
      );
      Navigator.of(context).pop(TxModalResult.changed);
    } catch (e) {
      if (!mounted) return;
      showToast(context, errorMessage(e), error: true);
      setState(() => _saving = false);
    }
  }

  /// 변동비 expense 신규 추가 시 그 카테고리 예산 임계 통과 평가.
  /// 거래 후 변동비/예산 = afterPct, 거래 전 = afterPct - amount/budget.
  /// 두 시점 사이에 80% 또는 100% 선을 *처음 넘은* 경우에만 메시지.
  Future<_BudgetThreshold?> _evaluateBudgetThreshold(
      String major, int amount) async {
    try {
      final ym = _date.text.length >= 7 ? _date.text.substring(0, 7) : null;
      if (ym == null) return null;
      final dash = await Api.instance.getDashboard(ym);
      final cat = dash.categories.firstWhere(
        (c) => c.major == major,
        orElse: () => const CategoryStats(
          major: '',
          spent: 0,
          fixedSpent: 0,
          variableSpent: 0,
          count: 0,
          budget: 0,
        ),
      );
      if (cat.major.isEmpty || cat.budget <= 0) return null;
      final after = cat.variableSpent;
      final before = after - amount;
      final beforePct = before / cat.budget;
      final afterPct = after / cat.budget;
      if (beforePct < 1.0 && afterPct >= 1.0) {
        return _BudgetThreshold('$major 예산을 넘었어요', over: true);
      }
      if (beforePct < 0.8 && afterPct >= 0.8) {
        return _BudgetThreshold('$major 예산의 80%를 썼어요');
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _delete() async {
    final tx = widget.tx;
    if (tx == null) return;
    final ok = await confirmDialog(
      context,
      title: '거래 삭제',
      message: '"${tx.merchant ?? '이 거래'}"를 삭제할까요?',
      confirmText: '삭제',
      danger: true,
    );
    if (!ok) return;
    try {
      await Api.instance.deleteTransaction(tx.id);
      if (!mounted) return;
      showToast(context, '삭제했어요');
      Navigator.of(context).pop(TxModalResult.changed);
    } catch (e) {
      if (!mounted) return;
      showToast(context, errorMessage(e), error: true);
    }
  }

  /// 현 거래(편집 모드)를 템플릿으로 저장. 이름 입력 다이얼로그 → createTemplate.
  /// 가맹점이 비어있으면 기본 이름 안내. 같은 이름 중복 시 에러 토스트.
  Future<void> _saveAsTemplate() async {
    final tx = widget.tx;
    if (tx == null) return;
    final defaultName = (tx.merchant?.trim().isNotEmpty == true
            ? tx.merchant!.trim()
            : (_major.isNotEmpty ? _major : '새 템플릿'));
    final name = await _promptText(
      title: '템플릿으로 저장',
      hint: defaultName,
      confirmText: '저장',
    );
    final finalName = (name?.isNotEmpty == true) ? name! : defaultName;
    try {
      await Api.instance.createTemplate(
        name: finalName,
        type: tx.type,
        amount: tx.amount,
        major: tx.majorCategory,
        sub: tx.subCategory,
        merchant: tx.merchant,
        memo: tx.memo,
        accountId: tx.accountId,
        cardId: tx.cardId,
      );
      if (!mounted) return;
      showToast(context, '"$finalName" 템플릿으로 저장했어요');
    } catch (e) {
      if (!mounted) return;
      showToast(context, errorMessage(e), error: true);
    }
  }

  /// 현 모달 type(expense/income)에 맞는 템플릿 목록을 시트로 띄움.
  /// 결과: TransactionTemplate → 폼 prefill, addNewSentinel → 새 템플릿 추가 흐름.
  Future<void> _pickTemplate() async {
    List<TransactionTemplate> templates;
    try {
      templates = await Api.instance.listTemplates(type: _type);
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e), error: true);
      return;
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TemplatePickerSheet(
        templates: templates,
        type: _type,
      ),
    );
    if (!mounted) return;
    // 토스트 없이 폼만 채운다. 하단 floating 토스트는 모달의 '추가' 버튼 위에
    // 겹쳐 1.9초간 탭을 가로채는데, 템플릿 적용은 폼이 채워지는 걸로 충분히 보여
    // 토스트가 불필요하다.
    if (picked is TransactionTemplate) {
      _applyTemplate(picked);
    } else if (picked == _TemplatePickerSheet.addNewSentinel) {
      // 새 템플릿 에디터 → 저장하면 자동으로 폼에 적용.
      final created =
          await showTemplateEditor(context, initialType: _type);
      if (!mounted || created == null) return;
      _applyTemplate(created);
    }
  }

  /// 템플릿 내용을 폼에 반영. type은 모달과 동일 가정 (필터로 보장).
  void _applyTemplate(TransactionTemplate tpl) {
    setState(() {
      if (tpl.amount > 0) AmountField.setNumber(_amount, tpl.amount);
      if (tpl.major != null && tpl.major!.isNotEmpty) {
        final majors = _typedMajors();
        if (majors.contains(tpl.major)) {
          _major = tpl.major!;
          // sub은 major 일치할 때만 적용.
          final subs = _cats.byMajor[_major] ?? const [];
          if (tpl.sub != null &&
              tpl.sub!.isNotEmpty &&
              subs.any((s) => s.sub == tpl.sub)) {
            _sub = tpl.sub;
          } else {
            _sub = null;
          }
        }
      }
      if (tpl.merchant != null && tpl.merchant!.isNotEmpty) {
        _merchant.text = tpl.merchant!;
      }
      if (tpl.memo != null && tpl.memo!.isNotEmpty) {
        _memo.text = tpl.memo!;
      }
      // 결제수단.
      if (_isIncome) {
        if (tpl.accountId != null &&
            _accounts.any((a) => a.id == tpl.accountId)) {
          _incomeAccountId = tpl.accountId;
        }
      } else {
        // expense — card_id 우선. 둘 다 null이면 폼 기본값 유지.
        if (tpl.cardId != null && _cards.any((c) => c.id == tpl.cardId)) {
          _expensePaymentKind = 'card';
          _selectedCardId = tpl.cardId;
        } else if (tpl.accountId != null &&
            _accounts.any((a) => a.id == tpl.accountId)) {
          _expensePaymentKind = 'account';
          _expenseAccountId = tpl.accountId;
        }
      }
    });
  }

  Future<void> _registerAsFixed() async {
    final tx = widget.tx;
    if (tx == null) return;
    final name = tx.merchant?.trim() ?? '';
    if (name.isEmpty) {
      showToast(context, '가맹점 이름이 있어야 등록할 수 있어요', error: true);
      return;
    }
    final day =
        int.tryParse(tx.date.split('-').last) ?? DateTime.now().day;
    try {
      final list = await Api.instance.listFixedExpenses();
      if (!mounted) return;
      final dup = list.any((f) =>
          f.name == name && f.major == tx.majorCategory && f.active);
      if (dup) {
        showToast(context, '이미 정기지출에 등록되어 있어요', error: true);
        return;
      }
      final ok = await confirmDialog(
        context,
        title: '정기지출 등록',
        message:
            '"$name"을 매월 $day일 결제되는 정기지출로 등록할까요?\n나중에 정기지출 탭에서 수정할 수 있어요.',
        confirmText: '등록',
      );
      if (!ok || !mounted) return;
      await Api.instance.createFixedExpense(
        name: name,
        major: tx.majorCategory,
        sub: tx.subCategory,
        amount: tx.amount,
        card: tx.card,
        dayOfMonth: day,
        active: true,
        memo: tx.memo,
        accountId: tx.accountId,
        cardId: tx.cardId,
      );
      // 원본 거래를 정기 거래로 마킹. 안 하면 _applyDueFixedImpl의 dedupe
      // (is_fixed=1만 기준)에 잡히지 않아 같은 (merchant, major) 페어로
      // 자동 적용이 한 번 더 돌아 거래가 2개 생김.
      if (!tx.isFixed) {
        await Api.instance.updateTransaction(tx.id, isFixed: true);
      }
      if (!mounted) return;
      showToast(context, '정기지출로 등록했어요');
      Navigator.of(context).pop(TxModalResult.changed);
    } catch (e) {
      if (!mounted) return;
      showToast(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final subs = _cats.byMajor[_major] ?? const [];
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
                    _modalTitle(),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  // 템플릿 불러오기 — 신규 등록 + 지출/수입 모드에서만.
                  // 이체는 템플릿 의미 없음, 편집 모드에선 폼이 이미 채워져 있어 불필요.
                  if (!_editing && !_isTransfer)
                    TextButton.icon(
                      onPressed: _pickTemplate,
                      icon: const Icon(Icons.bookmark_border, size: 16),
                      label: const Text('템플릿',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
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
                    _dateField(),
                    const SizedBox(height: 12),
                    AmountField(controller: _amount),
                    const SizedBox(height: 12),
                    if (_isTransfer) ...[
                      _accountDropdown(
                        label: '출금 계좌',
                        value: _fromAccountId,
                        excludeId: _toAccountId,
                        onChanged: (v) =>
                            setState(() => _fromAccountId = v),
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: Icon(Icons.arrow_downward,
                            size: 22, color: AppColors.text3),
                      ),
                      const SizedBox(height: 10),
                      _accountDropdown(
                        label: '입금 계좌',
                        value: _toAccountId,
                        excludeId: _fromAccountId,
                        onChanged: (v) =>
                            setState(() => _toAccountId = v),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _memo,
                        decoration: const InputDecoration(
                            labelText: '메모', hintText: '선택'),
                      ),
                      const SizedBox(height: 12),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(child: _majorDropdown()),
                          const SizedBox(width: 10),
                          Expanded(child: _subDropdown(subs)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _fieldWithChips(
                        controller: _merchant,
                        label: _isIncome ? '받은 곳' : '가맹점',
                        hint: _isIncome ? '예: 회사, 부모님' : '예: 스타벅스',
                        options: _merchantSuggestions(),
                        emptyHint: _major.isEmpty
                            ? null
                            : (_isIncome
                                ? null
                                : '$_major에 등록된 가맹점이 없어요'),
                      ),
                      const SizedBox(height: 12),
                      if (_isIncome)
                        _accountDropdown(
                          label: '입금 계좌',
                          value: _incomeAccountId,
                          excludeId: null,
                          onChanged: (v) =>
                              setState(() => _incomeAccountId = v),
                        )
                      else ...[
                        _expensePaymentKindToggle(),
                        const SizedBox(height: 10),
                        if (_expensePaymentKind == 'account')
                          _accountDropdown(
                            label: '출금 계좌',
                            value: _expenseAccountId,
                            excludeId: null,
                            onChanged: (v) =>
                                setState(() => _expenseAccountId = v),
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
                    if (!_isIncome && !_isTransfer)
                      InkWell(
                        onTap: () => setState(() {
                          _isFixed = !_isFixed;
                        }),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 8),
                          child: Row(
                            children: [
                              Switch(
                                value: _isFixed,
                                onChanged: (v) => setState(() {
                                  _isFixed = v;
                                }),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text('고정비로 표시',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.text)),
                                    SizedBox(height: 2),
                                    Text('월세, 구독료처럼 매달 정해진 지출',
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
                      const SizedBox(height: 8),
                      Divider(color: AppColors.line2, height: 1),
                      const SizedBox(height: 8),
                      // 템플릿 저장은 지출·수입 거래에만 (이체 X).
                      if (!_isTransfer)
                        TextButton.icon(
                          onPressed: _saveAsTemplate,
                          icon:
                              const Icon(Icons.bookmark_add_outlined, size: 18),
                          label: const Text('템플릿으로 저장',
                              style:
                                  TextStyle(fontWeight: FontWeight.w600)),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            alignment: Alignment.centerLeft,
                          ),
                        ),
                      // 정기지출 등록은 지출 거래에만 (이체·수입 X).
                      if (!_isIncome && !_isTransfer)
                        TextButton.icon(
                          onPressed: _registerAsFixed,
                          icon: const Icon(Icons.repeat, size: 18),
                          label: const Text('정기지출로 등록',
                              style:
                                  TextStyle(fontWeight: FontWeight.w600)),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            alignment: Alignment.centerLeft,
                          ),
                        ),
                      TextButton.icon(
                        onPressed: _delete,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('이 거래 삭제',
                            style:
                                TextStyle(fontWeight: FontWeight.w600)),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          alignment: Alignment.centerLeft,
                        ),
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
                child: Text(_editing ? '저장' : '추가'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _modalTitle() {
    if (_isTransfer) return _editing ? '이체 수정' : '내 계좌로 송금';
    if (_isIncome) return _editing ? '수입 수정' : '수입 추가';
    return _editing ? '지출 수정' : '지출 추가';
  }

  /// 지출 결제수단 토글 — [내 계좌 | 신용카드].
  /// 내 계좌: 체크카드/현금/이체 등 — 즉시 출금 → 출금 계좌 dropdown.
  /// 신용카드: 자산에 즉시 영향 X (B4에서 정식 처리 예정) → 카드 이름 자유 텍스트.
  Widget _expensePaymentKindToggle() {
    Widget item(String value, String label, IconData icon) {
      final selected = _expensePaymentKind == value;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_expensePaymentKind == value) return;
            setState(() => _expensePaymentKind = value);
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

  Widget _cardDropdown() {
    if (_cards.isEmpty) {
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
      value: _cards.any((c) => c.id == _selectedCardId)
          ? _selectedCardId
          : null,
      items: [
        for (final c in _cards)
          AppDropdownItem(value: c.id, label: c.name),
      ],
      onChanged: (v) => setState(() => _selectedCardId = v),
    );
  }

  Widget _accountDropdown({
    required String label,
    required int? value,
    required int? excludeId,
    required ValueChanged<int?> onChanged,
  }) {
    if (_accounts.isEmpty) {
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
    final items = _accounts
        .where((a) => a.id != excludeId)
        .toList();
    return AppDropdown<int>(
      label: label,
      value: items.any((a) => a.id == value) ? value : null,
      items: [
        for (final a in items) AppDropdownItem(value: a.id, label: a.name),
      ],
      onChanged: onChanged,
    );
  }

  Widget _dateField() {
    return GestureDetector(
      onTap: _pickDate,
      child: AbsorbPointer(
        child: TextField(
          controller: _date,
          decoration: InputDecoration(
            labelText: '날짜',
            suffixIcon:
                Icon(Icons.calendar_today, size: 18, color: AppColors.text3),
          ),
        ),
      ),
    );
  }

  static const _addMajorSentinel = '__add_major__';
  static const _addSubSentinel = '__add_sub__';

  Widget _majorDropdown() {
    final majors = _typedMajors();
    return AppDropdown<String>(
      label: '카테고리',
      value: majors.contains(_major) ? _major : null,
      items: [
        for (final m in majors) AppDropdownItem(value: m, label: m),
        AppDropdownItem(
            value: _addMajorSentinel,
            label: _isIncome ? '+ 새 수입 카테고리 추가' : '+ 새 카테고리 추가'),
      ],
      onChanged: (v) {
        if (v == _addMajorSentinel) {
          _addMajor();
        } else {
          setState(() {
            _major = v;
            _sub = null;
          });
        }
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
        if (_major.isNotEmpty)
          const AppDropdownItem(
              value: _addSubSentinel, label: '+ 새 태그 추가'),
      ],
      onChanged: (v) {
        if (v == _addSubSentinel) {
          _addSub();
        } else {
          setState(() => _sub = v.isEmpty ? null : v);
        }
      },
    );
  }

  Future<void> _addMajor() async {
    final name = await _promptText(
      title: '새 카테고리 추가',
      hint: '예: 식비/카페',
      confirmText: '추가',
    );
    if (name == null) return;
    try {
      final created = await Api.instance.createMajor(name, type: _type);
      // 카테고리 목록 갱신.
      final fresh = await Api.instance.listCategories();
      if (!mounted) return;
      setState(() {
        _cats = fresh;
        _major = created.name;
        _sub = null;
      });
      showToast(context, '카테고리 추가 완료');
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e), error: true);
    }
  }

  Future<void> _addSub() async {
    if (_major.isEmpty) return;
    final name = await _promptText(
      title: '$_major에 새 태그 추가',
      hint: '예: 점심',
      confirmText: '추가',
    );
    if (name == null) return;
    try {
      final created = await Api.instance.createCategory(_major, name);
      final fresh = await Api.instance.listCategories();
      if (!mounted) return;
      setState(() {
        _cats = fresh;
        _sub = created.sub;
      });
      showToast(context, '태그 추가 완료');
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e), error: true);
    }
  }

  Future<String?> _promptText({
    required String title,
    required String hint,
    String confirmText = '확인',
  }) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        title:
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (_) =>
              Navigator.of(ctx).pop(ctrl.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('취소',
                style: TextStyle(color: AppColors.text2)),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(ctrl.text.trim()),
            child: Text(confirmText,
                style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    // 다이얼로그 dismiss 애니메이션이 끝난 다음 frame에 dispose.
    // 즉시 dispose하면 TextField rebuild가 disposed controller를 건드려 폭발.
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    return (result == null || result.isEmpty) ? null : result;
  }

  List<String> _merchantSuggestions() {
    if (_major.isEmpty) return const [];
    return widget.suggestions.merchantsByMajor[_major] ?? const [];
  }

  Widget _fieldWithChips({
    required TextEditingController controller,
    required String label,
    required String hint,
    required List<String> options,
    String? emptyHint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          decoration: InputDecoration(labelText: label, hintText: hint),
          onChanged: (_) => setState(() {}),
        ),
        if (options.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final o in options)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _PickChip(
                        label: o,
                        selected: controller.text == o,
                        onTap: () => setState(() {
                          controller.text = o;
                          controller.selection =
                              TextSelection.collapsed(offset: o.length);
                        }),
                      ),
                    ),
                ],
              ),
            ),
          )
        else if (emptyHint != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              emptyHint,
              style: TextStyle(fontSize: 11.5, color: AppColors.text4),
            ),
          ),
      ],
    );
  }
}

class _BudgetThreshold {
  final String message;
  final bool over;
  const _BudgetThreshold(this.message, {this.over = false});
}

class _TemplatePickerSheet extends StatelessWidget {
  const _TemplatePickerSheet({
    required this.templates,
    required this.type,
  });
  final List<TransactionTemplate> templates;
  final String type;

  /// pop 시 이 값이 오면 부모는 "+ 새 템플릿 추가" 에디터를 띄움.
  static const String addNewSentinel = '__add_new__';

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Container(
      constraints: BoxConstraints(maxHeight: mq.size.height * 0.7),
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
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(
              children: [
                Text(
                  type == 'income' ? '수입 템플릿' : '지출 템플릿',
                  style: const TextStyle(
                    fontSize: 16,
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
            child: templates.isEmpty
                ? _emptyState(context)
                : ListView.separated(
                    padding:
                        const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    itemCount: templates.length,
                    separatorBuilder: (_, _) =>
                        Divider(color: AppColors.line2, height: 1),
                    itemBuilder: (ctx, i) {
                      final t = templates[i];
                      return InkWell(
                        onTap: () => Navigator.of(ctx).pop(t),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(t.name,
                                        style: const TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w700,
                                        )),
                                    if (_metaLine(t) != null) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        _metaLine(t)!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.text3,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              if (t.amount > 0)
                                Text(
                                  won(t.amount),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: t.type == 'income'
                                        ? AppColors.success
                                        : AppColors.text,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (templates.isNotEmpty)
            Padding(
              // 하단 안전영역(홈 인디케이터)만큼 더 띄워 버튼이 가리지 않게.
              padding: EdgeInsets.fromLTRB(20, 4, 20, 16 + mq.padding.bottom),
              child: _addNewButton(context, prominent: false),
            ),
        ],
      ),
    );
  }

  /// 빈 상태 + 목록 하단에서 공통으로 쓰는 "+ 새 템플릿 추가" 액션.
  /// 부모가 sentinel을 받으면 별도 에디터를 띄움.
  Widget _addNewButton(BuildContext context, {required bool prominent}) {
    const label = '새 템플릿 추가';
    if (prominent) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(addNewSentinel),
          icon: const Icon(Icons.add, size: 18),
          label: const Text(label,
              style: TextStyle(fontWeight: FontWeight.w600)),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 44),
          ),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => Navigator.of(context).pop(addNewSentinel),
        icon: const Icon(Icons.add, size: 18),
        label: const Text(label,
            style: TextStyle(fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: BorderSide(color: AppColors.primary),
          minimumSize: const Size(0, 42),
        ),
      ),
    );
  }

  static String? _metaLine(TransactionTemplate t) {
    final parts = <String>[];
    if (t.major != null && t.major!.isNotEmpty) parts.add(t.major!);
    if (t.sub != null && t.sub!.isNotEmpty) parts.add(t.sub!);
    if (t.merchant != null && t.merchant!.isNotEmpty) parts.add(t.merchant!);
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Widget _emptyState(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          28, 12, 28, 24 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bookmark_border, size: 36, color: AppColors.text4),
          const SizedBox(height: 10),
          Text(
            '등록한 템플릿이 없어요',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.text2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '자주 쓰는 거래를 한 번 저장해두면\n다음부터 한 번에 불러올 수 있어요',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.text3,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          _addNewButton(context, prominent: true),
        ],
      ),
    );
  }
}

class _PickChip extends StatelessWidget {
  const _PickChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primaryWeak : AppColors.surface2,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected ? AppColors.primary : Colors.transparent,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.primaryStrong : AppColors.text2,
            ),
          ),
        ),
      ),
    );
  }
}
