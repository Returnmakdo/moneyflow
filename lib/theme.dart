import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 라이트 모드 색상 (토스 톤). 다크 토글되면 [AppColors.x] getter가
/// dark 색을 반환하므로 화면 코드는 그대로 [AppColors.text] 사용 가능.
/// 다만 const 표현식 안에서는 컴파일 타임 평가라 dark 적용 안 됨 — 호출자가
/// const 제거 필요.
class _Light {
  static const bg = Color(0xFFF4F6F8);
  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFF7F9FB);
  static const text = Color(0xFF191F28);
  static const text2 = Color(0xFF4E5968);
  static const text3 = Color(0xFF8B95A1);
  static const text4 = Color(0xFFB0B8C1);
  static const line = Color(0xFFE5E8EB);
  static const line2 = Color(0xFFF0F2F5);
  static const primary = Color(0xFF3182F6);
  static const primaryWeak = Color(0xFFE8F1FF);
  static const primaryStrong = Color(0xFF1B64DA);
  static const success = Color(0xFF1ABF76);
  static const danger = Color(0xFFF04452);
  static const warning = Color(0xFFF59E0B);
  // 수입 강조 — 라이트 톤. 텍스트(진한)/배경(옅은)/테두리.
  // 검정과 명확히 구분되도록 더 밝고 선명한 파랑.
  static const incomeText = Color(0xFF3B82F6);
  static const incomeBg = Color(0xFFE0EDFF);
  static const incomeBorder = Color(0xFFBFDBFE);
  // 지출 강조 — 빨강 톤. 거래내역 amount + 카드 pill 모두 동일 톤 사용.
  static const expenseText = Color(0xFFB91C1C);
  static const expenseBg = Color(0xFFFEE2E2);
  static const expenseBorder = Color(0xFFFCA5A5);
}

class _Dark {
  static const bg = Color(0xFF111316);
  static const surface = Color(0xFF1A1D22);
  static const surface2 = Color(0xFF22262D);
  static const text = Color(0xFFE6E8EA);
  static const text2 = Color(0xFFB0B8C1);
  static const text3 = Color(0xFF8B95A1);
  static const text4 = Color(0xFF606770);
  static const line = Color(0xFF2F343A);
  static const line2 = Color(0xFF252A30);
  static const primary = Color(0xFF4D8FF7);
  static const primaryWeak = Color(0xFF1F2C44);
  static const primaryStrong = Color(0xFF6FAEFF);
  static const success = Color(0xFF2BC986);
  static const danger = Color(0xFFFF5762);
  static const warning = Color(0xFFFBA62C);
  // 수입 강조 — 다크 톤. 다크 배경에서 잘 보이게 밝은 파랑.
  static const incomeText = Color(0xFF7DB7FF);
  static const incomeBg = Color(0xFF152A4A);
  static const incomeBorder = Color(0xFF2A4977);
  // 지출 강조 — 다크 톤. 빨강 톤.
  static const expenseText = Color(0xFFFCA5A5);
  static const expenseBg = Color(0xFF3A1A1D);
  static const expenseBorder = Color(0xFF6B2B30);
}

/// 화면 코드에서 직접 참조 (예: `AppColors.text`). 현재 활성 ThemeMode에 따라
/// 동적으로 light/dark 색을 반환. const TextStyle/Container 안에서는 작동 안
/// 하므로 호출자가 const 제거 필요.
class AppColors {
  static bool _isDark = false;

  /// MaterialApp이 build할 때 매번 호출해서 현재 brightness 동기화.
  static void update(Brightness b) {
    _isDark = b == Brightness.dark;
  }

  static Color get bg => _isDark ? _Dark.bg : _Light.bg;
  static Color get surface => _isDark ? _Dark.surface : _Light.surface;
  static Color get surface2 => _isDark ? _Dark.surface2 : _Light.surface2;
  static Color get text => _isDark ? _Dark.text : _Light.text;
  static Color get text2 => _isDark ? _Dark.text2 : _Light.text2;
  static Color get text3 => _isDark ? _Dark.text3 : _Light.text3;
  static Color get text4 => _isDark ? _Dark.text4 : _Light.text4;
  static Color get line => _isDark ? _Dark.line : _Light.line;
  static Color get line2 => _isDark ? _Dark.line2 : _Light.line2;
  static Color get primary => _isDark ? _Dark.primary : _Light.primary;
  static Color get primaryWeak =>
      _isDark ? _Dark.primaryWeak : _Light.primaryWeak;
  static Color get primaryStrong =>
      _isDark ? _Dark.primaryStrong : _Light.primaryStrong;
  static Color get success => _isDark ? _Dark.success : _Light.success;
  static Color get danger => _isDark ? _Dark.danger : _Light.danger;
  static Color get warning => _isDark ? _Dark.warning : _Light.warning;
  // 수입 (income) — 텍스트/배경/테두리 3종.
  static Color get incomeText =>
      _isDark ? _Dark.incomeText : _Light.incomeText;
  static Color get incomeBg => _isDark ? _Dark.incomeBg : _Light.incomeBg;
  static Color get incomeBorder =>
      _isDark ? _Dark.incomeBorder : _Light.incomeBorder;
  // 지출 (expense) — 빨강 톤. 거래내역 amount + 카드 pill 등 공용.
  static Color get expenseText =>
      _isDark ? _Dark.expenseText : _Light.expenseText;
  static Color get expenseBg =>
      _isDark ? _Dark.expenseBg : _Light.expenseBg;
  static Color get expenseBorder =>
      _isDark ? _Dark.expenseBorder : _Light.expenseBorder;
}

class AppRadius {
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 18.0;
  static const xl = 22.0;
}

ThemeData buildLightTheme() => _build(brightness: Brightness.light);
ThemeData buildDarkTheme() => _build(brightness: Brightness.dark);

ThemeData _build({required Brightness brightness}) {
  // 주의: 여기서 AppColors.update를 호출하면 안 됨 — MaterialApp이 theme/darkTheme
  // 둘 다 build해서 마지막 호출(dark)이 _isDark를 덮어씀. 동기화는 main의
  // ValueListenableBuilder에서 themeMode 기준으로 한 번만 함.
  const fontFamily = 'Pretendard';
  final dark = brightness == Brightness.dark;
  final bg = dark ? _Dark.bg : _Light.bg;
  final surface = dark ? _Dark.surface : _Light.surface;
  final surface2 = dark ? _Dark.surface2 : _Light.surface2;
  final text = dark ? _Dark.text : _Light.text;
  final text2 = dark ? _Dark.text2 : _Light.text2;
  final line = dark ? _Dark.line : _Light.line;
  final primary = dark ? _Dark.primary : _Light.primary;
  final danger = dark ? _Dark.danger : _Light.danger;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: fontFamily,
    scaffoldBackgroundColor: bg,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: Colors.white,
      secondary: primary,
      onSecondary: Colors.white,
      surface: surface,
      onSurface: text,
      error: danger,
      onError: Colors.white,
    ),
    textTheme: TextTheme(
      headlineLarge: TextStyle(fontWeight: FontWeight.w700, color: text),
      headlineMedium: TextStyle(fontWeight: FontWeight.w700, color: text),
      titleLarge: TextStyle(fontWeight: FontWeight.w700, color: text),
      titleMedium: TextStyle(fontWeight: FontWeight.w600, color: text),
      bodyLarge: TextStyle(color: text),
      bodyMedium: TextStyle(color: text2),
      labelLarge: const TextStyle(fontWeight: FontWeight.w600),
    ).apply(fontFamily: fontFamily),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: danger, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: danger, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        textStyle: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: text,
      contentTextStyle:
          TextStyle(color: dark ? _Dark.bg : Colors.white),
    ),
  );
}

/// MaterialApp의 themeMode 결정 시 호출 — 시스템 기준일 때 platformBrightness
/// 따라 AppColors._isDark 동기화. main에서 ValueListenableBuilder가 mode
/// 변경 시 build 호출하므로 이 시점에 sync.
Brightness resolveBrightness(ThemeMode mode) {
  if (mode == ThemeMode.dark) return Brightness.dark;
  if (mode == ThemeMode.light) return Brightness.light;
  return SchedulerBinding.instance.platformDispatcher.platformBrightness;
}
