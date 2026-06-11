import 'models.dart';

// 자산 잔고·카드 부채 계산을 순수 함수로 분리. DB 의존 없음 —
// `getAssetSnapshot`이 fetch한 (accounts, cards, txs)로 호출. 단위 테스트 대상.
//
// 발생주의(accrual) 모델 (토스/뱅샐 동일):
//   계좌 잔고 = initial_balance + Σ(거래 변동)
//   카드 미정산 = Σ(카드 사용) − Σ(카드 결제)
//   총자산 = 계좌 잔고 합 − 카드 미정산 합

/// 거래 한 건이 계좌/카드 잔고 맵에 주는 변동을 누적한다.
///
/// [byAcc]/[byCard]에 *이미 존재하는* 키만 갱신한다 — 삭제된 계좌/카드를
/// 참조하는 거래는 무시(그 잔고에 안 잡힘). 키 부재 시 무시하는 게 의도된 동작.
void applyTxDelta(Tx t, Map<int, int> byAcc, Map<int, int> byCard) {
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
        // 카드 사용 — 자산에 즉시 영향 X, 카드 부채 +
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
      // 통장 −, 카드 부채 − (자산 이동, 총자산 변동 없음)
      addAcc(t.fromAccountId, -t.amount);
      addCard(t.cardId, -t.amount);
      break;
  }
}

/// 잔고 계산 결과.
class BalanceResult {
  /// accountId → 잔고 (initial_balance + Σ변동).
  final Map<int, int> byAccount;

  /// cardId → 미정산 부채 (Σ사용 − Σ결제).
  final Map<int, int> byCard;

  /// 활성/비활성 구분 없이 모든 계좌 잔고 합.
  final int accountsBalance;

  /// 모든 카드 미정산 부채 합.
  final int cardDebt;

  const BalanceResult({
    required this.byAccount,
    required this.byCard,
    required this.accountsBalance,
    required this.cardDebt,
  });

  /// 총자산 = 계좌 잔고 합 − 카드 부채 합.
  int get totalBalance => accountsBalance - cardDebt;
}

/// [cutoff] (YYYY-MM-DD, 포함) 시점까지의 계좌 잔고·카드 부채를 계산.
///
/// cutoff보다 *미래 일자* 거래는 제외 — 정기지출을 미리 일괄 등록해도 도래
/// 전엔 자산에서 안 빠지는 가계부 표준 동작. 현재 시점 스냅샷은 cutoff=오늘,
/// 과거 월 추이는 cutoff=그 월 말일로 호출한다.
BalanceResult computeBalances({
  required List<Account> accounts,
  required List<CreditCard> cards,
  required List<Tx> txs,
  required String cutoff,
}) {
  final byAcc = <int, int>{for (final a in accounts) a.id: a.initialBalance};
  final byCard = <int, int>{for (final c in cards) c.id: 0};
  for (final t in txs) {
    if (t.date.compareTo(cutoff) > 0) continue;
    applyTxDelta(t, byAcc, byCard);
  }
  final accountsBalance =
      accounts.fold<int>(0, (s, a) => s + (byAcc[a.id] ?? a.initialBalance));
  final cardDebt = cards.fold<int>(0, (s, c) => s + (byCard[c.id] ?? 0));
  return BalanceResult(
    byAccount: byAcc,
    byCard: byCard,
    accountsBalance: accountsBalance,
    cardDebt: cardDebt,
  );
}
