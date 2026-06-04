import 'models.dart';

/// 카드 한 장의 결제 사이클·청구 요약을 순수 계산. DB 의존 없음 —
/// `getAssetSnapshot`이 fetch한 (card, debt, txs, today)로 호출. 단위 테스트 대상.
///
/// [debt]는 그 카드의 전체 미정산(모든 사용 − 모든 결제)으로, 호출부에서 미리 계산.
/// 결제일/마감일이 그 달 일수를 넘으면 말일로 clamp(윤년 자동). statementCloseDay가
/// null이면 사이클 정보 없이 cycleAmount = 전체 미정산으로 둠.
CardSummary computeCardSummary({
  required CreditCard card,
  required int debt,
  required List<Tx> txs,
  required DateTime today,
  String? linkedAccountName,
}) {
  final c = card;
  // 결제일까지 D-일 (이번 달 결제일 또는 다음 달).
  // paymentDay가 month 일수보다 크면 그 month 마지막 날로 clamp.
  // 예: paymentDay=31 + 2월(28/29일) → 2/28(또는 29)에 결제. 윤년 자동.
  DateTime payDateOf(int y, int m) {
    final maxDay = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, c.paymentDay.clamp(1, maxDay));
  }

  final thisMonthPay = payDateOf(today.year, today.month);
  // needsSettlement: 결제일이 *지났는데* 이번 달 결제 거래 미등록.
  final ymThisPay =
      '${thisMonthPay.year}-${thisMonthPay.month.toString().padLeft(2, '0')}';
  final settledThisMonth = txs.any((t) =>
      t.type == 'card_payment' && t.cardId == c.id && t.ym == ymThisPay);
  // 결제일이 month 끝을 넘으면 clamp된 값으로 비교 (예: 31 paymentDay + 2월).
  final needs = today.day > thisMonthPay.day && !settledThisMonth && debt > 0;
  // 결제일 당일에 결제 등록을 마쳤다면 사이클이 끝났으므로 다음 결제 사이클로 넘김.
  final passedThisCycle = today.day > thisMonthPay.day ||
      (today.day == thisMonthPay.day && settledThisMonth);
  final paymentDate = passedThisCycle
      ? payDateOf(today.year, today.month + 1)
      : thisMonthPay;
  final daysUntil = paymentDate
      .difference(DateTime(today.year, today.month, today.day))
      .inDays;
  // 사용기간 (statement_close_day 있을 때만):
  // - 결제일 > 마감일(일반 카드): 다음 결제일 청구 사이클은 (전월 close+1 ~ 이번달 close)
  // - 결제일 ≤ 마감일 (결제 9·마감 20 같은 카드): 사이클이 한 달 앞당겨짐 — paymentLate 보정.
  final useThisMonthCycle = !passedThisCycle || needs;
  String? cycleStartStr;
  String? cycleEndStr;
  if (c.statementCloseDay != null) {
    final close = c.statementCloseDay!;
    final paymentLate = c.paymentDay <= close;
    late DateTime cs, ce;
    // close가 month 일수보다 크면 그 month 마지막 날로 clamp(윤년 자동).
    DateTime clamped(int y, int m) {
      final maxDay = DateTime(y, m + 1, 0).day;
      return DateTime(y, m, close.clamp(1, maxDay));
    }

    // 결제 빠른 카드는 사이클이 한 달 앞당겨짐.
    final mOffsetEnd = useThisMonthCycle
        ? (paymentLate ? -1 : 0)
        : (paymentLate ? 0 : 1);
    ce = clamped(today.year, today.month + mOffsetEnd);
    cs = clamped(today.year, today.month + mOffsetEnd - 1)
        .add(const Duration(days: 1));
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    cycleStartStr = fmt(cs);
    cycleEndStr = fmt(ce);
  }
  // cycleAmount — 사이클 내 카드 사용 합계. 사이클 정보 없으면 미정산 부채.
  // cycleSettled — 이번 결제 사이클의 결제 합. 미리 결제·분할 결제가 있을 때
  // 자동 채움·카드 row가 *남은* 청구액으로 보이도록.
  int cycleAmount;
  int cycleSettled = 0;
  if (cycleStartStr != null && cycleEndStr != null) {
    cycleAmount = 0;
    for (final t in txs) {
      if (t.type == 'expense' &&
          t.cardId == c.id &&
          t.date.compareTo(cycleStartStr) >= 0 &&
          t.date.compareTo(cycleEndStr) <= 0) {
        cycleAmount += t.amount;
      }
    }
    // 이번 사이클의 결제 = (지난 결제일 다음날 ~ 이번 결제일) 사이의 card_payment.
    // 사이클 중간(마감일 전)에 미리 결제한 것도 잡고 옛 사이클 결제일 거래는 뺌.
    late DateTime settleStartDate, settleEndDate;
    if (useThisMonthCycle) {
      final lastPay = payDateOf(today.year, today.month - 1);
      settleStartDate = lastPay.add(const Duration(days: 1));
      settleEndDate = thisMonthPay;
    } else {
      settleStartDate = thisMonthPay.add(const Duration(days: 1));
      settleEndDate = payDateOf(today.year, today.month + 1);
    }
    String fmtDate(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final settleStartStr = fmtDate(settleStartDate);
    final settleEndStr = fmtDate(settleEndDate);
    for (final t in txs) {
      if (t.type == 'card_payment' &&
          t.cardId == c.id &&
          t.date.compareTo(settleStartStr) >= 0 &&
          t.date.compareTo(settleEndStr) <= 0) {
        cycleSettled += t.amount;
      }
    }
  } else {
    cycleAmount = debt;
  }
  // 빨간 줄(needsSettle) 최종 판정 — 부분 결제 후 남은 청구액 케이스도 잡음.
  // 사이클 정보 있는 카드: 결제일 지났는데 *옛 사이클* 미정산이 있으면 빨간 줄.
  //   oldDebt = debt − remainingBilling (다음 사이클 청구분 제외).
  // 사이클 정보 없는 카드: 기존 로직 (debt > 0 + 이번 달 결제 거래 미존재).
  final bool finalNeeds;
  if (c.statementCloseDay != null) {
    final remainingBilling = (cycleAmount - cycleSettled).clamp(0, debt);
    final oldDebt = debt - remainingBilling;
    finalNeeds = today.day > thisMonthPay.day && oldDebt > 0;
  } else {
    finalNeeds = needs;
  }
  return CardSummary(
    cardId: c.id,
    name: c.name,
    paymentDay: c.paymentDay,
    linkedAccountId: c.linkedAccountId,
    linkedAccountName: linkedAccountName,
    active: c.active,
    pendingAmount: debt,
    cycleAmount: cycleAmount,
    cycleSettled: cycleSettled,
    daysUntilPayment: daysUntil,
    needsSettlement: finalNeeds,
    cycleStart: cycleStartStr,
    cycleEnd: cycleEndStr,
  );
}
