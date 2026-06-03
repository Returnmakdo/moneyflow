import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import 'api/api.dart';
import 'auth.dart';
import 'services/notifications.dart';
import 'screens/account_settings_screen.dart';
import 'screens/accounts_screen.dart';
import 'screens/budgets_screen.dart';
import 'screens/categories_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/fixed_expenses_screen.dart';
import 'screens/ai_import_screen.dart';
import 'screens/changelog_screen.dart';
import 'screens/help_screen.dart';
import 'screens/import_screen.dart';
import 'screens/theme_settings_screen.dart';
import 'screens/transaction_templates_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/shell_screen.dart';
import 'screens/spending_insights_screen.dart';
import 'screens/transactions_screen.dart';
import 'supabase.dart';
import 'theme.dart';
import 'utils/nav_back.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) usePathUrlStrategy();
  // 비번 재설정 메일 링크로 진입했는지 먼저 확인. supabase 이벤트는
  // initialize 중에 fire 될 수 있어서 listener 등록 전에 놓치므로 URL로 직접
  // 체크. (`#access_token=...&type=recovery&...` 형태)
  if (kIsWeb) {
    final href = Uri.base.toString();
    if (href.contains('type=recovery')) {
      AuthService.recoveryMode.value = true;
    }
  }
  await _ensureFontsLoaded();
  await initSupabase();
  // 로컬 캐시에서 테마 즉시 복원 (로그인 화면/콜드 부트에서도 깜빡임 없이 적용).
  // 로그인된 상태면 initListeners가 서버값으로 다시 동기화.
  await AuthService.bootstrapTheme();
  AuthService.initListeners();
  // 로컬 알림 플러그인 초기화 (timezone 등). 권한 요청과 스케줄링은 로그인 후.
  await NotificationsService.instance.init();
  runApp(const BudgetApp());
}

Future<void> _ensureFontsLoaded() async {
  final loader = FontLoader('Pretendard');
  for (final path in const [
    'assets/fonts/Pretendard-Regular.otf',
    'assets/fonts/Pretendard-Medium.otf',
    'assets/fonts/Pretendard-SemiBold.otf',
    'assets/fonts/Pretendard-Bold.otf',
  ]) {
    loader.addFont(rootBundle.load(path));
  }
  await loader.load();
}

class BudgetApp extends StatefulWidget {
  const BudgetApp({super.key});

  @override
  State<BudgetApp> createState() => _BudgetAppState();
}

class _BudgetAppState extends State<BudgetApp> {
  late final GoRouter _router;
  StreamSubscription<dynamic>? _authSub;
  bool _refreshScheduled = false;

  @override
  void initState() {
    super.initState();
    _router = _buildRouter();
    // 카드/거래 변경 시 결제일 알림 재스케줄 (debounce). 잔액 0이 되면 자동 cancel.
    Api.instance.cardsVersion.addListener(_scheduleCardRefresh);
    Api.instance.txVersion.addListener(_scheduleCardRefresh);
    // 콜드 부트 시 이미 로그인된 상태면 즉시 권한 요청 + 첫 스케줄.
    if (AuthService.currentUser != null) {
      _setupNotificationsForUser();
    }
    // 이후 로그인/로그아웃 이벤트도 listen — 로그인 시 권한 요청·스케줄, 로그아웃 시 cancel.
    _authSub = AuthService.onAuthStateChange.listen((data) {
      final ev = data.event;
      if (ev == AuthChangeEvent.signedIn ||
          ev == AuthChangeEvent.initialSession ||
          ev == AuthChangeEvent.tokenRefreshed) {
        if (AuthService.currentUser != null) _setupNotificationsForUser();
      } else if (ev == AuthChangeEvent.signedOut) {
        NotificationsService.instance.cancelAll();
      }
    });
  }

  @override
  void dispose() {
    Api.instance.cardsVersion.removeListener(_scheduleCardRefresh);
    Api.instance.txVersion.removeListener(_scheduleCardRefresh);
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _setupNotificationsForUser() async {
    // 권한 거부해도 OS는 스케줄 받아두므로 추후 권한 켜지면 알림 발화.
    await NotificationsService.instance.requestPermissions();
    await _refreshCardSchedules();
  }

  void _scheduleCardRefresh() {
    if (_refreshScheduled) return;
    _refreshScheduled = true;
    scheduleMicrotask(() async {
      _refreshScheduled = false;
      await _refreshCardSchedules();
    });
  }

  Future<void> _refreshCardSchedules() async {
    if (AuthService.currentUser == null) return;
    try {
      // trendMonths=0 — 알림은 카드 요약만 필요, 6개월 자산 추이 계산 불필요.
      final snap = await Api.instance.getAssetSnapshot(trendMonths: 0);
      await NotificationsService.instance.rescheduleCardPayments(snap.cards);
    } catch (_) {
      // 네트워크 실패 등은 무시 — 다음 변경 시 자동 재시도.
    }
  }

  GoRouter _buildRouter() {
    final notifier = _AuthNotifier();
    return GoRouter(
      refreshListenable: notifier,
      initialLocation: '/dashboard',
      redirect: (context, state) {
        final loggedIn = AuthService.currentUser != null;
        final atLogin = state.matchedLocation == '/login';
        final atReset = state.matchedLocation == '/reset-password';
        final atOnboarding = state.matchedLocation == '/onboarding';
        // 비밀번호 재설정 메일 링크로 들어왔으면 무조건 reset 화면
        if (AuthService.recoveryMode.value && loggedIn) {
          return atReset ? null : '/reset-password';
        }
        if (!loggedIn) return atLogin ? null : '/login';
        // 첫 로그인 — onboarding_seen 안 됐으면 슬라이드로
        if (!AuthService.onboardingSeen && !atOnboarding) {
          return '/onboarding';
        }
        if (atLogin) return '/dashboard';
        if (atReset) return '/dashboard';
        return null;
      },
      routes: [
        // OAuth 콜백(`/?code=...`) 등 루트 진입 시 인증 상태에 따라 분기
        GoRoute(
          path: '/',
          redirect: (_, _) => AuthService.currentUser != null
              ? '/dashboard'
              : '/login',
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) => const LoginScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, _) => const BackPopScope(
            fallback: '/dashboard',
            child: SettingsScreen(),
          ),
          routes: [
            GoRoute(
              path: 'account',
              builder: (_, _) => const BackPopScope(
                fallback: '/settings',
                child: AccountSettingsScreen(),
              ),
            ),
            GoRoute(
              path: 'categories',
              builder: (_, _) => const BackPopScope(
                fallback: '/settings',
                child: CategoriesScreen(),
              ),
            ),
            GoRoute(
              path: 'fixed',
              builder: (_, _) => const BackPopScope(
                fallback: '/settings',
                child: FixedExpensesScreen(),
              ),
            ),
            GoRoute(
              path: 'templates',
              builder: (_, _) => const BackPopScope(
                fallback: '/settings',
                child: TransactionTemplatesScreen(),
              ),
            ),
            GoRoute(
              path: 'help',
              builder: (_, _) => const BackPopScope(
                fallback: '/settings',
                child: HelpScreen(),
              ),
            ),
            GoRoute(
              path: 'import',
              builder: (_, _) => const BackPopScope(
                fallback: '/settings',
                child: ImportScreen(),
              ),
              routes: [
                GoRoute(
                  path: 'ai',
                  builder: (_, _) => const BackPopScope(
                    fallback: '/settings/import',
                    child: AiImportScreen(),
                  ),
                ),
              ],
            ),
            GoRoute(
              path: 'theme',
              builder: (_, _) => const BackPopScope(
                fallback: '/settings',
                child: ThemeSettingsScreen(),
              ),
            ),
            GoRoute(
              path: 'changelog',
              builder: (_, _) => const BackPopScope(
                fallback: '/settings',
                child: ChangelogScreen(),
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/reset-password',
          builder: (_, _) => const BackPopScope(
            fallback: '/login',
            child: ResetPasswordScreen(),
          ),
        ),
        GoRoute(
          path: '/onboarding',
          builder: (_, state) {
            final fromHelp =
                state.uri.queryParameters['from'] == 'help';
            return OnboardingScreen(fromHelp: fromHelp);
          },
        ),
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              ShellScreen(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/dashboard',
                builder: (_, _) => const DashboardScreen(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/transactions',
                builder: (_, state) {
                  final p = state.uri.queryParameters;
                  return TransactionsScreen(
                    initialMonth: p['month'],
                    initialMajor: p['major'],
                    initialSub: p['sub'],
                    initialSubIsNull: p['subnull'] == '1',
                    initialQ: p['q'],
                    initialFixed: p['fixed'],
                    initialDateFrom: p['from'],
                    initialDateTo: p['to'],
                    initialCardId: int.tryParse(p['cardId'] ?? ''),
                    initialCardName: p['cardName'],
                  );
                },
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/budgets',
                builder: (_, _) => const BudgetsScreen(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/accounts',
                builder: (_, _) => const AccountsScreen(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/insights',
                builder: (_, _) => const SpendingInsightsScreen(),
              ),
            ]),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AuthService.themeMode,
      builder: (context, mode, _) {
        // 화면 코드의 AppColors.* getter가 정확한 색을 내려고 미리 동기화.
        final brightness = resolveBrightness(mode);
        AppColors.update(brightness);
        return MaterialApp.router(
          // key를 brightness에 묶어서 모드 변경 시 전체 widget tree 재mount.
          // AppColors.* static get은 InheritedWidget 의존이 없어 자동 rebuild
          // 트리거가 안 됨 — key 교체로 강제 rebuild 보장. routerConfig는
          // 외부 변수에 보관되어 있어 재mount해도 라우트 state는 보존됨.
          key: ValueKey(brightness),
          title: '머니플로우',
          debugShowCheckedModeBanner: false,
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: mode,
          routerConfig: _router,
          locale: const Locale('ko', 'KR'),
          supportedLocales: const [
            Locale('ko', 'KR'),
            Locale('en', 'US'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        );
      },
    );
  }
}

class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier() {
    _sub = AuthService.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        AuthService.recoveryMode.value = true;
      }
      notifyListeners();
    });
    AuthService.recoveryMode.addListener(notifyListeners);
  }
  late final dynamic _sub;
  @override
  void dispose() {
    _sub.cancel();
    AuthService.recoveryMode.removeListener(notifyListeners);
    super.dispose();
  }
}
