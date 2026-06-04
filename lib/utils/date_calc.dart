import 'dart:math' as math;

/// 날짜 계산 순수 함수 모음 — DB 의존 없음. 정기 거래 도래일·카드 결제일·
/// 월 경계 처리에 쓰이며 엣지케이스(월말·윤년)가 많아 단위 테스트 대상.

/// [day]를 1~31로 clamp하고, [month](YYYY-MM)가 주어지면 그 달 마지막 날로도 clamp.
/// 예: `clampDay(31, month: '2026-02')` == 28 (윤년이면 29),
///     `clampDay(31, month: '2026-04')` == 30.
int clampDay(int day, {String? month}) {
  final d = day.clamp(1, 31);
  if (month == null) return d;
  final parts = month.split('-').map(int.parse).toList();
  final lastDay = DateTime(parts[0], parts[1] + 1, 0).day;
  return math.min(d, lastDay);
}

/// YYYY-MM 형식의 그 달 마지막 날을 YYYY-MM-DD로 반환. 2·4·6·9·11월 및
/// 윤년 자동 처리. query의 `'$month-31'` 문자열 hack 대신 명시적으로 계산.
String lastDayOf(String ym) {
  final parts = ym.split('-').map(int.parse).toList();
  final last = DateTime(parts[0], parts[1] + 1, 0);
  return '${last.year}-${last.month.toString().padLeft(2, '0')}-${last.day.toString().padLeft(2, '0')}';
}
