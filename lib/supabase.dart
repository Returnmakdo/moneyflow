import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = 'https://nwndjqgipjlxxoxptusn.supabase.co';
const supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im53bmRqcWdpcGpseHhveHB0dXNuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcyNzI1NTEsImV4cCI6MjA5Mjg0ODU1MX0.0FbipuhoAs-r8L4x-FDeBgjKytI0hoSFRb7dFebUE44';

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: supabaseUrl,
    // TODO(출시 전후): supabase_flutter 2.14+에서 anonKey deprecated → 차기 메이저에서
    // 제거 예정. Supabase 대시보드에서 publishable key(sb_publishable_...) 발급 후
    // publishableKey 파라미터로 교체할 것. 현재 anon JWT는 RLS로 계속 동작.
    // ignore: deprecated_member_use
    anonKey: supabaseAnonKey,
    // implicit 흐름: 메일 링크가 다른 브라우저/탭에서 열려도 동작.
    // PKCE는 같은 브라우저의 localStorage에 verifier 의존해서 비번 재설정에서
    // 종종 깨짐.
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.implicit,
    ),
  );
}

SupabaseClient get sb => Supabase.instance.client;
