# 가계부 프로젝트 — 인수인계 문서

토스/뱅크샐러드 톤의 가계부. Supabase(Postgres + Auth + Edge Functions)를 백엔드로 쓰는 Flutter 앱 (Android + Web). 2026-04-29에 웹 SPA(Express + vanilla JS)를 버리고 Flutter로 단일화. 같은 Supabase 백엔드를 Android와 Web 빌드가 공유. 2026-05-01에 AI 분석/온보딩/도움말/CSV 가져오기/다크모드 추가. 2026-05-07에 자산(계좌) 시스템 + 수입/지출 분리 + 이체 + 정기수입 + 신용카드 시스템(cards 테이블 + 결제일 정산 흐름) 추가 — 5탭 4번이 정기지출에서 *자산*으로 교체됨.

## 빠른 시작

```bash
cd "C:\billionaire"

# Android 에뮬레이터
"C:\Users\Public\flutter-sdk\flutter\bin\flutter.bat" run -d emulator-5554

# 크롬 (PC에서 빠르게 보기)
"C:\Users\Public\flutter-sdk\flutter\bin\flutter.bat" run -d chrome

# 프로덕션 웹 빌드 (Vercel 배포용)
"C:\Users\Public\flutter-sdk\flutter\bin\flutter.bat" build web --release
```

`r`/`R` = hot reload / restart. 웹은 hot restart만 안정적, 에셋(폰트 등) 변경은 `q` → 재실행.

**프로젝트 위치는 `C:\billionaire\` (ASCII 경로)** — 한글 폴더에서는 Gradle/aapt가 깨짐.

## 기술 스택

- **백엔드**: Supabase (Postgres + RLS + Auth + Edge Functions)
- **프론트**: Flutter 3.11+ (Material 3, GoRouter, supabase_flutter, intl, fl_chart)
- **AI**: Anthropic Claude Opus 4.7 — Edge Function 프록시 통해 호출 (API 키 클라이언트 노출 X)
- **인증**: Supabase Auth (이메일·비번, Google OAuth)
- **폰트**: Pretendard 4종 번들
- **타깃**: Android, Web. iOS/Windows desktop은 환경 셋업 필요.

### 주요 의존성
```yaml
supabase_flutter, go_router, intl
fl_chart, flutter_svg
flutter_markdown, markdown          # AI 인사이트 렌더링
file_picker                         # CSV 업로드
share_plus, path_provider           # 모바일 native 파일 공유
shared_preferences                  # 테마 로컬 캐시
```

## Supabase 정보

메모리 `supabase_setup.md`에 풀 정보. 핵심:
- Project ref: `nwndjqgipjlxxoxptusn` (region: ap-northeast-2)
- Anon key는 `lib/supabase.dart`에 박혀 있음 (RLS로 보호)
- Edge Function 시크릿: `ANTHROPIC_API_KEY` (Supabase 대시보드 Edge Functions Secrets)
- 어드민 작업은 Supabase MCP로 (`apply_migration`, `execute_sql`, `deploy_edge_function`)

## 폴더 구조

```
C:\billionaire\
├── CLAUDE.md
├── .github/workflows/deploy.yml
├── vercel.json                     # SPA fallback rewrite
├── supabase/
│   ├── schema.sql                  # 참고용
│   └── functions/spending-insights/index.ts  # AI 분석 Edge Function (Deno)
├── assets/
│   ├── fonts/                      # Pretendard 4종
│   ├── icons/                      # Google G logo
│   └── onboarding/                 # 01~04.png 슬라이드 스크린샷
└── lib/
    ├── main.dart                   # GoRouter + Auth gate + ThemeMode
    ├── theme.dart                  # AppColors (dynamic getter) + AppColorsDark + buildLight/DarkTheme
    ├── supabase.dart
    ├── auth.dart                   # AuthService (signIn/themeMode/userVersion 등)
    ├── api/
    │   ├── models.dart
    │   └── api.dart                # Api.instance + _txCache + version notifiers
    ├── state/selected_month.dart   # 전역 SelectedMonth ValueNotifier (탭 간 공유)
    ├── utils/
    │   ├── csv_download_{stub,web}.dart    # 파일 download + Web Share API
    │   ├── browser_back_{stub,web}.dart    # web: history.back()
    │   ├── is_mobile_{stub,web}.dart       # 모바일 web/native 판별
    │   └── nav_back.dart                   # goBackOr(context, fallback)
    ├── widgets/
    │   ├── common.dart             # PageHeader/AppCard/EmptyCard/ProgressTrack/_LogoutButton 등
    │   ├── format.dart             # won/smartWon/ymLabel
    │   ├── category_color.dart     # 8색 CatColor (bg/fg) 팔레트
    │   ├── account_meta.dart       # 계좌 type 5종 라벨/아이콘/색 + AccountBadge
    │   ├── kpi_card.dart           # KpiAccent enum (expense/income/good/bad/neutral)
    │   ├── budget_card.dart, merchant_item.dart, tx_row.dart
    │   ├── amount_field.dart       # 콤마 포맷팅 입력
    │   ├── ko_date_picker.dart     # 한국어 월/연 picker
    │   ├── skeleton.dart           # 로딩 스켈레톤
    │   ├── charts.dart             # CategoryShare, MonthlyTrendBar (지출·수입 그룹 막대)
    │   ├── asset_trend_chart.dart  # 자산 탭 6개월 자산 추이 라인 차트
    │   ├── ai_insight_card.dart    # AI 인사이트 PageView 카드
    │   └── spending_insight_pages.dart  # Summary/Pattern/Budget/Suggestion 페이지 + parseInsight
    └── screens/
        ├── login_screen.dart, reset_password_screen.dart
        ├── onboarding_screen.dart  # 첫 로그인 4장 슬라이드
        ├── shell_screen.dart       # 5탭 네비 (대시보드/거래내역/예산/자산/분석)
        ├── dashboard_screen.dart, transactions_screen.dart, tx_modal.dart
        ├── accounts_screen.dart    # 자산 메인 탭 — 총자산 + 추이차트 + 계좌·카드 CRUD + 결제 등록 시트
        ├── budgets_screen.dart
        ├── spending_insights_screen.dart  # AI 분석 탭
        ├── settings_screen.dart    # 메뉴 리스트 (계정/카테고리/정기 거래/import/export/테마/도움말)
        ├── account_settings_screen.dart, categories_screen.dart
        ├── fixed_expenses_screen.dart  # /settings/fixed (정기지출/정기수입 탭)
        ├── theme_settings_screen.dart, help_screen.dart, import_screen.dart
```

## 데이터 모델 (Postgres / RLS `auth.uid() = user_id`)

- `transactions` — id, user_id, date(YYYY-MM-DD), card(자유 텍스트 메모), merchant, amount, major_category, sub_category, memo, is_fixed (0/1), **account_id**, **from_account_id·to_account_id**, **card_id**, **type** ('expense'|'income'|'transfer'|'card_payment'), created_at, updated_at. CHECK constraint `tx_account_consistency`:
  - expense (account 결제): account_id만
  - expense (card 결제): card_id만 — 자산 영향 X, 카드 부채 +
  - income: account_id만
  - transfer: from/to_account_id 둘 다 (서로 다른 계좌)
  - card_payment: from_account_id(linked) + card_id (결제일 정산 거래)
- `accounts` — id, user_id, name, type ('checking'|'cash'|'savings'|'investment'|'other'), initial_balance, sort_order, active. UNIQUE (user_id, name). 신용카드는 cards 테이블에 별도.
- `cards` — id, user_id, name, payment_day(1~31), linked_account_id, statement_close_day(nullable), sort_order, active. UNIQUE (user_id, name). 카드 사용 거래는 자산에 즉시 영향 X, **결제일에 사용자가 청구액 확인 후 자산 탭의 빨간 줄 → 결제 등록 시트**로 card_payment 거래 생성 → linked_account에서 차감.
- `majors` — PK (user_id, major), sort_order, **type** ('expense'|'income'). 지출/수입 카테고리 분리.
- `categories` — id, user_id, major, sub, sort_order. UNIQUE (user_id, major, sub). type은 major에서 상속.
- `budgets` — PK (user_id, major), monthly_amount. **expense major에만 존재** (income은 budget 없음).
- `fixed_expenses` — id, user_id, name, major, sub, amount, card, day_of_month, active, memo, sort_order, **account_id NOT NULL**, **type** ('expense'|'income'). 정기지출·정기수입 *카탈로그(템플릿)*. 로그인/거래내역 진입 시 `applyDueFixedTransactions`가 도래일 ≤ 오늘 항목을 dedupe + log 체크 후 자동 등록.
- `fixed_apply_log` — PK (user_id, fixed_id, month). 한 번 적용된 (fixed, month) 페어 기록. 자동 적용 시 이 로그에 있는 페어는 *재적용 X* — 사용자가 거래 의도적으로 삭제해도 다시 등록 안 됨. 사용자가 직접 등록한 매칭 거래도 dedupe와 함께 log 기록 (재추가 차단). **`updateFixedExpense`도 created_month~이전 달까지 backfill upsert** — 카테고리/이름 변경으로 dedupe key 깨져도 과거 자동 재추가 차단.
- `ai_insights` — PK (user_id, month), content (text), generated_at. AI 분석 결과 캐시. **거래 변경 시 트리거(`tx_invalidate_ai_insights`)가 해당 월 캐시 자동 삭제**.

### 트리거/RPC
- `seed_default_data_for_new_user` — auth.users INSERT 시 expense major 10종 + income major 4종(월급·이자·용돈·기타수입) + budgets(expense만) + accounts '기본'(checking) 1개 시드.
- `tx_invalidate_ai_insights` — transactions INSERT/UPDATE/DELETE 시 ai_insights 자동 무효화 (date 기준 month)
- `check_email_exists(p_email)` RPC — 회원가입 실시간 중복 체크
- `delete_my_account()` RPC — 본인 계정 삭제 + ON DELETE CASCADE로 모든 데이터 정리

## API 레이어 (`lib/api/api.dart`)

`Api.instance` 싱글톤. 내부 `_txCache`로 transactions 캐싱.

- 거래/카테고리/태그/예산/정기지출 CRUD. `createTransaction/updateTransaction`은 `accountId`/`fromAccountId`/`toAccountId`/`type` 인자 받음.
- `listMajors({type})`, `listCategories({type})`, `listTransactions({type, ...})` — type 인자로 expense/income 필터
- `createMajor(name, {type='expense'})` — type='expense'면 budgets도 자동 생성, income은 안 생성
- **계좌 CRUD**: `listAccounts/createAccount/updateAccount/deleteAccount`. `_defaultAccountId()` 헬퍼는 사용자의 '기본' checking 또는 첫 활성 계좌 — 호출부가 `accountId` 명시 안 하면 자동 fallback.
- `getDashboard(month)` — expense/income 분리 집계. `Dashboard.thisMonthTotal`은 *지출*, `incomeTotal`/`netSaving` 신규.
- `getSubCategoryStats`, `getSuggestions` — 클라이언트 계산. getSubCategoryStats는 expense만.
- `getCachedSpendingInsight(month)` — ai_insights 직접 조회 (Edge Function 안 거침, 빠른 표시용)
- `getSpendingInsight(month, force: bool)` — Edge Function 호출 → AI 분석. force=true면 캐시 우회
- `importTransactions(rows)` — CSV import. row.type별 majors 자동 등록 (expense/income 분리), default 계좌로 account_id 자동 채움.
- `exportTransactionsCsv()` — '구분' 컬럼 포함 (round-trip 호환). 단, *수기 import 양식*은 지출/수입 분리 (구분 컬럼 없음) + 옛 양식 자동 호환.

### Notifier (mutation 알림)
`txVersion`, `majorsVersion`, `categoriesVersion`, `budgetsVersion`, `fixedVersion`, `accountsVersion`, `cardsVersion` — 변경 시 bump. 화면이 listening해서 자동 reload.

## Edge Function: `spending-insights`

`supabase/functions/spending-insights/index.ts` (Deno + Anthropic SDK).

- 클라이언트 JWT로 사용자 거래/예산 fetch
- 집계 (카테고리/태그/가맹점/요일/이상치/예산진행)
- Claude Opus 4.7 (`thinking: adaptive`, system prompt cache_control ephemeral) 호출
- ai_insights 테이블에 결과 upsert (user_id는 DEFAULT auth.uid()로 자동)
- force=false면 캐시 hit 시 즉시 반환

**시스템 프롬프트 변경 시 `mcp__supabase__deploy_edge_function`로 재배포.** 인라인 코드 대신 파일 통째로 보내는 게 안전.

## 자산 모델 (발생주의 + 신용카드 부채)

가계부 표준 모델을 따름 — 토스/뱅샐과 동일한 계산 구조. 사용자 직관과 회계 정확성 둘 다 만족.

### 핵심 공식
```
총자산 = 모든 계좌 잔고 합 − 모든 카드 미정산 합

계좌 잔고 = initial_balance + Σ(해당 계좌 거래 변동)
카드 미정산 = Σ(카드 사용) − Σ(카드 결제)
```

### 발생주의 (Accrual basis)
- **카드 사용 시점**에 즉시 부채 발생 → 총자산 −
- **카드 결제 시점**(card_payment 거래)엔 통장 잔고 −, 부채 −. 둘이 상쇄되어 *총자산 변동 없음*
- 결과: 카드 한 번 긁으면 그 순간부터 총자산에 미리 반영됨. 결제일에 통장에서 빠질 때 다시 변하지 않음 — 이중 카운트 방지.

### 두 가지 카드 금액의 의미 차이
- **남은 청구액** (자산 탭 카드 row 큰 숫자) = `cycleAmount − cycleSettled`. 미리/분할 결제가 있으면 그만큼 줄어들어 보임. 다음 결제일에 *실제로 빠질* 금액.
- **사이클 사용액** (`CardSummary.cycleAmount`) = 사이클 내 카드 사용 합. 결제와 무관.
- **사이클 정산** (`CardSummary.cycleSettled`) = 지난 결제일+1 ~ 이번 결제일 사이의 card_payment 합. 결제 등록 시트 자동 채움 = cycleAmount − cycleSettled.
- **카드 미정산** (총자산 계산용) = 모든 사용 − 모든 결제 = 전체 미상환 부채

옛 사이클이 모두 결제 완료된 상태라면 미정산 = 사이클 사용 + 다음 사이클부터 추가된 사용. 그 외엔 어긋남(과거 미상환분 누적 또는 사이클 안 결제 등). **이 둘이 일치 강제될 필요 없음** — 의미가 다른 두 값.

### 거래 type별 자산/부채 영향
| type | 계좌 잔고 | 카드 부채 | 총자산 |
|---|---|---|---|
| expense (account) | account_id에서 − | 영향 없음 | − |
| expense (card 사용) | 영향 없음 | card_id 부채 + | − (사용 즉시) |
| income | account_id에 + | 영향 없음 | + |
| transfer | from −, to + | 영향 없음 | 변동 없음 |
| card_payment | from_account_id에서 − | card_id 부채 − | 변동 없음 (자산 이동) |

### 처음 사용자 추천 플로우
1. **계좌 등록** + 시작 잔액 박기 (현재 통장 잔고 그대로). 자산 탭에서 추가.
2. **카드 등록** — 결제일·마감일·연동 계좌 입력. 자산 탭의 카드 섹션.
3. **거래 입력 시작** — 지출 시 [내 계좌 / 신용카드] 토글로 결제수단 명시. 카드면 어느 카드인지 선택.
4. **결제일 도래** → 자산 탭 카드 row의 빨간 줄(D-day 지남) → "결제 등록"에서 명세서 청구액 확인 후 등록 → linked_account에서 차감.
5. **AI CSV import**(`/settings/import/ai`) — 카드사 명세서 통째로 넣으면 자동 매핑.

### 흔한 실수와 대응
- **잔여할부**: 카드사가 매월 청구하는 할부금. 정기 거래로 등록(결제수단 [신용카드] + day_of_month는 *마감일* 또는 그 이전). day_of_month=결제일로 두면 사이클 다음 달로 넘어가서 안 잡힘.
- **친구 1/N 정산**: 카드 사용 거래는 *명세서대로 전체 금액*으로 등록. 친구한테 받은 돈은 별도 income으로 추가. 그래야 카드 청구액·자산 흐름 모두 정확.
- **시스템 시작 시 누락된 과거 거래**: 1월부터 데이터를 다 입력 못 했다면 1/1자 "시작 잔고 보정" income/expense로 net 0 만들어서 계좌 잔고 정상화. 또는 initial_balance를 직접 조정.
- **카드 결제 거래만 삭제 시 미정산 폭증**: 옛 사이클 정리할 땐 *사용 + 결제 짝 맞춰* 같이 삭제. 한쪽만 지우면 부채 잘못 잡힘.

## 화면 구성 (5탭 + 사이드 라우트)

### 메인 탭 (StatefulShellRoute)
1. **대시보드** `/dashboard` — KPI 4장 (지출/수입/순저축/일평균), 카테고리 비율(expense), 태그 TOP, 6개월 추이(지출·수입 그룹 막대)
2. **거래내역** `/transactions` — [전체/지출/수입] chip 필터 + 월/카테고리/검색/금액범위/정렬, FAB → [지출][수입] 큰 버튼 + 송금 + 명세서. 합계는 transfer 제외.
3. **예산** `/budgets` — 카테고리별 변동비 진행률 + 입력 + 저장 (expense만)
4. **자산** `/accounts` — 상단 총자산 카드(계좌 합 − 카드 부채) + 6개월 자산 추이 라인 차트. 계좌 섹션(잔고 = initial_balance + Σ거래) + 카드 섹션(이번 달 사용액·결제 D-일·연동 계좌). 결제일 지났는데 미정산이면 빨간 줄 → 결제 등록 시트(자동 합계 + 사용자 수정 + 더블 컨펌). 카드 사용 거래는 자산 영향 X, card_payment 거래만 linked_account에서 차감.
5. **분석** `/insights` — AI 인사이트 + 4페이지 PageView. spending-insights Edge Function이 expense만 분석.

### 설정 sub 라우트 (`/settings/...`)
- `/settings` — 메뉴 리스트
- `/settings/account` — 이름/비밀번호/회원탈퇴
- `/settings/categories` — 지출/수입 탭 + 카테고리·태그 CRUD
- `/settings/fixed` — 정기지출 카탈로그 (예전엔 메인 탭이었으나 자산 탭에 자리 양보)
- `/settings/import` — CSV 일괄 등록 (지출/수입 토글 + 양식 자동 판별)
- `/settings/import/ai` — AI CSV 자동 분류 (카드사 명세서 → 카테고리 매핑)
- `/settings/theme` — 시스템/라이트/다크
- `/settings/help` — 온보딩 다시 보기 + 화면별 가이드
- `/settings/changelog` — 업데이트 소식
- `/onboarding` — 첫 로그인 자동 진입. `?from=help`면 도움말에서 닫기

### 거래 모달 (showTxModal)
- `initialType` 인자 ('expense'|'income'|'transfer') — FAB 시트에서 명시 진입. 모달 안에 type 토글 *없음*.
- 수입 모드: 가맹점→'받은 곳', 카드 자리에 입금 계좌 dropdown(account_id 명시), 고정비 토글 hide
- 이체 모드: 카테고리/가맹점/카드 모두 hide. 출금↓입금 dropdown(같은 계좌 차단). major_category='이체' 자동.
- 지출 모드 결제수단 토글: [내 계좌 / 신용카드]
  - 내 계좌: 출금 계좌 dropdown — account_id 명시
  - 신용카드: cards dropdown(card_id 명시), 자산 영향 X. 카드 0개면 안내.

## 라우팅 패턴 (중요)

- **모든 navigation은 `context.go`로 통일.** GoRouter 14.x의 `context.push`는 ImperativeRouteMatch라 URL bar 갱신 안 되는 케이스가 있음.
- **뒤로가기는 `goBackOr(context, fallback)` 헬퍼** 사용 — web에선 `window.history.back()`, mobile native에선 `Navigator.canPop` 시도 후 fallback path.
- **MaterialApp에 `key: ValueKey(brightness)`** — AppColors의 static getter는 InheritedWidget 의존이 없어 Theme 변경 시 자동 rebuild 안 됨. key 교체로 전체 재mount.

## 디자인 시스템 (다크모드)

`lib/theme.dart`에 light/dark 두 세트 + `AppColors`는 동적 getter (현재 brightness에 맞춰 light/dark 색 반환).

```dart
AppColors.bg / surface / surface2  // dynamic — light/dark 자동
AppColors.text / text2 / text3 / text4
AppColors.line / line2
AppColors.primary / primaryWeak / primaryStrong
AppColors.success / danger / warning
AppRadius.sm:10 md:14 lg:18 xl:22
```

### 다크모드 구현 (Phase 2 완료)
- `AppColors`는 `static get` (const 아님). `_isDark` static 변수에 따라 light/dark 색 반환.
- `AuthService.themeMode` — `ValueNotifier<ThemeMode>` (system/light/dark)
- 저장: 서버(user_metadata.theme_mode) + 로컬(SharedPreferences). **서버 우선**, 로그아웃 상태에선 로컬 fallback.
- main에서 `bootstrapTheme()` await로 콜드 부트 시 즉시 복원.
- `AppColors.update(brightness)`는 main의 ValueListenableBuilder에서만 호출. theme.dart의 `_build()` 안에서는 호출 X (light/dark 둘 다 build되어 마지막 호출이 덮어씀).
- ⚠️ **`const TextStyle(color: AppColors.text)` 금지** — AppColors가 const 아니라 `invalid_constant` 에러. 화면 코드에서 const 표현식 안에 AppColors.* 사용 시 const 제거 필요.

## 사용자 선호 (협업 스타일)

- 한국어로 대화. 답변은 짧게, 핵심만.
- 옵션 두세 개 + 트레이드오프 + 추천 형태로 제시. "ㄱㄱ" / "ㅇㅇ" / 알파벳으로 빠르게 결정.
- 변경 즉시 적용 → 폰/웹에서 보면서 조정하는 반복 사이클.
- 디자인 디테일에 민감 (정렬·간격·폰트·여백). UI 변경 시 모바일 레이아웃 꼭 확인.
- 솔직한 피드백 환영. **"야매 쓰지말고 근본적으로 해결" 선호** — hack/임시방편 싫어함, 진짜 원인 찾아 고치는 거 선호.
- **커밋/푸시는 절대 자동 X.** 사용자가 명시적으로 "푸시" 또는 "커밋푸시"라고 한 경우에만 git 명령. 메모 `feedback_no_auto_push.md` 참고.

## Flutter 코딩 함정

- **`setState(() => _future = someFuture)` 금지** — 화살표 람다가 Future 반환하면 런타임 throw. 항상 블록: `setState(() { _future = ...; });`
- **Stack + FractionallySizedBox 비례 막대 width collapse** — 진행률 바는 `LayoutBuilder`로 maxWidth 받아 명시 width.
- **`.order()` ascending 명시 필수** — supabase_flutter 일부 버전에서 ascending 미명시 시 desc로 동작. `listMajors`/`listBudgets`/`listCategories` 등 항상 `ascending: true` 명시.
- **`const TextStyle(color: AppColors.text)` 금지** (다크모드 반영) — AppColors가 dynamic getter라 const 표현식 안에서 invalid_constant.
- **GoRouter `context.push` URL 갱신 누락** — 모든 navigation을 `context.go`로 + `goBackOr` 헬퍼.
- **모달/popup 안에서 displayName 같은 캐시된 값** — `AuthService.userVersion` ValueListenableBuilder로 감싸야 즉시 반영.
- **마크다운 한글 옆 `**`/`~`** — flutter_markdown이 한글 옆 단어 경계 인식 못 해서 `**xxx**` 그대로 노출되거나 `8~9건`/`6~7건`처럼 단일 ~가 strikethrough로 매칭됨. `_normalizeBold()` 헬퍼로 클라이언트 보정.
- **FAB hero tag 충돌** — StatefulShellRoute로 여러 탭 keep alive 시 FAB의 기본 hero tag 같으면 에러. 각 FAB에 `heroTag: 'fab_xxx'` 명시.
- **`fixed_apply_log` upsert는 `ignoreDuplicates: true`** — 그 테이블 RLS에 INSERT/SELECT/DELETE만 있고 UPDATE 정책 없음. `upsert(onConflict: ...)` 디폴트는 conflict 시 UPDATE라 권한 에러 → ignoreDuplicates로 회피.
- **AI 카드 명세서 import는 `csvDedupe: false`** — `importTransactions`의 dedupe key가 `카드+날짜+가맹점+금액`. 같은 매장 같은 금액으로 시간만 다른 *진짜 두 건*을 1건으로 합쳐버림. 카드사 검증 데이터라 csv 내부 중복 끄는 게 안전.

## 빌드/실행 디테일

- Flutter SDK: `C:\Users\Public\flutter-sdk\flutter\bin\flutter.bat`
- Android emulator: `flutter emulators --launch billionaire`
- 첫 빌드 ~60초, 이후 hot reload 가능. 웹은 hot restart만 안정.
- **OAuth redirect URL** — 끝에 `/` 명시. `Uri.base.origin` 만으로 보내면 Supabase 화이트리스트 `/**`와 매치 안 되어 Site URL로 fallback.
- **로컬 OAuth 테스트** — `--web-port 8080`으로 포트 고정 + Supabase Redirect URLs에 `http://localhost:8080/**` 등록.

## 다음 단계 후보

### 정합성·UX 보강 (작업 작음)
- **계좌 active 처리 일관화** — 자산 탭의 토글 IconButton은 제거됐는데 `_AccountEditor`에 active 체크박스가 없어서 한 번 비활성된 계좌를 다시 활성화할 방법이 없음. 옵션 A: editor에 토글 추가, B: `Account.active` 필드 자체 제거(deletion만 운영). 둘 중 결정.
- **카드 결제계좌 변경 시 동작 (확정 — 변경 X)**: `updateCard`로 linked_account 바꿔도 기존 `card_payment.from_account_id`는 *그대로 둠*. 옛 결제는 실제로 A 통장에서 빠진 사실이라 소급 이전하면 과거 자산 흐름이 거짓이 됨. 앞으로의 결제만 새 계좌에서 빠짐. 데이터 보정이 필요하면 거래별 수동 편집(거래 모달)으로. *자동 이전 다이얼로그 추가하지 말 것*.
- ~~**잔여할부 등록 시 day_of_month 인라인 가이드**~~ — 완료. 정기 거래 등록 신용카드 모드에서 카드 선택 시 마감일/결제일 안내 박스 노출.

### 정식 기능
- **알림** (예산 임박 / 정기 거래 미등록) — `flutter_local_notifications`. 작업 작음, 매일 가치 큼.
- **APK 빌드 + 안드 SMS 파싱** — 토스/뱅샐 못 하는 영역. 결제 SMS 자동 파싱 → 거래 자동 추가.
- **iOS 실기기/스토어** — 시뮬만 돌아가는 상태. Mac + Apple Developer 계정 필요.
- **오프라인 캐시** — `drift`로 로컬 캐시 + 백그라운드 sync.

## 작업 시 주의

- **DB 스키마 변경**은 Supabase MCP의 `apply_migration`으로. `supabase/schema.sql`은 참고용.
- **Edge Function 변경**은 `supabase/functions/spending-insights/index.ts` 편집 후 `mcp__supabase__deploy_edge_function`으로 통째로 재배포.
- **anon key 노출 OK** — RLS가 보호. service_role 키는 절대 클라이언트에 두지 말 것.
- **사용자 추가/삭제**는 Supabase 대시보드 → Authentication → Users.
- **화면 변경 후 `flutter analyze` 0 issues 유지**.
- **CSV 양식**:
  - export: `날짜,구분,금액,카테고리,가맹점,카드/결제수단,태그,메모,고정비` ('구분'은 지출/수입/이체)
  - 수기 import 템플릿: 지출/수입 분리 — 양식 자동 판별 (헤더에 '구분' 있으면 옛 호환, '받은 곳' 있으면 income, 그 외 expense). 토글로 어떤 템플릿 받을지 선택.
- **테스트 데이터 입력**은 Supabase MCP `execute_sql`로 직접 INSERT (한글 cp949 문제 회피).

### 업데이트 내역(changelog) 자동 갱신

`lib/data/changelog.dart`의 `changelog` 리스트가 설정 → "업데이트 소식" 화면에 그대로 노출. **사용자가 체감하는 변경**이 있으면 반드시 맨 위에 entry 추가.

**올릴 가치 있음 (반드시 추가)**:
- 새 기능 (예: AI CSV 자동 정리, 다크모드, 탭 재진입 스크롤)
- 사용자 보이는 UI/UX 개선 (안내 문구 정정, 차트 가독성 수정)
- 사용자 데이터·계산에 영향 주는 버그 수정 (취소 거래 자동 제외, 합계 정확성)
- 보안·개인정보 변화 (마스킹 카드번호 차단)

**올리지 않음**:
- 코드 리팩터링·내부 구조 변경
- Edge Function·API·시스템 프롬프트 튜닝(사용자 화면에 안 보이는 영역)
- 메모리/CLAUDE.md 문서 변경

**entry 형식** (lib/data/changelog.dart):
```dart
ChangelogEntry(
  id: 'YYYY-MM-DD-slug',          // 고유 slug, 같은 날 여러 개면 다른 키워드
  date: 'YYYY-MM-DD',
  title: '한 줄 요약',              // 사용자에게 보일 카드 제목
  items: [
    '구체적 변경 1 — 사용자 입장에서',
    '구체적 변경 2',
  ],
),
```

**커밋/푸시 워크플로 (중요)**:
사용자가 커밋·푸시를 요청하면 entry를 먼저 정리해서 확인받는다 — 자동으로 changelog 추가해서 같이 커밋하면 안 됨.

1. `git status` / `git diff`로 변경사항을 살핀다.
2. **사용자 체감 변경**이 있는지 판단 (위 "올릴 가치 있음" 기준 적용).
3. 있으면 entry 초안을 작성해 사용자에게 보여준다:
   - 위 톤 가이드 따라 헤드라인 + items 작성.
   - 메시지 형식: "이렇게 changelog에 올라갈 건데 괜찮을까요?" + entry 내용 미리보기 (코드 블록).
4. 사용자 OK → `lib/data/changelog.dart` 맨 앞에 추가 후 그 변경도 같은 커밋에 포함.
   사용자 NO/수정 요청 → 다시 다듬어서 재확인.
   체감 변경 없다고 판단 → entry 없이 그냥 커밋.
5. **체감 변경 있는데 묻지 않고 그냥 커밋하면 신뢰 위반**. 의심 가는 경계 케이스도 일단 물어보는 쪽이 안전.

리스트 **맨 앞**에 추가 (최신이 위). id는 새 항목마다 유일해야 함 — 이걸 기준으로 빨간점이 갱신됨. 하루에 여러 작업을 묶어 올릴 땐 entry 1개로 합치고 items에 bullet 여러 개.

**톤 — 명사형 + 간결 (커밋 로그 X, 친근체 X)**:
- title·items 모두 짧은 명사형 종결. "~기능 추가" / "~ 변경" / "~ 개선" / "~ 수정" 식.
- title은 한 줄로 큰 그림. 예: "다크모드 추가" / "AI 카드 명세서 자동 정리" / "신용카드 명세서 정리 흐름 정돈".
- items는 한 줄에 하나의 변화. 종결도 명사형. "~돼요"/"~할 수 있어요" 같은 친근체 사용 X.
- 기술 용어 X — `EmptyCard`, `headerRowIndex`, `BottomSheet`, `state`, `prefs` 같은 코드 식별자는 절대 X.
- 사용자 입장에서 의미 있는 변화 위주. "어떻게 구현했는지"가 아닌 "뭐가 바뀌었는지".
- 자잘한 변경은 묶거나 제외. "탭 재진입 스크롤", "도움말 톤 다듬기" 정도는 entry 하나에 묶고, 코드 리팩터링·내부 구조는 아예 빼기.

좋은 예: "탭 재진입 시 화면 맨 위로 자동 스크롤"
나쁜 예 (친근체): "탭을 다시 누르면 화면 맨 위로 부드럽게 올라가요"
나쁜 예 (커밋 로그): "ShellTabSignals에 5개 탭 ValueNotifier 확장 + ScrollController 연결"

좋은 예: "취소된 결제 자동 제외 (명세서 합계와 일치)"
나쁜 예 (친근체): "취소된 결제는 자동으로 빼서 명세서 합계랑 똑같이 맞춰드려요"
나쁜 예 (커밋 로그): "statusCol + excludedStatuses 추가로 취소 row 자동 필터링"

---

다음 세션 진입점: 이 문서 위에서 "현재 상태" 확인 후 작업.
