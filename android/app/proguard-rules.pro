# R8/ProGuard keep 규칙 (release minify 시 적용).
#
# 중요: Flutter 앱의 Dart 코드는 AOT 컴파일이라 R8 영향 없음. R8는 Android
# Java/Kotlin 측(플러그인·임베딩)만 축소·난독화한다. 따라서 keep 규칙은
# *리플렉션/직렬화를 쓰는 네이티브 코드*에만 필요하다.
#
# 현재 의존성(supabase_flutter·fl_chart·flutter_markdown·file_picker·share_plus·
# url_launcher·path_provider·shared_preferences·package_info_plus·excel)은 모두
# 순수 Dart거나 R8 안전한 표준 플러그인 — 별도 keep 불필요.
# Flutter 자체 규칙(flutter_proguard_rules.pro)이 임베딩/플러그인 등록을 자동 keep.

# ── Play Core (deferred components / split install) ──────────────────
# Flutter 임베딩이 Play Core를 *선택적으로* 참조 — 앱이 deferred component를
# 안 써도 R8가 "missing class" 경고/실패를 내는 흔한 케이스. 방어적으로 무시.
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# ── 코어 라이브러리 디슈가링 (java.time 등) ──────────────────────────
-dontwarn java.lang.invoke.**

# ── 향후 flutter_local_notifications 도입 시 주석 해제 ────────────────
# 예약 알림이 Gson 리플렉션으로 직렬화하므로 keep 필요.
# -keep class com.dexterous.** { *; }
# -keep class com.google.gson.** { *; }
# -keepattributes Signature
# -keepattributes *Annotation*
# -keepclassmembers,allowobfuscation class * {
#   @com.google.gson.annotations.SerializedName <fields>;
# }
# -keep class * extends com.google.gson.reflect.TypeToken
# -keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
