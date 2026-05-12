import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../theme.dart';
import '../utils/csv_parse.dart';
import '../utils/nav_back.dart';
import '../widgets/amount_field.dart';
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
  ImportDupPreview _dupPreview =
      const ImportDupPreview(dbDup: 0, csvDup: 0);

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
        // 신용카드 전용 — 카드가 있으면 첫 카드 선택, 0개면 _filePhase에서 추가 유도.
        // _accounts는 카드 추가(연동 계좌 선택) 시에만 사용.
        _payKind = 'card';
        if (_cards.isEmpty) {
          _selectedCardId = null;
        } else if (!_cards.any((c) => c.id == _selectedCardId)) {
          _selectedCardId = _cards.first.id;
        }
      });
    } catch (_) {/* 무시 */}
  }

  CreditCard? _selectedCardOrNull() {
    if (_selectedCardId == null) return null;
    for (final c in _cards) {
      if (c.id == _selectedCardId) return c;
    }
    return null;
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
    // FileType.any로 모든 파일 보이게 — Drive 등 클라우드 파일은 mime 매핑이
    // 안 돼서 confirm 후에야 확장자가 드러나는 경우가 많음. 호환성 우선.
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final ext = (file.extension ?? '').toLowerCase();
    if (!['csv', 'xlsx', 'xls'].contains(ext)) {
      setState(() => _error = 'CSV·XLS·XLSX 파일만 올릴 수 있어요.');
      return;
    }
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() => _error = '파일을 읽을 수 없어요.');
      return;
    }

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
            _busyText = '시트를 변환하고 있어요…';
          });
          final r = await Api.instance.parseSheetFile(bytes);
          parsed = CsvFile(headers: r.headers, rows: r.rows);
        }
      } else if (ext == 'xls') {
        // .xls(BIFF) 구버전은 무조건 서버 변환.
        setState(() {
          _busy = true;
          _busyText = '.xls를 변환하고 있어요…';
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
      _busyText = '컬럼을 분석하고 있어요…';
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
      _busyText = '가맹점을 분류하고 있어요…';
      _error = null;
      _normalized = rows;
      _skippedRowIndexes = skipped;
      _excludedByStatusCount = excludedByStatus;
    });

    try {
      final results = await Api.instance.getCsvClassification(
        merchants: merchants.toList(),
      );
      // 중복 카운트 미리 계산 — 사용자가 등록 전에 알 수 있게.
      ImportDupPreview dup =
          const ImportDupPreview(dbDup: 0, csvDup: 0);
      try {
        final selectedCardId = _selectedCardId;
        if (selectedCardId != null) {
          final previewRows = rows
              .map((r) => ImportRow(
                    date: r.date,
                    amount: r.amount,
                    majorCategory: r.majorCategory,
                    subCategory: r.subCategory,
                    card: r.card,
                    merchant: r.merchant,
                    memo: r.memo,
                    isFixed: false,
                    cardId: selectedCardId,
                    accountId: null,
                    type: 'expense',
                  ))
              .toList();
          dup =
              await Api.instance.countDuplicateImportRows(previewRows);
        }
      } catch (_) {/* dup count 실패해도 import 흐름은 계속 */}
      if (!mounted) return;
      setState(() {
        _classByMerchant = {for (final c in results) c.merchant: c};
        _phase = _Phase.classifyReview;
        _dupPreview = dup;
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

  /// 미리보기 노란 박스 메시지. DB 중복 vs CSV 안 중복 분리해서 안내.
  String _dupPreviewMessage(int total) {
    final db = _dupPreview.dbDup;
    final csv = _dupPreview.csvDup;
    final inserted = total - db - csv;
    final parts = <String>[];
    if (db > 0) parts.add('이미 등록된 $db건');
    if (csv > 0) parts.add('명세서 안 중복 $csv건');
    final skip = parts.join(' + ');
    if (inserted <= 0) {
      return '$skip은 건너뛸게요. 새로 등록할 거래가 없어요.';
    }
    return '$skip은 건너뛸게요. 나머지 $inserted건만 새로 등록돼요.';
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
    // allowToggle 인자는 과거 [신용카드/내 계좌] 토글 잔재. 신용카드 전용으로
    // 좁혀지면서 의미 없어졌고, 호환을 위해 시그니처만 유지.
    final hasCards = _cards.isNotEmpty;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '어느 카드의 명세서예요?',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.text2,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '선택한 카드로 모든 거래가 등록돼요.',
            style: TextStyle(fontSize: 12, color: AppColors.text3),
          ),
          const SizedBox(height: 12),
          if (!hasCards)
            _MissingDataPrompt(
              isCard: true,
              onAdd: () => _addInline(isCard: true),
            )
          else
            Row(
              children: [
                Expanded(
                  child: AppDropdown<int>(
                    label: '카드',
                    value: _cards.any((c) => c.id == _selectedCardId)
                        ? _selectedCardId
                        : null,
                    items: [
                      for (final c in _cards)
                        AppDropdownItem(value: c.id, label: c.name),
                    ],
                    onChanged: (v) => setState(() => _selectedCardId = v),
                  ),
                ),
                const SizedBox(width: 8),
                _AddInlineBtn(
                  tooltip: '카드 추가',
                  onTap: () => _addInline(isCard: true),
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
    final card = _selectedCardOrNull();
    if (card == null) {
      showToast(context, '카드를 선택해주세요', error: true);
      return;
    }
    if (card.statementCloseDay == null) {
      // 진입 단계에서 차단되지만 안전망.
      showToast(context, '카드 사용 마감일이 비어있어요', error: true);
      return;
    }

    // 분류 결과 적용한 finalRows.
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
        cardId: card.id,
        accountId: null,
      ));
    }

    // 옛 사이클 식별.
    final today = DateTime.now();
    final pastCycles = _identifyPastCycles(
      rows: finalRows,
      card: card,
      today: today,
    );

    // 옛 사이클이 있으면 자동 정리 다이얼로그.
    _PastCycleResult? settleResult;
    AccountBalance? linkedBalance;
    final alreadyAutoSettled = card.autoSettledAt != null;
    // 옛 사이클이 있어도 이미 자동 정리된 카드는 다이얼로그 안 띄움 — 시작잔고
      // 누적 보정 방지. 사용 거래만 추가 등록 (사이클이 새로 늘었을 수도).
    if (pastCycles.isNotEmpty && !alreadyAutoSettled) {
      try {
        final snap = await Api.instance.getAssetSnapshot();
        for (final a in snap.accounts) {
          if (a.accountId == card.linkedAccountId) {
            linkedBalance = a;
            break;
          }
        }
      } catch (e) {
        if (mounted) showToast(context, _friendlyError(e), error: true);
        return;
      }
      if (!mounted) return;
      if (linkedBalance == null) {
        showToast(context, '카드 연동 계좌 정보를 찾을 수 없어요', error: true);
        return;
      }
      settleResult = await _showPastCycleDialog(
        card: card,
        linkedAccount: linkedBalance,
        cycles: pastCycles,
      );
      if (settleResult == null) return; // 사용자가 다이얼로그 취소.
    }

    setState(() => _importing = true);
    try {
      // 1) 카드 사용 거래 일괄 등록. csvDedupe=false — 카드사 명세서는 같은 날
      // 같은 가맹점·금액으로 시간만 다른 *진짜 거래*가 흔히 있어서(예: 같은 매장
      // 두 번 결제) dedupe key가 합쳐버리면 안 됨. DB 중복 체크(dbDup)는 유지.
      final result = await Api.instance.importTransactions(
        finalRows,
        csvDedupe: false,
      );
      final n = result.inserted;
      final dupSkipped = result.totalSkipped;
      // 토스트용 dup 설명 — DB 중복 / CSV 안 중복 분리.
      final dupParts = <String>[];
      if (result.dbDup > 0) dupParts.add('이미 등록된 ${result.dbDup}건');
      if (result.csvDup > 0) dupParts.add('명세서 안 중복 ${result.csvDup}건');
      final dupDesc = dupParts.join(' + ');

      // 2) 옛 사이클 자동 결제 처리.
      int settledCount = 0;
      int settledSum = 0;
      if (settleResult?.autoSettle == true && pastCycles.isNotEmpty) {
        for (final cycle in pastCycles) {
          await Api.instance.createTransaction(
            date: cycle.paymentDate,
            amount: cycle.totalAmount,
            majorCategory: '카드결제',
            merchant: card.name,
            memo: 'CSV 가져오기 자동 정리',
            fromAccountId: card.linkedAccountId,
            cardId: card.id,
            type: 'card_payment',
          );
          settledCount++;
          settledSum += cycle.totalAmount;
        }

        // 3) 연동 통장 시작잔고 보정.
        // 사용자가 만족시키길 원함: import 후 통장 잔고 = 사용자 입력값
        // 새 시작잔고 = 기존 시작잔고 + (사용자 입력 - 기존 잔고) + 옛 결제 합
        final input = settleResult!.currentBalance!;
        final newInitial = linkedBalance!.initialBalance +
            (input - linkedBalance.balance) +
            settledSum;
        await Api.instance.updateAccount(
          linkedBalance.accountId,
          initialBalance: newInitial,
        );

        // 4) 카드에 자동 정리 마킹 — 같은 카드 다시 import해도 누적 안 됨.
        await Api.instance.markCardAutoSettled(card.id);
      }

      if (!mounted) return;
      final dupSuffix =
          dupSkipped > 0 ? ' · $dupDesc은 건너뛰었어요' : '';
      final msg = settledCount > 0
          ? '거래 $n건과 옛 결제 $settledCount건을 등록했어요. 통장 시작잔고도 맞춰뒀어요$dupSuffix'
          : (n == 0 && dupSkipped > 0
              ? '모두 건너뛰었어요 ($dupDesc)'
              : '거래 $n건이 등록됐어요. 대시보드에서 확인해보세요$dupSuffix');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 4),
        ));
      context.go('/dashboard');
    } catch (e) {
      if (mounted) showToast(context, _friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// 옛 사이클 자동 정리 다이얼로그.
  /// 결과: null=닫기(import 취소), autoSettle=false=사용만 등록, autoSettle=true=자동 정리.
  Future<_PastCycleResult?> _showPastCycleDialog({
    required CreditCard card,
    required AccountBalance linkedAccount,
    required List<_PastCycle> cycles,
  }) async {
    // 현재 잔고가 있으면 미리 채워둠. 사용자가 그대로 두거나 수정 가능.
    final ctrl = TextEditingController(
      text: linkedAccount.balance > 0 ? won(linkedAccount.balance) : '',
    );
    String error = '';
    bool busy = false;

    final totalSum = cycles.fold<int>(0, (s, c) => s + c.totalAmount);

    return showDialog<_PastCycleResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            void submit() {
              final raw = ctrl.text.replaceAll(RegExp(r'[,\s원]'), '');
              final v = int.tryParse(raw);
              if (v == null || v < 0) {
                setLocal(() => error = '숫자로 입력해주세요');
                return;
              }
              setLocal(() => busy = true);
              Navigator.of(ctx).pop(
                _PastCycleResult(autoSettle: true, currentBalance: v),
              );
            }

            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
              contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              title: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '옛 결제까지 등록해야\n자산이 정확해요',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    color: AppColors.text3,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    tooltip: '닫기',
                    onPressed:
                        busy ? null : () => Navigator.of(ctx).pop(null),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 1) 왜 필요한지 — 먼저 보여줌.
                    Text(
                      '카드 사용만 등록하면 옛 결제일에 통장에서 빠졌어야 할 돈이 그대로 남아 있어요. '
                      '결제 거래도 함께 만들면 자산이 깔끔하게 맞아 떨어져요.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.text2,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 14),
                    // 2) 정리할 사이클 목록.
                    Text(
                      '정리할 사이클 ${cycles.length}개',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text3,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final c in cycles)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Text(
                                    '${c.paymentDate} 결제',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.text2,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ],
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${won(c.totalAmount)}원',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.text,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 4),
                          Divider(color: AppColors.line2, height: 8),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                '합계',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.text,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${won(totalSum)}원',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primaryStrong,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 3) 잔고 입력 — 왜 필요한지 짧게 + 입력.
                    Text(
                      '지금 ${linkedAccount.name}(통장)에 얼마 들어있나요?',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      linkedAccount.balance > 0
                          ? '이미 등록된 잔고를 미리 채워뒀어요. 맞으면 그대로 두시고, 다르면 수정해주세요.'
                          : '옛 결제만큼 통장에서 빠지면 시작잔고를 그 시점 기준으로 자동 보정해드릴게요.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.text3,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    AmountField(
                      controller: ctrl,
                      label: '${linkedAccount.name}(통장) 현재 잔고',
                    ),
                    if (error.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        error,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy
                      ? null
                      : () => Navigator.of(ctx).pop(
                            const _PastCycleResult(autoSettle: false),
                          ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.text2,
                  ),
                  child: const Text('사용만 등록'),
                ),
                FilledButton(
                  onPressed: busy ? null : submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: const Text('자동 정리'),
                ),
              ],
            );
          },
        );
      },
    );
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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                'AI 카드 명세서 정리',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            const Pill(label: 'BETA'),
          ],
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
    final selected = _selectedCardOrNull();
    final missingCloseDay =
        selected != null && selected.statementCloseDay == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _paymentSelector(allowToggle: false),
        if (missingCloseDay) ...[
          const SizedBox(height: 12),
          _missingCloseDayCard(selected),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: ready ? _pickFile : null,
          icon: const Icon(Icons.folder_open, size: 20),
          label: Text(_pickButtonLabel(ready, missingCloseDay)),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 56),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _helpExpansion(),
      ],
    );
  }

  /// 부가 안내(지원 파일·한글 인코딩 등)는 평소엔 숨기고 펼쳐서 보기.
  Widget _helpExpansion() {
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 6),
        childrenPadding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
        iconColor: AppColors.text3,
        collapsedIconColor: AppColors.text3,
        title: Text(
          '어떤 파일을 올리면 돼요?',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.text3,
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '·  카드사에서 받은 이용내역(.csv·.xls·.xlsx)을 그대로 올리면 돼요\n'
              '·  컬럼 매핑·카테고리 분류는 AI가 추정해서 미리보기로 보여드려요\n'
              '·  한글이 깨져 보이면 엑셀에서 "CSV UTF-8"로 다시 저장해주세요',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.text3,
                height: 1.65,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isPaymentReady() {
    final c = _selectedCardOrNull();
    if (c == null) return false;
    // 사용 마감일 없으면 결제 사이클 구분 못 해서 자산 꼬일 수 있음 — 차단.
    return c.statementCloseDay != null;
  }

  String _pickButtonLabel(bool ready, bool missingCloseDay) {
    if (ready) return '명세서 파일 선택';
    if (_cards.isEmpty) return '먼저 신용카드를 추가해주세요';
    if (missingCloseDay) return '먼저 사용 마감일을 등록해주세요';
    return '먼저 카드를 골라주세요';
  }

  /// 선택된 카드의 사용 마감일이 비어있을 때 — 등록 유도 카드.
  /// 마감일 없이 명세서를 등록하면 이번 달/다음 달 결제 사이클을 구분 못 해서
  /// 자산이 꼬일 수 있어 막아둠.
  Widget _missingCloseDayCard(CreditCard card) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 18, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${card.name}의 사용 마감일이 비어있어요',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '마감일이 없으면 이번 달/다음 달 결제 사이클을 구분 못 해서 자산이 꼬일 수 있어요. '
            '카드 명세서 첫 페이지에 적힌 사용 마감일을 등록해주세요.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.text2,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _editCard(card),
            icon: const Icon(Icons.edit_calendar_outlined, size: 16),
            label: const Text('마감일 등록하기'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
          ),
        ],
      ),
    );
  }

  /// 선택된 카드를 CardEditor로 띄워서 수정 (주로 마감일 입력용).
  Future<void> _editCard(CreditCard card) async {
    if (_accounts.isEmpty) {
      // 카드 등록되어 있는데 계좌 없는 케이스는 사실상 X. 안전망.
      showToast(context, '연동 계좌 정보를 불러올 수 없어요', error: true);
      return;
    }
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
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl),
        ),
      ),
      builder: (_) => CardEditor(existing: card, accounts: accBalances),
    );
    if (saved == true) await _loadPaymentOptions();
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
      final prevIds = _cards.map((c) => c.id).toSet();
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
      if (saved == true) {
        await _loadPaymentOptions();
        // 새로 추가된 카드를 자동 선택.
        final newCard = _cards.where((c) => !prevIds.contains(c.id));
        if (newCard.isNotEmpty) {
          setState(() => _selectedCardId = newCard.first.id);
        }
      }
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
    // 카드 명세서가 아니라고 판단된 양식이면(통장 거래내역 등) 차단 화면.
    if (m.unsupportedKind == 'bank') return _unsupportedBankPhase();
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
                child: const Text('다른 파일'),
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
                child: const Text('가맹점 분류'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 통장 거래내역 등 카드 명세서가 아닌 양식이 들어왔을 때.
  /// 자동 분류가 위험한 이유 + 대안 가이드 + 다시 파일 선택 버튼.
  Widget _unsupportedBankPhase() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
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
                      color: const Color(0xFFFFF1F2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.account_balance_outlined,
                        size: 18, color: AppColors.danger),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '통장 거래내역은 AI 정리에서 빼뒀어요',
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
                'AI CSV 정리는 신용/체크카드 명세서 전용이에요. '
                '통장 거래내역은 자동으로 정리하기 어려운 함정이 많아서요.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.text2,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 14),
              _bullet('A 통장에서 B 통장으로 옮긴 돈이 지출+수입 양쪽으로 잡혀요'),
              _bullet('카드 결제대금이 이미 카드 명세서로 들어간 거랑 겹쳐서 두 번 빠져요'),
              _bullet('친구한테 보낸 돈 / 받은 돈을 자동으로 구분하기 어려워요'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: AppColors.primaryWeak,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb_outline,
                            size: 16, color: AppColors.primaryStrong),
                        const SizedBox(width: 6),
                        Text(
                          '이렇게 해보세요',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryStrong,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _howRow(
                      '카드 사용은',
                      '카드사 명세서를 여기에 그대로 올려주세요',
                    ),
                    _howRow(
                      '카드 결제대금은',
                      '자산 탭의 결제일 안내에서 등록하면 통장도 같이 처리돼요',
                    ),
                    _howRow(
                      '월급은',
                      '설정 → 정기 거래에 등록하면 매달 자동 입금 처리',
                    ),
                    _howRow(
                      '통장 시작 잔액은',
                      '자산 탭에서 계좌 시작잔고로 직접 입력',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
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
                      child: const Text('다른 파일'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () => goBackOr(context, '/settings/import'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        textStyle: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('확인했어요'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 8),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.text3,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.text2,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _howRow(String label, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryStrong,
              ),
            ),
          ),
          Expanded(
            child: Text(
              desc,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.text,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
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
        if (_dupPreview.total > 0) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4D6),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    size: 16, color: const Color(0xFF8A6A00)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _dupPreviewMessage(rows.length),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8A6A00),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
                onPressed:
                    (_importing || rows.length - _dupPreview.total <= 0)
                        ? null
                        : _import,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  textStyle: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(_importing
                    ? '등록 중…'
                    : (rows.length - _dupPreview.total <= 0
                        ? '등록할 거래 없음'
                        : '${rows.length - _dupPreview.total}건 등록하기')),
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
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

/// 카드 데이터 0개일 때 inline 추가 안내.
class _MissingDataPrompt extends StatelessWidget {
  const _MissingDataPrompt({required this.isCard, required this.onAdd});
  // isCard 인자는 과거 [신용카드/내 계좌] 토글 잔재. 신용카드 전용으로
  // 좁혀지면서 항상 true.
  final bool isCard;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
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
              '등록된 신용카드가 없어요',
              style: TextStyle(
                fontSize: 13,
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
            child: const Text('카드 추가'),
          ),
        ],
      ),
    );
  }
}

/// 카드 마감일 기준 사이클 정보. 결제일이 오늘 이전이면 옛 사이클로 분류.
class _PastCycle {
  final String paymentDate; // YYYY-MM-DD
  final int totalAmount; // 그 사이클 사용 합계
  final List<ImportRow> rows; // 그 사이클 사용 거래들 (참고)
  const _PastCycle({
    required this.paymentDate,
    required this.totalAmount,
    required this.rows,
  });
}

/// 옛 사이클 다이얼로그 결과.
class _PastCycleResult {
  final bool autoSettle; // true면 옛 결제 거래 + 시작잔고 자동 보정
  final int? currentBalance; // autoSettle=true일 때 사용자가 입력한 통장 잔고
  const _PastCycleResult({required this.autoSettle, this.currentBalance});
}

/// 사용일이 어느 결제일에 청구될지 계산.
/// - 사용일이 그 달 마감일 이하 → 그 달 결제일
/// - 마감일 초과 → 다음 달 결제일
/// - 결제일이 마감일보다 빠르거나 같으면 (paymentDay ≤ closeDay) 결제가 한 달 더
///   늦어지는 카드 — 추가로 한 달 밀어 처리. 예) 결제 9·마감 20 → 4/15 사용분은
///   5/9가 아니라 6/9 결제 사이클.
/// - 마감일/결제일이 그 달 말일보다 크면 말일로 클램프 (31일 결제일인 2월 등)
DateTime _paymentDateForUsage({
  required DateTime usageDate,
  required int closeDay,
  required int paymentDay,
}) {
  final lastDayOfUsageMonth =
      DateTime(usageDate.year, usageDate.month + 1, 0).day;
  final effectiveCloseDay =
      closeDay > lastDayOfUsageMonth ? lastDayOfUsageMonth : closeDay;

  int year = usageDate.year;
  int month = usageDate.month;
  if (usageDate.day > effectiveCloseDay) {
    month += 1;
  }
  // 결제일이 마감일보다 같거나 빠른 카드는 한 달 더 늦게 결제됨.
  if (paymentDay <= closeDay) {
    month += 1;
  }
  while (month > 12) {
    year += 1;
    month -= 12;
  }
  final lastDayOfPaymentMonth = DateTime(year, month + 1, 0).day;
  final effectivePaymentDay =
      paymentDay > lastDayOfPaymentMonth ? lastDayOfPaymentMonth : paymentDay;
  return DateTime(year, month, effectivePaymentDay);
}

/// import row들을 카드 마감일 기준으로 사이클별로 묶고,
/// 결제일이 오늘 이전인 옛 사이클만 반환. 결제일 오름차순.
List<_PastCycle> _identifyPastCycles({
  required List<ImportRow> rows,
  required CreditCard card,
  required DateTime today,
}) {
  if (card.statementCloseDay == null) return [];
  final closeDay = card.statementCloseDay!;
  final paymentDay = card.paymentDay;

  final groups = <String, List<ImportRow>>{};
  final paymentDateByKey = <String, DateTime>{};

  for (final r in rows) {
    final usageDate = DateTime.tryParse(r.date);
    if (usageDate == null) continue;
    final pDate = _paymentDateForUsage(
      usageDate: usageDate,
      closeDay: closeDay,
      paymentDay: paymentDay,
    );
    final key = '${pDate.year}-'
        '${pDate.month.toString().padLeft(2, '0')}-'
        '${pDate.day.toString().padLeft(2, '0')}';
    groups.putIfAbsent(key, () => []).add(r);
    paymentDateByKey[key] = pDate;
  }

  final result = <_PastCycle>[];
  final todayDate = DateTime(today.year, today.month, today.day);
  for (final entry in groups.entries) {
    final pDate = paymentDateByKey[entry.key]!;
    if (pDate.isBefore(todayDate)) {
      final total = entry.value.fold<int>(0, (s, r) => s + r.amount);
      result.add(_PastCycle(
        paymentDate: entry.key,
        totalAmount: total,
        rows: entry.value,
      ));
    }
  }
  result.sort((a, b) => a.paymentDate.compareTo(b.paymentDate));
  return result;
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

