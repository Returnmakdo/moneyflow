// 정적 changelog. 새 항목은 리스트 맨 위에 추가.
// id는 겹치지 않게 고유한 slug. 마지막으로 본 id는 SharedPreferences에 저장
// (lastSeenChangelogId) — 새 항목이 추가되면 빨간점이 다시 뜸.

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';

/// changelog "본 적 있음" 갱신 신호. settings_screen이 이걸 listen해서
/// 빨간점 다시 그림.
final ValueNotifier<int> changelogSeenSignal = ValueNotifier(0);

class ChangelogEntry {
  final String id;
  final String date; // YYYY-MM-DD
  final String title;
  final List<String> items;
  const ChangelogEntry({
    required this.id,
    required this.date,
    required this.title,
    required this.items,
  });
}

const List<ChangelogEntry> changelog = [
  ChangelogEntry(
    id: '2026-05-10-ai-card-import',
    date: '2026-05-10',
    title: '신용카드 명세서 정리 흐름 정돈',
    items: [
      'AI 정리 — 신용카드 명세서 전용으로 변경 (통장 거래내역 업로드 차단 + 안내)',
      '옛 결제 자동 등록 + 통장 시작잔고 자동 보정 기능 추가',
      '카드 사용 마감일 필수 입력으로 변경',
    ],
  ),
  ChangelogEntry(
    id: '2026-05-09-recurring-auto',
    date: '2026-05-09',
    title: '정기 거래 자동 등록',
    items: [
      '정기 거래 도래일에 거래내역 자동 추가 + 자산 반영',
      '정기 거래 등록 상태 표시 추가 (이번 달 등록됨 / 등록 예정)',
      '삭제한 정기 거래는 그 달 재등록 안 됨, 다음 달부터 정상 등록',
    ],
  ),
  ChangelogEntry(
    id: '2026-05-07-assets-income',
    date: '2026-05-07',
    title: '수입 거래 + 자산 흐름 + 신용카드 시스템 추가',
    items: [
      '수입 거래 등록 + 카테고리 분리',
      '자산 탭 추가 — 총자산·계좌·신용카드 한 화면',
      '신용카드 결제일 안내 + 결제 등록 시트',
      '대시보드 KPI 4개로 분리 (지출·수입·순저축·일평균)',
      '6개월 자산 추이 차트 추가',
    ],
  ),
  ChangelogEntry(
    id: '2026-05-03-import',
    date: '2026-05-03',
    title: 'AI 카드 명세서 자동 정리',
    items: [
      '카드사 이용내역 업로드 + AI 카테고리 자동 분류',
      '거래 추가 시 직접 입력 / 명세서 가져오기 선택 추가',
      '취소된 결제 자동 제외 (명세서 합계와 일치)',
    ],
  ),
  ChangelogEntry(
    id: '2026-05-03-polish',
    date: '2026-05-03',
    title: '사용성 개선',
    items: [
      '탭 재진입 시 화면 맨 위로 자동 스크롤',
      '다크모드 차트 가독성 개선',
      '도움말 안내 톤 다듬기',
    ],
  ),
  ChangelogEntry(
    id: '2026-05-01-dark',
    date: '2026-05-01',
    title: '다크모드 추가',
    items: [
      '시스템·라이트·다크 모드 선택 가능',
      '테마 설정 다른 기기 동기화',
    ],
  ),
  ChangelogEntry(
    id: '2026-05-01-ai',
    date: '2026-05-01',
    title: 'AI 분석 + 온보딩 + CSV 가져오기 추가',
    items: [
      '분석 탭 추가 — 이번 달 패턴·이상치·다음 달 제안',
      '첫 로그인 온보딩 슬라이드 + 화면별 도움말 추가',
      '다른 가계부 CSV 가져오기 기능 추가',
    ],
  ),
];

const _kLastSeenKey = 'changelog_last_seen_id';

String? get latestChangelogId =>
    changelog.isEmpty ? null : changelog.first.id;

/// 마지막으로 본 항목 이후 새 changelog가 있는지.
Future<bool> hasUnseenChangelog() async {
  final latest = latestChangelogId;
  if (latest == null) return false;
  final prefs = await SharedPreferences.getInstance();
  final last = prefs.getString(_kLastSeenKey);
  return last != latest;
}

/// changelog 화면을 봤다고 표시 (가장 최신 id 저장 + 신호 발사).
Future<void> markChangelogSeen() async {
  final latest = latestChangelogId;
  if (latest == null) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kLastSeenKey, latest);
  changelogSeenSignal.value++;
}
