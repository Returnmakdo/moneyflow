import 'package:flutter/material.dart';

import '../api/models.dart';

/// 계좌 type별 한국어 라벨/아이콘/색.
/// category_color.dart와 같은 8색 팔레트 톤.
class AccountMeta {
  const AccountMeta({
    required this.label,
    required this.icon,
    required this.bg,
    required this.fg,
  });
  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;
}

const _meta = <AccountType, AccountMeta>{
  AccountType.checking: AccountMeta(
    label: '입출금',
    icon: Icons.account_balance,
    bg: Color(0xFFE0EDFF),
    fg: Color(0xFF1D4ED8),
  ),
  AccountType.cash: AccountMeta(
    label: '현금',
    icon: Icons.payments_outlined,
    bg: Color(0xFFDCFCE7),
    fg: Color(0xFF15803D),
  ),
  AccountType.savings: AccountMeta(
    label: '예적금',
    icon: Icons.savings_outlined,
    bg: Color(0xFFEDE9FE),
    fg: Color(0xFF6D28D9),
  ),
  AccountType.investment: AccountMeta(
    label: '투자',
    icon: Icons.trending_up,
    bg: Color(0xFFFFF1E0),
    fg: Color(0xFFC2410C),
  ),
  AccountType.other: AccountMeta(
    label: '기타',
    icon: Icons.account_balance_wallet_outlined,
    bg: Color(0xFFF3F4F6),
    fg: Color(0xFF4B5563),
  ),
};

AccountMeta accountMeta(AccountType type) =>
    _meta[type] ?? _meta[AccountType.other]!;

/// 계좌 식별용 둥근 아이콘 배지.
class AccountBadge extends StatelessWidget {
  const AccountBadge(this.type, {super.key, this.size = 36});
  final AccountType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final m = accountMeta(type);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: m.bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(m.icon, color: m.fg, size: size * 0.55),
    );
  }
}
