# Windows에서만 할 수 있는 작업 (Android SDK·JDK 필요)

Mac에는 Android SDK/JDK가 없어 아래는 **Windows(Android Studio 설치된 환경)** 에서 해야 함.
iOS 빌드·웹·Supabase/Google 대시보드 작업은 Windows 아니어도 됨 — 여긴 **Android 빌드/서명 전용**.

> Flutter SDK 경로(기존): `C:\Users\Public\flutter-sdk\flutter\bin\flutter.bat`
> 프로젝트 폴더는 **ASCII 경로**에 둘 것(한글 폴더면 Gradle/aapt 깨짐). 예: `C:\moneyflow`

---

## 0. 사전 — 최신 코드 받기
```bash
git pull            # 원격: https://github.com/Returnmakdo/moneyflow.git
flutter pub get
```
※ Mac에서 한 주요 변경(이미 push됨): 패키지명 `moneyflow`, 번들 ID `com.cyahn.moneyflow`,
   R8 minify 활성화(`android/app/build.gradle.kts` + `proguard-rules.pro`), 도메인 `moneyflow-kr.vercel.app`.

## 1. Release keystore 생성  ← Windows 필수 (keytool=JDK)
```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```
- 비밀번호·이름 등 입력. **upload-keystore.jks는 안전하게 보관**(분실 시 앱 업데이트 영구 불가).
- Play App Signing 권장.

## 2. android/key.properties 작성  (이미 .gitignore됨 — 커밋 안 됨)
프로젝트 `android/` 폴더에 `key.properties` 생성:
```
storePassword=keystore에서_정한_비번
keyPassword=keystore에서_정한_비번
keyAlias=upload
storeFile=C:/경로/upload-keystore.jks   # 절대경로, 슬래시 / 사용
```
→ `build.gradle.kts`가 이 파일 있으면 자동으로 release 키 서명(없으면 debug 폴백).

## 3. Release .aab 빌드 + R8 검증  ← Windows 필수 (Android SDK)
```bash
flutter build appbundle --release
```
- **R8 minify/shrinkResources가 켜져 있으므로** 빌드가 깨지는지 꼭 확인.
  - 빌드 실패 시 missing class 류면 `android/app/proguard-rules.pro`에 keep 규칙 추가.
- 산출물: `build/app/outputs/bundle/release/app-release.aab`

## 4. .aab 실기기 동작 검증
```bash
# bundletool로 apks 생성 → 실기기 설치 (debug와 다르게 R8가 깨는 케이스 확인)
# 또는 Play Console 내부 테스트 트랙 업로드 후 설치
```
- debug에선 멀쩡한데 release(minify)에서 깨지는 화면 없는지 — 특히 거래/자산/차트/마크다운.

## 5. (선택) Android 에뮬레이터 전체 QA
```bash
flutter emulators --launch <emulator_id>
flutter run -d emulator-5554
```
- LAUNCH.md "4. 기능 점검 시나리오" 따라 자산·카드·결제·로그인 흐름 점검.

---

## 주의
- **번들 ID `com.cyahn.moneyflow`** (이미 변경 완료) — 건드리지 말 것.
- Google 로그인(Android deep link) 테스트하려면 Supabase Redirect URLs에
  `com.cyahn.moneyflow://login-callback/` 등록돼 있어야 함(Mac에서 등록 완료).
- `targetSdk`는 Flutter 기본값(36) 유지 — 핀 박지 말 것.

## Mac/브라우저에서 이미 끝낸 것 (참고, 다시 안 해도 됨)
- iOS 무선 빌드·실행, 패키지명/번들ID 변경, 도메인 변경, 처리방침 페이지+인앱 링크,
  자산 순수함수+테스트, 토스트 비차단화, Supabase Redirect URLs/Google OAuth 프로덕션 게시.
