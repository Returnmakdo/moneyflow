import 'package:flutter/material.dart';

import '../theme.dart';

/// KPI 강조 색.
/// - expense: 지출 (빨강)
/// - income: 수입 (파랑)
/// - good: 흑자/저축 양수 (초록)
/// - bad: 적자 (빨강 강함)
/// - neutral: 보조 정보 (검정)
enum KpiAccent { expense, income, good, bad, neutral }

/// 대시보드 KPI 카드.
/// accent로 value 색을 분기. 카드 배경은 모두 동일해서 시각 평탄.
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.unit = '원',
    this.delta,
    this.deltaExtra,
    this.accent = KpiAccent.neutral,
  });
  final String label;
  final String value; // 큰 숫자
  final String unit;
  final String? delta;
  final String? deltaExtra;
  final KpiAccent accent;

  Color _valueColor() {
    switch (accent) {
      case KpiAccent.expense:
        return AppColors.text; // 지출 = 검정 (기본 강조)
      case KpiAccent.income:
        return AppColors.incomeText;
      case KpiAccent.good:
        return AppColors.success;
      case KpiAccent.bad:
        return AppColors.danger;
      case KpiAccent.neutral:
        return AppColors.text;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = _valueColor();
    final fg2 = AppColors.text3;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: const [
          BoxShadow(color: Color(0x0A0F172A), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                color: fg2,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              )),
          const SizedBox(height: 6),
          // 카드 너비가 좁아져도 금액이 잘리지 않도록 FittedBox로 자동 축소.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    color: fg,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.02,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 2),
                Text(unit,
                    style: TextStyle(
                      color: fg2,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
          ),
          if (delta != null) ...[
            const SizedBox(height: 6),
            Text(delta!,
                style: TextStyle(
                  fontSize: 11.5,
                  color: fg2,
                  fontWeight: FontWeight.w500,
                )),
          ],
          if (deltaExtra != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(deltaExtra!,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: fg2,
                    fontWeight: FontWeight.w500,
                  )),
            ),
        ],
      ),
    );
  }
}
