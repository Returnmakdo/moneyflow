# 머니플로우 — 출시 체크리스트 (Android + iOS)

Android(Play Store) · iOS(App Store) 동시 출시 준비. 안드가 셋업이 더 빨라서 안드 먼저 마무리 → iOS는 Mac 환경 준비되면 병행.

iOS 특수 주의:
- "Sign in with Apple" 필수 — 구글 로그인 같은 3rd-party OAuth가 있으면 Apple 심사에서 자동 거부.
- Mac + Xcode 필요. 사이닝/프로비저닝 셋업이 안드보다 까다로움.
- 심사 시간 보통 1~3일.

---

## 0. 정책 결정 (먼저 결정해야 다음 작업 진행됨)

- [ ] **피드백 메일 주소** — 현재 `cldud970@gmail.com` 개인. 운영용 별도 메일(예: `support@…`)로 분리?
- [ ] **iPad 지원 여부** — 안 할 거면 iOS Info.plist `UIDeviceFamily=[1]` + App Store Connect iPhone-only.
- [ ] **AI 분석 정식 공개 정책** — 현재 베타 게이트(`auth.dart:20` 이메일 화이트리스트). 정식 공개 시 국외이전·신정법 동의 흐름 결정.
- [ ] **개발자 wipe 게이트 보존 여부** — `account_settings_screen.dart:37` 매직 이메일. `kReleaseMode` 분기 또는 유지.

---

## 1. 출시 전 필수 (계정·인프라)

### 양 OS 공통
- [ ] **앱 아이콘 1024×1024 마스터** — 안드 adaptive(foreground+background) + iOS 1024px 자동 생성용. 현재 default `ic_launcher` 교체.
- [ ] **개인정보 처리방침 URL** — 노션/구글사이트 한 장. 수집 항목(이메일·거래 데이터·인증 토큰), 보관/삭제 정책. Play Console + App Store Connect 둘 다 등록.
- [ ] **앱 소개 페이지/홈페이지 URL** (옵션이지만 권장) — App Store Connect 마케팅 URL용.
- [ ] **크래시 트래커 도입** — Sentry(무료 5K/월) 또는 Firebase Crashlytics. 안 넣으면 사용자 크래시 원인 추적 불가.
- [ ] **Supabase 개발 환경 분리** — 새 무료 plan project(region: ap-northeast-2). `lib/supabase.dart` ENV 분기 (`--dart-define=ENV=dev`로 dev/prod URL·key 분리). 마이그레이션·edge function dev에서 검증 → prod. **첫 사용자 받기 전에 반드시.**

### Android 전용
- [ ] **Google Play Console 계정 등록** — $25 일회성. 신원 인증 며칠 걸림.
- [ ] **Release keystore 생성 + 안전 보관** — Play App Signing 권장.
- [ ] **`.aab` 빌드 통과** — `flutter build appbundle --release`.

### iOS 전용
- [ ] **Apple Developer Program 가입** — $99/년. 카드 인증 + 영업일 1~3일.
- [ ] **Mac + 최신 Xcode 셋업** — 빌드·아카이브·업로드 모두 Mac 필요.
- [ ] **App Store Connect 앱 등록** — Bundle ID 등록 (`com.cyahn.billionaire`).
- [ ] **프로비저닝 프로파일 + Distribution 인증서** — Xcode "Automatically manage signing" 권장.
- [ ] **"Sign in with Apple" 구현** — supabase_flutter는 Apple Provider 지원. 구글 로그인 옆에 버튼 + Apple Developer 콘솔에서 Service ID·Key 등록.

---

## 2. 스토어 메타데이터

### 양 OS 공통
- [ ] 짧은 설명(안드 80자 / iOS subtitle 30자)
- [ ] 자세한 설명 (안드 4000자 / iOS description 4000자)
- [ ] **스크린샷** — 폰 2~8장. 1080×1920(안드), iPhone 6.7"(iOS) 권장. 대시보드·거래내역·예산·자산·분석 각 1장.
- [ ] 콘텐츠 등급 자가 평가 (전체이용가 예상)
- [ ] 카테고리 = "금융"

### Android 전용
- [ ] **피처 그래픽 1024×500**
- [ ] **데이터 안전 섹션** — 수집(이메일/거래/인증), 공유 없음, HTTPS, 삭제 요청 가능(회원 탈퇴)

### iOS 전용
- [ ] **App Privacy 자가 신고**
- [ ] **App Store 미리보기 영상** (옵션) — 15~30초
- [ ] **App Store 키워드** 100자

---

## 3. 기술 점검 (출시 전)

### Android
- [ ] `targetSdk = 35` 명시 (`android/app/build.gradle.kts`) — 2025-08-31부터 Play API 35 강제. 현재 `flutter.targetSdkVersion` 묵시 의존.
- [ ] **Release signingConfig를 release 키로 분리** — `build.gradle.kts:39` 현재 debug 키 사용 중. release 빌드해도 Play Console 자동 거부.
- [ ] **ProGuard/R8 keep 규칙** — `proguard-rules.pro` 생성 + `isMinifyEnabled = true`. supabase·fl_chart·markdown 리플렉션 깨짐 방지. Sentry mapping 업로드와 연결.
- [ ] **`backup_rules.xml` + `data_extraction_rules.xml`** — Android 12+ 자동 백업/이전에서 supabase 세션 토큰 포함 방지. `AndroidManifest`에 `android:allowBackup` / `dataExtractionRules` 명시.
- [ ] **Network Security Config** (`res/xml/network_security_config.xml`) — HTTPS-only 명시. `usesCleartextTraffic="false"`.
- [ ] **`SCHEDULE_EXACT_ALARM` 사용 사유** — Play Console에서 가계부는 "Calendars/Alarm clock" 카테고리 아니라 정당화 문구 강제. 카드 결제일 리마인더라는 사유 준비. `USE_EXACT_ALARM`만으로 가능한지 재검토.
- [ ] **launch theme 다크 미러링** — `values-night/styles.xml` 흰 배경 부모 확인 (다크 OS 첫 프레임 흰빛).
- [ ] **Release 빌드 동작 확인** — `.aab` → `bundletool`로 APK 추출 → 실기기. debug와 다르게 깨지는 R8 minify 케이스.
- [ ] dependencies 최신 — `flutter pub outdated`.

### iOS
- [ ] **iOS deployment target 13.0+** — `Podfile` `platform :ios, '13.0'` 주석 해제. supabase_flutter 2.5는 iOS 12+지만 13 명시로 CocoaPods 경고 제거.
- [ ] **iPad orientation 정리** — `UISupportedInterfaceOrientations~ipad` 4방향. 폰 전용 출시면 정리.
- [ ] **LaunchScreen.storyboard** — `flutter_native_splash`가 안드만 갱신. iOS 네이티브 splash는 별도 점검.
- [ ] **iOS 알림 권한 흐름** — 카드 결제일 푸시 정상 동작.
- [ ] **Safe Area / Notch / Dynamic Island** 레이아웃 확인.
- [ ] **Release archive 동작 확인** — Xcode → Product → Archive → 실기기 설치.

### 양 OS 공통 (인프라 보안)
- [ ] **Edge Function CORS 화이트리스트** — `spending-insights/index.ts:58` `Access-Control-Allow-Origin: "*"` → prod 도메인만. 와일드카드면 anon key 가진 누구든 브라우저에서 호출 가능 (AI 비용 폭주 위험). `import-csv-assist/index.ts`도 동일.
- [ ] **Edge Function rate limit** — `force=true` 호출로 캐시 우회 가능. (user_id, hour) 키로 throttle. Anthropic 청구액 폭주 방지.
- [ ] **Edge Function error 메시지 정리** — `catch (e) { error: String(e) }` 그대로 클라이언트에 노출 (`spending-insights/index.ts:352`, `import-csv-assist`). 서버 로그만 남기고 사용자에겐 generic 메시지.
- [ ] **Edge Function 입력 크기 서버 측 검증** — `parseSheetFile` 4MB는 클라이언트 검증만. 서버 body size 검증 추가.
- [ ] **`supabase/schema.sql` 갱신 or deprecated 표기** — `ai_insights`/`fixed_apply_log`/`transaction_templates` 등 후속 마이그레이션 미반영.
- [ ] **크래시 트래커 연동 확인** — 강제 크래시 한 번 발생시켜 대시보드 도착 확인.
- [ ] **Supabase Auth Redirect URLs** prod deep link scheme 등록 (`com.cyahn.billionaire://login-callback/`).

---

## 4. 기능 점검 시나리오 (출시 직전 수동 QA)

위험 큰 순. **양 OS 모두에서 동일 시나리오**.

### A. 자산·신용카드 흐름
- [ ] 계좌 등록·잔고 초기값 정확
- [ ] 거래 등록 후 계좌 잔고 즉시 갱신
- [ ] 카드 사용 → 자산 즉시 −, 카드 부채 +
- [ ] 카드 결제일 도래 → 빨간 줄 + 결제 등록 시트 자동 채움
- [ ] 결제일 당일 결제 등록 → 사이클이 다음 달로 넘어감
- [ ] 결제 등록 후 삭제 → 사이클 복귀
- [ ] 옛 사이클 미정산 있을 때 새 사이클 추가 → 부채 누적 정확
- [ ] 이체 → from − / to + / 총자산 변동 X
- [ ] 정기 거래 자동 적용 (도래일 ≤ 오늘만 / dedupe로 한 번만)
- [ ] 일반 거래 → 정기지출 등록 → 거래 1건만 남음
- [ ] 카드 결제계좌 변경 시 옛 결제는 그대로 (스펙)

### B. 거래 CRUD + 카테고리·예산·템플릿
- [ ] 거래 수정 시 자산·예산·통계 즉시 갱신
- [ ] 카테고리 삭제 시 매핑 거래 표시 정상
- [ ] 예산 0원 / 매우 큰 금액 입력
- [ ] 전체/지출/수입 필터 + 검색·카테고리·금액범위 동시
- [ ] **CSV 백업 round-trip** — export → 탈퇴 → 신규 가입 → import. 데이터 이식성 검증
- [ ] **거래 템플릿** — 생성 → 거래 모달에서 불러와 폼 자동 채움 → 저장 후 폼 그대로

### C. 로그인 / 회원 흐름
- [ ] 이메일 회원가입 → 트리거가 default 데이터 시드(카테고리 14종 + 기본 계좌)
- [ ] **구글 로그인 (Android deep link)** `com.cyahn.billionaire://login-callback/`
- [ ] **Apple 로그인 (iOS만)** — Supabase + Apple Service ID 연결 확인
- [ ] **Supabase 대시보드 Redirect URLs**에 위 scheme 등록 확인
- [ ] 비번 재설정 메일 → 모바일 클릭 → 앱 열림 → `/reset-password` (유효하지 않은 토큰 시 토스트)
- [ ] **회원탈퇴 + 같은 이메일 재가입** → 새 계정으로 분리되는지 확인. cascade 삭제 정상
- [ ] 로그아웃 후 다른 계정 로그인 시 옛 데이터 잠깐도 안 보임

### D. 엣지 케이스
- [ ] 월 경계 5/31 → 6/1
- [ ] 연 경계 12/31 → 1/1
- [ ] 윤년 2/29
- [ ] 카드 결제일 31일 + 2월 (clamp)
- [ ] 카드 결제일 = 마감일 (paymentLate)
- [ ] 한글·이모지·매우 긴 가맹점 이름
- [ ] 거래 1만 건+ 대시보드/자산 속도

### E. 빈 상태 / 첫 사용자
- [ ] 가입 직후 5개 탭 진입 — empty CTA 정상
- [ ] 거래 0건 상태 모든 모달 진입
- [ ] AI 분석 첫 진입 — 빈 안내 정상

### F. 네트워크·오류
- [ ] 비행기 모드 거래 추가 시도 → 명확한 에러 토스트
- [ ] 인증 토큰 만료 → 자동 갱신 또는 로그인 화면 이동
- [ ] Supabase 5xx 응답 시 사용자 토스트

### G. UX 마감
- [ ] 작은 폰 (iPhone SE 4.7" / 갤럭시 폴드 외부) 깨짐 X
- [ ] 다크모드 모든 화면 + 모달 일관
- [ ] OS 글자 크기 키운 환경에서 안 깨짐
- [ ] 키보드 가림 — 입력 필드 자동 스크롤
- [ ] **로그아웃 진입점** — 현재 PageHeader 우측 아바타뿐. 설정 메뉴에 "로그아웃" 항목 추가 권장.

---

## 5. 자동 QA (Unit Test)

수동 QA로 출시 가능. 회귀 방지 위해 핵심 계산 로직만 unit test 권장.

### 우선순위
1. **`api.dart` 자산·카드·정기 계산 로직** (가성비 최고)
   - 카드 사이클 (`cycleAmount`, `cycleSettled`, `passedThisCycle`)
   - 자산 합계 (`totalBalance = accountsBalance − cardDebtTotal`)
   - 정기지출 자동 적용 (`_applyDueFixedImpl`) — dedupe + log
   - 대시보드 집계 (`getDashboard`)
2. 위젯 테스트 우선순위 ↓
3. Integration test는 골든패스 몇 개만

### 셋업
- [ ] `mocktail` 또는 `mockito` 추가
- [ ] Supabase `sb` 클라이언트 mock — 거래/계좌/카드 fixture 인메모리
- [ ] 핵심 함수 케이스별 테스트
- [ ] GitHub Actions로 `flutter test` 자동 실행

---

## 6. 출시 후 작업

### 다음 기능
- [ ] **로컬 알림 강화** — 카드 결제 D-3 사전 알림, 예산 임박, 정기 거래 도래
- [ ] **안드 SMS 파싱** — 결제 SMS 자동 파싱 → 거래 자동 추가. 안드 전용 차별화
- [ ] **위젯** — 안드 홈 위젯 / iOS 위젯에 오늘 지출·잔고
- [ ] **오프라인 캐시** — `drift`로 로컬 캐시 + 백그라운드 sync
- [ ] **반복 거래 자동 감지 → 정기 거래 추천** — AI 분석 인프라 재활용

### 기술 부채
- [ ] **`flutter_markdown` 대안 이전** — 패키지 deprecated. `markdown_widget` 또는 `flutter_markdown_plus`로 마이그레이션 (AI 인사이트 UI).
- [ ] **OAuth deep link host 검증 강화** — Android Manifest는 `host="login-callback"` 명시. iOS Info.plist scheme만 있고 host 검증은 OS가 못 함 → 라우터에서 query 분기 시 피싱 방어.

---

## 7. 출시 직전 최종 점검 (D-1)

### 양 OS 공통
- [ ] `pubspec.yaml` version bump (예: 1.0.0+1)
- [ ] `lib/data/changelog.dart` 출시 entry `date`를 실제 출시일로 갱신
- [ ] 본인·지인 5명 정도 1주 사용 후 크래시 0건 확인
- [ ] 첫 1주 매일 Sentry/Crashlytics 확인 + 의견 메일 모니터링

### Android
- [ ] `flutter build appbundle --release` 통과
- [ ] Play Console 내부 테스트 → 비공개(closed) → 공개(production)

### iOS
- [ ] Xcode → Archive → App Store Connect 업로드
- [ ] TestFlight 베타 (내부 → 외부) → 정식 심사 제출
- [ ] 심사 1~3일 대기 / 거부 시 사유 보고 재제출

---

## 메모

- 안드 우선 출시도 OK. iOS는 Mac/Apple Developer 셋업 끝나는 대로 병행.
- 안드 출시 직후 1주는 신규 기능 X — 안정성 확인만.
- "Sign in with Apple"이 iOS 출시 최대 블로커. Apple Developer 가입 → Service ID·Key 만들고 Supabase에 연결까지 0.5일.
- Edge Function CORS·rate limit이 출시 후 비용 폭주 위험 1순위. 화이트리스트·throttle 필수.
