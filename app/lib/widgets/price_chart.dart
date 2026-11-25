// Simple line chart for price history, drawn with a [CustomPainter].
// No extra chart dependency — keeps the app light.

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/price_point.dart';
import '../utils/format.dart';

class PriceChart extends StatelessWidget {
  const PriceChart({super.key, required this.points});

  final List<PricePoint> points;

  @override
  Widget build(BuildContext context) {
    final lc = localeCode(context);
    if (points.isEmpty) {
      return SizedBox(
        height: 180,
        child: Center(child: Text(tr(context, 'noHistory'))),
      );
    }
    if (points.length == 1) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Text(
            tr(context, 'onePrice',
                <String, String>{'price': formatEgp(points.first.price, locale: lc)}),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
    // Lowest / highest are computed over LIVE points only when any exist,
    // so a flagged sample point can never be presented as the lowest
    // (or highest) price. When every point is a sample (offline fallback),
    // the range falls back to all points and the sample banner above the
    // chart already labels them as sample.
    final livePoints = points.where((p) => !p.isSample).toList();
    final rangePoints = livePoints.isEmpty ? points : livePoints;
    final prices = rangePoints.map((p) => p.price).toList();
    final min = prices.reduce((a, b) => a < b ? a : b);
    final max = prices.reduce((a, b) => a > b ? a : b);
    final hasSample = points.any((p) => p.isSample);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              tr(context, 'chartMax',
                  <String, String>{'price': formatEgp(max, locale: lc)}),
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
            Text(
              tr(context, 'chartMin',
                  <String, String>{'price': formatEgp(min, locale: lc)}),
              style: const TextStyle(
                color: Color(0xFF15803D),
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 180,
          child: CustomPaint(
            painter: _PriceChartPainter(points: points, min: min, max: max),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              shortDate(points.first.fetchedAt),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Text(
              shortDate(points.last.fetchedAt),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        if (hasSample) ...<Widget>[
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFFF59E0B),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  tr(context, 'chartSampleLegend'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF92400E),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PriceChartPainter extends CustomPainter {
  _PriceChartPainter({
    required this.points,
    required this.min,
    required this.max,
  });

  final List<PricePoint> points;
  final double min;
  final double max;

  @override
  void paint(Canvas canvas, Size size) {
    const padding = 12.0;
    final chartWidth = size.width - padding * 2;
    final chartHeight = size.height - padding * 2;
    final range = (max - min).abs() < 1 ? 1.0 : max - min;

    Offset toOffset(int index, double price) {
      final x = padding + chartWidth * index / (points.length - 1);
      final y = padding + chartHeight * (1 - (price - min) / range);
      return Offset(x, y);
    }

    // Grid lines.
    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = padding + chartHeight * i / 3;
      canvas.drawLine(Offset(padding, y), Offset(size.width - padding, y), gridPaint);
    }

    // Area fill under the line.
    final path = Path();
    path.moveTo(toOffset(0, points.first.price).dx, size.height - padding);
    for (var i = 0; i < points.length; i++) {
      final offset = toOffset(i, points[i].price);
      if (i == 0) {
        path.lineTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }
    path.lineTo(
      toOffset(points.length - 1, points.last.price).dx,
      size.height - padding,
    );
    path.close();
    canvas.drawPath(
      path,
      Paint()..color = const Color(0xFF475569).withValues(alpha: 0.12),
    );

    // Line.
    final linePaint = Paint()
      ..color = const Color(0xFF475569)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final linePath = Path();
    for (var i = 0; i < points.length; i++) {
      final offset = toOffset(i, points[i].price);
      if (i == 0) {
        linePath.moveTo(offset.dx, offset.dy);
      } else {
        linePath.lineTo(offset.dx, offset.dy);
      }
    }
    canvas.drawPath(linePath, linePaint);

    // Dots: sample points are amber; the cheapest point is highlighted
    // in green only when it is a LIVE point (a sample point can never be
    // the highlighted "lowest" — the live-only min is used for that).
    for (var i = 0; i < points.length; i++) {
      final offset = toOffset(i, points[i].price);
      final isSample = points[i].isSample;
      final isCheapest = !isSample && points[i].price == min;
      canvas.drawCircle(
        offset,
        isCheapest ? 5 : 3.5,
        Paint()
          ..color = isSample
              ? const Color(0xFFF59E0B)
              : isCheapest
                  ? const Color(0xFF15803D)
                  : Colors.white,
      );
      canvas.drawCircle(
        offset,
        isCheapest ? 5 : 3.5,
        Paint()
          ..color = isSample
              ? const Color(0xFF92400E)
              : const Color(0xFF475569)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_PriceChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.min != min ||
        oldDelegate.max != max;
  }
}
