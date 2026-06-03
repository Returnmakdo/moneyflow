import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api.dart';
import '../auth.dart';
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
  String? _versionLabel;

  @override
  void initState() {
    super.initState();
    _checkChangelog();
    _loadVersion();
    changelogSeenSignal.addListener(_checkChangelog);
  }

  @override
  void dispose() {
    changelogSeenSignal.removeListener(_checkChangelog);
    super.dispose();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _versionLabel = 'v${info.version} (${info.buildNumber})');
    } catch (_) {/* 무시 */}
  }

  Future<void> _checkChangelog() async {
    final unseen = await hasUnseenChangelog();
    if (!mounted) return;
    setState(() => _hasUnseenChangelog = unseen);
  }

  /// 의견·오류 메일 발송 — 기본 메일 클라이언트 열기.
  /// 본문에 앱 버전 + 사용자 ID(있을 때) 자동 채워서 디버깅 컨텍스트 확보.
  Future<void> _sendFeedback() async {
    String version = '';
    String build = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      build = info.buildNumber;
    } catch (_) {/* 무시 */}
    final uid = AuthService.currentUserId ?? '(비로그인)';
    final subject = '[머니플로우] 의견·오류 제보';
    final body = '''
아래에 내용을 적어주세요.



---
앱 버전: $version+$build
사용자 ID: $uid
''';
    final uri = Uri(
      scheme: 'mailto',
      path: 'cldud970@gmail.com',
      query: 'subject=${Uri.encodeComponent(subject)}'
          '&body=${Uri.encodeComponent(body)}',
    );
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        showToast(context, '메일 앱을 열 수 없어요', error: true);
      }
    } catch (e) {
      if (!mounted) return;
      showToast(context, errorMessage(e), error: true);
    }
  }

  /// 앱 리뷰 — Play Store 출시 전엔 안내 토스트.
  /// 출시 후 url_launcher로 market:// 또는 https://play.google.com/store/apps/details URL 열기.
  void _openReview() {
    showToast(context, '곧 스토어 출시 예정이에요. 조금만 기다려주세요!');
  }

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final csv = await Api.instance.exportTransactionsCsv();
      final ts = DateTime.now();
      final stamp =
          '${ts.year}${ts.month.toString().padLeft(2, '0')}${ts.day.toString().padLeft(2, '0')}';
      final shared =
          await triggerCsvDownload(csv, '머니플로우_$stamp.csv');
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
                subtitle: '매달 반복되는 거래',
                onTap: () => context.go('/settings/fixed'),
              ),
              _MenuItem(
                icon: Icons.bookmark_border,
                title: '거래 템플릿',
                subtitle: '자주 쓰는 거래 추가',
                onTap: () => context.go('/settings/templates'),
              ),
              _MenuItem(
                icon: Icons.upload_file_outlined,
                title: '데이터 가져오기',
                subtitle: 'CSV로 거래 일괄 등록',
                onTap: () => context.go('/settings/import'),
              ),
              _MenuItem(
                icon: Icons.download_outlined,
                title: '데이터 백업',
                subtitle: _exporting ? '백업 중...' : '거래내역을 파일로 저장',
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
                subtitle: '화면별 사용법',
                onTap: () => context.go('/settings/help'),
              ),
              _MenuItem(
                icon: Icons.campaign_outlined,
                title: '업데이트 소식',
                subtitle: '새 기능과 개선사항',
                showBadge: _hasUnseenChangelog,
                onTap: () => context.go('/settings/changelog'),
              ),
              _MenuItem(
                icon: Icons.mail_outline,
                title: '오류·의견 보내기',
                subtitle: '메일로 의견 보내기',
                onTap: _sendFeedback,
              ),
              _MenuItem(
                icon: Icons.star_outline,
                title: '앱 리뷰 남기기',
                subtitle: '스토어 별점 남기기',
                onTap: _openReview,
              ),
            ]),
            if (_versionLabel != null)
              Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 8),
                child: Center(
                  child: Text(
                    '머니플로우 ${_versionLabel!}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.text4,
                    ),
                  ),
                ),
              ),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
