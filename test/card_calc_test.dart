import 'package:flutter_test/flutter_test.dart';
import 'package:billionaire/api/card_calc.dart';
import 'package:billionaire/api/models.dart';

CreditCard _card({
  int id = 1,
  int paymentDay = 15,
  int? closeDay,
}) =>
    CreditCard(
      id: id,
      name: '카드',
      paymentDay: paymentDay,
      linkedAccountId: 9,
      statementCloseDay: closeDay,
    );

Tx _use(String date, int amount, {int cardId = 1}) => Tx(
      id: 0,
      date: date,
      amount: amount,
      majorCategory: '',
      isFixed: false,
      type: 'expense',
      cardId: cardId,
    );

Tx _pay(String date, int amount, {int cardId = 1}) => Tx(
      id: 0,
      date: date,
      amount: amount,
      majorCategory: '',
      isFixed: false,
      type: 'card_payment',
      cardId: cardId,
    );

void main() {
  group('사이클 정보 없는 카드 (statementCloseDay = null)', () {
    test('결제일 전 — cycleAmount = 전체 미정산, 빨간 줄 없음', () {
      final s = computeCardSummary(
        card: _card(paymentDay: 15),
        debt: 50000,
        txs: [_use('2026-06-05', 50000)],
        today: DateTime(2026, 6, 10),
      );
      expect(s.cycleAmount, 50000); // close 없음 → debt 그대로
      expect(s.cycleSettled, 0);
      expect(s.pendingAmount, 50000);
      expect(s.needsSettlement, false); // 결제일(15) 전
      expect(s.daysUntilPayment, 5); // 6/10 → 6/15
      expect(s.cycleStart, isNull);
      expect(s.cycleEnd, isNull);
    });

    test('결제일 지남 + 미정산 → 빨간 줄, 다음 달 결제일까지', () {
      final s = computeCardSummary(
        card: _card(paymentDay: 15),
        debt: 50000,
        txs: [_use('2026-06-05', 50000)],
        today: DateTime(2026, 6, 20),
      );
      expect(s.needsSettlement, true);
      expect(s.daysUntilPayment, 25); // 6/20 → 7/15
    });

    test('결제일 지났지만 이번 달 결제 완료 → 빨간 줄 없음', () {
      final s = computeCardSummary(
        card: _card(paymentDay: 15),
        debt: 0,
        txs: [_use('2026-05-20', 50000), _pay('2026-06-15', 50000)],
        today: DateTime(2026, 6, 20),
      );
      expect(s.needsSettlement, false); // settledThisMonth + debt 0
    });
  });

  group('결제일 월말 clamp (윤년 포함)', () {
    test('결제일 31일 + 2월 평년 → 28일 결제', () {
      final s = computeCardSummary(
        card: _card(paymentDay: 31),
        debt: 10000,
        txs: const [],
        today: DateTime(2026, 2, 20),
      );
      expect(s.daysUntilPayment, 8); // 2/20 → 2/28 (clamp)
    });

    test('결제일 31일 + 2월 윤년 → 29일 결제', () {
      final s = computeCardSummary(
        card: _card(paymentDay: 31),
        debt: 10000,
        txs: const [],
        today: DateTime(2024, 2, 20),
      );
      expect(s.daysUntilPayment, 9); // 2/20 → 2/29 (윤년 clamp)
    });
  });

  group('사이클 정보 있는 카드 — 사이클 윈도우', () {
    test('일반 카드(결제일 25 > 마감일 10) — 윈도우 = 전월 마감+1 ~ 이번달 마감', () {
      final s = computeCardSummary(
        card: _card(paymentDay: 25, closeDay: 10),
        debt: 30000,
        txs: [
          _use('2026-05-20', 30000), // 윈도우 내
          _use('2026-06-15', 20000), // 마감(6/10) 이후 → 다음 사이클
        ],
        today: DateTime(2026, 6, 15),
      );
      expect(s.cycleStart, '2026-05-11');
      expect(s.cycleEnd, '2026-06-10');
      expect(s.cycleAmount, 30000); // 윈도우 내 사용만
    });

    test('결제 빠른 카드(결제일 9 ≤ 마감일 20) — 사이클 한 달 앞당겨짐', () {
      final s = computeCardSummary(
        card: _card(paymentDay: 9, closeDay: 20),
        debt: 40000,
        txs: [
          _use('2026-05-01', 40000), // 앞당겨진 윈도우 내
          _use('2026-06-01', 10000), // 윈도우 밖
        ],
        today: DateTime(2026, 6, 5), // 결제일(9) 전
      );
      expect(s.cycleStart, '2026-04-21');
      expect(s.cycleEnd, '2026-05-20');
      expect(s.cycleAmount, 40000);
    });

    test('미리 결제(cycleSettled) — 남은 청구액이 줄어듦', () {
      final s = computeCardSummary(
        card: _card(paymentDay: 25, closeDay: 10),
        debt: 30000,
        txs: [
          _use('2026-05-20', 30000), // 사이클 사용
          _pay('2026-06-01', 30000), // 정산 기간(5/26~6/25) 내 미리 결제
        ],
        today: DateTime(2026, 6, 15),
      );
      expect(s.cycleAmount, 30000);
      expect(s.cycleSettled, 30000);
      // 남은 청구액 = cycleAmount - cycleSettled = 0
      expect(s.cycleAmount - s.cycleSettled, 0);
    });
  });
}
