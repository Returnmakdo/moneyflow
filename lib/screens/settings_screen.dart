import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api.dart';
import '../data/changelog.dart';
import '../theme.dart';
import '../utils/csv_download_stub.dart'
    if (dart.library.html) '../utils/csv_download_web.dart';
import '../utils/nav_back.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _exporting = false;
  bool _hasUnseenChangelog = false;

  @override
  void initState() {
    super.initState();
    _checkChangelog();
    changelogSeenSignal.addListener(_checkChangelog);
  }

  @override
  void dispose() {
    changelogSeenSignal.removeListener(_checkChangelog);
    super.dispose();
  }

  Future<void> _checkChangelog() async {
    final unseen = await hasUnseenChangelog();
    if (!mounted) return;
    setState(() => _hasUnseenChangelog = unseen);
  }

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final csv = await Api.instance.exportTransactionsCsv();
      final ts = DateTime.now();
      final stamp =
          '${ts.year}${ts.month.toString().padLeft(2, '0')}${ts.day.toString().padLeft(2, '0')}';
      final shared =
          await triggerCsvDownload(csv, '씀씀_$stamp.csv');
      if (!mounted) return;
      if (!shared) showToast(context, 'CSV 파일을 다운로드했어요');
    } catch (e) {
      if (!mounted) return;
      showToast(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.text2),
          onPressed: () => goBackOr(context, '/dashboard'),
        ),
        title: Text(
          '설정',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _menuGroup([
              _MenuItem(
                icon: Icons.person_outline,
                title: '계정 관리',
                subtitle: '이름·비밀번호·회원 탈퇴',
                onTap: () => context.go('/settings/account'),
              ),
              _MenuItem(
                icon: Icons.category_outlined,
                title: '카테고리 관리',
                subtitle: '카테고리·태그 추가, 수정',
                onTap: () => context.go('/settings/categories'),
              ),
              _MenuItem(
                icon: Icons.repeat,
                title: '정기 거래 관리',
                subtitle: '월세·구독료·월급처럼 매달 반복되는 거래',
                onTap: () => context.go('/settings/fixed'),
              ),
              _MenuItem(
                icon: Icons.upload_file_outlined,
                title: '데이터 가져오기',
                subtitle: 'CSV로 거래 일괄 등록',
                onTap: () => context.go('/settings/import'),
              ),
              _MenuItem(
                icon: Icons.download_outlined,
                title: 'CSV 내보내기',
                subtitle: _exporting ? '다운로드 중...' : '모든 거래내역 다운로드',
                trailing: _exporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: _exporting ? null : _exportCsv,
              ),
              _MenuItem(
                icon: Icons.dark_mode_outlined,
                title: '테마',
                subtitle: '시스템 / 라이트 / 다크',
                onTap: () => context.go('/settings/theme'),
              ),
              _MenuItem(
                icon: Icons.help_outline,
                title: '도움말',
                subtitle: '소개 슬라이드 + 화면별 사용법',
                onTap: () => context.go('/settings/help'),
              ),
              _MenuItem(
                icon: Icons.campaign_outlined,
                title: '업데이트 소식',
                subtitle: '새로 추가된 기능과 개선사항',
                showBadge: _hasUnseenChangelog,
                onTap: () => context.go('/settings/changelog'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _menuGroup(List<_MenuItem> items) {
    return AppCard(
      tight: true,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Divider(height: 1, color: AppColors.line2),
              ),
            _MenuRow(
              item: items[i],
              isFirst: i == 0,
              isLast: i == items.length - 1,
            ),
          ],
        ],
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showBadge = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showBadge;
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.item,
    this.isFirst = false,
    this.isLast = false,
  });
  final _MenuItem item;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final r = Radius.circular(AppRadius.xl);
    final radius = BorderRadius.only(
      topLeft: isFirst ? r : Radius.zero,
      topRight: isFirst ? r : Radius.zero,
      bottomLeft: isLast ? r : Radius.zero,
      bottomRight: isLast ? r : Radius.zero,
    );
    return InkWell(
      onTap: item.onTap,
      borderRadius: radius,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primaryWeak,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(item.icon,
                      size: 19, color: AppColors.primary),
                ),
                if (item.showBadge)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.surface, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  if (item.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle!,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.text3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            item.trailing ??
                Icon(Icons.chevron_right,
                    size: 22, color: AppColors.text4),
          ],
        ),
      ),
    );
  }
}
