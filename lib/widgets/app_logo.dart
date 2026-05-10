import 'package:flutter/material.dart';

import '../theme.dart';

/// 앱 로고 — 토스블루 배경의 둥근 사각형 안에 흰 W + 가로 한 줄.
/// splash·로그인 화면 등 어디서든 일관된 디자인으로 표시.
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 30,
    this.cornerRadius,
  });

  /// 정사각형 변 길이.
  final double size;

  /// 모서리 둥글기. null이면 size의 27% (앱 아이콘과 동일 비율).
  final double? cornerRadius;

  @override
  Widget build(BuildContext context) {
    final radius = cornerRadius ?? size * 0.267;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: CustomPaint(painter: _AppLogoMarkPainter()),
    );
  }
}

/// 배경 없는 W + 한 줄 마크 — 다른 색 위에 얹을 때 사용.
class AppLogoMark extends StatelessWidget {
  const AppLogoMark({super.key, this.size = 220});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _AppLogoMarkPainter()),
    );
  }
}

/// W + 가로 한 줄을 그리는 페인터.
/// 220x220 기준 좌표 → 실제 size에 비례해서 스케일.
/// 모든 곳에서 재사용 (splash·로그인·미니 로고).
class _AppLogoMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final scaleX = w / 220.0;
    final scaleY = h / 220.0;
    Offset p(double x, double y) => Offset(x * scaleX, y * scaleY);

    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 30 * scaleX
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // W stroke (\/\/) — 봉우리 (40, 55, 40), 골 (175)
    final path = Path()
      ..moveTo(p(38, 40).dx, p(38, 40).dy)
      ..lineTo(p(74, 175).dx, p(74, 175).dy)
      ..lineTo(p(110, 55).dx, p(110, 55).dy)
      ..lineTo(p(146, 175).dx, p(146, 175).dy)
      ..lineTo(p(182, 40).dx, p(182, 40).dy);
    canvas.drawPath(path, stroke);

    // 가로 한 줄 (W 위쪽 가로지름)
    final fill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final barRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        p(28, 85).dx,
        p(28, 85).dy,
        (220 - 28 * 2) * scaleX,
        18 * scaleY,
      ),
      Radius.circular(4 * scaleY),
    );
    canvas.drawRRect(barRect, fill);
  }

  @override
  bool shouldRepaint(covariant _AppLogoMarkPainter oldDelegate) => false;
}
