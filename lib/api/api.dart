import 'dart:convert' show base64Encode;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth.dart';
import '../supabase.dart';
import '../utils/date_calc.dart';
import 'card_calc.dart';
import 'models.dart';

/// Supabase에 직접 통신하는 Repository.
/// public/js/api.js와 시그니처를 맞춰서 화면 코드가 1:1 매핑되도록 한다.
class Api {
  Api._() {
    _lastUserId = sb.auth.currentUser?.id;
    sb.auth.onAuthStateChange.listen((state) {
      final newId = state.session?.user.id;
      if (newId != _lastUserId) {
        _lastUserId = newId;
        invalidateAllCaches();
      }
    });
  }
  static final Api instance = Api._();

  String? _lastUserId;

  // ── transactions 캐시 ───────────────────────────────────────
  List<Tx>? _txCache;
  // 사용자 default 계좌 ID 캐시. 한 번 조회 후 accounts 변경 시 비움.
  int? _defaultAccountIdCache;

  /// 데이터가 변경될 때마다 증가하는 버전 노티파이어들. 다른 화면에서
  /// listen 해서 자기 데이터를 자동 reload 하도록 알림용으로 사용.
  final ValueNotifier<int> txVersion = ValueNotifier(0);
  final ValueNotifier<int> majorsVersion = ValueNotifier(0);
  final ValueNotifier<int> categoriesVersion = ValueNotifier(0);
  final ValueNotifier<int> budgetsVersion = ValueNotifier(0);
  final ValueNotifier<int> fixedVersion = ValueNotifier(0);
  final ValueNotifier<int> accountsVersion = ValueNotifier(0);
  final ValueNotifier<int> cardsVersion = ValueNotifier(0);
  final ValueNotifier<int> templatesVersion = ValueNotifier(0);

  void invalidateTx() {
    _txCache = null;
    txVersion.value++;
  }

  void invalidateAccounts() {
    _defaultAccountIdCache = null;
    accountsVersion.value++;
  }

  void invalidateCards() {
    cardsVersion.value++;
  }

  /// 모든 캐시 무효화 + 모든 버전 bump → listening 중인 화면들이 일괄 reload.
  /// 사용자 전환(로그아웃→다른 계정 로그인) 시 호출.
  void invalidateAllCaches() {
    _txCache = null;
    _defaultAccountIdCache = null;
    txVersion.value++;
    majorsVersion.value++;
    categoriesVersion.value++;
    budgetsVersion.value++;
    fixedVersion.value++;
    accountsVersion.value++;
    cardsVersion.value++;
    templatesVersion.value++;
  }

  String _uid() {
    final id = AuthService.currentUserId;
    if (id == null) throw Exception('로그인이 필요합니다.');
    return id;
  }

  Future<List<Tx>> _getAllTx() async {
    final cached = _txCache;
    if (cached != null) return cached;
    final all = <Tx>[];
    const pageSize = 1000;
    var from = 0;
    while (true) {
      final rows = await sb
          .from('transactions')
          .select('*')
          .order('date', ascending: false)
          .order('id', ascending: false)
          .range(from, from + pageSize - 1);
      final list = (rows as List)
          .map((e) => Tx.fromJson(e as Map<String, dynamic>))
          .toList();
      all.addAll(list);
      if (list.length < pageSize) break;
      from += pageSize;
    }
    _txCache = all;
    return all;
  }

  /// 신규 가입 시 시드되는 기본 카테고리 (DB 트리거랑 동일).
  /// wipeMyData가 신규 가입자와 동일한 상태로 만들기 위해 같은 목록 사용.
  static const List<String> defaultMajors = [
    '식비',
    '교통',
    '쇼핑',
    '통신',
    '구독',
    '주거',
    '의료',
    '여가',
    '경조사·회비',
    '기타',
  ];

  /// 본인 모든 데이터 wipe (transactions/fixed/categories/budgets/majors/accounts/ai_insights)
  /// 후 기본 카테고리·계좌 시드. 신규 사용자 상태로 리셋.
  /// RLS로 본인 데이터만 삭제됨 (다른 사용자 데이터 안전).
  /// 삭제 순서 주의: account_id FK가 ON DELETE RESTRICT라 transactions/fixed_expenses
  /// 먼저 삭제하고 마지막에 accounts 삭제.
  Future<void> wipeMyData() async {
    final userId = _uid();
    await sb.from('transactions').delete().eq('user_id', userId);
    await sb.from('fixed_expenses').delete().eq('user_id', userId);
    await sb.from('categories').delete().eq('user_id', userId);
    await sb.from('budgets').delete().eq('user_id', userId);
    await sb.from('majors').delete().eq('user_id', userId);
    await sb.from('cards').delete().eq('user_id', userId);
    await sb.from('accounts').delete().eq('user_id', userId);
    await sb.from('ai_insights').delete().eq('user_id', userId);

    final majorsPayload = <Map<String, dynamic>>[];
    final budgetsPayload = <Map<String, dynamic>>[];
    for (var i = 0; i < defaultMajors.length; i++) {
      majorsPayload.add({
        'user_id': userId,
        'major': defaultMajors[i],
        'sort_order': i,
      });
      budgetsPayload.add({
        'user_id': userId,
        'major': defaultMajors[i],
        'monthly_amount': 0,
      });
    }
    await sb.from('majors').insert(majorsPayload);
    await sb.from('budgets').insert(budgetsPayload);
    await sb.from('accounts').insert({
      'user_id': userId,
      'name': '생활비',
      'type': 'checking',
      'sort_order': 0,
    });

    invalidateAllCaches();
  }

  /// 전체 거래 0건 여부 (신규 사용자 판별용). 캐시 채워져 있으면 즉시 반환,
  /// 없으면 head 1건 조회. 빈 상태 화면에서 도움말 진입점 노출 여부 결정에 사용.
  Future<bool> hasAnyTransactions() async {
    final cached = _txCache;
    if (cached != null) return cached.isNotEmpty;
    final row = await sb
        .from('transactions')
        .select('id')
        .limit(1)
        .maybeSingle();
    return row != null;
  }

  // ── transactions ─────────────────────────────────────────────
  /// dateFrom/dateTo가 있으면 month는 무시. cardId 필터도 임의 조합 가능.
  /// 캐시(_getAllTx)에서 클라이언트 필터링. 대시보드가 이미 워밍해두므로 즉시 반환.
  /// (서버에 필터별로 매번 fetch하는 것보다 빠름 — 특히 "올해"같은 큰 범위)
  Future<List<Tx>> listTransactions({
    String? month,
    String? major,
    String? sub,
    bool subIsNull = false,
    String? q,
    bool? fixed,
    String? type, // 'expense'|'income'|'transfer'|'card_payment' or null
    String? dateFrom, // YYYY-MM-DD
    String? dateTo,
    int? cardId,
    int? accountId,
  }) async {
    final all = await _getAllTx();
    final hasRange = dateFrom != null || dateTo != null;
    final qLower = q?.toLowerCase();
    final result = <Tx>[];
    for (final t in all) {
      // 날짜 필터
      if (hasRange) {
        if (dateFrom != null && t.date.compareTo(dateFrom) < 0) continue;
        if (dateTo != null && t.date.compareTo(dateTo) > 0) continue;
      } else if (month != null) {
        if (!t.date.startsWith('$month-')) continue;
      }
      // 카드/계좌 필터 (둘 다 걸면 OR — 한쪽만 매칭해도 포함)
      if (cardId != null && accountId != null) {
        final hit = t.cardId == cardId ||
            t.accountId == accountId ||
            t.fromAccountId == accountId ||
            t.toAccountId == accountId;
        if (!hit) continue;
      } else if (cardId != null) {
        if (t.cardId != cardId) continue;
      } else if (accountId != null) {
        if (t.accountId != accountId &&
            t.fromAccountId != accountId &&
            t.toAccountId != accountId) {
          continue;
        }
      }
      if (major != null && t.majorCategory != major) continue;
      if (subIsNull) {
        final s = t.subCategory;
        if (s != null && s.trim().isNotEmpty) continue;
      } else if (sub != null && t.subCategory != sub) {
        continue;
      }
      if (qLower != null && qLower.isNotEmpty) {
        final m = (t.merchant ?? '').toLowerCase();
        final memo = (t.memo ?? '').toLowerCase();
        if (!m.contains(qLower) && !memo.contains(qLower)) continue;
      }
      if (fixed == true && !t.isFixed) continue;
      if (fixed == false && t.isFixed) continue;
      if (type != null && t.type != type) continue;
      result.add(t);
    }
    // _getAllTx가 이미 date desc + id desc 정렬돼 있어 그대로 사용.
    return result;
  }

  /// 거래 등록.
  /// - type='expense' (account): accountId 필수
  /// - type='expense' (card 사용): cardId 필수, account_id NULL — 자산 영향 X
  /// - type='income': accountId 필수
  /// - type='transfer': fromAccountId, toAccountId 필수
  /// - type='card_payment': fromAccountId(연동 계좌), cardId 필수 — 결제일 정산
  /// DB CHECK constraint(tx_account_consistency)가 잘못된 조합 거부.
  Future<Tx> createTransaction({
    required String date,
    String? card,
    String? merchant,
    required int amount,
    required String majorCategory,
    String? subCategory,
    String? memo,
    bool isFixed = false,
    int? accountId,
    int? fromAccountId,
    int? toAccountId,
    int? cardId,
    String type = 'expense',
  }) async {
    final payload = <String, dynamic>{
      'user_id': _uid(),
      'date': date,
      'card': card,
      'merchant': merchant,
      'amount': amount,
      'major_category': majorCategory,
      'sub_category': subCategory,
      'memo': memo,
      'is_fixed': isFixed ? 1 : 0,
      'type': type,
    };
    if (type == 'transfer') {
      payload['from_account_id'] = fromAccountId;
      payload['to_account_id'] = toAccountId;
    } else if (type == 'card_payment') {
      payload['from_account_id'] = fromAccountId;
      payload['card_id'] = cardId;
    } else if (type == 'expense' && cardId != null) {
      // 카드 사용 거래 — account_id 비우고 card_id만.
      payload['card_id'] = cardId;
    } else {
      payload['account_id'] = accountId ?? await _defaultAccountId();
    }
    final row = await sb
        .from('transactions')
        .insert(payload)
        .select()
        .single();
    invalidateTx();
    return Tx.fromJson(row);
  }

  Future<Tx> updateTransaction(
    int id, {
    String? date,
    String? card,
    String? merchant,
    int? amount,
    String? majorCategory,
    String? subCategory,
    String? memo,
    bool? isFixed,
    int? accountId,
    int? fromAccountId,
    int? toAccountId,
    int? cardId,
    String? type,
    // null 명시 가능 항목용 sentinel — 필요해지면 유지하되 지금은 nullable 인자로 충분.
  }) async {
    final payload = <String, dynamic>{};
    if (date != null) payload['date'] = date;
    if (card != null) payload['card'] = card;
    if (merchant != null) payload['merchant'] = merchant;
    if (amount != null) payload['amount'] = amount;
    if (majorCategory != null) payload['major_category'] = majorCategory;
    if (subCategory != null) payload['sub_category'] = subCategory;
    if (memo != null) payload['memo'] = memo;
    if (isFixed != null) payload['is_fixed'] = isFixed ? 1 : 0;
    // type이 명시되면 그 type에 맞는 계좌/카드 컬럼만 채우고 나머지는 NULL로
    // 정리. 안 그러면 type 변경(account → card 등)할 때 기존 컬럼이 남아
    // tx_account_consistency CHECK constraint 위반.
    if (type != null) {
      payload['type'] = type;
      switch (type) {
        case 'expense':
          payload['from_account_id'] = null;
          payload['to_account_id'] = null;
          if (cardId != null) {
            payload['card_id'] = cardId;
            payload['account_id'] = null;
          } else {
            payload['card_id'] = null;
            payload['account_id'] = accountId;
          }
          break;
        case 'income':
          payload['card_id'] = null;
          payload['from_account_id'] = null;
          payload['to_account_id'] = null;
          if (accountId != null) payload['account_id'] = accountId;
          break;
        case 'transfer':
          payload['account_id'] = null;
          payload['card_id'] = null;
          if (fromAccountId != null) {
            payload['from_account_id'] = fromAccountId;
          }
          if (toAccountId != null) payload['to_account_id'] = toAccountId;
          break;
        case 'card_payment':
          payload['account_id'] = null;
          payload['to_account_id'] = null;
          if (fromAccountId != null) {
            payload['from_account_id'] = fromAccountId;
          }
          if (cardId != null) payload['card_id'] = cardId;
          break;
      }
    } else {
      // type 미변경 — 명시된 인자만 적용 (기존 동작 유지).
      if (accountId != null) payload['account_id'] = accountId;
      if (fromAccountId != null) payload['from_account_id'] = fromAccountId;
      if (toAccountId != null) payload['to_account_id'] = toAccountId;
      if (cardId != null) payload['card_id'] = cardId;
    }
    final row = await sb
        .from('transactions')
        .update(payload)
        .eq('id', id)
        .select()
        .single();
    invalidateTx();
    return Tx.fromJson(row);
  }

  Future<void> deleteTransaction(int id) async {
    await sb.from('transactions').delete().eq('id', id);
    invalidateTx();
  }

  /// CSV import — 검증된 거래 행을 한 번에 INSERT.
  /// 행에 등록 안 된 카테고리/태그가 있으면 함께 자동 추가.
  /// [rows]는 ImportRow 형태 — date, amount, majorCategory 필수.
  /// 반환: 등록 성공 건수.
  /// import 전 미리보기 — DB 중복(이미 등록된 거래)과 CSV 안 중복(명세서 안에서
  /// 같은 키가 두 번)을 분리해서 반환. 실제 insert는 안 함.
  Future<ImportDupPreview> countDuplicateImportRows(
      List<ImportRow> rows) async {
    if (rows.isEmpty) {
      return const ImportDupPreview(dbDup: 0, csvDup: 0);
    }
    final defaultId = await _defaultAccountId();
    // key에 type 포함 — 같은 가맹점·날·금액의 income과 expense가 동시 들어가도
    // 한쪽이 dbDup으로 빠지지 않게(예: 환불·이체 라벨링 케이스).
    String keyFor({
      int? cardId,
      int? accountId,
      required String date,
      required int amount,
      String? merchant,
      required String type,
    }) {
      final ref = cardId != null ? 'c$cardId' : 'a$accountId';
      return '$type|$ref|$date|$amount|${merchant ?? ""}';
    }

    final dates = rows.map((r) => r.date).toList()..sort();
    final existingRows = await sb
        .from('transactions')
        .select('date, amount, merchant, card_id, account_id, type')
        .gte('date', dates.first)
        .lte('date', dates.last);
    final existingKeys = <String>{};
    for (final e in (existingRows as List)) {
      final m = e as Map<String, dynamic>;
      existingKeys.add(keyFor(
        cardId: (m['card_id'] as num?)?.toInt(),
        accountId: (m['account_id'] as num?)?.toInt(),
        date: m['date'] as String,
        amount: (m['amount'] as num).toInt(),
        merchant: m['merchant'] as String?,
        type: (m['type'] as String?) ?? 'expense',
      ));
    }

    final seen = <String>{};
    int dbDup = 0;
    int csvDup = 0;
    for (final r in rows) {
      final useCard = r.cardId != null && r.type == 'expense';
      final key = keyFor(
        cardId: useCard ? r.cardId : null,
        accountId: useCard ? null : (r.accountId ?? defaultId),
        date: r.date,
        amount: r.amount,
        merchant: r.merchant,
        type: r.type,
      );
      if (existingKeys.contains(key)) {
        dbDup++;
      } else if (!seen.add(key)) {
        csvDup++;
      }
    }
    return ImportDupPreview(dbDup: dbDup, csvDup: csvDup);
  }

  /// [csvDedupe] — 같은 import 안에 같은 (카드/계좌+날짜+가맹점+금액) 거래가
  /// 둘 이상이면 1건만 등록. 수기 CSV는 사용자가 정리하지 못한 중복을 걸러야 해서
  /// true가 안전. 카드사 명세서는 *시간이 다른 진짜 거래*를 합쳐버리는 부작용이
  /// 있어서 false로 호출해야 함 (AI 카드 명세서 import 흐름).
  Future<ImportResult> importTransactions(
    List<ImportRow> rows, {
    bool csvDedupe = true,
  }) async {
    if (rows.isEmpty) {
      return const ImportResult(inserted: 0, dbDup: 0, csvDup: 0);
    }
    final userId = _uid();

    // 신규 카테고리/태그 자동 등록. row의 type에 맞는 majors에 추가.
    final existingMajors = await listMajors(); // 모든 type 포함
    final existingNamesByType = <String, Set<String>>{
      'expense': existingMajors
          .where((m) => m.type == 'expense')
          .map((m) => m.name)
          .toSet(),
      'income': existingMajors
          .where((m) => m.type == 'income')
          .map((m) => m.name)
          .toSet(),
    };
    final cats = await listCategories();
    final existingSubs = <String>{
      for (final c in cats.flat) '${c.major}|${c.sub}',
    };

    // type별로 신규 majors 분리.
    final newMajorsByType = <String, Set<String>>{
      'expense': <String>{},
      'income': <String>{},
    };
    final newSubs = <String>{};
    for (final r in rows) {
      final t = r.type == 'income' ? 'income' : 'expense';
      if (!existingNamesByType[t]!.contains(r.majorCategory)) {
        newMajorsByType[t]!.add(r.majorCategory);
      }
      final sub = r.subCategory;
      if (sub != null && sub.isNotEmpty) {
        final key = '${r.majorCategory}|$sub';
        if (!existingSubs.contains(key)) newSubs.add(key);
      }
    }

    for (final t in ['expense', 'income']) {
      final news = newMajorsByType[t]!;
      if (news.isEmpty) continue;
      // 기존 majors의 MAX(sort_order)+1부터 — `existingNames.length`로 시작하면
      // sort_order에 빈 값/큰 값 섞여있을 때 중복 발생해서 정렬 깨짐.
      final maxRow = await sb
          .from('majors')
          .select('sort_order')
          .eq('type', t)
          .order('sort_order', ascending: false)
          .limit(1)
          .maybeSingle();
      var nextOrder = ((maxRow?['sort_order'] as num?)?.toInt() ?? -1) + 1;
      await sb.from('majors').insert([
        for (final m in news)
          {
            'user_id': userId,
            'major': m,
            'sort_order': nextOrder++,
            'type': t,
          },
      ]);
      // 예산은 expense에만.
      if (t == 'expense') {
        await sb.from('budgets').insert([
          for (final m in news)
            {'user_id': userId, 'major': m, 'monthly_amount': 0},
        ]);
      }
    }
    if (newSubs.isNotEmpty) {
      await sb.from('categories').insert([
        for (final key in newSubs)
          {
            'user_id': userId,
            'major': key.split('|')[0],
            'sub': key.split('|')[1],
            'sort_order': 0,
          },
      ]);
    }

    // ImportRow.cardId가 있으면 카드 사용 거래(account_id NULL), 없으면 계좌 거래.
    // accountId 미지정 + cardId 미지정이면 default 계좌로 채움.
    final defaultId = await _defaultAccountId();

    // dedupe — 같은 명세서 두 번 올려도 중복 등록 안 되게.
    // (type, card_id 또는 account_id, date, amount, merchant) 조합이 이미 있으면 skip.
    // key에 type 포함 — 같은 가맹점·날·금액 income/expense 동시 보호 (예: 환불).
    String keyFor({
      int? cardId,
      int? accountId,
      required String date,
      required int amount,
      String? merchant,
      required String type,
    }) {
      final ref = cardId != null ? 'c$cardId' : 'a$accountId';
      return '$type|$ref|$date|$amount|${merchant ?? ""}';
    }

    final dates = rows.map((r) => r.date).toList()..sort();
    final minDate = dates.first;
    final maxDate = dates.last;
    final existingRows = await sb
        .from('transactions')
        .select('date, amount, merchant, card_id, account_id, type')
        .gte('date', minDate)
        .lte('date', maxDate);
    final existingKeys = <String>{};
    for (final e in (existingRows as List)) {
      final m = e as Map<String, dynamic>;
      existingKeys.add(keyFor(
        cardId: (m['card_id'] as num?)?.toInt(),
        accountId: (m['account_id'] as num?)?.toInt(),
        date: m['date'] as String,
        amount: (m['amount'] as num).toInt(),
        merchant: m['merchant'] as String?,
        type: (m['type'] as String?) ?? 'expense',
      ));
    }

    final payload = <Map<String, dynamic>>[];
    int dbDup = 0;
    int csvDup = 0;
    final seen = <String>{};
    for (final r in rows) {
      final useCard = r.cardId != null && r.type == 'expense';
      final key = keyFor(
        cardId: useCard ? r.cardId : null,
        accountId: useCard ? null : (r.accountId ?? defaultId),
        date: r.date,
        amount: r.amount,
        merchant: r.merchant,
        type: r.type,
      );
      if (existingKeys.contains(key)) {
        dbDup++;
        continue;
      }
      if (csvDedupe && !seen.add(key)) {
        csvDup++;
        continue;
      }
      payload.add({
        'user_id': userId,
        'date': r.date,
        'card': r.card,
        'merchant': r.merchant,
        'amount': r.amount,
        'major_category': r.majorCategory,
        'sub_category': r.subCategory,
        'memo': r.memo,
        'is_fixed': r.isFixed ? 1 : 0,
        'account_id': useCard ? null : (r.accountId ?? defaultId),
        'card_id': useCard ? r.cardId : null,
        'type': r.type,
      });
    }

    if (payload.isNotEmpty) {
      // batch insert (한 번에 수백 건 OK).
      await sb.from('transactions').insert(payload);
    }

    invalidateTx();
    final addedAnyMajor = newMajorsByType['expense']!.isNotEmpty ||
        newMajorsByType['income']!.isNotEmpty;
    if (addedAnyMajor) {
      majorsVersion.value++;
      // 예산은 expense majors가 추가됐을 때만 영향.
      if (newMajorsByType['expense']!.isNotEmpty) {
        budgetsVersion.value++;
      }
    }
    if (newSubs.isNotEmpty) categoriesVersion.value++;
    return ImportResult(
      inserted: payload.length,
      dbDup: dbDup,
      csvDup: csvDup,
    );
  }

  // ── majors ──────────────────────────────────────────────────
  /// type='expense'/'income'이면 해당 type만, null이면 모두.
  Future<List<Major>> listMajors({String? type}) async {
    dynamic query = sb.from('majors').select('major, sort_order, type');
    if (type != null) query = query.eq('type', type);
    final rows = await query
        .order('sort_order', ascending: true)
        .order('major', ascending: true);
    return (rows as List)
        .map((e) => Major.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 카테고리 추가. type='expense'면 budgets도 함께 만든다 (지출만 예산 적용).
  /// type='income'은 majors만 만들고 budgets 안 만듦.
  Future<Major> createMajor(String name, {String type = 'expense'}) async {
    final userId = _uid();
    final clean = name.trim();
    if (clean.isEmpty) throw Exception('카테고리 이름이 필요합니다.');
    final maxRow = await sb
        .from('majors')
        .select('sort_order')
        .eq('type', type)
        .order('sort_order', ascending: false)
        .limit(1)
        .maybeSingle();
    final next = ((maxRow?['sort_order'] as num?)?.toInt() ?? -1) + 1;
    try {
      await sb.from('majors').insert({
        'user_id': userId,
        'major': clean,
        'sort_order': next,
        'type': type,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') throw Exception('이미 존재하는 카테고리입니다.');
      rethrow;
    }
    if (type == 'expense') {
      await sb.from('budgets').insert({
        'user_id': userId,
        'major': clean,
        'monthly_amount': 0,
      });
      budgetsVersion.value++;
    }
    majorsVersion.value++;
    return Major(name: clean, sortOrder: next, type: type);
  }

  Future<void> renameMajor(String oldName, String newName) async {
    final clean = newName.trim();
    if (clean.isEmpty) throw Exception('새 이름이 필요합니다.');
    if (clean == oldName) return;
    // user_id 명시 — RLS 의존 외 방어 깊이. 본인 majors의 같은 이름만 잡아야
    // 다른 사용자 데이터 영향 X (cascade update도 모두 본인 row만 대상).
    final uid = _uid();
    final dup = await sb
        .from('majors')
        .select('major')
        .eq('user_id', uid)
        .eq('major', clean)
        .maybeSingle();
    if (dup != null) throw Exception('같은 이름의 카테고리가 이미 있습니다.');
    await sb
        .from('majors')
        .update({'major': clean})
        .eq('user_id', uid)
        .eq('major', oldName);
    await sb
        .from('categories')
        .update({'major': clean})
        .eq('user_id', uid)
        .eq('major', oldName);
    await sb
        .from('budgets')
        .update({'major': clean})
        .eq('user_id', uid)
        .eq('major', oldName);
    await sb
        .from('transactions')
        .update({'major_category': clean})
        .eq('user_id', uid)
        .eq('major_category', oldName);
    await sb
        .from('fixed_expenses')
        .update({'major': clean})
        .eq('user_id', uid)
        .eq('major', oldName);
    invalidateTx();
    majorsVersion.value++;
    categoriesVersion.value++;
    budgetsVersion.value++;
    fixedVersion.value++;
  }

  Future<void> deleteMajor(String major) async {
    final usage = await sb
        .from('transactions')
        .select('id')
        .eq('major_category', major)
        .count(CountOption.exact);
    if (usage.count > 0) {
      throw Exception('이 카테고리를 사용하는 거래가 ${usage.count}건 있어 삭제할 수 없습니다.');
    }
    final fxUsage = await sb
        .from('fixed_expenses')
        .select('id')
        .eq('major', major)
        .count(CountOption.exact);
    if (fxUsage.count > 0) {
      throw Exception('이 카테고리를 쓰는 정기 거래가 ${fxUsage.count}건 있어 삭제할 수 없습니다.');
    }
    await sb.from('categories').delete().eq('major', major);
    await sb.from('budgets').delete().eq('major', major);
    await sb.from('majors').delete().eq('major', major);
    majorsVersion.value++;
    categoriesVersion.value++;
    budgetsVersion.value++;
    fixedVersion.value++;
  }

  // ── categories ──────────────────────────────────────────────
  /// type 지정 시 해당 type majors만, null이면 모든 type.
  Future<CategoriesData> listCategories({String? type}) async {
    dynamic majorQuery = sb.from('majors').select('major, type');
    if (type != null) majorQuery = majorQuery.eq('type', type);
    final majorRows = await majorQuery
        .order('sort_order', ascending: true)
        .order('major', ascending: true);
    final majorMaps = (majorRows as List).cast<Map<String, dynamic>>();
    final majors = majorMaps.map((r) => r['major'] as String).toList();
    final majorSet = majors.toSet();
    final majorTypes = <String, String>{
      for (final r in majorMaps)
        r['major'] as String: (r['type'] as String?) ?? 'expense',
    };
    final rows = await sb
        .from('categories')
        .select('id, major, sub, sort_order')
        .order('major', ascending: true)
        .order('sort_order', ascending: true)
        .order('id', ascending: true);
    final allFlat = (rows as List)
        .map((e) => Category.fromJson(e as Map<String, dynamic>))
        .toList();
    // type 필터가 있으면 majors에 속한 sub만 노출.
    final flat = type == null
        ? allFlat
        : allFlat.where((c) => majorSet.contains(c.major)).toList();
    final byMajor = <String, List<Category>>{for (final m in majors) m: []};
    for (final c in flat) {
      byMajor.putIfAbsent(c.major, () => []).add(c);
    }
    return CategoriesData(
      majors: majors,
      byMajor: byMajor,
      flat: flat,
      majorTypes: majorTypes,
    );
  }

  Future<Category> createCategory(String major, String sub) async {
    final userId = _uid();
    final m = major.trim();
    final s = sub.trim();
    if (m.isEmpty || s.isEmpty) throw Exception('major, sub 필수');
    final maxRow = await sb
        .from('categories')
        .select('sort_order')
        .eq('major', m)
        .order('sort_order', ascending: false)
        .limit(1)
        .maybeSingle();
    final next = ((maxRow?['sort_order'] as num?)?.toInt() ?? -1) + 1;
    try {
      final row = await sb
          .from('categories')
          .insert({
            'user_id': userId,
            'major': m,
            'sub': s,
            'sort_order': next,
          })
          .select()
          .single();
      categoriesVersion.value++;
      return Category.fromJson(row);
    } on PostgrestException catch (e) {
      if (e.code == '23505') throw Exception('이미 존재하는 태그입니다.');
      rethrow;
    }
  }

  Future<Category> renameCategory(int id, String sub) async {
    final newSub = sub.trim();
    if (newSub.isEmpty) throw Exception('sub 필요');
    final cur = await sb.from('categories').select('*').eq('id', id).single();
    final curMajor = cur['major'] as String;
    final curSub = cur['sub'] as String;
    if (curSub == newSub) {
      return Category(id: id, major: curMajor, sub: newSub);
    }
    final dup = await sb
        .from('categories')
        .select('id')
        .eq('major', curMajor)
        .eq('sub', newSub)
        .maybeSingle();
    if (dup != null) throw Exception('같은 이름의 태그가 이미 있습니다.');
    await sb.from('categories').update({'sub': newSub}).eq('id', id);
    await sb
        .from('transactions')
        .update({'sub_category': newSub})
        .eq('major_category', curMajor)
        .eq('sub_category', curSub);
    // 정기 거래 sub도 같이 — 누락되면 다음 자동 적용에서 옛 sub로 거래 생성됨.
    await sb
        .from('fixed_expenses')
        .update({'sub': newSub})
        .eq('major', curMajor)
        .eq('sub', curSub);
    invalidateTx();
    categoriesVersion.value++;
    fixedVersion.value++;
    return Category(id: id, major: curMajor, sub: newSub);
  }

  Future<void> deleteCategory(int id) async {
    final cur = await sb.from('categories').select('*').eq('id', id).single();
    final curMajor = cur['major'] as String;
    final curSub = cur['sub'] as String;
    final usage = await sb
        .from('transactions')
        .select('id')
        .eq('major_category', curMajor)
        .eq('sub_category', curSub)
        .count(CountOption.exact);
    if (usage.count > 0) {
      throw Exception('이 태그를 사용하는 거래가 ${usage.count}건 있어 삭제할 수 없습니다.');
    }
    final fxUsage = await sb
        .from('fixed_expenses')
        .select('id')
        .eq('major', curMajor)
        .eq('sub', curSub)
        .count(CountOption.exact);
    if (fxUsage.count > 0) {
      throw Exception('이 태그를 쓰는 정기 거래가 ${fxUsage.count}건 있어 삭제할 수 없습니다.');
    }
    await sb.from('categories').delete().eq('id', id);
    categoriesVersion.value++;
  }

  // ── budgets ─────────────────────────────────────────────────
  Future<List<Budget>> listBudgets() async {
    // 예산은 지출 카테고리에만 — 수입 major(월급·이자 등)는 제외.
    final majorRows = await sb
        .from('majors')
        .select('major')
        .eq('type', 'expense')
        .order('sort_order', ascending: true)
        .order('major', ascending: true);
    final rows = await sb.from('budgets').select('major, monthly_amount');
    final map = <String, int>{
      for (final r in rows as List)
        r['major'] as String: (r['monthly_amount'] as num?)?.toInt() ?? 0,
    };
    return (majorRows as List)
        .map((m) => Budget(
              major: m['major'] as String,
              monthlyAmount: map[m['major']] ?? 0,
            ))
        .toList();
  }

  Future<List<Budget>> saveBudgets(List<Budget> budgets) async {
    final userId = _uid();
    // 예산은 지출 카테고리에만 — 수입 major에 budget row가 만들어지지 않게 필터.
    final validMajors =
        (await listMajors(type: 'expense')).map((m) => m.name).toSet();
    final rows = budgets
        .where((b) => validMajors.contains(b.major))
        .map((b) => {
              'user_id': userId,
              'major': b.major,
              'monthly_amount': math.max(0, b.monthlyAmount),
            })
        .toList();
    if (rows.isNotEmpty) {
      await sb.from('budgets').upsert(rows, onConflict: 'user_id,major');
      budgetsVersion.value++;
    }
    return listBudgets();
  }

  // ── dashboard (클라이언트 계산) ─────────────────────────────
  /// 지출 집계는 type='expense'만, 수입 집계는 type='income'만.
  /// transfer는 양쪽 어디에도 포함 안 됨 (자산 흐름 plan에서 별도 처리).
  Future<Dashboard> getDashboard([String? month]) async {
    final now = DateTime.now();
    final ym = month ?? _ymOf(now);
    final year = ym.substring(0, 4);
    final prev = _prevYm(ym);

    final results = await Future.wait([
      _getAllTx(),
      listMajors(type: 'expense'),
      listBudgets(),
    ]);
    final allTxs = results[0] as List<Tx>;
    final majors = results[1] as List<Major>;
    final budgets = results[2] as List<Budget>;
    final budgetMap = {for (final b in budgets) b.major: b.monthlyAmount};

    // 미래 일자 거래는 모든 통계에서 제외 — 자산 탭과 일관 (발생주의).
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final txs =
        allTxs.where((t) => t.date.compareTo(todayStr) <= 0).toList();

    // 지출 거래 집계
    final expenseTxs = txs.where((t) => t.type == 'expense').toList();
    final monthExpense = expenseTxs.where((t) => t.ym == ym).toList();
    final thisMonthTotal = monthExpense.fold<int>(0, (s, t) => s + t.amount);
    final prevMonthTotal = expenseTxs
        .where((t) => t.ym == prev)
        .fold<int>(0, (s, t) => s + t.amount);
    final fixedTotal = monthExpense
        .where((t) => t.isFixed)
        .fold<int>(0, (s, t) => s + t.amount);
    final variableTotal = monthExpense
        .where((t) => !t.isFixed)
        .fold<int>(0, (s, t) => s + t.amount);
    final yearTotal = expenseTxs
        .where((t) => t.year == year)
        .fold<int>(0, (s, t) => s + t.amount);

    // 수입 거래 집계
    final incomeTxs = txs.where((t) => t.type == 'income').toList();
    final incomeTotal = incomeTxs
        .where((t) => t.ym == ym)
        .fold<int>(0, (s, t) => s + t.amount);
    final prevIncomeTotal = incomeTxs
        .where((t) => t.ym == prev)
        .fold<int>(0, (s, t) => s + t.amount);
    final yearIncomeTotal = incomeTxs
        .where((t) => t.year == year)
        .fold<int>(0, (s, t) => s + t.amount);

    int daysDivisor;
    if (ym == _ymOf(now)) {
      daysDivisor = now.day;
    } else {
      final parts = ym.split('-').map(int.parse).toList();
      daysDivisor = DateTime(parts[0], parts[1] + 1, 0).day;
    }
    // 일평균은 변동비 기준 — 매월 고정 금액인 정기지출(월세·구독 등)이 들어가면
    // "오늘 얼마 쓰는지" 체감이 흐려져서. 변동비만 나눠야 소비 페이스를 본다.
    final dailyAvg =
        daysDivisor > 0 ? (variableTotal / daysDivisor).round() : 0;

    // 카테고리 집계는 expense majors만 (예산도 expense 전용).
    final perMajor = <String, _MajorAgg>{};
    for (final t in monthExpense) {
      final r = perMajor.putIfAbsent(t.majorCategory, () => _MajorAgg());
      r.spent += t.amount;
      r.count += 1;
      if (t.isFixed) {
        r.fixedSpent += t.amount;
      } else {
        r.variableSpent += t.amount;
      }
    }
    final categories = majors.map((m) {
      final r = perMajor[m.name] ?? _MajorAgg();
      return CategoryStats(
        major: m.name,
        spent: r.spent,
        fixedSpent: r.fixedSpent,
        variableSpent: r.variableSpent,
        count: r.count,
        budget: budgetMap[m.name] ?? 0,
      );
    }).toList();

    // 6개월 추이 — expense/income 두 시리즈.
    final expenseByYm = <String, int>{};
    final incomeByYm = <String, int>{};
    for (final t in expenseTxs) {
      expenseByYm[t.ym] = (expenseByYm[t.ym] ?? 0) + t.amount;
    }
    for (final t in incomeTxs) {
      incomeByYm[t.ym] = (incomeByYm[t.ym] ?? 0) + t.amount;
    }
    final allYms = <String>{...expenseByYm.keys, ...incomeByYm.keys}.toList()
      ..sort((a, b) => b.compareTo(a));
    final trend = allYms
        .take(6)
        .toList()
        .reversed
        .map((y) => TrendPoint(
              ym: y,
              expenseTotal: expenseByYm[y] ?? 0,
              incomeTotal: incomeByYm[y] ?? 0,
            ))
        .toList();

    return Dashboard(
      month: ym,
      year: year,
      thisMonthTotal: thisMonthTotal,
      prevMonthTotal: prevMonthTotal,
      yearTotal: yearTotal,
      fixedTotal: fixedTotal,
      variableTotal: variableTotal,
      dailyAvg: dailyAvg,
      categories: categories,
      trend: trend,
      incomeTotal: incomeTotal,
      prevIncomeTotal: prevIncomeTotal,
      yearIncomeTotal: yearIncomeTotal,
    );
  }

  // ── stats (클라이언트 계산) ─────────────────────────────────
  Future<Suggestions> getSuggestions() async {
    final txs = await _getAllTx();
    final merchantCounts = <String, int>{};
    final cardCounts = <String, int>{};
    final byMajorCounts = <String, Map<String, int>>{};
    for (final t in txs) {
      final mer = t.merchant;
      if (mer != null && mer.isNotEmpty) {
        merchantCounts[mer] = (merchantCounts[mer] ?? 0) + 1;
        final m = byMajorCounts.putIfAbsent(t.majorCategory, () => {});
        m[mer] = (m[mer] ?? 0) + 1;
      }
      final card = t.card;
      if (card != null && card.isNotEmpty) {
        cardCounts[card] = (cardCounts[card] ?? 0) + 1;
      }
    }
    final merchants = merchantCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final cards = cardCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final byMajor = <String, List<String>>{};
    byMajorCounts.forEach((maj, m) {
      final entries = m.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      byMajor[maj] = entries.take(20).map((e) => e.key).toList();
    });
    return Suggestions(
      merchants: merchants.take(200).map((e) => e.key).toList(),
      cards: cards.take(50).map((e) => e.key).toList(),
      merchantsByMajor: byMajor,
    );
  }

  Future<List<SubCategoryStat>> getSubCategoryStats({
    String? month,
    int limit = 10,
    bool? fixed,
  }) async {
    var txs = await _getAllTx();
    // 태그 통계는 지출만 — 수입 카테고리 통계는 다음 plan.
    txs = txs.where((t) => t.type == 'expense').toList();
    if (month != null) txs = txs.where((t) => t.ym == month).toList();
    txs = _filterFixed(txs, fixed);
    final map = <String, _SubAgg>{};
    for (final t in txs) {
      final sub = t.subCategory ?? '(태그 없음)';
      final key = '${t.majorCategory}|$sub';
      final r = map.putIfAbsent(
        key,
        () => _SubAgg(major: t.majorCategory, sub: sub),
      );
      r.count += 1;
      r.total += t.amount;
    }
    final list = map.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    final cap = math.min(50, math.max(1, limit));
    return list
        .take(cap)
        .map((r) => SubCategoryStat(
              major: r.major,
              sub: r.sub,
              count: r.count,
              total: r.total,
            ))
        .toList();
  }

  // ── fixed expenses ──────────────────────────────────────────
  /// type 지정 시 해당 type만 (expense/income), null이면 모두.
  Future<List<FixedExpense>> listFixedExpenses({String? type}) async {
    dynamic query = sb.from('fixed_expenses').select(
        'id, name, major, sub, amount, card, day_of_month, active, memo, sort_order, account_id, card_id, type');
    if (type != null) query = query.eq('type', type);
    final rows = await query
        .order('active', ascending: false)
        .order('day_of_month', ascending: true)
        .order('sort_order', ascending: true)
        .order('id', ascending: true);
    return (rows as List)
        .map((e) => FixedExpense.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 카탈로그별 *그 월 상태*. 카탈로그 화면 row에 자동 등록 상태 표시용.
  /// status: 'registered' (그달 거래 있음) | 'skipped' (log엔 있는데 거래 없음)
  ///         | 'dueLater' (도래일이 미래) | 'pending' (도래분인데 아직 처리 X)
  Future<Map<int, FixedStatus>> getFixedStatusForMonth(String month) async {
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(month)) return {};
    final results = await Future.wait([
      sb.from('fixed_expenses').select('id, name, major, type, day_of_month, active'),
      sb
          .from('transactions')
          .select('id, date, merchant, major_category, type, is_fixed')
          .gte('date', '$month-01')
          .lte('date', lastDayOf(month)),
      sb.from('fixed_apply_log').select('fixed_id').eq('month', month),
    ]);
    final fxs = results[0] as List;
    final txs = results[1] as List;
    final logs = results[2] as List;
    final loggedIds = <int>{
      for (final l in logs) (l['fixed_id'] as num).toInt(),
    };
    final today = DateTime.now();
    final ymToday =
        '${today.year}-${today.month.toString().padLeft(2, '0')}';
    final isCurrentMonth = month == ymToday;
    final isPastMonth = month.compareTo(ymToday) < 0;
    final out = <int, FixedStatus>{};
    for (final f in fxs) {
      final id = (f['id'] as num).toInt();
      final name = f['name'] as String;
      final major = f['major'] as String;
      final type = (f['type'] as String?) ?? 'expense';
      final day = clampDay(((f['day_of_month'] as num?)?.toInt() ?? 1),
          month: month);
      final dueDate = '$month-${day.toString().padLeft(2, '0')}';
      // 매칭 거래 찾기 (merchant+major+type)
      String? registeredDate;
      int? registeredTxId;
      for (final t in txs) {
        if (t['merchant'] == name &&
            t['major_category'] == major &&
            t['type'] == type) {
          registeredDate = t['date'] as String;
          registeredTxId = (t['id'] as num).toInt();
          break;
        }
      }
      final todayStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      String status;
      if (registeredDate != null) {
        // 매칭 거래 있음 — 그 거래 date가 미래면 '예정', 과거/오늘이면 '등록됨'.
        // 사용자가 sync로 거래를 미래로 옮긴 케이스 처리.
        status = registeredDate.compareTo(todayStr) <= 0
            ? 'registered'
            : 'dueLater';
      } else if (loggedIds.contains(id)) {
        status = 'skipped';
      } else if (isCurrentMonth) {
        status = dueDate.compareTo(todayStr) > 0 ? 'dueLater' : 'pending';
      } else if (isPastMonth) {
        status = 'pending'; // 과거 월인데 미등록 + 미log — 다음 호출에서 처리
      } else {
        status = 'dueLater'; // 미래 월
      }
      out[id] = FixedStatus(
        status: status,
        dueDate: dueDate,
        registeredDate: registeredDate,
        transactionId: registeredTxId,
      );
    }
    return out;
  }

  Future<FixedExpense> createFixedExpense({
    required String name,
    required String major,
    String? sub,
    required int amount,
    String? card,
    int dayOfMonth = 1,
    bool active = true,
    String? memo,
    int? accountId,
    int? cardId,
    String type = 'expense',
  }) async {
    final userId = _uid();
    final n = name.trim();
    final m = major.trim();
    if (n.isEmpty || m.isEmpty) throw Exception('name, major 필수');
    final day = clampDay(dayOfMonth);
    final maxRow = await sb
        .from('fixed_expenses')
        .select('sort_order')
        .order('sort_order', ascending: false)
        .limit(1)
        .maybeSingle();
    final next = ((maxRow?['sort_order'] as num?)?.toInt() ?? -1) + 1;
    // 카드 결제(card_id 명시)면 account_id NULL, 아니면 account_id 명시 또는 default.
    final payload = <String, dynamic>{
      'user_id': userId,
      'name': n,
      'major': m,
      'sub': sub,
      'amount': math.max(0, amount),
      'card': card,
      'day_of_month': day,
      'active': active ? 1 : 0,
      'memo': memo,
      'sort_order': next,
      'type': type,
    };
    if (cardId != null) {
      payload['card_id'] = cardId;
      payload['account_id'] = null;
    } else {
      payload['account_id'] = accountId ?? await _defaultAccountId();
      payload['card_id'] = null;
    }
    final row = await sb
        .from('fixed_expenses')
        .insert(payload)
        .select()
        .single();
    fixedVersion.value++;
    return FixedExpense.fromJson(row);
  }

  /// 카탈로그 편집 — 다음 자동 적용부터 반영. 이미 등록된 거래는 *건드리지
  /// 않음* (분리 모델). 거래도 함께 바꾸려면 거래내역에서 직접 편집.
  ///
  /// "이미 일어난 건 안 건드림" 정책 보강 — 수정 후 과거 월에 자동 backfill
  /// 발생 방지를 위해 `fixed_apply_log`에 (created_month ~ 이전 월) upsert.
  /// 카테고리/이름 변경으로 dedupe 키가 깨져도 이전 월에는 새 거래 INSERT 안 됨.
  /// 현재 월은 backfill 안 함 — 도래분은 새 정보로 정상 적용되어야 하므로.
  Future<FixedExpense> updateFixedExpense(
    int id, {
    String? name,
    String? major,
    String? sub,
    int? amount,
    String? card,
    int? dayOfMonth,
    bool? active,
    String? memo,
    int? accountId,
    int? cardId,
    bool clearCardId = false,
    bool clearAccountId = false,
    String? type,
  }) async {
    final payload = <String, dynamic>{};
    if (name != null) payload['name'] = name.trim();
    if (major != null) payload['major'] = major.trim();
    if (sub != null) payload['sub'] = sub;
    if (amount != null) payload['amount'] = math.max(0, amount);
    if (card != null) payload['card'] = card;
    if (dayOfMonth != null) payload['day_of_month'] = clampDay(dayOfMonth);
    if (active != null) payload['active'] = active ? 1 : 0;
    if (memo != null) payload['memo'] = memo;
    if (accountId != null) payload['account_id'] = accountId;
    if (clearAccountId) payload['account_id'] = null;
    if (cardId != null) payload['card_id'] = cardId;
    if (clearCardId) payload['card_id'] = null;
    if (type != null) payload['type'] = type;
    // type 변경 시 CHECK constraint(`fx_account_or_card`) 정합성 자동 보강:
    //   type='income'은 카드 결제 불가 → card_id NULL 강제.
    //   type='expense'이고 호출자가 card/account 명시 안 했으면 기존 row 유지.
    // 호출자가 매번 정확히 명시해주면 영향 없는 방어 코드.
    if (type == 'income') {
      payload['card_id'] = null;
      // account_id가 명시 안 됐고 기존 row가 card 결제였다면 default로 채워야 함.
      if (!payload.containsKey('account_id')) {
        final cur = await sb
            .from('fixed_expenses')
            .select('account_id')
            .eq('id', id)
            .maybeSingle();
        if (cur == null || cur['account_id'] == null) {
          payload['account_id'] = await _defaultAccountId();
        }
      }
    }
    final row = await sb
        .from('fixed_expenses')
        .update(payload)
        .eq('id', id)
        .select()
        .single();

    await _backfillFixedApplyLog(id, row);

    fixedVersion.value++;
    return FixedExpense.fromJson(row);
  }

  /// 카탈로그 수정 시 과거 월(created_month ~ 현재월 이전)에 대해
  /// fixed_apply_log를 채워 자동 backfill 차단. 이미 있는 (fixed_id, month)는
  /// upsert로 그대로 유지.
  Future<void> _backfillFixedApplyLog(
      int fixedId, Map<String, dynamic> row) async {
    final createdAt = row['created_at'] as String?;
    if (createdAt == null || createdAt.length < 7) return;
    final createdMonth = createdAt.substring(0, 7);
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(createdMonth)) return;
    final now = DateTime.now();
    final ymToday =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    if (createdMonth.compareTo(ymToday) >= 0) return; // 같은 달이거나 미래 — 차단 불필요
    final months = <String>[];
    var cursor = createdMonth;
    while (cursor.compareTo(ymToday) < 0) {
      months.add(cursor);
      cursor = _nextYmString(cursor);
    }
    if (months.isEmpty) return;
    final userId = _uid();
    final rows = [
      for (final m in months)
        {'user_id': userId, 'fixed_id': fixedId, 'month': m},
    ];
    // ignoreDuplicates — 이미 있는 (fxId, month)는 그대로 둠. fixed_apply_log에
    // UPDATE RLS 정책이 없어서 upsert가 conflict 시 UPDATE 시도하면 권한 에러.
    await sb.from('fixed_apply_log').upsert(
          rows,
          onConflict: 'user_id,fixed_id,month',
          ignoreDuplicates: true,
        );
  }

  String _nextYmString(String ym) {
    final y = int.parse(ym.substring(0, 4));
    final m = int.parse(ym.substring(5, 7));
    if (m == 12) return '${y + 1}-01';
    return '$y-${(m + 1).toString().padLeft(2, '0')}';
  }

  Future<void> deleteFixedExpense(int id) async {
    await sb.from('fixed_expenses').delete().eq('id', id);
    fixedVersion.value++;
  }

  /// 자동 적용 호출들을 직렬화 — 동시 호출 시 race condition 방지.
  /// 두 listener(거래내역+정기 거래 화면 등)가 같은 fixedVersion bump로 동시에
  /// 호출하면 둘 다 existing/log 빈 상태에서 시작해 같은 거래를 두 번 INSERT
  /// 하는 버그 회피. chain promise로 큐잉 — 이전 호출 끝나야 다음 진행.
  Future<int> _applyChain = Future.value(0);

  /// 자동 적용 — 지정된 월에서 *도래한* 정기 거래만 자동 등록.
  /// 현재 월: today까지 도래분만 / 지난 월: 월말까지 / 미래 월: 처리 X.
  ///
  /// 분리 모델:
  /// - `fixed_apply_log` 에 (user, fixed_id, month) 기록된 페어는 *재적용 X*.
  ///   사용자가 거래를 의도적으로 삭제해도 다시 등록되지 않음.
  /// - 사용자가 직접 등록한 (merchant+major) 매칭 거래가 있으면 dedupe로 skip
  ///   하면서 log에도 기록 — 이후 사용자가 그 거래 삭제 시 자동 재추가 차단.
  Future<int> applyDueFixedTransactions(String month) async {
    // 직렬화 — 진행 중인 호출 끝나야 다음 시작 (dedupe·log 정합성 보장).
    final next = _applyChain.then((_) => _applyDueFixedImpl(month));
    _applyChain = next.catchError((_) => 0);
    return next;
  }

  Future<int> _applyDueFixedImpl(String month) async {
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(month)) return 0;
    final today = DateTime.now();
    final ymToday =
        '${today.year}-${today.month.toString().padLeft(2, '0')}';
    String upTo;
    if (month == ymToday) {
      upTo =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    } else if (month.compareTo(ymToday) < 0) {
      upTo = lastDayOf(month);
    } else {
      return 0;
    }
    final userId = _uid();
    final items =
        await sb.from('fixed_expenses').select('*').eq('active', 1);
    if ((items as List).isEmpty) return 0;
    // 이미 적용 완료된 (fixed_id, month) 페어 — 다시 처리 안 함.
    final logRows = await sb
        .from('fixed_apply_log')
        .select('fixed_id')
        .eq('month', month);
    final appliedIds = <int>{
      for (final r in logRows as List) (r['fixed_id'] as num).toInt(),
    };
    final existing = await sb
        .from('transactions')
        .select('merchant, major_category, is_fixed, type')
        .gte('date', '$month-01')
        .lte('date', lastDayOf(month));
    final existExpense = <String>{
      for (final e in existing as List)
        if ((e['is_fixed'] as num?)?.toInt() == 1 && e['type'] != 'income')
          '${e['merchant']}|${e['major_category']}',
    };
    final existIncome = <String>{
      for (final e in existing as List)
        if (e['type'] == 'income')
          '${e['merchant']}|${e['major_category']}',
    };
    // candidate = (fxId, 그 fxId에 INSERT할 transactions payload 또는 null).
    // 매칭 거래 이미 있는 케이스(has=true)는 payload=null로 log만 박을 후보.
    final candidates = <(int, Map<String, dynamic>?)>[];
    for (final it in items) {
      final fxId = (it['id'] as num).toInt();
      if (appliedIds.contains(fxId)) continue; // 이미 적용 완료
      // 카탈로그 *생성 전* month는 처리 X — 사용자가 5/9에 등록한 정기 거래가
      // 4월에 소급 backfill되면 의도와 안 맞음.
      final createdAt = it['created_at'] as String?;
      if (createdAt != null && createdAt.length >= 7) {
        final createdMonth = createdAt.substring(0, 7);
        if (month.compareTo(createdMonth) < 0) continue;
      }
      final name = it['name'] as String;
      final major = it['major'] as String;
      final fxType = (it['type'] as String?) ?? 'expense';
      final day = clampDay(
        ((it['day_of_month'] as num?)?.toInt() ?? 1),
        month: month,
      );
      final date = '$month-${day.toString().padLeft(2, '0')}';
      final key = '$name|$major';
      final has = fxType == 'income'
          ? existIncome.contains(key)
          : existExpense.contains(key);
      if (has) {
        // 매칭 거래 이미 있음 — log만 박아서 사용자가 그 거래 삭제해도 재등록 X.
        candidates.add((fxId, null));
        continue;
      }
      if (date.compareTo(upTo) > 0) continue; // 도래 안 함 — 다음 호출에서 처리
      final fxCardId = (it['card_id'] as num?)?.toInt();
      final fxAccountId = (it['account_id'] as num?)?.toInt();
      final payload = <String, dynamic>{
        'user_id': userId,
        'date': date,
        'card': null,
        'merchant': name,
        'amount': (it['amount'] as num?)?.toInt() ?? 0,
        'major_category': major,
        'sub_category': it['sub'],
        'memo': it['memo'],
        'is_fixed': 1,
        'account_id': fxCardId != null ? null : fxAccountId,
        'card_id': fxCardId,
        'type': fxType,
      };
      candidates.add((fxId, payload));
    }
    if (candidates.isEmpty) return 0;

    // race fix — log INSERT를 *먼저* 시도 (ignoreDuplicates + select returning).
    // PK (user_id, fixed_id, month) unique constraint로 *first wins*가 보장됨.
    // 멀티탭/멀티디바이스 동시 호출 시 두 번째 process는 returning이 빈 list라
    // transactions 중복 INSERT 차단.
    final logPayload = candidates
        .map((c) => {'user_id': userId, 'fixed_id': c.$1, 'month': month})
        .toList();
    final logInserted = await sb.from('fixed_apply_log').upsert(
          logPayload,
          onConflict: 'user_id,fixed_id,month',
          ignoreDuplicates: true,
        ).select('fixed_id');
    final winningFxIds = <int>{
      for (final r in logInserted as List) (r['fixed_id'] as num).toInt(),
    };

    // log 차지에 성공한 candidate의 transactions만 INSERT.
    final toInsert = <Map<String, dynamic>>[];
    for (final c in candidates) {
      if (!winningFxIds.contains(c.$1)) continue;
      if (c.$2 == null) continue; // 매칭 케이스 — log만 박고 끝
      toInsert.add(c.$2!);
    }
    if (toInsert.isNotEmpty) {
      await sb.from('transactions').insert(toInsert);
      invalidateTx();
    }
    return toInsert.length;
  }

  Future<FixedApplyResult> applyFixedExpenses(String month) async {
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(month)) {
      throw Exception('month는 YYYY-MM 형식이어야 합니다.');
    }
    final userId = _uid();
    final items = await sb.from('fixed_expenses').select('*').eq('active', 1);
    final existing = await sb
        .from('transactions')
        .select('merchant, major_category, is_fixed, type')
        .gte('date', '$month-01')
        .lte('date', lastDayOf(month));
    // expense는 is_fixed=1 거래로 dedupe, income은 type='income' 거래면
    // is_fixed 무관하게 dedupe (사용자가 직접 등록한 income도 중복 방지).
    final existExpense = <String>{
      for (final e in existing as List)
        if ((e['is_fixed'] as num?)?.toInt() == 1 && e['type'] != 'income')
          '${e['merchant']}|${e['major_category']}',
    };
    final existIncome = <String>{
      for (final e in existing as List)
        if (e['type'] == 'income')
          '${e['merchant']}|${e['major_category']}',
    };
    final inserted = <FixedApplyEntry>[];
    final skipped = <FixedApplyEntry>[];
    final toInsert = <Map<String, dynamic>>[];
    for (final it in items as List) {
      final name = it['name'] as String;
      final major = it['major'] as String;
      final fxType = (it['type'] as String?) ?? 'expense';
      final day = clampDay(
        ((it['day_of_month'] as num?)?.toInt() ?? 1),
        month: month,
      );
      final date = '$month-${day.toString().padLeft(2, '0')}';
      final key = '$name|$major';
      final has = fxType == 'income'
          ? existIncome.contains(key)
          : existExpense.contains(key);
      if (has) {
        skipped.add(FixedApplyEntry(name: name, reason: '이미 등록됨'));
        continue;
      }
      // 카드 결제 정기지출이면 거래도 카드 사용 (account_id NULL, card_id set).
      // fixed_expenses.card 자유 텍스트는 *복사하지 않음* — account_id/card_id로
      // 결제수단을 명확히 표시하므로 옛 자유 텍스트("자동이체" 등)는 노이즈.
      // is_fixed=1 마커는 expense·income 모두 적용 — pending 배너 dedupe가
      // is_fixed=1 거래만 "이미 등록됨"으로 인식하기 때문. (expense 고정/변동
      // 통계는 type='expense' 거래만 분류하므로 income에 is_fixed=1 줘도 영향 X)
      final fxCardId = (it['card_id'] as num?)?.toInt();
      final fxAccountId = (it['account_id'] as num?)?.toInt();
      toInsert.add({
        'user_id': userId,
        'date': date,
        'card': null,
        'merchant': name,
        'amount': (it['amount'] as num?)?.toInt() ?? 0,
        'major_category': major,
        'sub_category': it['sub'],
        'memo': it['memo'],
        'is_fixed': 1,
        'account_id': fxCardId != null ? null : fxAccountId,
        'card_id': fxCardId,
        'type': (it['type'] as String?) ?? 'expense',
      });
      inserted.add(FixedApplyEntry(
        name: name,
        date: date,
        amount: (it['amount'] as num?)?.toInt() ?? 0,
      ));
    }
    if (toInsert.isNotEmpty) {
      await sb.from('transactions').insert(toInsert);
      invalidateTx();
    }
    return FixedApplyResult(
      month: month,
      insertedCount: inserted.length,
      skippedCount: skipped.length,
      inserted: inserted,
      skipped: skipped,
    );
  }

  // ── transaction templates (즐겨찾기 거래) ─────────────────────
  /// 사용자 트리거 카탈로그. 거래 모달에서 불러와서 폼 prefill.
  /// fixed_expenses와 다르게 자동 적용 X.
  Future<List<TransactionTemplate>> listTemplates({String? type}) async {
    dynamic query = sb.from('transaction_templates').select(
        'id, name, type, amount, major, sub, merchant, memo, account_id, card_id, sort_order');
    if (type != null) query = query.eq('type', type);
    final rows = await query
        .order('sort_order', ascending: true)
        .order('id', ascending: true);
    return (rows as List)
        .map((e) => TransactionTemplate.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TransactionTemplate> createTemplate({
    required String name,
    required String type,
    int amount = 0,
    String? major,
    String? sub,
    String? merchant,
    String? memo,
    int? accountId,
    int? cardId,
  }) async {
    final userId = _uid();
    final n = name.trim();
    if (n.isEmpty) throw Exception('템플릿 이름이 필요해요');
    if (type != 'expense' && type != 'income') {
      throw Exception('지원하지 않는 type');
    }
    if (type == 'income' && cardId != null) {
      throw Exception('수입은 카드로 받을 수 없어요');
    }
    if (type == 'expense' && accountId != null && cardId != null) {
      throw Exception('계좌와 카드 중 하나만 선택해주세요');
    }
    if (amount <= 0) throw Exception('금액을 입력해주세요');
    if (major == null || major.trim().isEmpty) {
      throw Exception('카테고리를 선택해주세요');
    }
    final maxRow = await sb
        .from('transaction_templates')
        .select('sort_order')
        .order('sort_order', ascending: false)
        .limit(1)
        .maybeSingle();
    final next = ((maxRow?['sort_order'] as num?)?.toInt() ?? -1) + 1;
    final payload = <String, dynamic>{
      'user_id': userId,
      'name': n,
      'type': type,
      'amount': math.max(0, amount),
      'major': major.trim(),
      'sub': sub?.trim().isEmpty == true ? null : sub?.trim(),
      'merchant': merchant?.trim().isEmpty == true ? null : merchant?.trim(),
      'memo': memo?.trim().isEmpty == true ? null : memo?.trim(),
      'account_id': accountId,
      'card_id': cardId,
      'sort_order': next,
    };
    final row = await sb
        .from('transaction_templates')
        .insert(payload)
        .select()
        .single();
    templatesVersion.value++;
    return TransactionTemplate.fromJson(row);
  }

  Future<TransactionTemplate> updateTemplate(
    int id, {
    String? name,
    String? type,
    int? amount,
    String? major,
    String? sub,
    String? merchant,
    String? memo,
    int? accountId,
    int? cardId,
    bool clearAccount = false,
    bool clearCard = false,
    bool clearMajor = false,
    bool clearSub = false,
    bool clearMerchant = false,
    bool clearMemo = false,
  }) async {
    final payload = <String, dynamic>{};
    if (name != null) {
      final n = name.trim();
      if (n.isEmpty) throw Exception('템플릿 이름이 필요해요');
      payload['name'] = n;
    }
    if (type != null) {
      if (type != 'expense' && type != 'income') {
        throw Exception('지원하지 않는 type');
      }
      payload['type'] = type;
    }
    if (amount != null) payload['amount'] = math.max(0, amount);
    if (clearMajor) {
      payload['major'] = null;
    } else if (major != null) {
      payload['major'] = major.trim().isEmpty ? null : major.trim();
    }
    if (clearSub) {
      payload['sub'] = null;
    } else if (sub != null) {
      payload['sub'] = sub.trim().isEmpty ? null : sub.trim();
    }
    if (clearMerchant) {
      payload['merchant'] = null;
    } else if (merchant != null) {
      payload['merchant'] = merchant.trim().isEmpty ? null : merchant.trim();
    }
    if (clearMemo) {
      payload['memo'] = null;
    } else if (memo != null) {
      payload['memo'] = memo.trim().isEmpty ? null : memo.trim();
    }
    if (clearAccount) {
      payload['account_id'] = null;
    } else if (accountId != null) {
      payload['account_id'] = accountId;
    }
    if (clearCard) {
      payload['card_id'] = null;
    } else if (cardId != null) {
      payload['card_id'] = cardId;
    }
    final row = await sb
        .from('transaction_templates')
        .update(payload)
        .eq('id', id)
        .select()
        .single();
    templatesVersion.value++;
    return TransactionTemplate.fromJson(row);
  }

  Future<void> deleteTemplate(int id) async {
    await sb.from('transaction_templates').delete().eq('id', id);
    templatesVersion.value++;
  }

  // ── accounts ───────────────────────────────────────────────
  /// 사용자 계좌 목록. UI에서 비활성 진입 경로가 없어 모두 활성 가정.
  /// (active 컬럼은 그대로 두지만 필터·정렬에 사용 안 함)
  Future<List<Account>> listAccounts() async {
    final rows = await sb
        .from('accounts')
        .select('*')
        .order('sort_order', ascending: true)
        .order('id', ascending: true);
    return (rows as List)
        .map((e) => Account.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Account> createAccount({
    required String name,
    required AccountType type,
    int initialBalance = 0,
  }) async {
    final userId = _uid();
    final clean = name.trim();
    if (clean.isEmpty) throw Exception('계좌 이름이 필요합니다.');
    final maxRow = await sb
        .from('accounts')
        .select('sort_order')
        .order('sort_order', ascending: false)
        .limit(1)
        .maybeSingle();
    final next = ((maxRow?['sort_order'] as num?)?.toInt() ?? -1) + 1;
    try {
      final row = await sb
          .from('accounts')
          .insert({
            'user_id': userId,
            'name': clean,
            'type': type.name,
            'initial_balance': initialBalance,
            'sort_order': next,
          })
          .select()
          .single();
      invalidateAccounts();
      return Account.fromJson(row);
    } on PostgrestException catch (e) {
      if (e.code == '23505') throw Exception('이미 존재하는 계좌 이름입니다.');
      rethrow;
    }
  }

  Future<Account> updateAccount(
    int id, {
    String? name,
    AccountType? type,
    int? initialBalance,
    int? sortOrder,
    bool? active,
  }) async {
    final payload = <String, dynamic>{};
    if (name != null) {
      final clean = name.trim();
      if (clean.isEmpty) throw Exception('계좌 이름이 필요합니다.');
      payload['name'] = clean;
    }
    if (type != null) payload['type'] = type.name;
    if (initialBalance != null) payload['initial_balance'] = initialBalance;
    if (sortOrder != null) payload['sort_order'] = sortOrder;
    if (active != null) payload['active'] = active ? 1 : 0;
    if (payload.isEmpty) {
      final row = await sb.from('accounts').select('*').eq('id', id).single();
      return Account.fromJson(row);
    }
    try {
      final row = await sb
          .from('accounts')
          .update(payload)
          .eq('id', id)
          .select()
          .single();
      invalidateAccounts();
      return Account.fromJson(row);
    } on PostgrestException catch (e) {
      if (e.code == '23505') throw Exception('이미 존재하는 계좌 이름입니다.');
      rethrow;
    }
  }

  /// 계좌 삭제. transactions/fixed_expenses에서 사용 중이면 throw
  /// (FK가 ON DELETE RESTRICT라 DB도 막지만, 사용자에게 친절히 알리기 위해 사전 체크).
  Future<void> deleteAccount(int id) async {
    final txUsage = await sb
        .from('transactions')
        .select('id')
        .or('account_id.eq.$id,from_account_id.eq.$id,to_account_id.eq.$id')
        .count(CountOption.exact);
    if (txUsage.count > 0) {
      throw Exception('이 계좌를 사용하는 거래가 ${txUsage.count}건 있어 삭제할 수 없습니다.');
    }
    final fxUsage = await sb
        .from('fixed_expenses')
        .select('id')
        .eq('account_id', id)
        .count(CountOption.exact);
    if (fxUsage.count > 0) {
      throw Exception('이 계좌를 사용하는 정기 거래가 ${fxUsage.count}건 있어 삭제할 수 없습니다.');
    }
    await sb.from('accounts').delete().eq('id', id);
    invalidateAccounts();
  }

  /// 자산 스냅샷 — 계좌 잔고 + 카드 부채 + 총자산 + 최근 N개월 추이.
  /// 잔고 = initial_balance + Σ(income) − Σ(account expense) + Σ(transfer to)
  ///        − Σ(transfer from) − Σ(card_payment from)
  /// 카드 부채 = Σ(card expense) − Σ(card_payment for that card)
  /// 총자산 = 활성 계좌 잔고 합 − 카드 부채 합
  Future<AssetSnapshot> getAssetSnapshot({int trendMonths = 6}) async {
    final results = await Future.wait([
      listAccounts(),
      listCards(),
      _getAllTx(),
    ]);
    final accounts = results[0] as List<Account>;
    final cards = results[1] as List<CreditCard>;
    final txs = results[2] as List<Tx>;

    // 거래 한 건의 계좌·카드 영향을 byAcc/byCard 맵에 직접 누적.
    // 거래의 account_id/card_id로 즉시 매핑 — 기존엔 거래 × (계좌+카드) iteration이라
    // 1년+ 사용자에서 체감. O(N) → O(N + M + K).
    void applyDelta(Tx t, Map<int, int> byAcc, Map<int, int> byCard) {
      void addAcc(int? accId, int delta) {
        if (accId == null) return;
        final cur = byAcc[accId];
        if (cur != null) byAcc[accId] = cur + delta;
      }
      void addCard(int? cardId, int delta) {
        if (cardId == null) return;
        final cur = byCard[cardId];
        if (cur != null) byCard[cardId] = cur + delta;
      }
      switch (t.type) {
        case 'expense':
          if (t.cardId != null) {
            addCard(t.cardId, t.amount);
          } else {
            addAcc(t.accountId, -t.amount);
          }
          break;
        case 'income':
          addAcc(t.accountId, t.amount);
          break;
        case 'transfer':
          addAcc(t.fromAccountId, -t.amount);
          addAcc(t.toAccountId, t.amount);
          break;
        case 'card_payment':
          addAcc(t.fromAccountId, -t.amount);
          addCard(t.cardId, -t.amount);
          break;
      }
    }

    // 미래 일자 거래는 자산 계산에서 제외 — 정기지출 일괄 등록을 미리 눌러도
    // 도래 전엔 자산에서 안 빠짐. 가계부 표준(토스/뱅샐) 동작.
    // cycleAmount(다음 결제일 청구액)는 예외 — 예정 사용액 표시용이라 그대로.
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    // 현재 계좌 잔고 + 카드 부채 — 거래 *1회 순회*로 같이 누적.
    // 기존 코드는 거래 N건 × (계좌 M + 카드 K) iteration이었음 — 1년+ 사용자에서
    // 체감. 거래의 account_id/card_id로 직접 매핑하면 O(N + M + K).
    final currentByAcc = <int, int>{
      for (final a in accounts) a.id: a.initialBalance,
    };
    final debtByCard = <int, int>{for (final c in cards) c.id: 0};
    for (final t in txs) {
      if (t.date.compareTo(todayStr) > 0) continue;
      applyDelta(t, currentByAcc, debtByCard);
    }
    final perAccount = accounts
        .map((a) => AccountBalance(
              accountId: a.id,
              name: a.name,
              type: a.type,
              initialBalance: a.initialBalance,
              balance: currentByAcc[a.id] ?? a.initialBalance,
              active: a.active,
            ))
        .toList();
    final accountsBalance =
        perAccount.fold<int>(0, (s, a) => s + a.balance);

    // 카드별 미정산 부채 — 위 루프에서 이미 계산됨 (debtByCard).
    final accountNames = {for (final a in accounts) a.id: a.name};
    final cardSummaries = <CardSummary>[];
    var cardDebtTotal = 0;
    for (final c in cards) {
      final debt = debtByCard[c.id] ?? 0;
      // 카드 사이클·청구 계산은 순수 함수로 분리 (card_calc.dart, 단위 테스트 대상).
      cardSummaries.add(computeCardSummary(
        card: c,
        debt: debt,
        txs: txs,
        today: today,
        linkedAccountName: accountNames[c.linkedAccountId],
      ));
      cardDebtTotal += debt;
    }

    final totalBalance = accountsBalance - cardDebtTotal;

    // 월별 추이 — 각 월 말 시점의 (계좌 잔고 합 - 카드 부채 합).
    final months = <String>[];
    for (var i = trendMonths - 1; i >= 0; i--) {
      final dt = DateTime(today.year, today.month - i, 1);
      final ym =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
      months.add(ym);
    }
    final trend = <AssetTrendPoint>[];
    for (final ym in months) {
      // 이번 달 cutoff은 오늘 — 미래 일자 거래(예정)는 자산 추이에 미포함.
      // 과거 월은 그 월 말일까지 누적.
      final monthEnd = lastDayOf(ym);
      final cutoff =
          monthEnd.compareTo(todayStr) > 0 ? todayStr : monthEnd;
      final byAcc = <int, int>{
        for (final a in accounts) a.id: a.initialBalance,
      };
      final byCard = <int, int>{for (final c in cards) c.id: 0};
      for (final t in txs) {
        if (t.date.compareTo(cutoff) > 0) continue;
        applyDelta(t, byAcc, byCard);
      }
      final monthAccounts = accounts.fold<int>(
          0, (s, a) => s + (byAcc[a.id] ?? a.initialBalance));
      final monthCards =
          cards.fold<int>(0, (s, c) => s + (byCard[c.id] ?? 0));
      trend.add(AssetTrendPoint(
        ym: ym,
        totalAssets: monthAccounts - monthCards,
      ));
    }

    return AssetSnapshot(
      totalBalance: totalBalance,
      accountsBalance: accountsBalance,
      cardDebt: cardDebtTotal,
      accounts: perAccount,
      cards: cardSummaries,
      trend: trend,
    );
  }

  // ── cards ───────────────────────────────────────────────────
  Future<List<CreditCard>> listCards() async {
    final rows = await sb
        .from('cards')
        .select('*')
        .order('sort_order', ascending: true)
        .order('id', ascending: true);
    return (rows as List)
        .map((e) => CreditCard.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CreditCard> createCard({
    required String name,
    required int paymentDay,
    required int linkedAccountId,
    int? statementCloseDay,
  }) async {
    final userId = _uid();
    final clean = name.trim();
    if (clean.isEmpty) throw Exception('카드 이름이 필요합니다.');
    if (paymentDay < 1 || paymentDay > 31) {
      throw Exception('결제일은 1~31 사이여야 해요.');
    }
    if (statementCloseDay != null &&
        (statementCloseDay < 1 || statementCloseDay > 31)) {
      throw Exception('사용기간 마감일은 1~31 사이여야 해요.');
    }
    final maxRow = await sb
        .from('cards')
        .select('sort_order')
        .order('sort_order', ascending: false)
        .limit(1)
        .maybeSingle();
    final next = ((maxRow?['sort_order'] as num?)?.toInt() ?? -1) + 1;
    try {
      final row = await sb
          .from('cards')
          .insert({
            'user_id': userId,
            'name': clean,
            'payment_day': paymentDay,
            'linked_account_id': linkedAccountId,
            'statement_close_day': statementCloseDay,
            'sort_order': next,
          })
          .select()
          .single();
      invalidateCards();
      return CreditCard.fromJson(row);
    } on PostgrestException catch (e) {
      if (e.code == '23505') throw Exception('이미 존재하는 카드 이름입니다.');
      rethrow;
    }
  }

  Future<CreditCard> updateCard(
    int id, {
    String? name,
    int? paymentDay,
    int? linkedAccountId,
    int? statementCloseDay,
    bool? active,
    int? sortOrder,
  }) async {
    final payload = <String, dynamic>{};
    if (name != null) {
      final clean = name.trim();
      if (clean.isEmpty) throw Exception('카드 이름이 필요합니다.');
      payload['name'] = clean;
    }
    if (paymentDay != null) {
      if (paymentDay < 1 || paymentDay > 31) {
        throw Exception('결제일은 1~31 사이여야 해요.');
      }
      payload['payment_day'] = paymentDay;
    }
    if (linkedAccountId != null) {
      payload['linked_account_id'] = linkedAccountId;
    }
    if (statementCloseDay != null) {
      if (statementCloseDay < 1 || statementCloseDay > 31) {
        throw Exception('사용기간 마감일은 1~31 사이여야 해요.');
      }
      payload['statement_close_day'] = statementCloseDay;
    }
    if (active != null) payload['active'] = active ? 1 : 0;
    if (sortOrder != null) payload['sort_order'] = sortOrder;
    if (payload.isEmpty) {
      final row = await sb.from('cards').select('*').eq('id', id).single();
      return CreditCard.fromJson(row);
    }
    try {
      final row = await sb
          .from('cards')
          .update(payload)
          .eq('id', id)
          .select()
          .single();
      invalidateCards();
      return CreditCard.fromJson(row);
    } on PostgrestException catch (e) {
      if (e.code == '23505') throw Exception('이미 존재하는 카드 이름입니다.');
      rethrow;
    }
  }

  /// 카드의 card_payment 거래 건수. 1건 이상이면 결제일·마감일 변경 차단 —
  /// 옛 결제는 옛 약관 기준이라 새 결제일로 재정리할 수 없어서.
  Future<int> countCardPayments(int cardId) async {
    final res = await sb
        .from('transactions')
        .select('id')
        .eq('card_id', cardId)
        .eq('type', 'card_payment')
        .count(CountOption.exact);
    return res.count;
  }

  /// AI import의 옛 사이클 자동 정리가 적용됐다고 카드에 마킹.
  /// 이후 같은 카드로 import해도 다이얼로그가 자동 정리를 다시 권하지 않음 —
  /// 시작잔고 누적 보정 방지.
  Future<void> markCardAutoSettled(int cardId) async {
    await sb
        .from('cards')
        .update({'auto_settled_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', cardId);
    invalidateCards();
  }

  /// 카드 결제일/마감일 변경 시 자동 정리됐던 결제 거래를 모두 되돌림.
  /// - 자동 정리로 만들어진 card_payment 거래(메모로 식별) 삭제
  /// - 그 합만큼 linked_account.initial_balance에서 빼서 시작잔고 역보정
  /// - cards.auto_settled_at 초기화 (다시 import 시 자동 정리 다이얼로그 정상 동작)
  /// 반환: 삭제된 거래 건수.
  ///
  /// race 보호 — DELETE … RETURNING 패턴으로 *실제 삭제된 row만* 차감. 두 번
  /// 동시 호출돼도 두 번째는 0건 반환받아서 이중 차감 안 됨.
  Future<int> rollbackAutoSettlement(int cardId) async {
    // 거래 삭제 + 삭제된 row 반환 (atomic). 다른 process가 같은 시점에 호출해도
    // 첫 호출만 returning에 row 잡고 두 번째는 빈 list — 이중 차감 차단.
    final deletedRows = await sb
        .from('transactions')
        .delete()
        .eq('card_id', cardId)
        .eq('type', 'card_payment')
        .eq('memo', 'CSV 가져오기 자동 정리')
        .select('amount, from_account_id');
    final list = deletedRows as List;
    // 시작잔고에서 빼야 할 금액을 통장별로 합산 (보통 한 통장).
    final byAccount = <int, int>{};
    for (final r in list) {
      final m = r as Map<String, dynamic>;
      final amount = (m['amount'] as num).toInt();
      final accId = (m['from_account_id'] as num?)?.toInt();
      if (accId != null) {
        byAccount[accId] = (byAccount[accId] ?? 0) + amount;
      }
    }
    // 통장 시작잔고 역보정 — 실제 삭제된 거래 합만큼.
    for (final entry in byAccount.entries) {
      final accRow = await sb
          .from('accounts')
          .select('initial_balance')
          .eq('id', entry.key)
          .single();
      final cur = (accRow['initial_balance'] as num).toInt();
      await sb
          .from('accounts')
          .update({'initial_balance': cur - entry.value})
          .eq('id', entry.key);
    }
    // 카드 마킹 초기화 (거래 0건이어도 실행 — 마킹만 남은 상태 정리).
    await sb
        .from('cards')
        .update({'auto_settled_at': null}).eq('id', cardId);
    if (list.isNotEmpty) {
      invalidateTx();
      invalidateAccounts();
    }
    invalidateCards();
    return list.length;
  }

  /// 카드 삭제. transactions에서 사용 중이면 throw (FK ON DELETE RESTRICT).
  Future<void> deleteCard(int id) async {
    final usage = await sb
        .from('transactions')
        .select('id')
        .eq('card_id', id)
        .count(CountOption.exact);
    if (usage.count > 0) {
      throw Exception('이 카드를 쓴 거래가 ${usage.count}건 있어 삭제할 수 없어요.');
    }
    await sb.from('cards').delete().eq('id', id);
    invalidateCards();
  }

  /// 사용자 default 계좌 ID. '생활비'(현재 시드) 또는 '기본'(옛 시드) 우선,
  /// 없으면 첫 활성 계좌. 호출부가 accountId를 명시 안 했을 때 자동 fallback.
  /// 한 번 조회 후 캐시 — invalidateAccounts/invalidateAllCaches에서 비움.
  Future<int> _defaultAccountId() async {
    final cached = _defaultAccountIdCache;
    if (cached != null) return cached;
    // user_id 명시 — RLS가 막아주긴 하지만 방어 깊이로 둠. onAuthStateChange가
    // 캐시 invalidate 비동기로 도는데, 그 사이 다른 사용자 계좌가 잡힐 위험 차단.
    final uid = _uid();
    final byName = await sb
        .from('accounts')
        .select('id, name')
        .eq('user_id', uid)
        .inFilter('name', ['생활비', '기본'])
        .eq('active', 1)
        .order('sort_order', ascending: true)
        .limit(1)
        .maybeSingle();
    if (byName != null) {
      final id = (byName['id'] as num).toInt();
      _defaultAccountIdCache = id;
      return id;
    }
    final firstActive = await sb
        .from('accounts')
        .select('id')
        .eq('user_id', uid)
        .eq('active', 1)
        .order('sort_order', ascending: true)
        .order('id', ascending: true)
        .limit(1)
        .maybeSingle();
    if (firstActive == null) {
      throw Exception('계좌가 없습니다. 설정에서 계좌를 먼저 추가해주세요.');
    }
    final id = (firstActive['id'] as num).toInt();
    _defaultAccountIdCache = id;
    return id;
  }

  /// 모든 거래내역을 CSV 문자열로 export. 엑셀/구글 시트에서 바로 열림.
  /// 큰 따옴표/콤마/줄바꿈 escape 처리됨.
  Future<String> exportTransactionsCsv() async {
    final txs = await _getAllTx();
    final sorted = [...txs]..sort((a, b) {
        final dc = b.date.compareTo(a.date);
        return dc != 0 ? dc : b.id.compareTo(a.id);
      });
    final buf = StringBuffer()
      // 필수(날짜·금액·카테고리)를 앞에 두고 import 양식과 일치시킴 (round-trip 보장).
      ..writeln('날짜,구분,금액,카테고리,가맹점,카드/결제수단,태그,메모,고정비');
    for (final t in sorted) {
      // transfer는 자산 흐름 plan 전엔 0건이지만 안전하게 매핑.
      final kind = switch (t.type) {
        'income' => '수입',
        'transfer' => '이체',
        _ => '지출',
      };
      buf.writeln([
        t.date,
        kind,
        t.amount.toString(),
        _csvField(t.majorCategory),
        _csvField(t.merchant),
        _csvField(t.card),
        _csvField(t.subCategory),
        _csvField(t.memo),
        t.isFixed ? '예' : '아니오',
      ].join(','));
    }
    return buf.toString();
  }

  // ── AI 인사이트 (Edge Function 프록시) ─────────────────────
  /// 빠른 캐시 조회 — Edge Function 거치지 않고 ai_insights 테이블에서 바로
  /// 가져와서 분석 화면 마운트 시 즉시 표시용. RLS로 본인 데이터만 보임.
  Future<SpendingInsight?> getCachedSpendingInsight(String month) async {
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(month)) return null;
    final row = await sb
        .from('ai_insights')
        .select('content, generated_at')
        .eq('month', month)
        .maybeSingle();
    if (row == null) return null;
    final content = row['content'] as String?;
    if (content == null || content.isEmpty) return null;
    return SpendingInsight(
      text: content,
      cached: true,
      generatedAt: DateTime.tryParse(row['generated_at']?.toString() ?? ''),
    );
  }

  /// [force]가 true면 캐시 무시하고 새로 분석.
  /// 응답에는 insight 본문 + cached 여부 + (있다면) generated_at 포함.
  Future<SpendingInsight> getSpendingInsight(
    String month, {
    bool force = false,
  }) async {
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(month)) {
      throw Exception('month 필요');
    }
    final res = await sb.functions.invoke(
      'spending-insights',
      body: {'month': month, 'force': force},
    );
    final data = res.data;
    if (data is Map && data['insight'] is String) {
      return SpendingInsight(
        text: data['insight'] as String,
        cached: data['cached'] == true,
        generatedAt: data['generatedAt'] is String
            ? DateTime.tryParse(data['generatedAt'] as String)
            : null,
      );
    }
    if (data is Map && data['error'] != null) {
      throw Exception(data['error'].toString());
    }
    throw Exception('분석 결과를 받을 수 없어요.');
  }

  // ── AI CSV import 보조 (Edge Function 프록시) ─────────────
  /// .xls(BIFF)·.xlsx 파일을 서버에서 SheetJS로 변환. 한국 카드사 .xls(구버전)는
  /// 클라이언트 excel 패키지가 못 읽어서 fallback으로 사용.
  /// 큰 파일은 base64 변환에서 메모리를 많이 쓰니 4MB 제한 (서버에서도 검증).
  Future<({List<String> headers, List<List<String>> rows})> parseSheetFile(
      List<int> bytes) async {
    final encoded = base64Encode(bytes);
    final res = await sb.functions.invoke(
      'import-csv-assist',
      body: {'mode': 'parse-sheet', 'fileBase64': encoded},
    );
    final data = res.data;
    if (data is Map && data['headers'] is List && data['rows'] is List) {
      final headers = (data['headers'] as List)
          .map((e) => e?.toString() ?? '')
          .toList();
      final rows = (data['rows'] as List)
          .map((r) => (r as List).map((e) => e?.toString() ?? '').toList())
          .toList();
      return (headers: headers, rows: rows);
    }
    if (data is Map && data['error'] != null) {
      throw Exception(data['error'].toString());
    }
    throw Exception('파일을 변환할 수 없어요.');
  }

  /// 파일 상단 row들을 통째로 보내서 (1) 어느 row가 헤더인지 (2) 컬럼 매핑이
  /// 어떻게 되는지 추정 받기. 카드사 .xls는 상단 1~2 row가 제목인 경우가 많아서
  /// AI가 직접 진짜 헤더 위치를 잡도록 함.
  Future<CsvMapping> getCsvMapping({
    required List<List<String>> firstRows,
  }) async {
    if (firstRows.isEmpty) throw Exception('파일 상단 row가 비어있어요.');
    final res = await sb.functions.invoke(
      'import-csv-assist',
      body: {
        'mode': 'mapping',
        'firstRows': firstRows,
      },
    );
    final data = res.data;
    if (data is Map && data['mapping'] is Map) {
      return CsvMapping.fromJson(
          (data['mapping'] as Map).cast<String, dynamic>());
    }
    if (data is Map && data['error'] != null) {
      throw Exception(data['error'].toString());
    }
    throw Exception('매핑 결과를 받을 수 없어요.');
  }

  /// 가맹점 리스트를 보내서 사용자 기존 카테고리/태그에 매핑.
  /// 가맹점이 많으면 batch (200건씩 나눠 호출)로 처리.
  Future<List<CsvClassifyItem>> getCsvClassification({
    required List<String> merchants,
  }) async {
    if (merchants.isEmpty) return const [];

    // 사용자 기존 카테고리/태그 조회 (분류 힌트로 전달).
    final cats = await listCategories();
    final majorList = cats.majors;
    final subList = cats.flat
        .map((c) => {'major': c.major, 'sub': c.sub})
        .toList();

    const batchSize = 200;
    final results = <CsvClassifyItem>[];
    for (var i = 0; i < merchants.length; i += batchSize) {
      final chunk = merchants.sublist(
          i, math.min(i + batchSize, merchants.length));
      final res = await sb.functions.invoke(
        'import-csv-assist',
        body: {
          'mode': 'classify',
          'merchants': chunk,
          'userMajors': majorList,
          'userCategories': subList,
        },
      );
      final data = res.data;
      if (data is Map && data['classification'] is Map) {
        final clf = (data['classification'] as Map).cast<String, dynamic>();
        final items = (clf['items'] as List?) ?? const [];
        for (final it in items) {
          if (it is Map) {
            results.add(CsvClassifyItem.fromJson(
                it.cast<String, dynamic>()));
          }
        }
      } else if (data is Map && data['error'] != null) {
        throw Exception(data['error'].toString());
      } else {
        throw Exception('분류 결과를 받을 수 없어요.');
      }
    }
    return results;
  }

  Future<PendingFixed> getPendingFixedExpenses(String month) async {
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(month)) {
      throw Exception('month 필요');
    }
    final items = await sb
        .from('fixed_expenses')
        .select('name, major, type')
        .eq('active', 1);
    final existing = await sb
        .from('transactions')
        .select('merchant, major_category, is_fixed, type')
        .gte('date', '$month-01')
        .lte('date', lastDayOf(month));
    // expense는 is_fixed=1 거래로 dedupe, income은 type='income' 거래면
    // is_fixed 무관하게 dedupe (사용자가 직접 등록한 income도 중복 방지).
    final existExpense = <String>{
      for (final e in existing as List)
        if ((e['is_fixed'] as num?)?.toInt() == 1 && e['type'] != 'income')
          '${e['merchant']}|${e['major_category']}',
    };
    final existIncome = <String>{
      for (final e in existing as List)
        if (e['type'] == 'income')
          '${e['merchant']}|${e['major_category']}',
    };
    var pending = 0;
    for (final it in items as List) {
      final type = (it['type'] as String?) ?? 'expense';
      final key = '${it['name']}|${it['major']}';
      final has = type == 'income'
          ? existIncome.contains(key)
          : existExpense.contains(key);
      if (!has) pending++;
    }
    return PendingFixed(
      month: month,
      total: (items as List).length,
      pending: pending,
    );
  }
}

// ── 헬퍼 ────────────────────────────────────────────────────────

String _ymOf(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

String _prevYm(String ym) {
  final parts = ym.split('-').map(int.parse).toList();
  final d = DateTime(parts[0], parts[1] - 1, 1);
  return _ymOf(d);
}

/// CSV 한 필드 escape — 콤마/큰따옴표/줄바꿈 포함 시 큰따옴표로 감쌈.
String _csvField(String? v) {
  if (v == null || v.isEmpty) return '';
  if (v.contains(',') || v.contains('"') || v.contains('\n')) {
    return '"${v.replaceAll('"', '""')}"';
  }
  return v;
}

List<Tx> _filterFixed(List<Tx> txs, bool? fixed) {
  if (fixed == true) return txs.where((t) => t.isFixed).toList();
  if (fixed == false) return txs.where((t) => !t.isFixed).toList();
  return txs;
}

class SpendingInsight {
  const SpendingInsight({
    required this.text,
    required this.cached,
    this.generatedAt,
  });
  final String text;
  final bool cached;
  final DateTime? generatedAt;
}

class _MajorAgg {
  int spent = 0;
  int fixedSpent = 0;
  int variableSpent = 0;
  int count = 0;
}

class _SubAgg {
  final String major;
  final String sub;
  int count = 0;
  int total = 0;
  _SubAgg({required this.major, required this.sub});
}

