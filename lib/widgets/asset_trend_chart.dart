import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';
import 'format.dart';

/// 자산 추이 라인 차트 — 최근 N개월 월말 총자산.
/// 음수 잔고 가능 (적자) — minY 동적 조정.
class AssetTrendChart extends StatelessWidget {
  const AssetTrendChart({super.key, required this.trend});
  final List<AssetTrendPoint> trend;

  static const _line = Color(0xFF1D4ED8);
  static const _fillTop = Color(0x331D4ED8);
  static const _fillBottom = Color(0x001D4ED8);

  @override
  Widget build(BuildContext context) {
    if (trend.length < 2) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Text(
            '자산 추이를 보려면 거래가 더 필요해요',
            style: TextStyle(fontSize: 12.5, color: AppColors.text3),
          ),
        ),
      );
    }
    final values = trend.map((t) => t.totalAssets).toList();
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final pad = ((maxV - minV).abs() * 0.15).round().clamp(10000, 1000000000);
    final maxY = (maxV + pad).toDouble();
    final minY = minV >= 0 ? 0.0 : (minV - pad).toDouble();

    return SizedBox(
      height: 150,
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                // interval=1 명시 — 미명시 시 fl_chart가 fractional value에도
                // 호출해서 같은 정수 인덱스 라벨이 중복 그려지는 버그 회피.
                interval: 1,
                reservedSize: 26,
                getTitlesWidget: (value, meta) {
                  // 정수가 아닌 호출도 들어오면 그릴 필요 없음.
                  if ((value - value.roundToDouble()).abs() > 0.001) {
                    return const SizedBox();
                  }
                  final i = value.toInt();
                  if (i < 0 || i >= trend.length) return const SizedBox();
                  final isLast = i == trend.length - 1;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${int.parse(trend[i].ym.substring(5, 7))}월',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight:
                            isLast ? FontWeight.w700 : FontWeight.w500,
                        color: isLast ? _line : AppColors.text3,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF191F28),
              tooltipPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              getTooltipItems: (spots) => spots.map((s) {
                final i = s.x.toInt();
                final mLabel =
                    '${int.parse(trend[i].ym.substring(5, 7))}월';
                return LineTooltipItem(
                  '$mLabel\n',
                  const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  children: [
                    TextSpan(
                      text: '${won(trend[i].totalAssets)}원',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < trend.length; i++)
                  FlSpot(i.toDouble(), trend[i].totalAssets.toDouble()),
              ],
              isCurved: true,
              curveSmoothness: 0.25,
              color: _line,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, _, bar, idx) {
                  final isLast = idx == trend.length - 1;
                  return FlDotCirclePainter(
                    radius: isLast ? 4.5 : 3,
                    color: Colors.white,
                    strokeWidth: 2,
                    strokeColor: _line,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: const LinearGradient(
                  colors: [_fillTop, _fillBottom],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
