import 'package:flutter_test/flutter_test.dart';
import 'package:billionaire/utils/date_calc.dart';

void main() {
  group('clampDay (month 없음)', () {
    test('정상 범위는 그대로', () {
      expect(clampDay(1), 1);
      expect(clampDay(15), 15);
      expect(clampDay(31), 31);
    });
    test('1 미만은 1로 clamp', () {
      expect(clampDay(0), 1);
      expect(clampDay(-5), 1);
    });
    test('31 초과는 31로 clamp', () {
      expect(clampDay(32), 31);
      expect(clampDay(99), 31);
    });
  });

  group('clampDay (month 기준 월말 clamp)', () {
    test('2월 비윤년 — 31 → 28', () {
      expect(clampDay(31, month: '2026-02'), 28);
      expect(clampDay(29, month: '2026-02'), 28);
    });
    test('2월 윤년 — 31 → 29', () {
      expect(clampDay(31, month: '2024-02'), 29);
      expect(clampDay(29, month: '2024-02'), 29);
    });
    test('400으로 나뉘는 해(2000)는 윤년 — 29', () {
      expect(clampDay(31, month: '2000-02'), 29);
    });
    test('100으로만 나뉘는 해(1900)는 평년 — 28', () {
      expect(clampDay(31, month: '1900-02'), 28);
    });
    test('30일 달 — 31 → 30', () {
      expect(clampDay(31, month: '2026-04'), 30); // 4월
      expect(clampDay(31, month: '2026-06'), 30); // 6월
      expect(clampDay(31, month: '2026-09'), 30); // 9월
      expect(clampDay(31, month: '2026-11'), 30); // 11월
    });
    test('31일 달 — 31 유지', () {
      expect(clampDay(31, month: '2026-01'), 31);
      expect(clampDay(31, month: '2026-12'), 31);
    });
    test('월 마지막 날 이하면 그대로', () {
      expect(clampDay(15, month: '2026-02'), 15);
      expect(clampDay(28, month: '2026-02'), 28);
    });
    test('범위 밖 입력도 먼저 1~31 clamp 후 월말 clamp', () {
      expect(clampDay(99, month: '2026-02'), 28);
      expect(clampDay(0, month: '2026-02'), 1);
    });
  });

  group('lastDayOf', () {
    test('30일 달', () {
      expect(lastDayOf('2026-04'), '2026-04-30');
      expect(lastDayOf('2026-06'), '2026-06-30');
      expect(lastDayOf('2026-11'), '2026-11-30');
    });
    test('31일 달', () {
      expect(lastDayOf('2026-01'), '2026-01-31');
      expect(lastDayOf('2026-12'), '2026-12-31');
    });
    test('2월 평년/윤년', () {
      expect(lastDayOf('2026-02'), '2026-02-28');
      expect(lastDayOf('2024-02'), '2024-02-29');
      expect(lastDayOf('2000-02'), '2000-02-29'); // 400 윤년
      expect(lastDayOf('1900-02'), '1900-02-28'); // 100 평년
    });
    test('월/일 zero-padding 유지', () {
      expect(lastDayOf('2026-02'), '2026-02-28');
      expect(lastDayOf('2026-09'), '2026-09-30');
    });
  });
}
