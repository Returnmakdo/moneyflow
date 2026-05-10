import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:go_router/go_router.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../theme.dart';
import '../utils/csv_download_stub.dart'
    if (dart.library.html) '../utils/csv_download_web.dart';
import '../utils/is_mobile_stub.dart'
    if (dart.library.html) '../utils/is_mobile_web.dart';
import '../utils/nav_back.dart';
import '../widgets/common.dart';
import '../widgets/format.dart';

/// 설정 → 데이터 가져오기. CSV 파일을 받아 거래로 일괄 등록.
/// 1) 템플릿 CSV 다운로드 → 2) 채워서 업로드 → 3) 미리보기 → 4) 가져오기.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  List<ImportRow>? _rows;
  String? _fileName;
  List<String> _errors = [];
  bool _importing = false;
  ImportDupPreview _dupPreview =
      const ImportDupPreview(dbDup: 0, csvDup: 0);
  // 'expense' | 'income' — 토글로 결정. 템플릿/안내/파싱 모두 이 값에 분기.
  String _type = 'expense';

  // 양식별 헤더 — '구분' 컬럼 없음. 토글로 어떤 양식인지 결정.
  static const _expenseHeader =
      '날짜,금액,카테고리,가맹점,카드/결제수단,태그,메모,고정비';
  static const _expenseTemplate = '$_expenseHeader\n'
      '2026-05-01,5800,식비/카페,스타벅스,체크카드,카페,,아니오\n'
      '2026-05-01,18500,식비/카페,쿠팡이츠,,배달,점심,아니오\n'
      '2026-05-01,700000,주거,월세,자동이체,월세,,예\n';

  static const _incomeHeader =
      '날짜,금액,카테고리,받은 곳,입금 계좌,태그,메모';
  static const _incomeTemplate = '$_incomeHeader\n'
      '2026-05-25,3500000,월급,회사,신한 입출금,정기,5월분\n'
      '2026-05-10,50000,용돈,부모님,현금,,\n';

  static const _webUrl = 'https://billionaire-chi.vercel.app/settings/import';

  bool get _isIncome => _type == 'income';

  Future<void> _downloadTemplate() async {
    final template = _isIncome ? _incomeTemplate : _expenseTemplate;
    final fileName = _isIncome
        ? '가계부_수입_템플릿.csv'
        : '가계부_지출_템플릿.csv';
    final shared = await triggerCsvDownload(template, fileName);
    if (!mounted) return;
    if (!shared) showToast(context, '템플릿을 다운로드했어요');
  }

  Future<void> _copyWebUrl() async {
    await Clipboard.setData(const ClipboardData(text: _webUrl));
    if (mounted) showToast(context, 'URL을 복사했어요');
  }

  Future<void> _pickFile() async {
    // FileType.any로 모든 파일 보이게 — Drive 등 클라우드 파일은 mime 매핑이
    // 안 돼서 확장자 필터 걸면 안 보이는 경우가 많음.
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final ext = (file.extension ?? '').toLowerCase();
    if (ext != 'csv') {
      if (mounted) showToast(context, 'CSV 파일만 올릴 수 있어요', error: true);
      return;
    }
    final bytes = file.bytes;
    if (bytes == null) {
      if (mounted) showToast(context, '파일을 읽을 수 없어요', error: true);
      return;
    }

    // BOM 제거 + UTF-8 시도, 실패하면 EUC-KR(latin1로 대체) — 한국 카드사 일부.
    String text;
    try {
      text = utf8.decode(_stripBom(bytes));
    } catch (_) {
      text = latin1.decode(bytes);
    }

    final parsed = _parseCsv(text);
    if (!mounted) return;
    setState(() {
      _fileName = file.name;
      _rows = parsed.rows;
      _errors = parsed.errors;
      _dupPreview = const ImportDupPreview(dbDup: 0, csvDup: 0);
    });
    // 중복 카운트 미리 계산 (실패해도 import 흐름은 계속).
    if (parsed.rows.isNotEmpty) {
      try {
        final dup =
            await Api.instance.countDuplicateImportRows(parsed.rows);
        if (mounted) setState(() => _dupPreview = dup);
      } catch (_) {}
    }
  }

  List<int> _stripBom(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return bytes.sublist(3);
    }
    return bytes;
  }

  _ParseResult _parseCsv(String text) {
    final lines = const LineSplitter().convert(text);
    if (lines.isEmpty) {
      return const _ParseResult(rows: [], errors: ['파일이 비어있어요']);
    }
    // 양식 자동 판별 — 헤더 보고 expense / income / 옛 호환 결정.
    // - '구분' 컬럼 → 옛 양식(export 호환), 각 row의 구분 값으로 type
    // - '받은 곳' → income 양식, 모든 row income
    // - 그 외 → expense 양식
    final headerFields =
        _parseCsvLine(lines.first).map((s) => s.trim()).toList();
    final hasKind = headerFields.contains('구분');
    final isIncomeTemplate =
        !hasKind && headerFields.contains('받은 곳');
    final dataLines = lines.skip(1).where((l) => l.trim().isNotEmpty).toList();
    if (dataLines.isEmpty) {
      return const _ParseResult(rows: [], errors: ['데이터 행이 없어요']);
    }

    // 컬럼 인덱스 매핑.
    final int iDate = 0;
    final int? iKind = hasKind ? 1 : null;
    final int iAmount = hasKind ? 2 : 1;
    final int iMajor = hasKind ? 3 : 2;
    final int iMerchant = hasKind ? 4 : 3;
    final int iCard = hasKind ? 5 : 4;
    final int iSub = hasKind ? 6 : 5;
    final int iMemo = hasKind ? 7 : 6;
    // income 양식엔 고정비 컬럼 없음.
    final int? iFixed = isIncomeTemplate ? null : (hasKind ? 8 : 7);

    final rows = <ImportRow>[];
    final errors = <String>[];
    for (var i = 0; i < dataLines.length; i++) {
      final lineNo = i + 2; // 헤더가 1행
      try {
        final fields = _parseCsvLine(dataLines[i]);
        final minLen = hasKind ? 4 : 3;
        if (fields.length < minLen) {
          errors.add('$lineNo행: 컬럼이 부족해요 (날짜·금액·카테고리 필수)');
          continue;
        }
        final date = _normalizeDate(fields[iDate]);
        if (date == null) {
          errors.add('$lineNo행: 날짜 형식이 잘못됐어요 (예: 2026-05-01)');
          continue;
        }
        // type 결정 — 옛 양식은 row별 '구분', 새 양식은 헤더로 결정.
        String type = isIncomeTemplate ? 'income' : 'expense';
        if (iKind != null) {
          final k = _get(fields, iKind).trim();
          if (k == '수입' || k.toLowerCase() == 'income') {
            type = 'income';
          } else if (k == '이체' || k.toLowerCase() == 'transfer') {
            errors.add('$lineNo행: 이체 거래는 아직 지원 안 해요 (지출로 등록됨)');
          }
        }
        final amountStr = _get(fields, iAmount);
        final amount = _parseAmount(amountStr);
        if (amount == null || amount <= 0) {
          errors.add('$lineNo행: 금액이 잘못됐어요 ("$amountStr")');
          continue;
        }
        final major = _get(fields, iMajor).trim();
        if (major.isEmpty) {
          errors.add('$lineNo행: 카테고리는 필수예요');
          continue;
        }
        final merchant = _emptyToNull(_get(fields, iMerchant));
        final card = _emptyToNull(_get(fields, iCard));
        final sub = _emptyToNull(_get(fields, iSub));
        final memo = _emptyToNull(_get(fields, iMemo));
        var isFixed = false;
        if (iFixed != null) {
          final fixedStr = _get(fields, iFixed).trim();
          isFixed = fixedStr == '예' ||
              fixedStr.toLowerCase() == 'y' ||
              fixedStr.toLowerCase() == 'true' ||
              fixedStr == '1';
        }
        // 수입 거래엔 고정비 적용 안 함 (정기수입은 다음 plan).
        if (type == 'income') isFixed = false;

        rows.add(ImportRow(
          date: date,
          card: card,
          merchant: merchant,
          amount: amount,
          majorCategory: major,
          subCategory: sub,
          memo: memo,
          isFixed: isFixed,
          type: type,
        ));
      } catch (e) {
        errors.add('$lineNo행: $e');
      }
    }
    return _ParseResult(rows: rows, errors: errors);
  }

  String _get(List<String> fields, int i) =>
      i < fields.length ? fields[i] : '';

  String? _emptyToNull(String? v) {
    final t = v?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }

  /// 큰따옴표 escape 지원하는 CSV 한 줄 파서.
  List<String> _parseCsvLine(String line) {
    final result = <String>[];
    final buf = StringBuffer();
    var inQuote = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (inQuote) {
        if (ch == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            buf.write('"');
            i++;
          } else {
            inQuote = false;
          }
        } else {
          buf.write(ch);
        }
      } else {
        if (ch == ',') {
          result.add(buf.toString());
          buf.clear();
        } else if (ch == '"') {
          inQuote = true;
        } else {
          buf.write(ch);
        }
      }
    }
    result.add(buf.toString());
    return result;
  }

  /// 미리보기 노란 박스 메시지 — DB 중복 vs CSV 안 중복 분리.
  String _dupMessage(int total) {
    final db = _dupPreview.dbDup;
    final csv = _dupPreview.csvDup;
    final inserted = total - db - csv;
    final parts = <String>[];
    if (db > 0) parts.add('이미 등록된 $db건');
    if (csv > 0) parts.add('파일 안 중복 $csv건');
    final skip = parts.join(' + ');
    if (inserted <= 0) {
      return '$skip은 건너뛸게요. 새로 등록할 거래가 없어요.';
    }
    return '$skip은 건너뛸게요. 나머지 $inserted건만 새로 등록돼요.';
  }

  /// "2026-05-01", "2026/5/1", "2026.05.01" 등 → "2026-05-01".
  String? _normalizeDate(String s) {
    final cleaned = s.trim().replaceAll(RegExp(r'[./]'), '-');
    final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(cleaned);
    if (m == null) return null;
    final y = m.group(1)!;
    final mo = m.group(2)!.padLeft(2, '0');
    final d = m.group(3)!.padLeft(2, '0');
    return '$y-$mo-$d';
  }

  /// "5,800원", "5800", "5,800" 등 → 5800.
  int? _parseAmount(String s) {
    final cleaned = s.replaceAll(RegExp(r'[,\s원]'), '');
    return int.tryParse(cleaned);
  }

  Future<void> _import() async {
    final rows = _rows;
    if (rows == null || rows.isEmpty) return;
    setState(() => _importing = true);
    try {
      final result = await Api.instance.importTransactions(rows);
      if (!mounted) return;
      final n = result.inserted;
      final dup = result.totalSkipped;
      final msg = n == 0 && dup > 0
          ? '모두 건너뛰었어요 ($dup건이 이미 등록되어 있거나 명세서 안 중복)'
          : (dup > 0
              ? '$n건 등록 · 건너뛴 $dup건'
              : '$n건을 등록했어요');
      showToast(context, msg);
      setState(() {
        _rows = null;
        _fileName = null;
        _errors = [];
      });
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _importing = false);
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
          '데이터 가져오기',
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
            _aiImportCard(),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                children: [
                  Expanded(child: Divider(color: AppColors.line2, height: 1)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      '또는 우리 양식 CSV로 직접',
                      style:
                          TextStyle(fontSize: 11.5, color: AppColors.text3),
                    ),
                  ),
                  Expanded(child: Divider(color: AppColors.line2, height: 1)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // 어떤 거래를 가져올지 먼저 선택 — 템플릿/안내가 토글 따라 분기.
            _typeToggle(),
            const SizedBox(height: 12),
            _stepCard(
              step: '1',
              title: _isIncome ? '수입 템플릿 받기' : '지출 템플릿 받기',
              body: !isMobileEnv()
                  ? '빈 양식 + 예시가 들어있는 CSV 파일을 받으세요. 엑셀에서 열어 거래 내역을 채우면 돼요.'
                  : '템플릿 CSV를 다른 앱(메일·카카오톡·구글드라이브 등)으로 공유해서 PC에서 받을 수 있어요. 또는 아래 PC 웹 URL로 직접 받으세요.',
              action: OutlinedButton.icon(
                onPressed: _downloadTemplate,
                icon: Icon(
                  !isMobileEnv() ? Icons.download : Icons.ios_share,
                  size: 18,
                ),
                label: Text(!isMobileEnv() ? '템플릿 받기' : '템플릿 공유'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(
                      color: AppColors.primaryWeak, width: 1.5),
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            ),
            if (isMobileEnv()) ...[
              const SizedBox(height: 8),
              _webUrlCard(),
            ],
            const SizedBox(height: 12),
            _stepCard(
              step: '2',
              title: '파일 선택',
              body: '채운 CSV 파일을 선택하세요. '
                  'UTF-8로 저장하면 한글이 안 깨져요.',
              action: FilledButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('파일 선택'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            ),
            if (_rows != null) ...[
              const SizedBox(height: 12),
              _previewCard(),
            ],
            const SizedBox(height: 18),
            _formatGuide(),
          ],
        ),
      ),
    );
  }

  Widget _typeToggle() {
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
              // 양식이 바뀌니 미리보기 초기화.
              _rows = null;
              _fileName = null;
              _errors = const [];
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
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
                  fontSize: 14,
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
          tab('expense', '지출 가져오기'),
          tab('income', '수입 가져오기'),
        ],
      ),
    );
  }

  Widget _aiImportCard() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.go('/settings/import/ai'),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            color: AppColors.primaryWeak,
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_awesome,
                    size: 20, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'AI 카드 명세서 정리',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Pill(label: 'BETA'),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '이용내역만 올리면 자동 분류',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.text2,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 22, color: AppColors.primaryStrong),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepCard({
    required String step,
    required String title,
    required String body,
    Widget? action,
  }) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  step,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.text2,
              height: 1.55,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: action),
          ],
        ],
      ),
    );
  }

  Widget _previewCard() {
    final rows = _rows!;
    final hasErrors = _errors.isNotEmpty;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.description_outlined,
                  size: 18, color: AppColors.text2),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _fileName ?? '미리보기',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '읽은 거래 ${rows.length}건${hasErrors ? ' · 건너뛴 행 ${_errors.length}개' : ''}',
            style: TextStyle(fontSize: 12.5, color: AppColors.text3),
          ),
          if (_dupPreview.total > 0) ...[
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
                      _dupMessage(rows.length),
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
          ],
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(color: AppColors.line2, height: 1),
            const SizedBox(height: 8),
            // 첫 5건만 미리보기
            for (final r in rows.take(5)) _previewRow(r),
            if (rows.length > 5) ...[
              const SizedBox(height: 4),
              Text(
                '… 외 ${rows.length - 5}건',
                style: TextStyle(
                    fontSize: 12, color: AppColors.text3),
              ),
            ],
          ],
          if (hasErrors) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final e in _errors.take(5))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '· $e',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.danger,
                          height: 1.5,
                        ),
                      ),
                    ),
                  if (_errors.length > 5)
                    Text(
                      '… 외 ${_errors.length - 5}건',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.danger),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: (rows.isEmpty ||
                    _importing ||
                    rows.length - _dupPreview.total <= 0)
                ? null
                : _import,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
              textStyle: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(_importing
                ? '등록 중...'
                : (rows.length - _dupPreview.total <= 0
                    ? '등록할 거래 없음'
                    : '${rows.length - _dupPreview.total}건 등록하기')),
          ),
        ],
      ),
    );
  }

  Widget _previewRow(ImportRow r) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            r.date,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.text3,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              r.merchant ?? '(가맹점 없음)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.text,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            '${won(r.amount)}원',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _webUrlCard() {
    return Container(
      padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
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
              SizedBox(width: 6),
              Text(
                'PC 웹에서 작업하기를 추천해요',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryStrong,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '모바일에서도 가능하지만, 엑셀로 거래 정리하는 건 PC에서 훨씬 편해요. 아래 URL을 복사해서 PC 브라우저에 붙여넣으세요.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.text2,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _copyWebUrl,
              icon: const Icon(Icons.content_copy, size: 14),
              label: const Text('URL 복사'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryStrong,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formatGuide() {
    return AppCard(
      padding: EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline,
                  size: 16, color: AppColors.primaryStrong),
              SizedBox(width: 8),
              Text(
                'CSV 양식 안내',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '필수',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.danger,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          _guideRow('날짜', 'YYYY-MM-DD (예: 2026-05-01)', required: true),
          _guideRow('금액', '숫자, 콤마/원 OK', required: true),
          _guideRow(
            '카테고리',
            _isIncome
                ? '월급·이자 등. 새 카테고리면 자동 추가됨'
                : '새 카테고리면 자동 추가됨',
            required: true,
          ),
          const SizedBox(height: 14),
          Text(
            '선택',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.text3,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          if (_isIncome) ...[
            _guideRow('받은 곳', '거래처 이름 (예: 회사, 부모님)'),
            _guideRow('입금 계좌', '메모용. 예: 신한 입출금'),
          ] else ...[
            _guideRow('가맹점', '거래처 이름'),
            _guideRow('카드/결제수단', '예: 체크카드, 자동이체'),
          ],
          _guideRow('태그', '카테고리 하위, 새 태그면 자동 추가됨'),
          _guideRow('메모', '자유 텍스트'),
          if (!_isIncome)
            _guideRow('고정비', '"예" 또는 "아니오" (기본 아니오)'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              '카드사 명세서 → 엑셀 → 템플릿 양식대로 정리 → 저장(CSV UTF-8) → 가져오기',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.text3,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _guideRow(String name, String desc, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (required)
            Container(
              margin: const EdgeInsets.only(top: 1, right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '필수',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.danger,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          Text(
            name,
            style: TextStyle(
              fontSize: 13,
              fontWeight: required ? FontWeight.w700 : FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              desc,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.text3,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ParseResult {
  const _ParseResult({required this.rows, required this.errors});
  final List<ImportRow> rows;
  final List<String> errors;
}
