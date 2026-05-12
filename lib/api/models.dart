// 가계부 데이터 모델 — public/js/api.js 1:1 매핑.
// JSON 키는 Postgres snake_case, Dart 필드는 lowerCamelCase.

/// 계좌(자산) 종류. DB CHECK constraint와 1:1.
/// 신용카드는 계좌가 아닌 별도 entity(cards 테이블, 추후 도입)로 처리.
enum AccountType { checking, cash, savings, investment, other }

AccountType _accountTypeFrom(String? s) {
  if (s == null) return AccountType.other;
  for (final t in AccountType.values) {
    if (t.name == s) return t;
  }
  return AccountType.other;
}

/// 신용카드 entity. 계좌(자산)과 분리 — 사용 시점엔 자산 안 빠지고
/// 결제일에 연동 입출금 계좌(linkedAccountId)에서 한 번에 차감됨.
/// importTransactions 결과.
/// - inserted: 실제 등록된 건수
/// - dbDup: 기존 DB에 같은 거래가 있어서 skip된 건수
/// - csvDup: 명세서 안에 같은 키가 두 번 이상 있어서 한 번만 등록 후 skip된 건수
class ImportResult {
  final int inserted;
  final int dbDup;
  final int csvDup;
  const ImportResult({
    required this.inserted,
    required this.dbDup,
    required this.csvDup,
  });

  int get totalSkipped => dbDup + csvDup;
}

/// import 미리보기 결과 — 등록 전 dedupe 카운트만 검사.
class ImportDupPreview {
  final int dbDup;
  final int csvDup;
  const ImportDupPreview({required this.dbDup, required this.csvDup});
  int get total => dbDup + csvDup;
}

class CreditCard {
  final int id;
  final String name;
  final int paymentDay; // 매월 결제일 1~31
  final int linkedAccountId;
  final int? statementCloseDay; // 사용 마감일 (모르면 null)
  final int sortOrder;
  final bool active;
  /// AI import 옛 사이클 자동 정리가 한 번이라도 적용된 시각.
  /// 같은 카드에 대해 다시 자동 정리되면 시작잔고가 누적 보정돼 자산이 깨짐 —
  /// 이 값이 있으면 다이얼로그에서 자동 정리 옵션을 막음.
  final DateTime? autoSettledAt;

  const CreditCard({
    required this.id,
    required this.name,
    required this.paymentDay,
    required this.linkedAccountId,
    this.statementCloseDay,
    this.sortOrder = 0,
    this.active = true,
    this.autoSettledAt,
  });

  factory CreditCard.fromJson(Map<String, dynamic> j) => CreditCard(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String,
        paymentDay: (j['payment_day'] as num).toInt(),
        linkedAccountId: (j['linked_account_id'] as num).toInt(),
        statementCloseDay:
            (j['statement_close_day'] as num?)?.toInt(),
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
        active: ((j['active'] as num?)?.toInt() ?? 1) == 1,
        autoSettledAt: j['auto_settled_at'] == null
            ? null
            : DateTime.parse(j['auto_settled_at'] as String),
      );
}

/// 카드별 미정산 사용액·결제일 요약 (자산 탭 카드 섹션 + 결제 등록 배너용).
class CardSummary {
  final int cardId;
  final String name;
  final int paymentDay;
  final int linkedAccountId;
  final String? linkedAccountName;
  final bool active;
  /// 전체 미정산 카드 부채(모든 사용 − 모든 결제). 자산 총합 계산용.
  final int pendingAmount;
  /// 다음 결제 사이클의 사용액(cycleStart~cycleEnd 내 카드 사용 합계).
  /// statement_close_day 없으면 pendingAmount와 같음. 카드 row 표시용.
  final int cycleAmount;
  /// 이번 사이클 기간 내 card_payment 거래 합. 미리 결제·분할 결제 추적용.
  /// 결제 등록 시트의 자동 채움 = cycleAmount − cycleSettled.
  final int cycleSettled;
  /// 결제일까지 남은 일수. 음수면 결제일이 지남(등록 대기).
  final int daysUntilPayment;
  /// 결제일이 오늘 이전으로 지났는데 결제 거래가 미등록인지.
  final bool needsSettlement;
  /// 이번 결제 사이클 시작일·끝일 (statement_close_day 있을 때만). YYYY-MM-DD.
  /// 끝일이 결제일에 정산되는 사용기간. 예: payment_day=20, close=6, 오늘 5/7
  /// → cycleStart=4/7, cycleEnd=5/6.
  final String? cycleStart;
  final String? cycleEnd;
  const CardSummary({
    required this.cardId,
    required this.name,
    required this.paymentDay,
    required this.linkedAccountId,
    this.linkedAccountName,
    required this.active,
    required this.pendingAmount,
    required this.cycleAmount,
    this.cycleSettled = 0,
    required this.daysUntilPayment,
    required this.needsSettlement,
    this.cycleStart,
    this.cycleEnd,
  });
}

class AccountBalance {
  final int accountId;
  final String name;
  final AccountType type;
  final int initialBalance;
  final int balance; // 현재 잔고 = 시작잔고 + 거래 누적
  final bool active;
  const AccountBalance({
    required this.accountId,
    required this.name,
    required this.type,
    required this.initialBalance,
    required this.balance,
    required this.active,
  });
}

class AssetTrendPoint {
  final String ym;
  final int totalAssets; // 그 월 말 시점의 총 자산
  const AssetTrendPoint({required this.ym, required this.totalAssets});
}

class AssetSnapshot {
  /// 순자산 = 활성 계좌 잔고 합 − 카드 미정산 부채 합.
  final int totalBalance;
  /// 활성 계좌 잔고 합 (부채 차감 전).
  final int accountsBalance;
  /// 모든 활성 카드의 미정산 부채 합 (이번 달 카드 사용 - 정산 거래).
  final int cardDebt;
  final List<AccountBalance> accounts;
  final List<CardSummary> cards;
  final List<AssetTrendPoint> trend; // 최근 N개월 + 현재
  const AssetSnapshot({
    required this.totalBalance,
    required this.accountsBalance,
    required this.cardDebt,
    required this.accounts,
    required this.cards,
    required this.trend,
  });
}

class Account {
  final int id;
  final String name;
  final AccountType type;
  final int initialBalance;
  final int sortOrder;
  final bool active;

  const Account({
    required this.id,
    required this.name,
    required this.type,
    this.initialBalance = 0,
    this.sortOrder = 0,
    this.active = true,
  });

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String,
        type: _accountTypeFrom(j['type'] as String?),
        initialBalance: (j['initial_balance'] as num?)?.toInt() ?? 0,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
        active: ((j['active'] as num?)?.toInt() ?? 1) == 1,
      );
}

class Tx {
  final int id;
  final String date; // YYYY-MM-DD
  final String? card;
  final String? merchant;
  final int amount;
  final String majorCategory;
  final String? subCategory;
  final String? memo;
  final bool isFixed;
  // expense(account): accountId만
  // expense(card): cardId만 — 자산 영향 X, 카드 부채 +
  // income: accountId만
  // transfer: from/toAccountId
  // card_payment: fromAccountId(linked) + cardId
  final int? accountId;
  final int? fromAccountId;
  final int? toAccountId;
  final int? cardId;
  final String type; // 'expense' | 'income' | 'transfer' | 'card_payment'

  const Tx({
    required this.id,
    required this.date,
    this.card,
    this.merchant,
    required this.amount,
    required this.majorCategory,
    this.subCategory,
    this.memo,
    required this.isFixed,
    this.accountId,
    this.fromAccountId,
    this.toAccountId,
    this.cardId,
    this.type = 'expense',
  });

  factory Tx.fromJson(Map<String, dynamic> j) => Tx(
        id: (j['id'] as num).toInt(),
        date: j['date'] as String,
        card: j['card'] as String?,
        merchant: j['merchant'] as String?,
        amount: (j['amount'] as num).toInt(),
        majorCategory: j['major_category'] as String,
        subCategory: j['sub_category'] as String?,
        memo: j['memo'] as String?,
        isFixed: ((j['is_fixed'] as num?)?.toInt() ?? 0) == 1,
        accountId: (j['account_id'] as num?)?.toInt(),
        fromAccountId: (j['from_account_id'] as num?)?.toInt(),
        toAccountId: (j['to_account_id'] as num?)?.toInt(),
        cardId: (j['card_id'] as num?)?.toInt(),
        type: (j['type'] as String?) ?? 'expense',
      );

  String get ym => date.substring(0, 7);
  String get year => date.substring(0, 4);
}

class Major {
  final String name;
  final int sortOrder;
  final String type; // 'expense' | 'income'

  const Major({
    required this.name,
    required this.sortOrder,
    this.type = 'expense',
  });

  factory Major.fromJson(Map<String, dynamic> j) => Major(
        name: j['major'] as String,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
        type: (j['type'] as String?) ?? 'expense',
      );
}

class Category {
  final int id;
  final String major;
  final String sub;
  final int sortOrder;

  const Category({
    required this.id,
    required this.major,
    required this.sub,
    this.sortOrder = 0,
  });

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: (j['id'] as num).toInt(),
        major: j['major'] as String,
        sub: j['sub'] as String,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      );
}

class Budget {
  final String major;
  final int monthlyAmount;

  const Budget({required this.major, required this.monthlyAmount});

  factory Budget.fromJson(Map<String, dynamic> j) => Budget(
        major: j['major'] as String,
        monthlyAmount: (j['monthly_amount'] as num?)?.toInt() ?? 0,
      );
}

/// 카탈로그 row의 그 월 자동 등록 상태.
/// - registered: 그달 거래 등록 완료 (자동 또는 수동)
/// - skipped: 사용자가 의도적으로 삭제 (log엔 남아 자동 재등록 X)
/// - pending: 도래일이 today 이전인데 아직 처리 X (보통 자동 적용 직전 상태)
/// - dueLater: 도래일이 미래
class FixedStatus {
  final String status;
  final String dueDate; // YYYY-MM-DD
  final String? registeredDate; // YYYY-MM-DD (registered일 때)
  final int? transactionId; // 매칭된 거래 id (registered일 때)
  const FixedStatus({
    required this.status,
    required this.dueDate,
    this.registeredDate,
    this.transactionId,
  });
}

class FixedExpense {
  final int id;
  final String name;
  final String major;
  final String? sub;
  final int amount;
  final String? card;
  final int dayOfMonth;
  final bool active;
  final String? memo;
  final int sortOrder;
  // 정기 거래의 결제수단:
  //   account_id가 있으면 → 계좌에서 직접 출금/입금
  //   card_id가 있으면 → 신용카드 사용 (결제일에 연동 계좌에서 정산)
  //   둘 중 하나만 채워짐 (DB CHECK fx_account_or_card).
  final int? accountId;
  final int? cardId;
  // 'expense' | 'income' — 정기지출/정기수입 구분.
  final String type;

  const FixedExpense({
    required this.id,
    required this.name,
    required this.major,
    this.sub,
    required this.amount,
    this.card,
    required this.dayOfMonth,
    required this.active,
    this.memo,
    this.sortOrder = 0,
    this.accountId,
    this.cardId,
    this.type = 'expense',
  });

  factory FixedExpense.fromJson(Map<String, dynamic> j) => FixedExpense(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String,
        major: j['major'] as String,
        sub: j['sub'] as String?,
        amount: (j['amount'] as num?)?.toInt() ?? 0,
        card: j['card'] as String?,
        dayOfMonth: (j['day_of_month'] as num?)?.toInt() ?? 1,
        active: ((j['active'] as num?)?.toInt() ?? 1) == 1,
        memo: j['memo'] as String?,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
        accountId: (j['account_id'] as num?)?.toInt(),
        cardId: (j['card_id'] as num?)?.toInt(),
        type: (j['type'] as String?) ?? 'expense',
      );
}

// ── 대시보드 / 통계 결과 ────────────────────────────────────

class CategoryStats {
  final String major;
  final int spent;
  final int fixedSpent;
  final int variableSpent;
  final int count;
  final int budget;

  const CategoryStats({
    required this.major,
    required this.spent,
    required this.fixedSpent,
    required this.variableSpent,
    required this.count,
    required this.budget,
  });
}

/// 6개월 추이 한 점 — expense/income 두 시리즈.
class TrendPoint {
  final String ym;
  final int expenseTotal;
  final int incomeTotal;
  const TrendPoint({
    required this.ym,
    required this.expenseTotal,
    this.incomeTotal = 0,
  });

  /// 호환용. 기존 코드가 단일 total을 기대하면 expense를 반환.
  int get total => expenseTotal;
}

class Dashboard {
  final String month;
  final String year;
  // 'thisMonthTotal' 의미는 *지출* 그대로 — 기존 호출부 호환.
  final int thisMonthTotal;
  final int prevMonthTotal;
  final int yearTotal;
  final int fixedTotal;
  final int variableTotal;
  final int dailyAvg;
  // 신규: 수입 집계
  final int incomeTotal;
  final int prevIncomeTotal;
  final int yearIncomeTotal;
  final List<CategoryStats> categories;
  final List<TrendPoint> trend;

  const Dashboard({
    required this.month,
    required this.year,
    required this.thisMonthTotal,
    required this.prevMonthTotal,
    required this.yearTotal,
    required this.fixedTotal,
    required this.variableTotal,
    required this.dailyAvg,
    required this.categories,
    required this.trend,
    this.incomeTotal = 0,
    this.prevIncomeTotal = 0,
    this.yearIncomeTotal = 0,
  });

  /// 이번 달 순 저축 = 수입 − 지출.
  int get netSaving => incomeTotal - thisMonthTotal;
}

class SubCategoryStat {
  final String major;
  final String sub;
  final int count;
  final int total;
  const SubCategoryStat({
    required this.major,
    required this.sub,
    required this.count,
    required this.total,
  });
}

class Suggestions {
  final List<String> merchants;
  final List<String> cards;
  // 카테고리(major)별 자주 쓴 가맹점. 사용 빈도순.
  final Map<String, List<String>> merchantsByMajor;
  const Suggestions({
    required this.merchants,
    required this.cards,
    this.merchantsByMajor = const <String, List<String>>{},
  });
}

class CategoriesData {
  final List<String> majors;
  final Map<String, List<Category>> byMajor;
  final List<Category> flat;
  /// major 이름 → 'expense'|'income'.
  final Map<String, String> majorTypes;

  const CategoriesData({
    required this.majors,
    required this.byMajor,
    required this.flat,
    this.majorTypes = const {},
  });

  String typeOf(String major) => majorTypes[major] ?? 'expense';

  List<String> majorsOf(String type) =>
      majors.where((m) => typeOf(m) == type).toList();
}

class FixedApplyEntry {
  final String name;
  final String? date;
  final int? amount;
  final String? reason;
  const FixedApplyEntry({required this.name, this.date, this.amount, this.reason});
}

class FixedApplyResult {
  final String month;
  final int insertedCount;
  final int skippedCount;
  final List<FixedApplyEntry> inserted;
  final List<FixedApplyEntry> skipped;
  const FixedApplyResult({
    required this.month,
    required this.insertedCount,
    required this.skippedCount,
    required this.inserted,
    required this.skipped,
  });
}

/// CSV import 한 행. 검증·정규화된 거래 데이터.
class ImportRow {
  const ImportRow({
    required this.date,
    required this.amount,
    required this.majorCategory,
    this.card,
    this.merchant,
    this.subCategory,
    this.memo,
    this.isFixed = false,
    this.accountId,
    this.cardId,
    this.type = 'expense',
  });
  final String date; // YYYY-MM-DD
  final int amount;
  final String majorCategory;
  final String? card;
  final String? merchant;
  final String? subCategory;
  final String? memo;
  final bool isFixed;
  // accountId / cardId 둘 중 하나만 사용. cardId 있으면 카드 사용 거래로
  // 등록 (account_id NULL, 자산엔 즉시 영향 없음, 카드 부채 +).
  // 둘 다 null이면 importTransactions에서 사용자 default 계좌로 자동 채움.
  final int? accountId;
  final int? cardId;
  final String type; // 'expense' | 'income' | 'transfer'
}

class PendingFixed {
  final String month;
  final int total;
  final int pending;
  const PendingFixed({
    required this.month,
    required this.total,
    required this.pending,
  });
}

// ── AI CSV import 보조 ─────────────────────────────────────

/// 카드사 CSV/XLS 매핑 추정 결과.
/// headerRowIndex: 진짜 헤더 row의 0-based 인덱스 (파일 기준, 첫 줄=0).
/// 컬럼 인덱스(date/amount/merchant 등)는 헤더 row의 컬럼 순서 기준.
/// statusCol/excludedStatuses: 취소·반려 거래 자동 제외용. statusCol의 값이
/// excludedStatuses 중 하나에 매칭되면 그 row 무시 (명세서 합계와 일치 위함).
class CsvMapping {
  final int headerRowIndex;
  final int dateCol;
  final int amountCol;
  final int merchantCol;
  final int? cardCol;
  final int? memoCol;
  final int? statusCol;
  final List<String> excludedStatuses;
  final String dateFormat; // "YYYY-MM-DD" 등 추정 형식
  final String amountSign; // "positive" | "negative" | "absolute"
  final String confidence; // "high" | "medium" | "low"
  final String note;
  // 카드 명세서가 아니라고 판단된 양식. "bank"면 통장 거래내역 — 차단.
  final String? unsupportedKind;
  const CsvMapping({
    this.headerRowIndex = 0,
    required this.dateCol,
    required this.amountCol,
    required this.merchantCol,
    this.cardCol,
    this.memoCol,
    this.statusCol,
    this.excludedStatuses = const [],
    required this.dateFormat,
    required this.amountSign,
    required this.confidence,
    required this.note,
    this.unsupportedKind,
  });

  factory CsvMapping.fromJson(Map<String, dynamic> j) {
    final unsup = (j['unsupportedKind'] as String?)?.trim();
    return CsvMapping(
      headerRowIndex: (j['headerRowIndex'] as num?)?.toInt() ?? 0,
      // 차단 응답일 땐 dateCol/amountCol/merchantCol이 dummy 0으로 와도 무방.
      dateCol: (j['dateCol'] as num?)?.toInt() ?? 0,
      amountCol: (j['amountCol'] as num?)?.toInt() ?? 0,
      merchantCol: (j['merchantCol'] as num?)?.toInt() ?? 0,
      cardCol: (j['cardCol'] as num?)?.toInt(),
      memoCol: (j['memoCol'] as num?)?.toInt(),
      statusCol: (j['statusCol'] as num?)?.toInt(),
      excludedStatuses: (j['excludedStatuses'] as List?)
              ?.map((e) => e?.toString().trim() ?? '')
              .where((s) => s.isNotEmpty)
              .toList() ??
          const [],
      dateFormat: (j['dateFormat'] as String?) ?? 'auto',
      amountSign: (j['amountSign'] as String?) ?? 'absolute',
      confidence: (j['confidence'] as String?) ?? 'medium',
      note: (j['note'] as String?) ?? '',
      unsupportedKind: (unsup == null || unsup.isEmpty) ? null : unsup,
    );
  }
}

/// 가맹점 한 건 분류 결과.
class CsvClassifyItem {
  final String merchant;
  final String major;
  final String? sub;
  final bool isNewMajor;
  final bool isNewSub;
  final String confidence; // "high" | "medium" | "low"
  const CsvClassifyItem({
    required this.merchant,
    required this.major,
    this.sub,
    required this.isNewMajor,
    required this.isNewSub,
    required this.confidence,
  });

  factory CsvClassifyItem.fromJson(Map<String, dynamic> j) => CsvClassifyItem(
        merchant: j['merchant'] as String,
        major: j['major'] as String,
        sub: (j['sub'] as String?)?.trim().isEmpty == true
            ? null
            : j['sub'] as String?,
        isNewMajor: j['isNewMajor'] == true,
        isNewSub: j['isNewSub'] == true,
        confidence: (j['confidence'] as String?) ?? 'medium',
      );

  CsvClassifyItem copyWith({
    String? major,
    String? sub,
    bool clearSub = false,
    bool? isNewMajor,
    bool? isNewSub,
    String? confidence,
  }) {
    return CsvClassifyItem(
      merchant: merchant,
      major: major ?? this.major,
      sub: clearSub ? null : (sub ?? this.sub),
      isNewMajor: isNewMajor ?? this.isNewMajor,
      isNewSub: isNewSub ?? this.isNewSub,
      confidence: confidence ?? this.confidence,
    );
  }
}
