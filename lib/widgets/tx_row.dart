import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';
import 'category_color.dart';
import 'common.dart';
import 'format.dart';

/// 거래내역 한 줄.
class TxRow extends StatelessWidget {
  const TxRow({
    super.key,
    required this.tx,
    this.isRecurring = false,
    this.accountsById = const {},
    this.cardsById = const {},
    this.onTap,
  });
  final Tx tx;
  final bool isRecurring;
  /// 이체·카드 결제 거래의 계좌 이름 표시용. {id: name}.
  final Map<int, String> accountsById;
  /// 카드 거래의 카드 이름 표시용. {id: name}.
  final Map<int, String> cardsById;
  final VoidCallback? onTap;

  /// 거래 일자가 오늘 이후 — 자산 계산 미반영(도래일에 자동 반영).
  bool get _isPending {
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return tx.date.compareTo(today) > 0;
  }

  Widget _pendingPill() => Pill(
        label: '예정',
        color: AppColors.text3,
        bg: AppColors.surface2,
      );

  @override
  Widget build(BuildContext context) {
    final isIncome = tx.type == 'income';
    final isTransfer = tx.type == 'transfer';
    final isCardPayment = tx.type == 'card_payment';
    final isCardExpense = tx.type == 'expense' && tx.cardId != null;
    if (isTransfer) return _buildTransfer(context);
    if (isCardPayment) return _buildCardPayment(context);

    final meta = StringBuffer(tx.majorCategory);
    if (tx.subCategory?.isNotEmpty ?? false) meta.write(' · ${tx.subCategory}');
    // 결제수단 표시 — card_id면 카드 이름, account_id면 계좌 이름. 자유 텍스트
    // (옛 '자동이체'·'이체' 등)는 무시 — account_id/card_id가 정확한 정보원.
    if (isCardExpense && tx.cardId != null) {
      final cardName = cardsById[tx.cardId!];
      if (cardName != null) meta.write(' · $cardName');
    } else if (tx.accountId != null) {
      final accName = accountsById[tx.accountId!];
      if (accName != null) meta.write(' · $accName');
    } else if (tx.card?.isNotEmpty ?? false) {
      // 매핑 불가능한 옛 거래 fallback.
      meta.write(' · ${tx.card}');
    }
    if (tx.memo?.isNotEmpty ?? false) meta.write(' · ${tx.memo}');

    // 수입은 파란색 강조. 지출은 기본 텍스트(다크모드 자동 분기).
    // 지출=빨강, 수입=파랑 — 거래 추가 시트의 [지출][수입] 버튼 톤과 동일.
    final amountColor =
        isIncome ? AppColors.incomeText : AppColors.expenseText;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            CategoryDot(tx.majorCategory, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          tx.merchant?.isNotEmpty == true
                              ? tx.merchant!
                              : (isIncome ? '(받은 곳 없음)' : '(가맹점 없음)'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      if (isIncome) ...[
                        const SizedBox(width: 6),
                        Pill(
                          label: '수입',
                          color: AppColors.incomeText,
                          bg: AppColors.incomeBg,
                        ),
                      ],
                      if (isCardExpense) ...[
                        const SizedBox(width: 6),
                        Pill(
                          label: '카드',
                          color: AppColors.expenseText,
                          bg: AppColors.expenseBg,
                        ),
                      ],
                      // isFixed (자동 등록 거래) + isRecurring (카탈로그 매칭) —
                      // 둘은 거의 항상 동시 만족하므로 하나의 '정기' pill로 통합.
                      if (tx.isFixed || isRecurring) ...[
                        const SizedBox(width: 6),
                        Pill(
                            label: '정기',
                            color: AppColors.success,
                            bg: Color(0xFFDFF7EB)),
                      ],
                      if (_isPending) ...[
                        const SizedBox(width: 4),
                        _pendingPill(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(meta.toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.text3,
                      )),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text('${isIncome ? '+' : '−'}${won(tx.amount)}원',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: amountColor,
                  fontFeatures: [FontFeature.tabularFigures()],
                )),
            Icon(Icons.chevron_right,
                color: AppColors.text4, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildCardPayment(BuildContext context) {
    final cardName = (tx.cardId != null
            ? cardsById[tx.cardId!]
            : null) ??
        '카드';
    final accountName = (tx.fromAccountId != null
            ? accountsById[tx.fromAccountId!]
            : null) ??
        '계좌';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.expenseBg,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.credit_card,
                  size: 19, color: AppColors.expenseText),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '$cardName 결제',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Pill(
                        label: '카드 결제',
                        color: AppColors.expenseText,
                        bg: AppColors.expenseBg,
                      ),
                      if (_isPending) ...[
                        const SizedBox(width: 4),
                        _pendingPill(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$accountName에서 인출',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.text3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text('${won(tx.amount)}원',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                  fontFeatures: [FontFeature.tabularFigures()],
                )),
            Icon(Icons.chevron_right,
                color: AppColors.text4, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildTransfer(BuildContext context) {
    final fromName = (tx.fromAccountId != null
            ? accountsById[tx.fromAccountId!]
            : null) ??
        '계좌';
    final toName = (tx.toAccountId != null
            ? accountsById[tx.toAccountId!]
            : null) ??
        '계좌';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.swap_horiz,
                  size: 20, color: AppColors.text3),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '$fromName → $toName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Pill(
                        label: '이체',
                        color: AppColors.text2,
                        bg: AppColors.surface2,
                      ),
                      if (_isPending) ...[
                        const SizedBox(width: 4),
                        _pendingPill(),
                      ],
                    ],
                  ),
                  if (tx.memo?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 2),
                    Text(tx.memo!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.text3,
                        )),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text('${won(tx.amount)}원',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text3,
                  fontFeatures: [FontFeature.tabularFigures()],
                )),
            Icon(Icons.chevron_right,
                color: AppColors.text4, size: 20),
          ],
        ),
      ),
    );
  }
}

/// 날짜 그룹 헤더.
class TxDayHeader extends StatelessWidget {
  const TxDayHeader({super.key, required this.date, required this.total});
  final String date; // YYYY-MM-DD
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(fmtDate(date),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.text3,
              )),
          Text('${won(total)}원',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.text3,
                fontFeatures: [FontFeature.tabularFigures()],
              )),
        ],
      ),
    );
  }
}
