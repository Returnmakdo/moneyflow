import 'package:flutter/foundation.dart' show ValueNotifier, kIsWeb;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'api/api.dart';
import 'supabase.dart';

class AuthService {
  static User? get currentUser => sb.auth.currentUser;
  static String? get currentUserId => sb.auth.currentUser?.id;
  static Stream<AuthState> get onAuthStateChange => sb.auth.onAuthStateChange;

  /// 비밀번호 재설정 메일 링크로 들어왔을 때 true. 라우터가 /reset-password로
  /// 강제 이동시킬 때 참고. 새 비번 변경 후 false로 리셋.
  static final ValueNotifier<bool> recoveryMode = ValueNotifier(false);

  /// 사용자 정보(이름 등) 변경 시 bump. 화면들이 listening해서 자동 rebuild용.
  static final ValueNotifier<int> userVersion = ValueNotifier(0);

  /// 앱 테마 모드 — system / light / dark.
  /// 저장: 서버 우선(user_metadata) + 로컬 캐시(SharedPreferences).
  /// - 로그인 화면(서버값 모르는 상태): 로컬 캐시 fallback
  /// - 로그인 후: 서버값으로 갱신 + 로컬 동기화
  /// - 사용자 변경: 로컬 즉시 + 서버 fire-and-forget
  static final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier(ThemeMode.system);

  static const _kPrefThemeMode = 'theme_mode';

  static ThemeMode _parseMode(String? raw) => switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  /// 앱 시작 시 로컬 캐시에서 테마 즉시 적용. main()에서 await.
  static Future<void> bootstrapTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      themeMode.value = _parseMode(prefs.getString(_kPrefThemeMode));
    } catch (_) {/* 실패해도 default(system) */}
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    // 로컬은 동기화 — 다음 콜드 부트/로그아웃 상태에서 즉시 사용.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefThemeMode, mode.name);
    } catch (_) {}
    // 서버 저장은 fire-and-forget (UX 막지 않게).
    try {
      await sb.auth.updateUser(
        UserAttributes(data: {'theme_mode': mode.name}),
      );
    } catch (_) {}
  }

  /// 로그인 직후 호출 — 서버값을 themeMode + 로컬에 동기화.
  static Future<void> _syncThemeFromUser() async {
    final saved = currentUser?.userMetadata?['theme_mode'] as String?;
    if (saved == null) return; // 서버에 안 저장된 사용자: 로컬값 유지
    final mode = _parseMode(saved);
    themeMode.value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefThemeMode, mode.name);
    } catch (_) {}
  }

  /// supabase 측에서 user 정보가 바뀌면(updateUser, refreshSession 등) userUpdated
  /// 이벤트가 fire — 그때 userVersion bump해서 listening 화면들 자동 갱신.
  /// main()의 initSupabase 후 한 번 호출.
  static void initListeners() {
    // 초기 진입 시 user 있으면 테마 동기화 + 정기 거래 자동 적용.
    if (currentUser != null) {
      _syncThemeFromUser();
      _autoApplyDueFixed();
    }

    sb.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.userUpdated) {
        userVersion.value++;
      }
      // signedIn / userUpdated 시 테마 메타도 다시 동기화.
      if (data.event == AuthChangeEvent.signedIn ||
          data.event == AuthChangeEvent.userUpdated) {
        _syncThemeFromUser();
      }
      // 로그인 직후 — 이번 달 도래분 정기 거래 자동 등록.
      if (data.event == AuthChangeEvent.signedIn) {
        _autoApplyDueFixed();
      }
    });
  }

  /// 이번 달 도래한 정기 거래를 자동 등록. fire-and-forget.
  /// dedupe 적용되어 있어 중복 호출 안전.
  static void _autoApplyDueFixed() {
    final now = DateTime.now();
    final ym =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    Api.instance.applyDueFixedTransactions(ym).catchError((_) => 0);
  }

  static Future<void> signIn(String email, String password) async {
    await sb.auth.signInWithPassword(email: email, password: password);
  }

  /// 이메일·비밀번호 회원가입. 가입 즉시 세션 생성됨 (이메일 확인 비활성).
  /// [name]은 user_metadata에 `name`/`full_name`으로 저장.
  static Future<void> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    final res = await sb.auth.signUp(
      email: email,
      password: password,
      data: {'name': name, 'full_name': name},
    );
    if (res.user == null) {
      throw Exception('회원가입에 실패했어요. 잠시 후 다시 시도해주세요.');
    }
  }

  static Future<void> signOut() async {
    await sb.auth.signOut();
  }

  /// 가입 화면 실시간 중복 체크. 존재하면 true.
  static Future<bool> emailExists(String email) async {
    final r = await sb.rpc('check_email_exists', params: {'p_email': email});
    return r as bool;
  }

  /// 화면에 표시할 사용자 이름. user_metadata의 name → full_name → 이메일의
  /// @ 앞부분 → '사용자' 순서로 폴백.
  static String displayName() {
    final user = currentUser;
    final meta = user?.userMetadata;
    final name = (meta?['name'] as String?)?.trim();
    if (name != null && name.isNotEmpty) return name;
    final full = (meta?['full_name'] as String?)?.trim();
    if (full != null && full.isNotEmpty) return full;
    final email = user?.email;
    if (email != null && email.isNotEmpty) return email.split('@').first;
    return '사용자';
  }

  /// OAuth 로그인. 웹에선 현재 origin으로 리다이렉트, 모바일은 Site URL 사용.
  /// 신규 사용자면 자동 가입(트리거가 '기타' 카테고리 시드).
  static Future<void> signInWithProvider(OAuthProvider provider) async {
    // 끝에 '/' 강제 — Supabase Redirect URLs 화이트리스트가 'http://host/**' 형식이라
    // path 없는 origin('http://host')은 매치 안 되어 Site URL(production)로 fallback됨.
    await sb.auth.signInWithOAuth(
      provider,
      redirectTo: kIsWeb ? '${Uri.base.origin}/' : null,
    );
  }

  /// 첫 로그인 온보딩 완료 여부 (user_metadata.onboarding_seen).
  /// 로그인된 사용자에게만 의미 있음.
  static bool get onboardingSeen {
    final user = currentUser;
    return user?.userMetadata?['onboarding_seen'] == true;
  }

  /// 온보딩 보기 완료 표시 — 다음 로그인부터 자동으로 안 뜨게.
  static Future<void> markOnboardingSeen() async {
    await sb.auth.updateUser(
      UserAttributes(data: {'onboarding_seen': true}),
    );
  }

  /// 사용자 이름 변경 — user_metadata의 name/full_name 갱신.
  static Future<void> updateName(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw Exception('이름은 비울 수 없어요');
    await sb.auth.updateUser(
      UserAttributes(data: {'name': clean, 'full_name': clean}),
    );
    userVersion.value++;
  }

  /// 비밀번호 변경. OAuth 가입자에겐 의미 없음 (Supabase가 비번 없는 계정에 새로
  /// 비번을 세팅하긴 하지만 OAuth 흐름엔 안 쓰임).
  static Future<void> updatePassword(String newPassword) async {
    if (newPassword.length < 8) {
      throw Exception('비밀번호는 8자 이상이어야 해요');
    }
    await sb.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// 본인 계정 삭제. delete_my_account RPC가 auth.users에서 본인 행 삭제 →
  /// ON DELETE CASCADE로 모든 데이터 자동 정리. 이후 onAuthStateChange가
  /// signedOut으로 떨어져 자동 로그인 화면으로 이동.
  static Future<void> deleteAccount() async {
    await sb.rpc('delete_my_account');
    await sb.auth.signOut();
  }

  /// 비밀번호 재설정 메일 발송. 로그인 화면 "비밀번호 잊으셨나요?"용.
  /// redirectTo는 root origin만 — Supabase Redirect URLs 화이트리스트랑 매칭
  /// 안 되면 Site URL(prod)로 fallback 됨. 클릭 후 우리 앱이 passwordRecovery
  /// 이벤트 받아서 /reset-password 화면으로 강제 이동.
  static Future<void> sendPasswordReset(String email) async {
    await sb.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: kIsWeb ? Uri.base.origin : null,
    );
  }
}
