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
    id: '2026-05-09-recurring-auto',
    date: '2026-05-09',
    title: '정기 거래, 알아서 들어와요',
    items: [
      '월세·월급 같은 정기 거래는 도래일이 되면 자동으로 거래내역에 추가되고 자산에 반영돼요',
      '정기 거래 화면에서 "이번 달 등록됨" / "5/15 등록 예정" 같은 상태가 한눈에 보여요',
      '거래를 삭제하면 그 달엔 자동으로 다시 들어오지 않아요. 다음 달부터는 정상 등록돼요',
    ],
  ),
  ChangelogEntry(
    id: '2026-05-07-assets-income',
    date: '2026-05-07',
    title: '돈 들어오는 것까지 한눈에, 자산 흐름',
    items: [
      '월급·이자·용돈 같은 수입을 등록하고 카테고리별로 정리할 수 있어요',
      '이체·신용카드까지 자산 탭에서 한꺼번에 보여드려요 (총자산 = 통장 잔고 합 − 카드 미정산)',
      '카드를 등록해두면 결제일이 다가올 때 청구액 안내가 떠요',
      '대시보드 KPI를 지출·수입·순저축·일평균 4장으로 분리해서 한 달 흐름이 한눈에 들어와요',
      '6개월 자산 추이 그래프가 자산 탭에 추가됐어요',
    ],
  ),
  ChangelogEntry(
    id: '2026-05-03-import',
    date: '2026-05-03',
    title: '한 달치 지출, 명세서로 한 번에',
    items: [
      '카드사에서 받은 이용내역만 올리면 AI가 카테고리까지 알아서 정리해드려요',
      '거래 추가 버튼을 누르면 "직접 입력"과 "명세서로 한 번에" 둘 중에 골라요',
      '취소된 결제는 자동으로 빼서 명세서 합계랑 똑같이 맞춰드려요',
    ],
  ),
  ChangelogEntry(
    id: '2026-05-03-polish',
    date: '2026-05-03',
    title: '여기저기 더 편해졌어요',
    items: [
      '탭을 다시 누르면 화면 맨 위로 부드럽게 올라가요',
      '다크모드에서 차트 글씨가 또렷하게 보이도록 다듬었어요',
      '도움말 안내가 더 친근하게 정리됐어요',
    ],
  ),
  ChangelogEntry(
    id: '2026-05-01-dark',
    date: '2026-05-01',
    title: '밤에도 편하게, 다크모드',
    items: [
      '시스템·라이트·다크 중에 골라서 쓸 수 있어요',
      '한 번 정해두면 다른 기기에서도 같은 테마로 따라가요',
    ],
  ),
  ChangelogEntry(
    id: '2026-05-01-ai',
    date: '2026-05-01',
    title: 'AI가 한 달 지출을 짚어드려요',
    items: [
      '분석 탭에서 이번 달 패턴·이상치·다음 달 제안까지 한 번에',
      '처음 들어왔을 때 보는 슬라이드와 화면별 도움말도 함께 추가됐어요',
      '다른 가계부에서 쓰던 데이터도 CSV로 쉽게 옮길 수 있어요',
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
