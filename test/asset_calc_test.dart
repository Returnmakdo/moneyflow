import 'package:flutter_test/flutter_test.dart';
import 'package:billionaire/api/asset_calc.dart';
import 'package:billionaire/api/models.dart';

Account _acc(int id, {int initial = 0}) => Account(
      id: id,
      name: '계좌$id',
      type: AccountType.checking,
      initialBalance: initial,
    );

CreditCard _card(int id) => CreditCard(
      id: id,
      name: '카드$id',
      paymentDay: 15,
      linkedAccountId: 1,
    );

Tx _expenseAcc(String date, int amount, {required int accountId}) => Tx(
      id: 0,
      date: date,
      amount: amount,
      majorCategory: '',
      isFixed: false,
      type: 'expense',
      accountId: accountId,
    );

Tx _expenseCard(String date, int amount, {required int cardId}) => Tx(
      id: 0,
      date: date,
      amount: amount,
      majorCategory: '',
      isFixed: false,
      type: 'expense',
      cardId: cardId,
    );

Tx _income(String date, int amount, {required int accountId}) => Tx(
      id: 0,
      date: date,
      amount: amount,
      majorCategory: '',
      isFixed: false,
      type: 'income',
      accountId: accountId,
    );

Tx _transfer(String date, int amount,
        {required int from, required int to}) =>
    Tx(
      id: 0,
      date: date,
      amount: amount,
      majorCategory: '',
      isFixed: false,
      type: 'transfer',
      fromAccountId: from,
      toAccountId: to,
    );

Tx _cardPayment(String date, int amount,
        {required int from, required int cardId}) =>
    Tx(
      id: 0,
      date: date,
      amount: amount,
      majorCategory: '',
      isFixed: false,
      type: 'card_payment',
      fromAccountId: from,
      cardId: cardId,
    );

void main() {
  group('계좌 잔고 (initial_balance + Σ거래)', () {
    test('초기 잔고만 있으면 그대로', () {
      final r = computeBalances(
        accounts: [_acc(1, initial: 100000)],
        cards: const [],
        txs: const [],
        cutoff: '2026-06-30',
      );
      expect(r.byAccount[1], 100000);
      expect(r.accountsBalance, 100000);
      expect(r.cardDebt, 0);
      expect(r.totalBalance, 100000);
    });

    test('지출은 계좌에서 빠지고 수입은 더해진다', () {
      final r = computeBalances(
        accounts: [_acc(1, initial: 100000)],
        cards: const [],
        txs: [
          _expenseAcc('2026-06-05', 30000, accountId: 1),
          _income('2026-06-06', 50000, accountId: 1),
        ],
        cutoff: '2026-06-30',
      );
      expect(r.byAccount[1], 120000); // 100000 - 30000 + 50000
      expect(r.totalBalance, 120000);
    });

    test('이체는 from −, to +, 총자산 변동 없음', () {
      final r = computeBalances(
        accounts: [_acc(1, initial: 100000), _acc(2, initial: 0)],
        cards: const [],
        txs: [_transfer('2026-06-05', 40000, from: 1, to: 2)],
        cutoff: '2026-06-30',
      );
      expect(r.byAccount[1], 60000);
      expect(r.byAccount[2], 40000);
      expect(r.accountsBalance, 100000);
      expect(r.totalBalance, 100000); // 이동만, 총합 불변
    });
  });

  group('카드 부채 (발생주의)', () {
    test('카드 사용은 계좌 영향 X, 부채 +, 총자산 − (사용 즉시)', () {
      final r = computeBalances(
        accounts: [_acc(1, initial: 100000)],
        cards: [_card(10)],
        txs: [_expenseCard('2026-06-05', 30000, cardId: 10)],
        cutoff: '2026-06-30',
      );
      expect(r.byAccount[1], 100000); // 계좌 안 빠짐
      expect(r.byCard[10], 30000); // 부채 +
      expect(r.cardDebt, 30000);
      expect(r.totalBalance, 70000); // 100000 - 30000
    });

    test('카드 결제는 통장 −, 부채 −, 총자산 변동 없음 (이중카운트 방지)', () {
      final r = computeBalances(
        accounts: [_acc(1, initial: 100000)],
        cards: [_card(10)],
        txs: [
          _expenseCard('2026-06-05', 30000, cardId: 10),
          _cardPayment('2026-06-15', 30000, from: 1, cardId: 10),
        ],
        cutoff: '2026-06-30',
      );
      expect(r.byAccount[1], 70000); // 통장에서 결제분 빠짐
      expect(r.byCard[10], 0); // 부채 상쇄
      expect(r.totalBalance, 70000); // 사용 시점에 이미 반영됨 — 결제로 안 변함
    });

    test('부분 결제 — 남은 미정산만큼 부채 유지', () {
      final r = computeBalances(
        accounts: [_acc(1, initial: 100000)],
        cards: [_card(10)],
        txs: [
          _expenseCard('2026-06-05', 50000, cardId: 10),
          _cardPayment('2026-06-15', 20000, from: 1, cardId: 10),
        ],
        cutoff: '2026-06-30',
      );
      expect(r.byCard[10], 30000); // 50000 - 20000
      expect(r.byAccount[1], 80000);
      expect(r.totalBalance, 50000); // 100000 - 50000(사용)
    });
  });

  group('cutoff (미래 일자 제외)', () {
    test('cutoff 이후 거래는 무시', () {
      final r = computeBalances(
        accounts: [_acc(1, initial: 100000)],
        cards: const [],
        txs: [
          _expenseAcc('2026-06-10', 10000, accountId: 1), // 포함
          _expenseAcc('2026-07-01', 99999, accountId: 1), // 제외 (미래)
        ],
        cutoff: '2026-06-30',
      );
      expect(r.byAccount[1], 90000);
    });

    test('cutoff 당일 거래는 포함 (경계)', () {
      final r = computeBalances(
        accounts: [_acc(1, initial: 100000)],
        cards: const [],
        txs: [_expenseAcc('2026-06-30', 10000, accountId: 1)],
        cutoff: '2026-06-30',
      );
      expect(r.byAccount[1], 90000);
    });
  });

  group('삭제된 계좌/카드 참조 (방어)', () {
    test('맵에 없는 account_id/card_id 거래는 무시', () {
      final r = computeBalances(
        accounts: [_acc(1, initial: 100000)],
        cards: [_card(10)],
        txs: [
          _expenseAcc('2026-06-05', 30000, accountId: 999), // 없는 계좌
          _expenseCard('2026-06-05', 40000, cardId: 888), // 없는 카드
        ],
        cutoff: '2026-06-30',
      );
      expect(r.byAccount[1], 100000); // 영향 없음
      expect(r.byCard[10], 0);
      expect(r.totalBalance, 100000);
    });
  });

  group('종합 시나리오', () {
    test('여러 계좌·카드 혼합', () {
      final r = computeBalances(
        accounts: [_acc(1, initial: 500000), _acc(2, initial: 200000)],
        cards: [_card(10), _card(20)],
        txs: [
          _income('2026-06-01', 3000000, accountId: 1), // 월급
          _expenseAcc('2026-06-03', 50000, accountId: 1), // 현금 지출
          _expenseCard('2026-06-04', 80000, cardId: 10), // 카드10 사용
          _expenseCard('2026-06-05', 25000, cardId: 20), // 카드20 사용
          _transfer('2026-06-06', 100000, from: 1, to: 2), // 이체
          _cardPayment('2026-06-15', 80000, from: 1, cardId: 10), // 카드10 결제
        ],
        cutoff: '2026-06-30',
      );
      // 계좌1: 500000 + 3000000 - 50000 - 100000(이체) - 80000(결제) = 3270000
      expect(r.byAccount[1], 3270000);
      // 계좌2: 200000 + 100000 = 300000
      expect(r.byAccount[2], 300000);
      expect(r.accountsBalance, 3570000);
      // 카드10: 80000 - 80000 = 0, 카드20: 25000
      expect(r.byCard[10], 0);
      expect(r.byCard[20], 25000);
      expect(r.cardDebt, 25000);
      expect(r.totalBalance, 3545000); // 3570000 - 25000
    });
  });
}
