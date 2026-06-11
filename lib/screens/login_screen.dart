import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show OAuthProvider;
import 'package:url_launcher/url_launcher.dart';
import '../auth.dart';
import '../theme.dart';
import '../widgets/common.dart' show errorMessage, kPrivacyPolicyUrl;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _passConfirmCtrl = TextEditingController();
  bool _busy = false;
  bool _signupMode = false;
  // 회원가입 시 개인정보처리방침 동의 — 미동의면 가입 버튼 비활성.
  bool _agreedPrivacy = false;

  // 가입 모드일 때 이메일 실시간 중복 체크 상태.
  Timer? _emailCheckTimer;
  bool _emailChecking = false;
  bool _emailExists = false;
  String? _emailFormatError;

  // 가입 모드 비밀번호 강도 체크.
  bool _hasMinLength = false;
  bool _hasLower = false;
  bool _hasUpper = false;
  bool _hasDigit = false;
  bool _hasSymbol = false;

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool get _passwordValid =>
      _hasMinLength && _hasLower && _hasUpper && _hasDigit && _hasSymbol;
  bool get _passwordsMatch =>
      _passConfirmCtrl.text.isNotEmpty &&
      _passCtrl.text == _passConfirmCtrl.text;

  @override
  void dispose() {
    _emailCheckTimer?.cancel();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _passConfirmCtrl.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _signupMode = !_signupMode;
      _agreedPrivacy = false;
      _nameCtrl.clear();
      _passCtrl.clear();
      _passConfirmCtrl.clear();
      _emailCheckTimer?.cancel();
      _emailChecking = false;
      _emailExists = false;
      _emailFormatError = null;
      _hasMinLength = false;
      _hasLower = false;
      _hasUpper = false;
      _hasDigit = false;
      _hasSymbol = false;
    });
  }

  void _onPasswordChanged(String v) {
    setState(() {
      _hasMinLength = v.length >= 8;
      _hasLower = RegExp(r'[a-z]').hasMatch(v);
      _hasUpper = RegExp(r'[A-Z]').hasMatch(v);
      _hasDigit = RegExp(r'\d').hasMatch(v);
      _hasSymbol = RegExp(r'[^a-zA-Z0-9\s]').hasMatch(v);
    });
  }

  void _onEmailChanged(String value) {
    _emailCheckTimer?.cancel();
    final email = value.trim();
    if (!_signupMode || email.isEmpty) {
      setState(() {
        _emailChecking = false;
        _emailExists = false;
        _emailFormatError = null;
      });
      return;
    }
    if (!_emailRegex.hasMatch(email)) {
      setState(() {
        _emailChecking = false;
        _emailExists = false;
        _emailFormatError = '올바른 이메일 형식이 아니에요';
      });
      return;
    }
    setState(() {
      _emailFormatError = null;
      _emailExists = false;
      _emailChecking = true;
    });
    _emailCheckTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        final exists = await AuthService.emailExists(email);
        if (!mounted || _emailCtrl.text.trim() != email) return;
        setState(() {
          _emailChecking = false;
          _emailExists = exists;
        });
      } catch (_) {
        if (!mounted) return;
        // 체크 실패해도 가입은 시도 가능. 서버에서 한 번 더 검증함.
        setState(() => _emailChecking = false);
      }
    });
  }

  Future<void> _openPrivacyPolicy() async {
    try {
      final ok = await launchUrl(Uri.parse(kPrivacyPolicyUrl),
          mode: LaunchMode.externalApplication);
      if (!ok && mounted) _showError('처리방침을 열 수 없어요');
    } catch (e) {
      if (mounted) _showError(errorMessage(e));
    }
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      _showError('이메일과 비밀번호를 입력해주세요');
      return;
    }
    if (_signupMode && !_agreedPrivacy) {
      _showError('개인정보처리방침에 동의해주세요');
      return;
    }
    if (_signupMode) {
      final name = _nameCtrl.text.trim();
      if (name.isEmpty) {
        _showError('이름을 입력해주세요');
        return;
      }
      if (name.characters.length > 6) {
        _showError('이름은 최대 6자까지예요');
        return;
      }
      if (_emailFormatError != null) {
        _showError(_emailFormatError!);
        return;
      }
      if (_emailExists) {
        _showError('이미 가입된 이메일이에요');
        return;
      }
      if (!_passwordValid) {
        _showError('비밀번호 조건을 모두 만족해야 해요');
        return;
      }
      if (!_passwordsMatch) {
        _showError('비밀번호가 일치하지 않아요');
        return;
      }
    }
    setState(() => _busy = true);
    try {
      if (_signupMode) {
        await AuthService.signUp(
          email: email,
          password: password,
          name: _nameCtrl.text.trim(),
        );
      } else {
        await AuthService.signIn(email, password);
      }
      // 라우터가 onAuthStateChange로 자동 이동
    } catch (e) {
      _showError(errorMessage(e));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _oauth(OAuthProvider provider) async {
    try {
      await AuthService.signInWithProvider(provider);
      // 성공 시 브라우저 리다이렉트 → 라우터가 onAuthStateChange로 자동 이동
    } catch (e) {
      if (mounted) _showError(errorMessage(e));
    }
  }

  Future<void> _forgotPassword() async {
    final ctrl = TextEditingController(text: _emailCtrl.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: const Text('비밀번호 재설정',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '가입한 이메일을 입력하시면 재설정 링크를 보내드려요.',
              style: TextStyle(fontSize: 13, color: AppColors.text2),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(hintText: '이메일'),
              onSubmitted: (_) =>
                  Navigator.of(ctx).pop(ctrl.text.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('취소',
                style: TextStyle(color: AppColors.text2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: Text('메일 보내기',
                style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (email == null || email.isEmpty) return;
    if (!_emailRegex.hasMatch(email)) {
      if (mounted) _showError('올바른 이메일 형식이 아니에요');
      return;
    }
    try {
      await AuthService.sendPasswordReset(email);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(
                '재설정 메일을 보냈어요. 메일함을 확인해주세요'),
            backgroundColor: AppColors.text,
            duration: Duration(seconds: 4),
          ));
      }
    } catch (e) {
      if (mounted) _showError(errorMessage(e));
    }
  }

  Widget _passwordChecklist() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _ReqChip(label: '8자 이상', met: _hasMinLength),
        _ReqChip(label: '대문자', met: _hasUpper),
        _ReqChip(label: '소문자', met: _hasLower),
        _ReqChip(label: '숫자', met: _hasDigit),
        _ReqChip(label: '특수문자', met: _hasSymbol),
      ],
    );
  }

  Widget? _emailSuffixIcon() {
    if (_emailChecking) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_emailFormatError != null || _emailExists) {
      return Icon(Icons.error_outline,
          color: AppColors.danger, size: 20);
    }
    if (_emailRegex.hasMatch(_emailCtrl.text.trim())) {
      return Icon(Icons.check_circle_outline,
          color: AppColors.success, size: 20);
    }
    return null;
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.danger,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final title = _signupMode ? '회원가입' : '로그인';
    final subtitle =
        _signupMode ? '이메일·비밀번호로 가입해요' : '이메일·비밀번호로 로그인';
    final submitLabel = _busy
        ? (_signupMode ? '가입 중...' : '로그인 중...')
        : (_signupMode ? '회원가입' : '로그인');
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  boxShadow: const [
                    BoxShadow(color: Color(0x0F0F172A), blurRadius: 16, offset: Offset(0, 4)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '₩',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '머니플로우',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.text3, fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    if (_signupMode) ...[
                      const _Label('이름'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _nameCtrl,
                        autofillHints: const [AutofillHints.name],
                        textInputAction: TextInputAction.next,
                        maxLength: 6,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(6),
                        ],
                        decoration: const InputDecoration(
                          hintText: '이름 (최대 6자)',
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    const _Label('이메일'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _emailCtrl,
                      autofillHints: const [AutofillHints.email],
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.next,
                      onChanged: _onEmailChanged,
                      decoration: InputDecoration(
                        errorText: _signupMode
                            ? (_emailFormatError ??
                                (_emailExists
                                    ? '이미 가입된 이메일이에요'
                                    : null))
                            : null,
                        suffixIcon: _signupMode &&
                                _emailCtrl.text.trim().isNotEmpty
                            ? _emailSuffixIcon()
                            : null,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const _Label('비밀번호'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _passCtrl,
                      autofillHints: [
                        _signupMode
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      obscureText: true,
                      textInputAction: _signupMode
                          ? TextInputAction.next
                          : TextInputAction.done,
                      onSubmitted: _signupMode ? null : (_) => _submit(),
                      onChanged: _signupMode ? _onPasswordChanged : null,
                    ),
                    if (!_signupMode) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _busy ? null : _forgotPassword,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 4),
                            minimumSize: const Size(0, 28),
                            tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            '비밀번호 잊으셨나요?',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.text3,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (_signupMode) ...[
                      const SizedBox(height: 8),
                      _passwordChecklist(),
                      const SizedBox(height: 14),
                      const _Label('비밀번호 확인'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _passConfirmCtrl,
                        autofillHints: const [AutofillHints.newPassword],
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          errorText: _passConfirmCtrl.text.isNotEmpty &&
                                  !_passwordsMatch
                              ? '비밀번호가 일치하지 않아요'
                              : null,
                          suffixIcon: _passConfirmCtrl.text.isEmpty
                              ? null
                              : (_passwordsMatch
                                  ? Icon(Icons.check_circle_outline,
                                      color: AppColors.success, size: 20)
                                  : Icon(Icons.error_outline,
                                      color: AppColors.danger, size: 20)),
                        ),
                      ),
                    ],
                    if (_signupMode) ...[
                      const SizedBox(height: 14),
                      _PrivacyConsent(
                        agreed: _agreedPrivacy,
                        onChanged: (v) =>
                            setState(() => _agreedPrivacy = v),
                        onOpenPolicy: _openPrivacyPolicy,
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy || (_signupMode && !_agreedPrivacy)
                          ? null
                          : _submit,
                      child: Text(submitLabel),
                    ),
                    const SizedBox(height: 16),
                    const _OrDivider(),
                    const SizedBox(height: 16),
                    _OAuthButton(
                      label: 'Google로 계속하기',
                      bg: AppColors.surface,
                      fg: AppColors.text,
                      bordered: true,
                      icon: SvgPicture.asset(
                        'assets/icons/google_g.svg',
                        width: 18,
                        height: 18,
                      ),
                      onTap: _busy
                          ? null
                          : () => _oauth(OAuthProvider.google),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _signupMode ? '이미 계정이 있으신가요?' : '계정이 없으신가요?',
                          style: TextStyle(
                            color: AppColors.text3,
                            fontSize: 13,
                          ),
                        ),
                        TextButton(
                          onPressed: _busy ? null : _toggleMode,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            _signupMode ? '로그인' : '회원가입',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 회원가입 개인정보처리방침 동의 줄 — 체크박스 + "처리방침" 링크.
class _PrivacyConsent extends StatelessWidget {
  const _PrivacyConsent({
    required this.agreed,
    required this.onChanged,
    required this.onOpenPolicy,
  });
  final bool agreed;
  final ValueChanged<bool> onChanged;
  final VoidCallback onOpenPolicy;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!agreed),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: agreed,
                onChanged: (v) => onChanged(v ?? false),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  GestureDetector(
                    onTap: onOpenPolicy,
                    child: Text(
                      '개인정보처리방침',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.primary,
                      ),
                    ),
                  ),
                  Text(
                    '에 동의합니다',
                    style: TextStyle(fontSize: 13, color: AppColors.text2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: 13, color: AppColors.text2, fontWeight: FontWeight.w500),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: AppColors.line2, height: 1)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            '또는',
            style: TextStyle(
              color: AppColors.text3,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(child: Divider(color: AppColors.line2, height: 1)),
      ],
    );
  }
}

class _OAuthButton extends StatelessWidget {
  const _OAuthButton({
    required this.label,
    required this.bg,
    required this.fg,
    required this.onTap,
    this.icon,
    this.bordered = false,
  });
  final String label;
  final Color bg;
  final Color fg;
  final VoidCallback? onTap;
  final Widget? icon;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: bordered
                  ? Border.all(color: AppColors.line)
                  : null,
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  icon!,
                  const SizedBox(width: 10),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
