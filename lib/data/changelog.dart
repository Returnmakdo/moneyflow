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
  // ⚠️ 출시 직전에 date를 실제 출시일로 갱신할 것.
  ChangelogEntry(
    id: '2026-06-03-launch',
    date: '2026-06-03',
    title: '머니플로우 출시',
    items: [
      '머니플로우에 오신 걸 환영해요',
      '의견·오류는 설정 → 오류·의견 보내기로 알려주세요',
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
