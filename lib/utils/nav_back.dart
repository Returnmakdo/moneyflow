import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'browser_back_stub.dart'
    if (dart.library.html) 'browser_back_web.dart';

/// 뒤로가기 통일 핸들러.
/// - 웹: 브라우저 history.back() — GoRouter가 url strategy로 history에 entry를
///       push하므로 정확히 이전 path로 돌아감.
/// - 모바일 native: navigator stack pop, 안 되면 fallback path로 go.
void goBackOr(BuildContext context, String fallback) {
  if (tryBrowserBack()) return;
  if (Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
  } else {
    context.go(fallback);
  }
}

/// Android 시스템 뒤로가기 처리. context.go로 navigation해서 stack에 안
/// 쌓인 화면들에서, 시스템 back 버튼 누르면 앱이 종료되는 걸 막기 위해
/// fallback path로 이동시킴. 웹 브라우저 뒤로가기는 URL history 기반이라
/// PopScope 통과 안 함 — 영향 없음.
class BackPopScope extends StatelessWidget {
  const BackPopScope({
    super.key,
    required this.child,
    required this.fallback,
  });

  final Widget child;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        goBackOr(context, fallback);
      },
      child: child,
    );
  }
}
