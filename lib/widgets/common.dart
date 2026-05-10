import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth.dart';
import '../theme.dart';

const _kCardShadow = [
  BoxShadow(color: Color(0x0A0F172A), blurRadius: 6, offset: Offset(0, 1)),
];

/// 화면 상단 공통 헤더: 제목 + 부제 + 우측 액션 + 프로필 아바타.
/// 좁은 화면에서는 actions(MonthSwitcher 등)을 title 아래 줄로 내려서 title이
/// 좁아지지 않게 함.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
  });
  final String title;
  final String? subtitle;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final acts = actions;
    final isWide = MediaQuery.sizeOf(context).width >= 700;
    final titleSize = isWide ? 28.0 : 22.0;

    final titleWidget = Text(
      title,
      style: TextStyle(
        fontSize: titleSize,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
        letterSpacing: -0.01 * titleSize,
        height: 1.2,
      ),
    );
    final subtitleWidget = (subtitle != null && subtitle!.isNotEmpty)
        ? Text(
            subtitle!,
            style: TextStyle(fontSize: 14, color: AppColors.text3),
          )
        : null;
    final hasActions = acts != null && acts.isNotEmpty;

    if (isWide) {
      // 넓은 화면: 한 줄에 title | actions + avatar
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  titleWidget,
                  if (subtitleWidget != null) ...[
                    const SizedBox(height: 4),
                    subtitleWidget,
                  ],
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (acts != null) ...acts,
                const _LogoutButton(),
              ],
            ),
          ],
        ),
      );
    }

    // 모바일: title + actions + avatar 한 줄 (compact MonthSwitcher 덕분에 들어감)
    // 이름이 길어도 잘리지 않도록 FittedBox로 자동 축소.
    final mobileTitle = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        maxLines: 1,
        style: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
          letterSpacing: -0.2,
          height: 1.2,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: mobileTitle),
              const SizedBox(width: 8),
              if (hasActions) ...[
                ...acts,
                const SizedBox(width: 6),
              ],
              const _LogoutButton(),
            ],
          ),
          if (subtitleWidget != null) ...[
            const SizedBox(height: 4),
            subtitleWidget,
          ],
        ],
      ),
    );
  }
}


class _LogoutButton extends StatelessWidget {
  const _LogoutButton();

  String _initial(String name) {
    final ch = name.characters.firstOrNull;
    return (ch ?? '?').toUpperCase();
  }

  Future<void> _onTap(BuildContext context) async {
    final action = await showMenu<String>(
      context: context,
      position: _menuPosition(context),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          padding: EdgeInsets.zero,
          // userVersion bump 시 popup 열린 동안에도 이름/이메일 자동 갱신.
          child: ValueListenableBuilder<int>(
            valueListenable: AuthService.userVersion,
            builder: (_, _, _) {
              final name = AuthService.displayName();
              final email = AuthService.currentUser?.email;
              return Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        )),
                    if (email != null && email.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(email,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.text3,
                          )),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'settings',
          child: Row(
            children: [
              Icon(Icons.settings_outlined, size: 18, color: AppColors.text2),
              SizedBox(width: 10),
              Text('설정',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.text,
                    fontWeight: FontWeight.w500,
                  )),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout, size: 18, color: AppColors.text2),
              SizedBox(width: 10),
              Text('로그아웃',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.text,
                    fontWeight: FontWeight.w500,
                  )),
            ],
          ),
        ),
      ],
    );
    if (!context.mounted) return;
    if (action == 'settings') {
      // push 대신 go — GoRouter 14.x에서 push는 ImperativeRouteMatch라
      // URL bar가 갱신 안 되는 케이스가 있어서 강제 교체.
      // 뒤로가기는 브라우저 history(또는 navigator stack)로 처리.
      context.go('/settings');
    } else if (action == 'logout') {
      final ok = await confirmDialog(
        context,
        title: '로그아웃',
        message: '정말 로그아웃 할까요?',
        confirmText: '로그아웃',
      );
      if (ok) await AuthService.signOut();
    }
  }

  RelativeRect _menuPosition(BuildContext context) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final button = context.findRenderObject() as RenderBox;
    final topLeft = button.localToGlobal(
      Offset(0, button.size.height + 4),
      ancestor: overlay,
    );
    final bottomRight = button.localToGlobal(
      button.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    return RelativeRect.fromRect(
      Rect.fromPoints(topLeft, bottomRight),
      Offset.zero & overlay.size,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AuthService.userVersion,
      builder: (context, _, _) {
        final name = AuthService.displayName();
        return Material(
          color: AppColors.surface2,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _onTap(context),
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 32,
              height: 32,
              child: Center(
                child: Text(
                  _initial(name),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text2,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 월 이동 버튼. label 탭하면 onTapLabel 호출 (년/월 picker 열기 용).
class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({
    super.key,
    required this.label,
    required this.onPrev,
    required this.onNext,
    this.onTapLabel,
  });
  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback? onTapLabel;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 700;
    // 좁은 화면이면 라벨 짧게 ('26년 4월') + 컴팩트 패딩
    final compact = !isWide;
    final labelChild = Padding(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 2 : 8, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: compact ? 12 : 14,
                color: AppColors.text,
              )),
          if (onTapLabel != null) ...[
            const SizedBox(width: 1),
            Icon(Icons.expand_more,
                size: compact ? 14 : 16, color: AppColors.text3),
          ],
        ],
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: _kCardShadow,
      ),
      padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            iconSize: compact ? 16 : 20,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.all(compact ? 2 : 8),
            constraints: const BoxConstraints(),
            onPressed: onPrev,
            icon: Icon(Icons.chevron_left,
                color: AppColors.text2),
          ),
          if (onTapLabel != null)
            InkWell(
              onTap: onTapLabel,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: labelChild,
            )
          else
            labelChild,
          IconButton(
            iconSize: compact ? 16 : 20,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.all(compact ? 2 : 8),
            constraints: const BoxConstraints(),
            onPressed: onNext,
            icon: Icon(Icons.chevron_right,
                color: AppColors.text2),
          ),
        ],
      ),
    );
  }
}

/// 카드 컨테이너 — 토스 톤. tight 옵션으로 패딩 줄임.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.tight = false,
    this.padding,
    this.onTap,
  });
  final Widget child;
  final bool tight;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pad = padding ??
        EdgeInsets.all(tight ? 14 : 22);
    final card = Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: _kCardShadow,
      ),
      // child(InkWell ripple/hover 등)가 카드 둥근 모서리 밖으로 빠져나가는
      // 문제 방지. boxShadow는 decoration에 있어 outer라 clip 영향 없음.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Padding(padding: pad, child: child),
      ),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: card,
      ),
    );
  }
}

/// 섹션 제목 ("태그 TOP 10" + meta).
class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.meta});
  final String title;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
                letterSpacing: -0.005,
              )),
          if (meta != null && meta!.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(meta!,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.text3,
                  )),
            ),
          ],
        ],
      ),
    );
  }
}

/// 빈 상태 카드.
class EmptyCard extends StatelessWidget {
  const EmptyCard({
    super.key,
    required this.title,
    this.body,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });
  final String title;
  final String? body;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final hasPrimary = actionLabel != null && onAction != null;
    final hasSecondary =
        secondaryActionLabel != null && onSecondaryAction != null;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primaryWeak,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 26, color: AppColors.primary),
            ),
            const SizedBox(height: 14),
          ],
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: AppColors.text,
              )),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(body!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.text3,
                  height: 1.5,
                )),
          ],
          if (hasPrimary || hasSecondary) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (hasPrimary)
                  FilledButton(
                    onPressed: onAction,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      textStyle: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(actionLabel!),
                  ),
                if (hasSecondary)
                  OutlinedButton(
                    onPressed: onSecondaryAction,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.text2,
                      side: BorderSide(color: AppColors.line),
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      textStyle: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(secondaryActionLabel!),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 토스트 (스낵바).
void showToast(BuildContext context, String message,
    {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.danger : AppColors.text,
      duration: const Duration(seconds: 2),
    ));
}

/// 사용자에게 보여줄 에러 메시지로 변환.
/// Supabase Auth/Postgrest 예외는 한글 메시지로 매핑하고, 그 외는 개발자용
/// 프리픽스("Exception: ", "*Exception: ")를 제거한다.
String errorMessage(Object e) {
  if (e is AuthException) return _authMsg(e);
  if (e is PostgrestException) return _postgrestMsg(e);
  final s = e is Exception ? e.toString() : '$e';
  final m = RegExp(r'^[A-Z]\w*(?:Exception|Error): ').firstMatch(s);
  final stripped = m != null
      ? s.substring(m.end)
      : (s.startsWith('Exception: ') ? s.substring(11) : s);
  return _genericTranslate(stripped);
}

String _authMsg(AuthException e) {
  switch (e.code) {
    case 'invalid_credentials':
      return '이메일 또는 비밀번호가 일치하지 않아요';
    case 'email_address_invalid':
      return '올바른 이메일 형식이 아니에요';
    case 'weak_password':
      return '비밀번호가 너무 짧아요 (6자 이상)';
    case 'same_password':
      return '기존 비밀번호와 다른 비밀번호를 입력해주세요';
    case 'user_already_exists':
    case 'email_exists':
      return '이미 가입된 이메일이에요';
    case 'over_email_send_rate_limit':
      return '메일 발송 한도를 초과했어요. 잠시 후 다시 시도해주세요';
    case 'over_request_rate_limit':
      return '요청이 너무 많아요. 잠시 후 다시 시도해주세요';
    case 'email_not_confirmed':
      return '이메일 확인이 안 됐어요. 메일함을 확인해주세요';
    case 'signup_disabled':
      return '현재 회원가입이 비활성화돼 있어요';
    case 'user_not_found':
      return '사용자를 찾을 수 없어요';
  }
  if (e.statusCode == '429') {
    return '요청이 너무 많아요. 잠시 후 다시 시도해주세요';
  }
  final msg = e.message.toLowerCase();
  if (msg.contains('rate limit') || msg.contains('too many')) {
    return '요청이 너무 많아요. 잠시 후 다시 시도해주세요';
  }
  if (msg.contains('invalid login') || msg.contains('invalid credentials')) {
    return '이메일 또는 비밀번호가 일치하지 않아요';
  }
  if (msg.contains('already registered') || msg.contains('already exists')) {
    return '이미 가입된 이메일이에요';
  }
  if (msg.contains('email not confirmed')) {
    return '이메일 확인이 안 됐어요. 메일함을 확인해주세요';
  }
  if (msg.contains('same') && msg.contains('password')) {
    return '기존 비밀번호와 다른 비밀번호를 입력해주세요';
  }
  if (msg.contains('network')) {
    return '네트워크 오류가 발생했어요';
  }
  return '문제가 발생했어요. 잠시 후 다시 시도해주세요';
}

String _postgrestMsg(PostgrestException e) {
  switch (e.code) {
    case '23505':
      return '이미 존재하는 항목이에요';
    case '23503':
      return '연결된 데이터가 있어 처리할 수 없어요';
    case '42501':
      return '권한이 없어요';
    case 'PGRST301':
      return '로그인이 만료됐어요. 다시 로그인해주세요';
  }
  return '서버 처리 중 문제가 발생했어요';
}

String _genericTranslate(String s) {
  final lower = s.toLowerCase();
  if (lower.contains('rate limit') || lower.contains('too many requests')) {
    return '요청이 너무 많아요. 잠시 후 다시 시도해주세요';
  }
  if (lower.contains('failed host lookup') ||
      lower.contains('socketexception') ||
      lower.contains('network')) {
    return '네트워크 오류가 발생했어요';
  }
  if (lower.contains('timeout')) {
    return '응답이 지연되고 있어요. 잠시 후 다시 시도해주세요';
  }
  return s;
}

/// 가벼운 확인 다이얼로그.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = '확인',
  bool danger = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w700)),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('취소',
              style: TextStyle(color: AppColors.text2)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmText,
              style: TextStyle(
                color: danger ? AppColors.danger : AppColors.primary,
                fontWeight: FontWeight.w600,
              )),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// 통일된 드랍다운. TextField 디자인과 매칭, 트리거 바로 아래로 펼쳐짐.
class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.hint,
    this.placeholder = '선택',
  });
  final T? value;
  final List<AppDropdownItem<T>> items;
  final ValueChanged<T> onChanged;
  final String? label;
  final String? hint;
  final String placeholder;

  Future<void> _open(BuildContext context) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final button = context.findRenderObject() as RenderBox;
    final width = button.size.width;
    final topLeft = button.localToGlobal(
      Offset(0, button.size.height + 4),
      ancestor: overlay,
    );
    final bottomRight = button.localToGlobal(
      button.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final position = RelativeRect.fromRect(
      Rect.fromPoints(topLeft, bottomRight),
      Offset.zero & overlay.size,
    );
    final result = await showMenu<T>(
      context: context,
      position: position,
      color: AppColors.surface,
      constraints: BoxConstraints.tightFor(width: width),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      items: [
        for (final it in items)
          PopupMenuItem<T>(
            value: it.value,
            child: Text(it.label,
                style: TextStyle(
                  fontWeight: it.value == value
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: it.value == value
                      ? AppColors.primary
                      : AppColors.text,
                )),
          ),
      ],
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final selected =
        items.where((it) => it.value == value).cast<AppDropdownItem<T>?>().firstOrNull;
    final display = selected?.label ?? hint ?? placeholder;
    final isEmpty = selected == null;
    return Material(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () => _open(context),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (label != null)
                      Text(label!,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.text3,
                            height: 1.2,
                          )),
                    if (label != null) const SizedBox(height: 2),
                    Text(display,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: isEmpty ? AppColors.text3 : AppColors.text,
                        )),
                  ],
                ),
              ),
              Icon(Icons.expand_more,
                  size: 20, color: AppColors.text3),
            ],
          ),
        ),
      ),
    );
  }
}

class AppDropdownItem<T> {
  const AppDropdownItem({required this.value, required this.label});
  final T value;
  final String label;
}

/// 진행률 바 (예산용). 80% 이상 노란색, 100% 이상 빨간색.
class ProgressTrack extends StatelessWidget {
  const ProgressTrack({super.key, required this.percent});
  final double percent; // 0.0 ~ 1.0+

  @override
  Widget build(BuildContext context) {
    final p = percent.clamp(0.0, 1.0);
    Color color;
    if (percent >= 1.0) {
      color = AppColors.danger;
    } else if (percent >= 0.8) {
      color = AppColors.warning;
    } else {
      color = AppColors.primary;
    }
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return Stack(
          children: [
            Container(
              width: w,
              height: 8,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D6DD),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Container(
              width: w * p,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 단순 라벨/값 배지.
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, this.color, this.bg});
  final String label;
  final Color? color;
  final Color? bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg ?? AppColors.primaryWeak,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
            color: color ?? AppColors.primary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          )),
    );
  }
}
