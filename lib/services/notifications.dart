import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../api/models.dart';
import '../widgets/format.dart';

/// 로컬 알림 서비스 — 카드 결제일 당일 09:00 (Asia/Seoul) 푸시.
/// 외부 푸시 서버 없이 OS 스케줄러로 동작 (APNs/FCM 불필요).
class NotificationsService {
  NotificationsService._();
  static final NotificationsService instance = NotificationsService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// 채널 ID — Android 알림 채널 분리용. 향후 다른 종류 알림 추가 시 분리.
  static const _cardChannelId = 'card_payments';
  static const _cardChannelName = '카드 결제일';
  static const _cardChannelDesc = '카드 결제일 당일 오전 9시 알림';

  /// 카드 알림 id 베이스 — cardId와 1:1 매핑. 다른 알림 종류 추가 시 다른 베이스 사용.
  static const _cardIdBase = 1000000;

  Future<void> init() async {
    if (_ready || kIsWeb) return;

    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    } catch (_) {
      // fallback — 기기 로컬 TZ 그대로.
    }

    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      // 권한은 별도 [requestPermissions] 단계에서. 첫 init 때 다이얼로그 X.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );
    _ready = true;
  }

  /// 알림 권한 요청. Android 13+ POST_NOTIFICATIONS, iOS alert/badge/sound.
  /// 이미 권한 받았으면 no-op. 거부 상태면 다이얼로그 다시 안 뜸 (OS 정책).
  Future<bool> requestPermissions() async {
    if (kIsWeb || !_ready) return false;
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? true;
    }
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final granted = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }
    return false;
  }

  /// 카드 결제일 알림 재스케줄. 활성 카드 + 남은 청구액 > 0만 예약.
  /// 호출 시점: 앱 부팅, 카드/거래 변경 시. 매번 전체 cancel → 재예약.
  Future<void> rescheduleCardPayments(List<CardSummary> cards) async {
    if (kIsWeb || !_ready) return;
    // 카드 알림은 단일 베이스라 전부 cancel하고 재예약. cancelAll은 다른 종류
    // 알림(향후 추가)까지 지워서 위험 — cardId 베이스 알림만 개별 cancel.
    for (final c in cards) {
      await _plugin.cancel(_cardIdBase + c.cardId);
    }

    if (!(Platform.isAndroid || Platform.isIOS)) return;
    final now = tz.TZDateTime.now(tz.local);

    for (final c in cards) {
      if (!c.active) continue;
      final remaining = c.cycleAmount - c.cycleSettled;
      if (remaining <= 0) continue; // 미리 결제로 잔액 0이면 알림 skip.

      final scheduled = _nextPaymentAt9am(now, c.paymentDay);
      if (!scheduled.isAfter(now)) continue;

      await _plugin.zonedSchedule(
        _cardIdBase + c.cardId,
        '오늘 ${c.name} 결제일',
        '${smartWon(remaining)}원 청구 — 결제 등록하세요',
        scheduled,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _cardChannelId,
            _cardChannelName,
            channelDescription: _cardChannelDesc,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        // exact 권한 없으면 inexact로 fallback (대부분 ±15분 내 동작).
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        // iOS는 wall-clock 기준 (사용자 로컬 시간대 09:00 그대로 발화).
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.wallClockTime,
      );
    }
  }

  /// 결제일 09:00 (Asia/Seoul). 이번 달 09시 지났으면 다음 달.
  /// paymentDay가 그 달 일수보다 크면 말일로 clamp (예: 31 + 2월 → 2/28).
  tz.TZDateTime _nextPaymentAt9am(tz.TZDateTime now, int paymentDay) {
    int y = now.year, m = now.month;
    int day = _clampDay(y, m, paymentDay);
    var sched = tz.TZDateTime(tz.local, y, m, day, 9);
    if (!sched.isAfter(now)) {
      m += 1;
      if (m > 12) {
        m = 1;
        y += 1;
      }
      day = _clampDay(y, m, paymentDay);
      sched = tz.TZDateTime(tz.local, y, m, day, 9);
    }
    return sched;
  }

  int _clampDay(int year, int month, int day) {
    final last = DateTime(year, month + 1, 0).day;
    return day > last ? last : day;
  }

  Future<void> cancelAll() async {
    if (kIsWeb || !_ready) return;
    await _plugin.cancelAll();
  }
}
