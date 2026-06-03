import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/account_meta.dart';
import '../widgets/amount_field.dart';
import '../widgets/asset_trend_chart.dart';
import '../widgets/common.dart';
import '../widgets/format.dart';
import '../widgets/ko_date_picker.dart';
import '../widgets/skeleton.dart';
import 'shell_screen.dart';

/// 자산 메인 탭. 총자산 카드 + 6개월 추이 차트 + 계좌별 잔고 CRUD.
class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  AssetSnapshot? _snapshot;
  Object? _error;
  bool _reloadScheduled = false;
  final ScrollController _scrollCtrl = ScrollController();

  late final Listenable _apiListenable = Listenable.merge([
    Api.instance.accountsVersion,
    Api.instance.txVersion,
  ]);

  @override
  void initState() {
    super.initState();
    _apiListenable.addListener(_onApiChanged);
    ShellTabSignals.accountsTab.addListener(_onTabPressed);
    _reload();
  }

  @override
  void dispose() {
    _apiListenable.removeListener(_onApiChanged);
    ShellTabSignals.accountsTab.removeListener(_onTabPressed);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onApiChanged() {
    if (_reloadScheduled || !mounted) return;
    _reloadScheduled = true;
    scheduleMicrotask(() {
      _reloadScheduled = false;
      if (mounted) _reload();
    });
  }

  void _onTabPressed() {
    if (!mounted) return;
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    _reload();
  }

  Future<void> _reload() async {
    try {
      // 자산 탭만 보는 사용자도 도래분 누락되지 않게 자동 적용 호출.
      // 직렬화·dedupe·log로 idempotent 보장.
      final now = DateTime.now();
      final ym =
          '${now.year}-${now.month.toString().padLeft(2, '0')}';
      await Api.instance.applyDueFixedTransactions(ym).catchError((_) => 0);
      final snap = await Api.instance.getAssetSnapshot();
      if (!mounted) return;
      setState(() {
        _snapshot = snap;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<void> _openEditor({Account? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl),
        ),
      ),
      builder: (ctx) => AccountEditor(existing: existing),
    );
    if (saved == true) _reload();
  }

  Future<void> _delete(AccountBalance a) async {
    final total = (_snapshot?.accounts ?? const []).length;
    if (total <= 1) {
      showToast(context, '최소 1개의 계좌가 필요해요', error: true);
      return;
    }
    final ok = await confirmDialog(
      context,
      title: '계좌 삭제',
      message: '"${a.name}"을(를) 삭제할까요?\n'
          '이 계좌를 쓰는 거래나 정기 거래가 있으면 삭제할 수 없어요.',
      confirmText: '삭제',
      danger: true,
    );
    if (!ok) return;
    try {
      await Api.instance.deleteAccount(a.accountId);
      if (!mounted) return;
      showToast(context, '삭제했어요');
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e), error: true);
    }
  }

  Future<void> _editFromBalance(AccountBalance a) async {
    // AccountBalance에서 Account 생성. sortOrder는 updateAccount가 미변경 처리.
    final asAccount = Account(
      id: a.accountId,
      name: a.name,
      type: a.type,
      initialBalance: a.initialBalance,
      sortOrder: 0,
      active: a.active,
    );
    await _openEditor(existing: asAccount);
  }

  Future<void> _openCardEditor({CardSummary? existing}) async {
    final accounts = (_snapshot?.accounts ?? const []).toList();
    if (accounts.isEmpty) {
      showToast(context, '입출금 계좌를 먼저 추가해주세요', error: true);
      return;
    }
    CreditCard? full;
    if (existing != null) {
      try {
        final list = await Api.instance.listCards();
        full = list.firstWhere((c) => c.id == existing.cardId);
      } catch (e) {
        if (mounted) showToast(context, errorMessage(e), error: true);
        return;
      }
    }
    if (!mounted) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl),
        ),
      ),
      builder: (ctx) => CardEditor(existing: full, accounts: accounts),
    );
    if (saved == true) _reload();
  }

  void _navigateToCardTransactions(CardSummary c) {
    final params = <String, String>{
      'cardId': c.cardId.toString(),
      'cardName': c.name,
    };
    if (c.cycleStart != null) params['from'] = c.cycleStart!;
    if (c.cycleEnd != null) params['to'] = c.cycleEnd!;
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    context.go('/transactions?$query');
  }

  Future<void> _openSettlement(CardSummary c) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl),
        ),
      ),
      builder: (ctx) => _CardSettlementSheet(card: c),
    );
    if (saved == true) _reload();
  }

  Future<void> _deleteCard(CardSummary c) async {
    final ok = await confirmDialog(
      context,
      title: '카드 삭제',
      message: '"${c.name}"을(를) 삭제할까요?\n'
          '이 카드를 쓴 거래가 있으면 삭제할 수 없어요.',
      confirmText: '삭제',
      danger: true,
    );
    if (!ok) return;
    try {
      await Api.instance.deleteCard(c.cardId);
      if (!mounted) return;
      showToast(context, '삭제했어요');
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_accounts',
        onPressed: () => _openEditor(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('계좌 추가'),
      ),
      body: SafeArea(
        child: Builder(
          builder: (context) {
            if (_snapshot == null) {
              if (_error != null) {
                return Center(child: Text(errorMessage(_error!)));
              }
              return ListView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 90),
                children: [
                  const PageHeader(
                    title: '자산',
                    subtitle: '계좌·카드를 한눈에 모아서 흐름을 추적해요',
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: AppCard(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SkeletonLine(width: 80, height: 12),
                        SizedBox(height: 8),
                        SkeletonLine(width: 180, height: 26),
                        SizedBox(height: 18),
                        Skeleton(height: 120, radius: 8),
                      ],
                    ),
                  ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        for (var i = 0; i < 3; i++) ...[
                          AppCard(
                            padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
                            child: Row(
                              children: const [
                                Skeleton(width: 36, height: 36, radius: 18),
                                SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SkeletonLine(width: 100, height: 16),
                                      SizedBox(height: 8),
                                      SkeletonLine(width: 60, height: 12),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            }
            final snap = _snapshot!;
            if (snap.accounts.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    '계좌가 아직 없어요.\n오른쪽 아래 버튼으로 추가해보세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.text3,
                      height: 1.6,
                    ),
                  ),
                ),
              );
            }
            // 가상화: PageHeader/총자산/섹션 헤더 + 계좌·카드 row를 단일
            // ListView.builder로. 화면 밖 row는 빌드 안 됨.
            final items = <Widget Function(BuildContext)>[];
            items.add((_) => const PageHeader(
                  title: '자산',
                  subtitle: '계좌·카드를 한눈에 모아서 흐름을 추적해요',
                ));
            items.add((_) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: _TotalAssetsCard(snapshot: snap),
                ));
            items.add((_) => const SizedBox(height: 14));
            items.add((_) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Text(
                    '내 계좌',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text2,
                    ),
                  ),
                ));
            for (final a in snap.accounts) {
              items.add((_) => Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: _AccountCard(
                      account: a,
                      onTap: () => _editFromBalance(a),
                      onDelete: () => _delete(a),
                    ),
                  ));
            }
            items.add((_) => const SizedBox(height: 14));
            items.add((_) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _CardSectionHeader(
                    onAdd: () => _openCardEditor(),
                  ),
                ));
            items.add((_) => const SizedBox(height: 8));
            if (snap.cards.isEmpty) {
              items.add((_) => Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      '신용카드를 등록하면 사용액·결제일·연동 계좌를 함께 추적할 수 있어요.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.text3,
                        height: 1.55,
                      ),
                    ),
                  ));
            } else {
              for (final c in snap.cards) {
                items.add((_) => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: _CardCard(
                        card: c,
                        onTap: () => _navigateToCardTransactions(c),
                        onEdit: () => _openCardEditor(existing: c),
                        onSettle: () => _openSettlement(c),
                        onDelete: () => _deleteCard(c),
                      ),
                    ));
              }
            }
            return ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 90),
              itemCount: items.length,
              itemBuilder: (ctx, i) => items[i](ctx),
            );
          },
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.onTap,
    required this.onDelete,
  });
  final AccountBalance account;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final meta = accountMeta(account.type);
    final isNegative = account.balance < 0;
    return AppCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
          child: Row(
              children: [
                AccountBadge(account.type, size: 38),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        meta.label,
                        style: TextStyle(
                          fontSize: 12,
                          color: meta.fg,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${won(account.balance)}원',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: isNegative
                            ? AppColors.danger
                            : AppColors.text,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (account.initialBalance != 0)
                      Text(
                        '시작 ${won(account.initialBalance)}원',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.text4,
                          fontFeatures: const [
                            FontFeature.tabularFigures()
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onDelete,
                  tooltip: '삭제',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.delete_outline,
                    color: AppColors.text3,
                    size: 20,
                  ),
                ),
              ],
            ),
        ),
      ),
    );
  }
}

class _CardSectionHeader extends StatelessWidget {
  const _CardSectionHeader({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          Text(
            '신용카드',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.text2,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('카드 추가'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "2026-04-07" → "4.7"
String _shortMD(String iso) {
  final p = iso.split('-');
  if (p.length != 3) return iso;
  return '${int.parse(p[1])}.${int.parse(p[2])}';
}

class _CardCard extends StatelessWidget {
  const _CardCard({
    required this.card,
    required this.onTap,
    required this.onEdit,
    required this.onSettle,
    required this.onDelete,
  });
  final CardSummary card;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onSettle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final needsSettle = card.needsSettlement;
    final dLabel = needsSettle
        ? '결제일 지남'
        : (card.daysUntilPayment == 0
            ? '오늘 결제'
            : 'D-${card.daysUntilPayment}');
    // 메타 라인 — "매월 N일 결제 · 연동 계좌". 빡빡함 줄이려고 두 줄을 한 줄로.
    final metaParts = <String>['매월 ${card.paymentDay}일 결제'];
    final linked = card.linkedAccountName;
    if (linked != null && linked.isNotEmpty) metaParts.add(linked);
    final metaText = metaParts.join(' · ');
    // 사이클 + D-day 한 줄로 우측 작게.
    String? rightMeta;
    if (card.cycleStart != null && card.cycleEnd != null) {
      rightMeta =
          '${_shortMD(card.cycleStart!)}~${_shortMD(card.cycleEnd!)} · $dLabel';
    } else {
      rightMeta = dLabel;
    }
    // 카드 row 큰 숫자 — *남은* 청구액(사용액 − 이번 사이클에 이미 결제한 금액).
    // 미리 결제·분할 결제하면 그만큼 줄어들어 보임 — 사용자 직관(토스/뱅샐 톤).
    // 음수 가능 (과결제) → 0으로 클램프.
    final remainingBilling = (card.cycleAmount - card.cycleSettled)
        .clamp(0, 1 << 31);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 4, 14),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.expenseBg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.credit_card,
                          color: AppColors.expenseText, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            metaText,
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          remainingBilling > 0
                              ? '-${won(remainingBilling)}원'
                              : '${won(remainingBilling)}원',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: remainingBilling > 0
                                ? AppColors.expenseText
                                : AppColors.text,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          rightMeta,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: needsSettle
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: needsSettle
                                ? AppColors.danger
                                : AppColors.text4,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (card.cycleSettled > 0) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${won(card.cycleSettled)}원 결제됨',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.success,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    IconButton(
                      onPressed: () => _showCardActions(context),
                      tooltip: '카드 메뉴',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.more_vert,
                        color: AppColors.text3,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 결제일 지났는데 미정산 → 빨간 액션 줄.
            if (needsSettle)
              Material(
                color: AppColors.expenseBg,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(AppRadius.xl),
                ),
                child: InkWell(
                  onTap: onSettle,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(AppRadius.xl),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 14, 10),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 16, color: AppColors.expenseText),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '이번 달 결제일이 지났어요. 청구액 등록하기',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.expenseText,
                            ),
                          ),
                        ),
                        Icon(Icons.chevron_right,
                            size: 18, color: AppColors.expenseText),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
    );
  }

  /// 카드 메뉴 시트 — 우측 ⋮ 탭 시. 편집·결제 등록·삭제 한 곳에 모아 행 자체의
  /// 시각 무게를 줄임.
  void _showCardActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl),
        ),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Row(
                  children: [
                    Text(
                      card.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                  ],
                ),
              ),
              _CardActionTile(
                icon: Icons.edit_outlined,
                label: '카드 정보 수정',
                onTap: () {
                  Navigator.of(ctx).pop();
                  onEdit();
                },
              ),
              _CardActionTile(
                icon: Icons.receipt_long_outlined,
                label: '청구액 결제 등록',
                onTap: () {
                  Navigator.of(ctx).pop();
                  onSettle();
                },
              ),
              _CardActionTile(
                icon: Icons.delete_outline,
                label: '카드 삭제',
                danger: true,
                onTap: () {
                  Navigator.of(ctx).pop();
                  onDelete();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _CardActionTile extends StatelessWidget {
  const _CardActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.text;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 카드 결제일 정산 시트 — 자동 합계 + 사용자 수정 + 청구일 입력.
class _CardSettlementSheet extends StatefulWidget {
  const _CardSettlementSheet({required this.card});
  final CardSummary card;

  @override
  State<_CardSettlementSheet> createState() => _CardSettlementSheetState();
}

class _CardSettlementSheetState extends State<_CardSettlementSheet> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _dateCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController();
    // 자동 채움 = 사이클 사용액 − 이번 사이클에 이미 결제한 금액. 미리·분할 결제도
    // 자연스럽게 *남은* 청구액으로 채워짐. 음수가 되면 0으로 클램프(과결제 상태).
    final remaining = widget.card.cycleAmount - widget.card.cycleSettled;
    AmountField.setNumber(_amountCtrl, remaining > 0 ? remaining : 0);
    // 기본 청구일 — 이번 달 결제일.
    final now = DateTime.now();
    final pay = DateTime(now.year, now.month, widget.card.paymentDay);
    _dateCtrl = TextEditingController(
      text:
          '${pay.year}-${pay.month.toString().padLeft(2, '0')}-${pay.day.toString().padLeft(2, '0')}',
    );
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _dateCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    // 결제 거래는 *실제로 통장에서 빠지는 시점*이라 미래 일자 허용 — 결제일이
    // 며칠 후라면 그 날짜로 등록해도 자산은 도래 후 반영(미래 거래 제외 로직).
    final now = DateTime.now();
    final initial = DateTime.tryParse(_dateCtrl.text) ?? now;
    final picked = await showKoDatePicker(
      context: context,
      initial: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      _dateCtrl.text =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() {});
    }
  }

  /// 청구액 입력란 아래 안내 — 미리 결제·분할 결제 상황을 보여줘서 사용자가
  /// 자동 채움 값이 왜 그렇게 들어갔는지 이해할 수 있게.
  String _autoFillHint() {
    final cycle = widget.card.cycleAmount;
    final settled = widget.card.cycleSettled;
    if (settled <= 0) {
      return '사이클 사용액 ${won(cycle)}원이 자동으로 채워졌어요. 카드사 명세서 보고 다르면 수정.';
    }
    final remaining = cycle - settled;
    if (remaining > 0) {
      return '사이클 사용액 ${won(cycle)}원 중 이미 ${won(settled)}원이 결제됐어요. 남은 ${won(remaining)}원이 채워졌어요.';
    }
    return '사이클 사용액 ${won(cycle)}원이 이미 결제 완료됐어요 (${won(settled)}원). 추가 등록할 금액을 직접 입력해주세요.';
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final amount = AmountField.parse(_amountCtrl);
    if (amount == null || amount <= 0) {
      showToast(context, '청구액을 입력해주세요', error: true);
      return;
    }
    if (_dateCtrl.text.isEmpty) {
      showToast(context, '결제일을 입력해주세요', error: true);
      return;
    }
    // 더블 컨펌 — 결제 거래는 계좌에서 실제로 빠지는 거고, 자동 되돌릴 수 없음.
    final ok = await confirmDialog(
      context,
      title: '결제 등록할까요?',
      message: '${widget.card.name} ${won(amount)}원이 '
          '${widget.card.linkedAccountName ?? "연동 계좌"}에서 빠지는 거래로 등록돼요.\n\n'
          '카드사 명세서 청구액과 같은지 확인했나요? '
          '잘못 등록했으면 거래내역에서 그 출금 거래를 삭제하면 카드 부채가 다시 돌아와서 재등록할 수 있어요.',
      confirmText: '등록',
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      await Api.instance.createTransaction(
        date: _dateCtrl.text,
        amount: amount,
        majorCategory: '카드결제',
        merchant: '${widget.card.name} 결제',
        type: 'card_payment',
        fromAccountId: widget.card.linkedAccountId,
        cardId: widget.card.cardId,
      );
      if (mounted) {
        showToast(context, '결제 등록 완료');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                '${widget.card.name} 결제 등록',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.card.linkedAccountName ?? "연동 계좌"}에서 청구액이 빠져나가는 거래로 등록돼요.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.text3,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              AmountField(controller: _amountCtrl, label: '청구액'),
              const SizedBox(height: 6),
              Text(
                _autoFillHint(),
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.text3,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _pickDate,
                child: AbsorbPointer(
                  child: TextField(
                    controller: _dateCtrl,
                    decoration: InputDecoration(
                      labelText: '결제일',
                      suffixIcon: Icon(
                        Icons.calendar_today,
                        size: 18,
                        color: AppColors.text3,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(_saving ? '등록 중...' : '결제 등록'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CardEditor extends StatefulWidget {
  const CardEditor({super.key, this.existing, required this.accounts});
  final CreditCard? existing;
  final List<AccountBalance> accounts;

  @override
  State<CardEditor> createState() => CardEditorState();
}

class CardEditorState extends State<CardEditor> {
  late final TextEditingController _nameCtrl;
  late int _paymentDay;
  late int _linkedAccountId;
  int? _statementCloseDay;
  // BottomSheet 안에서 SnackBar는 모달에 가려져서, 마감일 검증은 inline으로.
  bool _closeDayError = false;
  bool _saving = false;
  // 결제 거래가 있는 카드는 결제일·마감일 변경 차단 — 옛 결제는 옛 약관 기준.
  int _paymentCount = 0;

  bool get _isEdit => widget.existing != null;
  bool get _cycleLocked => _isEdit && _paymentCount > 0;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _nameCtrl = TextEditingController(text: ex?.name ?? '');
    _paymentDay = ex?.paymentDay ?? 25;
    _linkedAccountId = ex?.linkedAccountId ?? widget.accounts.first.accountId;
    _statementCloseDay = ex?.statementCloseDay;
    if (ex != null) _loadPaymentCount(ex.id);
  }

  Future<void> _loadPaymentCount(int cardId) async {
    try {
      final n = await Api.instance.countCardPayments(cardId);
      if (!mounted) return;
      setState(() => _paymentCount = n);
    } catch (_) {/* 카운트 조회 실패해도 흐름은 계속 (default 0 = 변경 가능) */}
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showToast(context, '카드 이름을 입력해주세요', error: true);
      return;
    }
    if (_statementCloseDay == null) {
      setState(() => _closeDayError = true);
      return;
    }

    final ex = widget.existing;
    setState(() => _saving = true);
    try {
      if (ex == null) {
        await Api.instance.createCard(
          name: name,
          paymentDay: _paymentDay,
          linkedAccountId: _linkedAccountId,
          statementCloseDay: _statementCloseDay,
        );
        if (mounted) showToast(context, '카드 추가 완료');
      } else {
        // 결제 거래 있는 카드는 결제일·마감일이 잠겨 있어 변경 안 됨 (UI에서 차단).
        // 안전망: 보내는 값이 기존과 다르면 무시 (변경 사항 null).
        await Api.instance.updateCard(
          ex.id,
          name: name == ex.name ? null : name,
          paymentDay: _cycleLocked || _paymentDay == ex.paymentDay
              ? null
              : _paymentDay,
          linkedAccountId: _linkedAccountId == ex.linkedAccountId
              ? null
              : _linkedAccountId,
          statementCloseDay:
              _cycleLocked ? ex.statementCloseDay : _statementCloseDay,
        );
        if (mounted) showToast(context, '수정했어요');
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                _isEdit ? '카드 수정' : '신용카드 추가',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtrl,
                autofocus: !_isEdit,
                decoration: const InputDecoration(
                  labelText: '카드 이름',
                  hintText: '예: 신한카드, 현대카드',
                ),
              ),
              const SizedBox(height: 18),
              if (_cycleLocked) ...[
                _LockedDayField(
                  label: '결제일 (매월)',
                  text: '$_paymentDay일',
                ),
                const SizedBox(height: 12),
              ] else ...[
                AppDropdown<int>(
                  label: '결제일 (매월)',
                  value: _paymentDay,
                  items: [
                    for (var d = 1; d <= 31; d++)
                      AppDropdownItem(value: d, label: '$d일'),
                  ],
                  onChanged: (v) => setState(() => _paymentDay = v),
                ),
                const SizedBox(height: 12),
              ],
              AppDropdown<int>(
                label: '연동 계좌 (결제일에 빠질 곳)',
                value: _linkedAccountId,
                items: [
                  for (final a in widget.accounts)
                    AppDropdownItem(value: a.accountId, label: a.name),
                ],
                onChanged: (v) => setState(() => _linkedAccountId = v),
              ),
              const SizedBox(height: 12),
              if (_cycleLocked) ...[
                _LockedDayField(
                  label: '사용 마감일 (매월)',
                  text: _statementCloseDay != null
                      ? '$_statementCloseDay일'
                      : '없음',
                ),
                const SizedBox(height: 8),
                _CycleLockedNotice(paymentCount: _paymentCount),
              ] else ...[
                AppDropdown<int>(
                  label: '사용 마감일 (매월)',
                  value: _statementCloseDay,
                  items: [
                    for (var d = 1; d <= 31; d++)
                      AppDropdownItem(value: d, label: '$d일'),
                  ],
                  onChanged: (v) => setState(() {
                    _statementCloseDay = v;
                    _closeDayError = false;
                  }),
                ),
                const SizedBox(height: 6),
                _closeDayHelp(highlightError: _closeDayError),
              ],
              const SizedBox(height: 22),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(_saving ? '저장 중...' : '저장'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 사용 마감일 안내 + 처음 사용자를 위한 펼치기 가이드.
  /// highlightError=true면 첫 줄을 빨간 에러 톤으로 토글 (펼치기는 유지).
  Widget _closeDayHelp({bool highlightError = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          highlightError
              ? '사용 마감일을 골라주세요'
              : '이 날 이후 사용분은 다음 달 결제로 넘어가요.',
          style: TextStyle(
            fontSize: 11.5,
            color: highlightError ? AppColors.danger : AppColors.text3,
            fontWeight:
                highlightError ? FontWeight.w600 : FontWeight.w400,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 4),
        Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
            iconColor: AppColors.text3,
            collapsedIconColor: AppColors.text3,
            visualDensity: VisualDensity.compact,
            title: Text(
              '마감일은 어디서 보나요?',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '·  카드사 앱 → "결제예정금액" 또는 "이용내역" 화면\n'
                  '·  종이 명세서 첫 페이지 (예: "OO/OO ~ OO/OO 사용분")\n'
                  '·  카드사마다 달라요. 같은 카드사라도 카드 종류별로 다르니 본인 카드 명세서로 확인해주세요',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.text3,
                    height: 1.65,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 결제일·마감일이 잠긴 read-only 표시. 결제 거래가 1건이라도 있으면 변경 차단.
class _LockedDayField extends StatelessWidget {
  const _LockedDayField({required this.label, required this.text});
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.text3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text2,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.lock_outline,
              size: 16, color: AppColors.text3),
        ],
      ),
    );
  }
}

/// 결제 거래가 있는 카드는 결제일·마감일이 잠겼다는 안내.
class _CycleLockedNotice extends StatelessWidget {
  const _CycleLockedNotice({required this.paymentCount});
  final int paymentCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
              '이 카드의 결제 거래가 $paymentCount건 있어 결제일·마감일을 바꿀 수 없어요. '
              '카드 약관이 진짜 바뀌었다면 새 카드로 등록해주세요.',
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFF8A6A00),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 자산 탭 상단 — 총 자산 큰 숫자 + 6개월 추이 차트.
class _TotalAssetsCard extends StatelessWidget {
  const _TotalAssetsCard({required this.snapshot});
  final AssetSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final accountCount = snapshot.accounts.length;
    final firstTrend =
        snapshot.trend.isNotEmpty ? snapshot.trend.first : null;
    final lastTrend =
        snapshot.trend.isNotEmpty ? snapshot.trend.last : null;
    int? delta;
    if (firstTrend != null && lastTrend != null) {
      delta = lastTrend.totalAssets - firstTrend.totalAssets;
    }
    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '총 자산',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.text3,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  won(snapshot.totalBalance),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                    letterSpacing: -0.4,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '원',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '계좌 $accountCount개',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.text3,
                ),
              ),
              if (delta != null && delta != 0) ...[
                Text(
                  '  ·  ',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.text4),
                ),
                Text(
                  '6개월 ${delta >= 0 ? '+' : ''}${won(delta)}원',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: delta >= 0
                        ? AppColors.success
                        : AppColors.danger,
                  ),
                ),
              ],
            ],
          ),
          if (snapshot.cardDebt > 0) ...[
            const SizedBox(height: 4),
            Text(
              '계좌 ${won(snapshot.accountsBalance)}원 − 카드 미정산 ${won(snapshot.cardDebt)}원',
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.text4,
              ),
            ),
          ],
          const SizedBox(height: 14),
          AssetTrendChart(trend: snapshot.trend),
        ],
      ),
    );
  }
}

class AccountEditor extends StatefulWidget {
  const AccountEditor({super.key, this.existing});
  final Account? existing;

  @override
  State<AccountEditor> createState() => AccountEditorState();
}

class AccountEditorState extends State<AccountEditor> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _balCtrl;
  late AccountType _type;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _nameCtrl = TextEditingController(text: ex?.name ?? '');
    _balCtrl = TextEditingController(
      text: ex == null || ex.initialBalance == 0
          ? ''
          : won(ex.initialBalance),
    );
    _type = ex?.type ?? AccountType.checking;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _balCtrl.dispose();
    super.dispose();
  }

  int _parseBal() {
    final raw = _balCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (raw.isEmpty) return 0;
    return int.tryParse(raw) ?? 0;
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showToast(context, '계좌 이름을 입력해주세요', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final bal = _parseBal();
      final ex = widget.existing;
      if (ex == null) {
        await Api.instance.createAccount(
          name: name,
          type: _type,
          initialBalance: bal,
        );
        if (mounted) showToast(context, '추가했어요');
      } else {
        await Api.instance.updateAccount(
          ex.id,
          name: name == ex.name ? null : name,
          type: _type == ex.type ? null : _type,
          initialBalance: bal == ex.initialBalance ? null : bal,
        );
        if (mounted) showToast(context, '수정했어요');
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                _isEdit ? '계좌 수정' : '새 계좌',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtrl,
                autofocus: !_isEdit,
                decoration: const InputDecoration(
                  labelText: '계좌 이름',
                  hintText: '예: 신한 체크, 카카오뱅크, 현금',
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 18),
              Text(
                '종류',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text2,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in AccountType.values)
                    _TypeChip(
                      type: t,
                      selected: _type == t,
                      onTap: () => setState(() => _type = t),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              AmountField(
                controller: _balCtrl,
                label: '시작 잔고 (선택)',
                hint: '0',
              ),
              const SizedBox(height: 6),
              Text(
                '비워두면 0원으로 시작해요. 자산 흐름 차트의 출발점이에요.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.text3,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(_saving ? '저장 중...' : '저장'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.type,
    required this.selected,
    required this.onTap,
  });
  final AccountType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = accountMeta(type);
    return Material(
      color: selected ? m.bg : AppColors.surface2,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected ? m.fg.withValues(alpha: 0.4) : AppColors.line2,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                m.icon,
                size: 15,
                color: selected ? m.fg : AppColors.text3,
              ),
              const SizedBox(width: 6),
              Text(
                m.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? m.fg : AppColors.text2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
