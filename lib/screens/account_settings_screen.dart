import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../api/api.dart';
import '../auth.dart';
import '../theme.dart';
import '../utils/nav_back.dart';
import '../widgets/common.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  late final TextEditingController _nameCtrl;
  bool _savingName = false;

  late final TextEditingController _newPassCtrl;
  late final TextEditingController _newPassConfirmCtrl;
  bool _savingPassword = false;
  bool _hasMinLength = false;
  bool _hasLower = false;
  bool _hasUpper = false;
  bool _hasDigit = false;
  bool _hasSymbol = false;

  bool _deleting = false;
  bool _wiping = false;

  // 데이터 초기화 버튼은 이 계정에서만 노출 (개발/테스트용).
  static const _wipeAllowedEmail = 'cldud970@naver.com';

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: AuthService.displayName());
    _newPassCtrl = TextEditingController();
    _newPassConfirmCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _newPassCtrl.dispose();
    _newPassConfirmCtrl.dispose();
    super.dispose();
  }

  bool get _isEmailUser {
    final user = AuthService.currentUser;
    if (user == null) return false;
    final providers = (user.appMetadata['providers'] as List?)?.cast<String>();
    if (providers != null) return providers.contains('email');
    final provider = user.appMetadata['provider'] as String?;
    return provider == 'email' || provider == null;
  }

  bool get _passwordValid =>
      _hasMinLength && _hasLower && _hasUpper && _hasDigit && _hasSymbol;
  bool get _passwordsMatch =>
      _newPassConfirmCtrl.text.isNotEmpty &&
      _newPassCtrl.text == _newPassConfirmCtrl.text;

  void _onPasswordChanged(String v) {
    setState(() {
      _hasMinLength = v.length >= 8;
      _hasLower = RegExp(r'[a-z]').hasMatch(v);
      _hasUpper = RegExp(r'[A-Z]').hasMatch(v);
      _hasDigit = RegExp(r'\d').hasMatch(v);
      _hasSymbol = RegExp(r'[^a-zA-Z0-9\s]').hasMatch(v);
    });
  }

  Future<void> _saveName() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showToast(context, '이름은 비울 수 없어요', error: true);
      return;
    }
    if (name.characters.length > 6) {
      showToast(context, '이름은 최대 6자까지예요', error: true);
      return;
    }
    if (name == AuthService.displayName()) return;
    setState(() => _savingName = true);
    try {
      await AuthService.updateName(name);
      if (!mounted) return;
      showToast(context, '이름을 변경했어요');
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _changePassword() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_passwordValid) {
      showToast(context, '비밀번호 조건을 모두 만족해야 해요', error: true);
      return;
    }
    if (!_passwordsMatch) {
      showToast(context, '비밀번호가 일치하지 않아요', error: true);
      return;
    }
    setState(() => _savingPassword = true);
    try {
      await AuthService.updatePassword(_newPassCtrl.text);
      if (!mounted) return;
      showToast(context, '비밀번호를 변경했어요');
      _newPassCtrl.clear();
      _newPassConfirmCtrl.clear();
      _onPasswordChanged('');
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  Future<void> _wipeData() async {
    final ok = await confirmDialog(
      context,
      title: '데이터 초기화',
      message: '거래내역·카테고리·예산·정기 거래·AI 분석을 모두 삭제하고 \'기타\' 카테고리만 남깁니다. 계정은 유지돼요. 복구할 수 없어요.',
      confirmText: '초기화',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _wiping = true);
    try {
      await Api.instance.wipeMyData();
      if (!mounted) return;
      showToast(context, '데이터를 초기화했어요');
      context.go('/dashboard');
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _wiping = false);
    }
  }

  Future<void> _deleteAccount() async {
    final email = AuthService.currentUser?.email ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteAccountDialog(requiredText: email),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await AuthService.deleteAccount();
    } catch (e) {
      if (!mounted) return;
      showToast(context, errorMessage(e), error: true);
      setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.text2),
          onPressed: () => goBackOr(context, '/settings'),
        ),
        title: Text(
          '계정 관리',
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
            _profileCard(user),
            const SizedBox(height: 14),
            _nameCard(),
            if (_isEmailUser) ...[
              const SizedBox(height: 14),
              _passwordCard(),
            ],
            if (user?.email == _wipeAllowedEmail) ...[
              const SizedBox(height: 14),
              _wipeCard(),
            ],
            const SizedBox(height: 32),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _deleting ? null : _deleteAccount,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.text3,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _deleting ? '탈퇴 중...' : '회원 탈퇴',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileCard(User? user) {
    final email = user?.email ?? '-';
    final providers =
        (user?.appMetadata['providers'] as List?)?.cast<String>() ??
            [if (user?.appMetadata['provider'] != null)
              user!.appMetadata['provider'] as String];
    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('계정',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.text3,
                fontWeight: FontWeight.w600,
              )),
          const SizedBox(height: 8),
          _row('이메일', Text(email,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.text,
                fontWeight: FontWeight.w500,
              ))),
          const SizedBox(height: 8),
          _row('가입 방식', _providerBadge(providers)),
        ],
      ),
    );
  }

  Widget _providerBadge(List<String> providers) {
    if (providers.isEmpty) {
      return Text('-',
          style: TextStyle(
            fontSize: 14,
            color: AppColors.text,
            fontWeight: FontWeight.w500,
          ));
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final p in providers) _ProviderChip(provider: p),
      ],
    );
  }

  Widget _row(String label, Widget value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.text3,
                )),
          ),
          Expanded(child: value),
        ],
      ),
    );
  }

  Widget _nameCard() {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('이름',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.text3,
                fontWeight: FontWeight.w600,
              )),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _saveName(),
            maxLength: 6,
            inputFormatters: [LengthLimitingTextInputFormatter(6)],
            decoration: const InputDecoration(
              hintText: '이름 (최대 6자)',
              counterText: '',
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(80, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: _savingName ? null : _saveName,
              child: Text(_savingName ? '저장 중...' : '저장'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _wipeCard() {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cleaning_services_outlined,
                  size: 16, color: AppColors.warning),
              const SizedBox(width: 6),
              Text('데이터 초기화 (테스트용)',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.text3,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '거래내역·카테고리·예산·정기 거래·AI 분석을 모두 지우고 \'기타\' 카테고리만 남겨서 신규 사용자 상태로 되돌려요. 계정은 유지돼요.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.text2,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: _wiping ? null : _wipeData,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.warning,
                side: BorderSide(color: AppColors.warning),
                minimumSize: const Size(80, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: Text(_wiping ? '초기화 중...' : '초기화'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _passwordCard() {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('비밀번호 변경',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.text3,
                fontWeight: FontWeight.w600,
              )),
          const SizedBox(height: 8),
          TextField(
            controller: _newPassCtrl,
            obscureText: true,
            textInputAction: TextInputAction.next,
            onChanged: _onPasswordChanged,
            decoration: const InputDecoration(hintText: '새 비밀번호'),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _ReqChip(label: '8자 이상', met: _hasMinLength),
              _ReqChip(label: '대문자', met: _hasUpper),
              _ReqChip(label: '소문자', met: _hasLower),
              _ReqChip(label: '숫자', met: _hasDigit),
              _ReqChip(label: '특수문자', met: _hasSymbol),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _newPassConfirmCtrl,
            obscureText: true,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _changePassword(),
            decoration: InputDecoration(
              hintText: '새 비밀번호 확인',
              errorText: _newPassConfirmCtrl.text.isNotEmpty &&
                      !_passwordsMatch
                  ? '비밀번호가 일치하지 않아요'
                  : null,
              suffixIcon: _newPassConfirmCtrl.text.isEmpty
                  ? null
                  : (_passwordsMatch
                      ? Icon(Icons.check_circle_outline,
                          color: AppColors.success, size: 20)
                      : Icon(Icons.error_outline,
                          color: AppColors.danger, size: 20)),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(80, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: _savingPassword ? null : _changePassword,
              child: Text(_savingPassword ? '변경 중...' : '비밀번호 변경'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderChip extends StatelessWidget {
  const _ProviderChip({required this.provider});
  final String provider;

  @override
  Widget build(BuildContext context) {
    Widget icon;
    String label;
    switch (provider) {
      case 'google':
        icon = SvgPicture.asset(
          'assets/icons/google_g.svg',
          width: 14,
          height: 14,
        );
        label = 'Google';
        break;
      case 'email':
        icon = Icon(Icons.mail_outline,
            size: 14, color: AppColors.text2);
        label = '이메일';
        break;
      case 'kakao':
        icon = Container(
          width: 14,
          height: 14,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFFFEE500),
            shape: BoxShape.circle,
          ),
          child: const Text(
            'K',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: Color(0xFF191919),
            ),
          ),
        );
        label = 'Kakao';
        break;
      default:
        icon = Icon(Icons.account_circle_outlined,
            size: 14, color: AppColors.text2);
        label = provider;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.requiredText});
  final String requiredText;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _matches => _ctrl.text.trim() == widget.requiredText;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      backgroundColor: AppColors.surface,
      title: const Text(
        '정말 탈퇴할까요?',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '계정과 모든 거래내역·카테고리·예산·정기 거래이 영구 삭제돼요. '
            '복구할 수 없어요.',
            style: TextStyle(fontSize: 13.5, color: AppColors.text2),
          ),
          const SizedBox(height: 14),
          RichText(
            text: TextSpan(
              style: TextStyle(
                  fontSize: 13, color: AppColors.text2),
              children: [
                const TextSpan(text: '확인을 위해 '),
                TextSpan(
                  text: widget.requiredText,
                  style: TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const TextSpan(text: ' 을(를) 그대로 입력해주세요'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(hintText: '이메일'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('취소',
              style: TextStyle(color: AppColors.text2)),
        ),
        TextButton(
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
          child: Text(
            '탈퇴',
            style: TextStyle(
              color: _matches ? AppColors.danger : AppColors.text4,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReqChip extends StatelessWidget {
  const _ReqChip({required this.label, required this.met});
  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: met ? AppColors.primaryWeak : AppColors.surface2,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            met ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 13,
            color: met ? AppColors.primary : AppColors.text4,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: met ? AppColors.primaryStrong : AppColors.text3,
            ),
          ),
        ],
      ),
    );
  }
}
