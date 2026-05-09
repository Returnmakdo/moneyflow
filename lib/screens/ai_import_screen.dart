import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../theme.dart';
import '../utils/csv_parse.dart';
import '../utils/nav_back.dart';
import '../widgets/common.dart';
import '../widgets/format.dart';
import 'accounts_screen.dart' show AccountEditor, CardEditor;

/// 카드사 CSV → AI가 컬럼 매핑 + 카테고리 분류 → 거래 등록.
/// 단계: 파일 선택 → AI 매핑 미리보기 → AI 분류 미리보기 → 등록.
class AiImportScreen extends StatefulWidget {
  const AiImportScreen({super.key});

  @override
  State<AiImportScreen> createState() => _AiImportScreenState();
}

enum _Phase { selectFile, mappingReview, classifyReview }

class _AiImportScreenState extends State<AiImportScreen> {
  _Phase _phase = _Phase.selectFile;

  String? _fileName;
  CsvFile? _csv;
  bool _mojibake = false;

  CsvMapping? _mapping;
  List<ImportRow>? _normalized;
  List<int> _skippedRowIndexes = const [];
  int _excludedByStatusCount = 0;
  Map<String, CsvClassifyItem> _classByMerchant = const {};

  bool _busy = false;
  String? _busyText;
  String? _error;
  bool _importing = false;

  // 결제수단 — 등록 시 모든 row에 일괄 적용. 'card'면 cardId, 'account'면 accountId.
  String _payKind = 'card'; // 'card' | 'account'
  int? _selectedCardId;
  int? _selectedAccountId;
  List<CreditCard> _cards = const [];
  List<Account> _accounts = const [];

  @override
  void initState() {
    super.initState();
    _loadPaymentOptions();
  }

  Future<void> _loadPaymentOptions() async {
    try {
      final results = await Future.wait([
        Api.instance.listCards(),
        Api.instance.listAccounts(),
      ]);
      if (!mounted) return;
      setState(() {
        _cards = results[0] as List<CreditCard>;
        _accounts = results[1] as List<Account>;
        // default: 카드가 있으면 카드 첫 번째, 없으면 계좌 첫 번째.
        if (_cards.isNotEmpty) {
          _payKind = 'card';
          _selectedCardId = _cards.first.id;
        } else if (_accounts.isNotEmpty) {
          _payKind = 'account';
          _selectedAccountId = _accounts.first.id;
        }
      });
    } catch (_) {/* 무시 — 결제수단 미선택 시 default 계좌로 fallback */}
  }

  /// 기술적 에러 메시지를 사용자가 알아들을 수 있게 매핑.
  /// errorMessage()의 일반 매핑(네트워크/timeout/auth) 위에 import 흐름 전용
  /// 케이스(서버 영어 메시지, SheetJS 파싱 실패 등) 추가.
  String _friendlyError(Object e) {
    final s = errorMessage(e);
    final lower = s.toLowerCase();

    // 파일 자체 문제
    if (s.contains('파일이 너무 커요')) return s; // 이미 친근
    if (s.contains('파일이 비어있어요')) return s;
    if (s.contains('데이터 행이 없어요')) {
      return '거래 데이터를 찾지 못했어요. 명세서가 비어있거나 양식이 달라요.';
    }
    if (s.contains('시트가 없어요')) return '엑셀에 시트가 없어요.';
    if (lower.contains('password-protected') ||
        lower.contains('password protected') ||
        lower.contains('encrypted')) {
      return '비밀번호로 잠긴 파일이에요. 엑셀에서 열어 비번을 풀고 .xlsx로 "다른 이름 저장" 후 올려주세요.';
    }
    if (s.contains('시트 파싱 실패') || lower.contains('decode failed')) {
      return '엑셀 파일을 읽지 못했어요. 엑셀에서 열어 .xlsx로 다시 저장해주세요.';
    }
    if (s.contains('XLSX를 읽지 못했어요')) {
      return '엑셀 파일이 손상됐거나 형식이 달라요. 엑셀에서 .xlsx로 다시 저장해보세요.';
    }
    if (s.contains('파일을 읽을 수 없어요')) return s;
    if (s.contains('파일을 변환할 수 없어요')) {
      return '파일을 변환하지 못했어요. 다른 파일을 시도하거나 .xlsx 형식으로 저장해주세요.';
    }
    if (s.contains('fileBase64')) {
      return '파일 인코딩에 문제가 있어요. 다시 올려주세요.';
    }

    // AI 응답
    if (lower.contains('ai response was not valid json') ||
        s.contains('AI response')) {
      return 'AI 응답을 처리하지 못했어요. 다시 시도해주세요.';
    }
    if (s.contains('매핑 결과를 받을 수 없어요')) {
      return 'AI가 컬럼을 못 잡았어요. 다른 파일을 올리거나 잠시 후 다시 시도해주세요.';
    }
    if (s.contains('분류 결과를 받을 수 없어요')) {
      return 'AI 분류에 실패했어요. 잠시 후 다시 시도해주세요.';
    }
    if (lower.contains('anthropic_api_key') ||
        lower.contains('api key')) {
      return 'AI 서버 설정 문제예요. 잠시 후 다시 시도해주세요.';
    }

    // 서버 검증 실패
    if (lower.contains('firstrows')) {
      return '파일 상단 row를 읽지 못했어요. 파일이 양식대로인지 확인해주세요.';
    }
    if (lower.contains('merchants')) {
      return '가맹점 목록이 비어있어요. 매핑 단계로 돌아가서 다시 확인해주세요.';
    }
    if (lower.contains('headers')) {
      return '헤더 row를 찾지 못했어요. 파일에 컬럼 이름이 있는지 확인해주세요.';
    }
    if (lower.contains('missing auth') ||
        lower.contains('jwt')) {
      return '로그인이 만료됐어요. 다시 로그인해주세요.';
    }
    if (lower.contains('invalid mode')) {
      return '요청 형식이 잘못됐어요. 새로고침 후 다시 시도해주세요.';
    }

    // 정규화 실패
    if (s.contains('정규화된 거래가 없어요')) return s;
    if (s.contains('헤더가 비어있어요')) {
      return '파일 헤더가 비어있어요. 다른 파일을 올려주세요.';
    }
    if (s.contains('샘플 row가 필요해요')) {
      return '파일에 데이터 row가 부족해요.';
    }

    // function invoke 일반 에러 (FunctionException 등)
    if (lower.contains('functionexception') ||
        lower.contains('500') ||
        lower.contains('internal')) {
      return '서버에 일시적 문제가 있어요. 잠시 후 다시 시도해주세요.';
    }
    if (lower.contains('429') || lower.contains('rate limit')) {
      return '요청이 너무 많아요. 잠시 후 다시 시도해주세요.';
    }

    return s;
  }

  Future<void> _pickFile() async {
    setState(() => _error = null);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'xls'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() => _error = '파일을 읽을 수 없어요.');
      return;
    }

    final ext = (file.extension ?? '').toLowerCase();
    late final CsvFile parsed;
    var mojibake = false;
    try {
      if (ext == 'xlsx') {
        // 1차: 클라이언트 파싱. 실패 시 서버 fallback.
        CsvFile? local;
        try {
          local = parseXlsxBytes(bytes);
        } catch (_) {
          local = null;
        }
        if (local != null) {
          parsed = local;
        } else {
          setState(() {
            _busy = true;
            _busyText = 'AI 서버에서 시트를 변환하고 있어요…';
          });
          final r = await Api.instance.parseSheetFile(bytes);
          parsed = CsvFile(headers: r.headers, rows: r.rows);
        }
      } else if (ext == 'xls') {
        // .xls(BIFF) 구버전은 무조건 서버 변환.
        setState(() {
          _busy = true;
          _busyText = 'AI 서버에서 .xls를 변환하고 있어요…';
        });
        final r = await Api.instance.parseSheetFile(bytes);
        parsed = CsvFile(headers: r.headers, rows: r.rows);
      } else {
        final text = decodeCsvBytes(bytes);
        mojibake = looksMojibake(text);
        parsed = parseCsv(text);
      }
    } catch (e) {
      setState(() {
        _error = _friendlyError(e);
        _busy = false;
        _busyText = null;
      });
      return;
    }
    if (parsed.headers.isEmpty || parsed.rows.isEmpty) {
      setState(() => _error = '파일에 데이터 행이 없어요.');
      return;
    }

    setState(() {
      _fileName = file.name;
      _csv = parsed;
      _mojibake = mojibake;
    });
    await _runMapping();
  }

  Future<void> _runMapping() async {
    final csv = _csv;
    if (csv == null) return;
    setState(() {
      _busy = true;
      _busyText = 'AI가 컬럼을 분석하고 있어요…';
      _error = null;
    });
    try {
      // 파일 상단 12 row를 통째로 보냄 (헤더 row + 샘플 데이터 모두 포함).
      // csv.headers = 파일 row 0, csv.rows[0] = 파일 row 1.
      final firstRows = <List<String>>[
        csv.headers,
        ...csv.rows.take(11),
      ];
      final mapping = await Api.instance.getCsvMapping(firstRows: firstRows);
      if (!mounted) return;
      setState(() {
        _mapping = mapping;
        _phase = _Phase.mappingReview;
        _busy = false;
        _busyText = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _busy = false;
        _busyText = null;
      });
    }
  }

  /// 카드사 .xls의 "카드종류" 컬럼처럼 마스킹된 카드번호("5***-****-****-810*")를
  /// 결제수단으로 저장하지 않도록 차단. * 가 2개 이상 들어가거나 동일 패턴이면 마스킹.
  bool _looksMaskedCard(String s) {
    if (s.isEmpty) return false;
    // *가 여러 번 등장하거나 4자리 묶음 패턴 (마스킹된 카드번호 패턴).
    if (s.split('*').length - 1 >= 2) return true;
    if (RegExp(r'\*{2,}').hasMatch(s)) return true;
    if (RegExp(r'^[\d*\-\s]+$').hasMatch(s) && s.contains('*')) return true;
    return false;
  }

  /// AI가 추정한 headerRowIndex 기준으로 진짜 헤더 row + 데이터 rows를 추출.
  ({List<String> headers, List<List<String>> rows}) _effectiveCsv() {
    final csv = _csv!;
    final hri = _mapping?.headerRowIndex ?? 0;
    if (hri == 0) {
      return (headers: csv.headers, rows: csv.rows);
    }
    // hri == 1 → 진짜 헤더는 csv.rows[0], 데이터는 csv.rows[1:]
    final headerIdxInRows = hri - 1;
    if (headerIdxInRows >= csv.rows.length) {
      return (headers: csv.headers, rows: csv.rows);
    }
    return (
      headers: csv.rows[headerIdxInRows],
      rows: csv.rows.sublist(headerIdxInRows + 1),
    );
  }

  Future<void> _runClassify() async {
    final csv = _csv;
    final mapping = _mapping;
    if (csv == null || mapping == null) return;

    final eff = _effectiveCsv();
    final dataRows = eff.rows;

    // 1) 매핑으로 모든 row 정규화.
    final rows = <ImportRow>[];
    final skipped = <int>[];
    var excludedByStatus = 0;
    for (var i = 0; i < dataRows.length; i++) {
      final r = dataRows[i];

      // 취소·반려 row 제외 (명세서 합계와 일치하도록).
      if (mapping.statusCol != null &&
          mapping.excludedStatuses.isNotEmpty &&
          r.length > mapping.statusCol!) {
        final status = r[mapping.statusCol!].trim();
        if (status.isNotEmpty &&
            mapping.excludedStatuses.any(
                (s) => status.contains(s) || s.contains(status))) {
          excludedByStatus++;
          continue;
        }
      }

      final dateRaw = r.length > mapping.dateCol ? r[mapping.dateCol] : '';
      final amountRaw =
          r.length > mapping.amountCol ? r[mapping.amountCol] : '';
      final merchantRaw =
          r.length > mapping.merchantCol ? r[mapping.merchantCol] : '';
      final cardRaw = mapping.cardCol != null &&
              r.length > mapping.cardCol!
          ? r[mapping.cardCol!]
          : null;
      final memoRaw = mapping.memoCol != null &&
              r.length > mapping.memoCol!
          ? r[mapping.memoCol!]
          : null;

      final date = normalizeDate(dateRaw, dateFormat: mapping.dateFormat);
      final amount = parseAmount(amountRaw, amountSign: mapping.amountSign);
      final merchant = merchantRaw.trim();

      if (date == null || amount == null || amount <= 0 || merchant.isEmpty) {
        skipped.add(i);
        continue;
      }
      // 카드번호 마스킹 컬럼은 절대 저장 X (개인정보).
      final cardClean = (cardRaw?.trim().isNotEmpty ?? false)
          ? (_looksMaskedCard(cardRaw!.trim()) ? null : cardRaw.trim())
          : null;

      rows.add(ImportRow(
        date: date,
        amount: amount,
        majorCategory: '기타', // 분류 전 임시.
        merchant: merchant,
        card: cardClean,
        memo: (memoRaw?.trim().isNotEmpty ?? false) ? memoRaw!.trim() : null,
        isFixed: false,
      ));
    }

    if (rows.isEmpty) {
      setState(() => _error =
          '정규화된 거래가 없어요. 매핑을 확인해주세요. (스킵 ${skipped.length}건)');
      return;
    }

    final merchants = <String>{};
    for (final r in rows) {
      if (r.merchant != null) merchants.add(r.merchant!);
    }

    setState(() {
      _busy = true;
      _busyText = 'AI가 가맹점을 분류하고 있어요…';
      _error = null;
      _normalized = rows;
      _skippedRowIndexes = skipped;
      _excludedByStatusCount = excludedByStatus;
    });

    try {
      final results = await Api.instance.getCsvClassification(
        merchants: merchants.toList(),
      );
      if (!mounted) return;
      setState(() {
        _classByMerchant = {for (final c in results) c.merchant: c};
        _phase = _Phase.classifyReview;
        _busy = false;
        _busyText = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _busy = false;
        _busyText = null;
      });
    }
  }

  /// 분류 미리보기 단계 — 결제수단 확정값만 보여줌 (편집 X).
  Widget _paymentSummary() {
    final isCard = _payKind == 'card';
    String? name;
    if (isCard) {
      name = _cards
          .firstWhere((c) => c.id == _selectedCardId,
              orElse: () => const CreditCard(
                    id: 0,
                    name: '',
                    paymentDay: 1,
                    linkedAccountId: 0,
                    active: true,
                    sortOrder: 0,
                  ))
          .name;
    } else {
      name = _accounts
          .firstWhere((a) => a.id == _selectedAccountId,
              orElse: () => const Account(
                    id: 0,
                    name: '',
                    type: AccountType.checking,
                    initialBalance: 0,
                    sortOrder: 0,
                    active: true,
                  ))
          .name;
    }
    if (name.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.primaryWeak,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(
            isCard ? Icons.credit_card : Icons.account_balance_wallet_outlined,
            size: 18,
            color: AppColors.primaryStrong,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.text,
                  height: 1.5,
                ),
                children: [
                  TextSpan(
                    text: name,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryStrong,
                    ),
                  ),
                  const TextSpan(text: '으로 등록될 거에요'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentSelector({bool allowToggle = false}) {
    final hasCards = _cards.isNotEmpty;
    final hasAccounts = _accounts.isNotEmpty;
    final isCard = _payKind == 'card';
    final dataMissing = (isCard && !hasCards) || (!isCard && !hasAccounts);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '이 명세서는 어디서 결제됐어요?',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.text2,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '선택한 결제수단으로 모든 거래가 등록돼요.',
            style: TextStyle(fontSize: 12, color: AppColors.text3),
          ),
          const SizedBox(height: 12),
          if (allowToggle)
            Row(
              children: [
                Expanded(
                  child: _PayKindBtn(
                    label: '신용카드',
                    selected: _payKind == 'card',
                    onTap: () => setState(() {
                      _payKind = 'card';
                      if (hasCards && _selectedCardId == null) {
                        _selectedCardId = _cards.first.id;
                      }
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PayKindBtn(
                    label: '내 계좌',
                    selected: _payKind == 'account',
                    onTap: () => setState(() {
                      _payKind = 'account';
                      if (hasAccounts && _selectedAccountId == null) {
                        _selectedAccountId = _accounts.first.id;
                      }
                    }),
                  ),
                ),
              ],
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primaryWeak,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                isCard ? '신용카드 명세서' : '입출금 거래내역',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryStrong,
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (dataMissing)
            _MissingDataPrompt(
              isCard: isCard,
              onAdd: () => _addInline(isCard: isCard),
            )
          else
            Row(
              children: [
                Expanded(
                  child: isCard
                      ? AppDropdown<int>(
                          label: '카드',
                          value: _cards.any((c) => c.id == _selectedCardId)
                              ? _selectedCardId
                              : null,
                          items: [
                            for (final c in _cards)
                              AppDropdownItem(value: c.id, label: c.name),
                          ],
                          onChanged: (v) =>
                              setState(() => _selectedCardId = v),
                        )
                      : AppDropdown<int>(
                          label: '계좌',
                          value: _accounts
                                  .any((a) => a.id == _selectedAccountId)
                              ? _selectedAccountId
                              : null,
                          items: [
                            for (final a in _accounts)
                              AppDropdownItem(value: a.id, label: a.name),
                          ],
                          onChanged: (v) =>
                              setState(() => _selectedAccountId = v),
                        ),
                ),
                const SizedBox(width: 8),
                _AddInlineBtn(
                  tooltip: isCard ? '카드 추가' : '계좌 추가',
                  onTap: () => _addInline(isCard: isCard),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _import() async {
    final rows = _normalized;
    if (rows == null || rows.isEmpty) return;
    // 카드 모드인데 카드 미선택, 계좌 모드인데 계좌 미선택은 막음.
    if (_payKind == 'card' && _selectedCardId == null) {
      showToast(context, '카드를 선택해주세요', error: true);
      return;
    }
    if (_payKind == 'account' && _selectedAccountId == null) {
      showToast(context, '계좌를 선택해주세요', error: true);
      return;
    }
    final useCard = _payKind == 'card';
    setState(() => _importing = true);
    try {
      final finalRows = <ImportRow>[];
      for (final r in rows) {
        final m = r.merchant;
        final cls = m != null ? _classByMerchant[m] : null;
        finalRows.add(ImportRow(
          date: r.date,
          amount: r.amount,
          majorCategory: cls?.major ?? r.majorCategory,
          subCategory: cls?.sub,
          // 결제수단 일괄 적용 — free-text card 필드는 비움.
          card: null,
          merchant: r.merchant,
          memo: r.memo,
          isFixed: false,
          cardId: useCard ? _selectedCardId : null,
          accountId: useCard ? null : _selectedAccountId,
        ));
      }
      final n = await Api.instance.importTransactions(finalRows);
      if (!mounted) return;
      // 등록 완료 → 대시보드로 이동하면서 토스트로 알림.
      // SnackBar는 mount된 ScaffoldMessenger에 즉시 push되므로 화면 전환 후에도
      // 잠깐 보임 (ScaffoldMessenger가 root에 있으면).
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('거래 $n건이 등록됐어요. 대시보드에서 확인해보세요'),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 3),
        ));
      context.go('/dashboard');
    } catch (e) {
      if (mounted) showToast(context, _friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _restart() {
    setState(() {
      _phase = _Phase.selectFile;
      _csv = null;
      _fileName = null;
      _mojibake = false;
      _mapping = null;
      _normalized = null;
      _skippedRowIndexes = const [];
      _classByMerchant = const {};
      _error = null;
    });
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
          onPressed: () => goBackOr(context, '/settings/import'),
        ),
        title: Text(
          'AI로 카드사 CSV 정리',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _StepBar(phase: _phase),
            const SizedBox(height: 16),
            if (_error != null) _errorCard(_error!),
            if (_busy) _busyCard(_busyText ?? '잠시만요…'),
            if (!_busy) _phaseBody(),
          ],
        ),
      ),
    );
  }

  Widget _phaseBody() {
    switch (_phase) {
      case _Phase.selectFile:
        return _filePhase();
      case _Phase.mappingReview:
        return _mappingPhase();
      case _Phase.classifyReview:
        return _classifyPhase();
    }
  }

  Widget _filePhase() {
    final ready = _isPaymentReady();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _paymentSelector(allowToggle: true),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primaryWeak,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.auto_awesome,
                        size: 18, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'AI가 카드사 CSV 양식을 자동으로 정리해요',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '카드사에서 다운받은 이용내역을 그대로 올리면, '
                '컬럼 매핑부터 카테고리 분류까지 AI가 추정해드려요. '
                '미리보기에서 확인 후 등록할 수 있어요.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.text2,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4D6),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        size: 14, color: const Color(0xFF8A6A00)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '은행 거래내역(입출금이 분리된 양식)은 아직 지원 안 해요. 카드 명세서만 올려주세요.',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF8A6A00),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: ready ? _pickFile : null,
                icon: const Icon(Icons.folder_open, size: 18),
                label: Text(ready ? '명세서 파일 선택' : '먼저 결제수단을 골라주세요'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 44),
                  textStyle: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  '·  .xls 구버전도 그대로 올리면 서버에서 자동으로 변환해드려요.\n'
                  '·  CSV가 EUC-KR(CP949)이면 한글이 깨질 수 있어요. 엑셀에서 "CSV UTF-8(쉼표로 분리)"로 다시 저장하면 정확해요.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.text3,
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool _isPaymentReady() {
    if (_payKind == 'card') return _selectedCardId != null;
    return _selectedAccountId != null;
  }

  /// 카드 또는 계좌가 없을 때 inline 추가 — 자산 탭의 editor를 그대로 사용.
  Future<void> _addInline({required bool isCard}) async {
    if (isCard) {
      // 카드는 연동 계좌가 필요하니 계좌가 0개면 먼저 계좌 추가.
      if (_accounts.isEmpty) {
        final accSaved = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.xl),
            ),
          ),
          builder: (_) => const AccountEditor(),
        );
        if (accSaved != true) return;
        await _loadPaymentOptions();
        if (_accounts.isEmpty) return;
      }
      // CardEditor는 List<AccountBalance>를 기대 — 시작잔고로 dummy balance 채워서 wrap.
      final accBalances = [
        for (final a in _accounts)
          AccountBalance(
            accountId: a.id,
            name: a.name,
            type: a.type,
            initialBalance: a.initialBalance,
            balance: a.initialBalance,
            active: a.active,
          ),
      ];
      if (!mounted) return;
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
        builder: (_) => CardEditor(accounts: accBalances),
      );
      if (saved == true) await _loadPaymentOptions();
    } else {
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
        builder: (_) => const AccountEditor(),
      );
      if (saved == true) await _loadPaymentOptions();
    }
  }

  Widget _mappingPhase() {
    final m = _mapping!;
    final eff = _effectiveCsv();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_mojibake)
          _warningCard(
              '한글이 깨진 것 같아요. 엑셀에서 "CSV UTF-8"로 다시 저장하면 정확하게 분석돼요.'),
        if (_mojibake) const SizedBox(height: 10),
        AppCard(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.description_outlined,
                      size: 18, color: AppColors.text2),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _fileName ?? '파일',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text),
                    ),
                  ),
                  _ConfidencePill(level: m.confidence),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${eff.rows.length}건의 거래'
                '${m.headerRowIndex > 0 ? ' · 안내 ${m.headerRowIndex}줄은 건너뛸게요' : ''}',
                style: TextStyle(fontSize: 12, color: AppColors.text3),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: AppColors.primaryWeak,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline,
                        size: 16, color: AppColors.primaryStrong),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '아래 컬럼 매칭이 맞는지 한 번 봐주세요. 맞으면 다음으로, 아니면 다른 파일을 올려주세요.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primaryStrong,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _mappingTable(eff.headers, m),
              const SizedBox(height: 14),
              Text('이렇게 읽혔어요',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text3,
                    letterSpacing: 0.3,
                  )),
              const SizedBox(height: 6),
              for (final r in eff.rows.take(3)) _samplePreviewRow(r, m),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _restart,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.text2,
                  side: BorderSide(color: AppColors.line),
                  minimumSize: const Size(0, 44),
                ),
                child: const Text('다른 파일 선택'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: _runClassify,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  textStyle: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('가맹점 분류로 진행'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _mappingTable(List<String> headers, CsvMapping m) {
    Widget row(String label, int? colIdx, {bool required = false}) {
      final colName = colIdx != null && colIdx < headers.length
          ? (headers[colIdx].trim().isEmpty
              ? '컬럼 $colIdx'
              : headers[colIdx])
          : '(없음)';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: 88,
              child: Row(
                children: [
                  Text(label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text2,
                      )),
                  if (required) ...[
                    const SizedBox(width: 4),
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: Text(
                colName,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colIdx == null
                      ? AppColors.text3
                      : AppColors.text,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        children: [
          row('날짜', m.dateCol, required: true),
          row('금액', m.amountCol, required: true),
          row('가맹점', m.merchantCol, required: true),
          row('카드/결제', m.cardCol),
          row('메모', m.memoCol),
        ],
      ),
    );
  }

  Widget _samplePreviewRow(List<String> r, CsvMapping m) {
    final dateRaw = r.length > m.dateCol ? r[m.dateCol] : '';
    final amountRaw = r.length > m.amountCol ? r[m.amountCol] : '';
    final merchantRaw = r.length > m.merchantCol ? r[m.merchantCol] : '';
    final amount = parseAmount(amountRaw, amountSign: m.amountSign);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              normalizeDate(dateRaw, dateFormat: m.dateFormat) ?? dateRaw,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.text3,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Text(
              merchantRaw,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.text,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            amount != null ? '${won(amount)}원' : amountRaw,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _classifyPhase() {
    final rows = _normalized!;
    final dates = rows.map((r) => r.date).toList()..sort();
    final earliest = dates.isNotEmpty ? dates.first : null;
    final latest = dates.isNotEmpty ? dates.last : null;
    final total = rows.fold<int>(0, (s, r) => s + r.amount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _verifySummaryCard(
          earliest: earliest,
          latest: latest,
          count: rows.length,
          total: total,
          merchantCount: _classByMerchant.length,
          skippedCount: _skippedRowIndexes.length,
          excludedByStatusCount: _excludedByStatusCount,
        ),
        const SizedBox(height: 12),
        _paymentSummary(),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '분류 결과',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text2,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 8),
              Divider(color: AppColors.line2, height: 1),
              const SizedBox(height: 8),
              for (final r in rows.take(20)) _classifyRow(r),
              if (rows.length > 20) ...[
                const SizedBox(height: 4),
                Text(
                  '… 외 ${rows.length - 20}건도 같이 등록돼요',
                  style: TextStyle(fontSize: 12, color: AppColors.text3),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed:
                    _importing ? null : () => setState(() => _phase = _Phase.mappingReview),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.text2,
                  side: BorderSide(color: AppColors.line),
                  minimumSize: const Size(0, 44),
                ),
                child: const Text('이전'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: _importing ? null : _import,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  textStyle: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(_importing
                    ? '등록 중…'
                    : '${rows.length}건 등록하기'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _classifyRow(ImportRow r) {
    final cls = r.merchant != null ? _classByMerchant[r.merchant!] : null;
    final major = cls?.major ?? r.majorCategory;
    final sub = cls?.sub;
    final lowConf = cls != null && cls.confidence == 'low';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              r.date.substring(5).replaceAll('-', '/'),
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.text3,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.merchant ?? '(가맹점 없음)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: lowConf
                            ? const Color(0xFFFFF4D6)
                            : AppColors.primaryWeak,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        sub != null ? '$major / $sub' : major,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: lowConf
                              ? const Color(0xFF8A6A00)
                              : AppColors.primaryStrong,
                        ),
                      ),
                    ),
                    if (cls?.isNewMajor == true) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '신규 카테고리',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.text3,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${won(r.amount)}원',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  /// 등록 전 마지막 검토 카드 — 사용자가 카드사 명세서랑 비교할 수 있도록
  /// 기간·건수·합계를 강조. 안 맞으면 "이전" 눌러 매핑 다시 확인 유도.
  Widget _verifySummaryCard({
    required String? earliest,
    required String? latest,
    required int count,
    required int total,
    required int merchantCount,
    required int skippedCount,
    required int excludedByStatusCount,
  }) {
    final periodText = (earliest != null && latest != null)
        ? (earliest == latest
            ? _prettyDate(earliest)
            : '${_prettyDate(earliest)} ~ ${_prettyDate(latest)}')
        : '-';
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.primaryWeak,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_outlined,
                  size: 18, color: AppColors.primaryStrong),
              const SizedBox(width: 6),
              Text(
                '카드사 명세서랑 맞는지 한 번만 확인해주세요',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryStrong,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _summaryRow('기간', periodText),
          _summaryRow('거래 건수', '$count건'
              '${merchantCount > 0 ? ' · 가맹점 $merchantCount곳' : ''}'),
          _summaryRow('총액', '${won(total)}원', emphasize: true),
          if (excludedByStatusCount > 0) ...[
            const SizedBox(height: 6),
            Text(
              '취소·반려된 거래 $excludedByStatusCount건 자동 제외',
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.primaryStrong,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (skippedCount > 0) ...[
            const SizedBox(height: 4),
            Text(
              '읽지 못한 행 $skippedCount건은 자동 스킵',
              style: TextStyle(fontSize: 11.5, color: AppColors.text3),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '카드사 명세서의 합계와 다르면 아래 "이전"을 눌러 매핑(특히 금액 컬럼)을 다시 확인해주세요.',
            style: TextStyle(
              fontSize: 11.5,
              color: AppColors.text2,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.text2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: emphasize ? 16 : 13,
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
                color: AppColors.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _prettyDate(String yyyymmdd) {
    if (yyyymmdd.length != 10) return yyyymmdd;
    return '${yyyymmdd.substring(0, 4)}.${yyyymmdd.substring(5, 7)}.${yyyymmdd.substring(8, 10)}';
  }

  Widget _busyCard(String text) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  fontSize: 13.5,
                  color: AppColors.text2,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline,
              size: 16, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.danger,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _warningCard(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D6),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 16, color: const Color(0xFF8A6A00)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFF8A6A00),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepBar extends StatelessWidget {
  const _StepBar({required this.phase});
  final _Phase phase;

  @override
  Widget build(BuildContext context) {
    final steps = ['파일 선택', '컬럼 매핑', '카테고리 분류'];
    final cur = phase.index;
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i <= cur
                        ? AppColors.primary
                        : AppColors.surface2,
                    shape: BoxShape.circle,
                  ),
                  child: i < cur
                      ? const Icon(Icons.check,
                          size: 14, color: Colors.white)
                      : Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: i == cur
                                ? Colors.white
                                : AppColors.text3,
                          ),
                        ),
                ),
                const SizedBox(height: 4),
                Text(
                  steps[i],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        i == cur ? FontWeight.w700 : FontWeight.w500,
                    color:
                        i <= cur ? AppColors.text : AppColors.text3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ConfidencePill extends StatelessWidget {
  const _ConfidencePill({required this.level});
  final String level;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (level) {
      'high' => ('높음', AppColors.primaryWeak, AppColors.primaryStrong),
      'medium' => ('보통', AppColors.surface2, AppColors.text2),
      _ => ('낮음', const Color(0xFFFFF4D6), const Color(0xFF8A6A00)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        '신뢰도 $label',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

/// 카드/계좌 데이터 0개일 때 inline 추가 안내.
class _MissingDataPrompt extends StatelessWidget {
  const _MissingDataPrompt({required this.isCard, required this.onAdd});
  final bool isCard;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final label = isCard ? '신용카드' : '계좌';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Icon(Icons.add_circle_outline,
              size: 18, color: AppColors.text3),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '등록된 $label이(가) 없어요. 바로 추가하면 돼요.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.text2,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onAdd,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 34),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: Text('$label 추가'),
          ),
        ],
      ),
    );
  }
}

/// dropdown 옆 + 버튼 — 카드/계좌를 그 자리에서 추가.
class _AddInlineBtn extends StatelessWidget {
  const _AddInlineBtn({required this.tooltip, required this.onTap});
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          alignment: Alignment.center,
          child: Tooltip(
            message: tooltip,
            child: Icon(Icons.add, size: 20, color: AppColors.text2),
          ),
        ),
      ),
    );
  }
}

/// AI import 결제수단 토글 — [신용카드] / [내 계좌].
class _PayKindBtn extends StatelessWidget {
  const _PayKindBtn({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final fg = disabled
        ? AppColors.text4
        : (selected ? AppColors.primaryStrong : AppColors.text2);
    final bg = disabled
        ? AppColors.surface2
        : (selected ? AppColors.primaryWeak : AppColors.surface2);
    final border =
        selected && !disabled ? AppColors.primary : AppColors.line;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: border,
              width: selected && !disabled ? 1.2 : 1,
            ),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
