import 'package:flutter/material.dart';
import 'package:strumm/core/theme/app_colors.dart';

/// Horizontal seismograph-style tuning display.
/// Centre line = 0 cents (perfect tune).
/// Trace rises above centre when sharp, dips below when flat.
/// History scrolls right-to-left like a real seismograph.
class TuningGauge extends StatefulWidget {
  final double centsDiff; // expected range approximately -50..50
  final bool isListening;
  final bool isInTune;
  final bool hasPitch; // whether a valid pitch was detected
  final Color tuningColor;
  final ValueNotifier<DateTime?>? lastPitchNotifier;

  const TuningGauge({
    super.key,
    required this.centsDiff,
    required this.isListening,
    required this.isInTune,
    required this.hasPitch,
    this.lastPitchNotifier,
    required this.tuningColor,
  });

  @override
  State<TuningGauge> createState() => _TuningGaugeState();
}

class _TuningGaugeState extends State<TuningGauge>
    with SingleTickerProviderStateMixin {
  // Sliding window of cents readings.  120 pts @ 16 ms ≈ 2 s visible history.
  // Use nullable entries: `null` = no valid pitch (gap in trace).
  final List<double?> _history = [];
  static const int _maxPoints = 120;

  // Drives constant repaints for smooth sub-pixel scrolling.
  late final AnimationController _ticker;

  // Time since the last data push, used to interpolate scroll position.
  final Stopwatch _lastFrameTimer = Stopwatch()..start();
  double _accumulatedTime = 0.0;

  // Expected ms between pushed readings (matches 60 fps UI throttle).
  static const double _msPerPoint = 16.66; // 60Hz

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    
    // Drive sample pushes based on elapsed time to maintain constant scroll speed
    // regardless of frame rate (decoupled simulation loop).
    _ticker.addListener(() {
      if (!widget.isListening) {
        _lastFrameTimer.reset();
        _accumulatedTime = 0.0;
        return;
      }

      final elapsed = _lastFrameTimer.elapsedMicroseconds / 1000.0;
      _lastFrameTimer.reset();
      _accumulatedTime += elapsed;

      // Cap catch-up to prevent "spiral of death" or huge jumps after pause
      if (_accumulatedTime > 100.0) _accumulatedTime = 100.0; 

      while (_accumulatedTime >= _msPerPoint) {
        _accumulatedTime -= _msPerPoint;

        // Append a sample every _msPerPoint (16.6ms) for constant speed.
        final now = DateTime.now();
        final notifierTs = widget.lastPitchNotifier?.value;
        final notifierHas = notifierTs != null && now.difference(notifierTs).inMilliseconds < 250;
        final hasPitch = widget.lastPitchNotifier != null ? notifierHas : widget.hasPitch;

        if (hasPitch) {
          _history.add(widget.centsDiff.clamp(-50.0, 50.0));
        } else {
          _history.add(null);
        }

        while (_history.length > _maxPoints) {
          _history.removeAt(0);
        }
      }
    });
  }

  @override
  void didUpdateWidget(TuningGauge oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Session ended — clear trace
    if (!widget.isListening && oldWidget.isListening) {
      _history.clear();
      _lastFrameTimer.reset();
      _accumulatedTime = 0.0;
      return;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ticker,
      builder: (context, _) {
        // subOffset is the fractional scroll based on remaining accumulated time.
        final subOffset = (_accumulatedTime / _msPerPoint).clamp(0.0, 1.0);
        return SizedBox(
          width: double.infinity,
          height: 130,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: CustomPaint(
              painter: _SeismographPainter(
                history: List.unmodifiable(_history),
                subOffset: subOffset,
                activeColor: widget.isListening
                    ? widget.tuningColor
                    : AppColors.textDim,
                isInTune: widget.isInTune,
                isListening: widget.isListening,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Seismograph painter
// ---------------------------------------------------------------------------

class _SeismographPainter extends CustomPainter {
  final List<double?> history;
  final double subOffset;
  final Color activeColor;
  final bool isInTune;
  final bool isListening;

  // Must match _TuningGaugeState._maxPoints for fixed-spacing scroll.
  static const int _maxPoints = 120;

  const _SeismographPainter({
    required this.history,
    required this.subOffset,
    required this.activeColor,
    required this.isInTune,
    required this.isListening,
  });

  // Sharp (+) → above centre (smaller Y), Flat (-) → below centre.
  double _centsToY(double cents, double height) {
    final ratio = -cents / 50.0;
    return (height / 2) + ratio * (height / 2 - 18);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final bounds = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(bounds, const Radius.circular(14));

    // ── Background ───────────────────────────────────────────────────────────
    canvas.drawRRect(rrect, Paint()..color = AppColors.surface);
    canvas.save();
    canvas.clipRRect(rrect);

    // ── ±5-cent in-tune corridor ─────────────────────────────────────────────
    final corridorTop = _centsToY(5, size.height);
    final corridorBot = _centsToY(-5, size.height);
    canvas.drawRect(
      Rect.fromLTRB(0, corridorTop, size.width, corridorBot),
      Paint()..color = AppColors.inTune.withValues(alpha: isInTune ? 0.14 : 0.04),
    );

    // ── Dashed ±25-cent guides ───────────────────────────────────────────────
    void drawDashed(double cents) {
      final y = _centsToY(cents, size.height);
      final p = Paint()
        ..color = AppColors.textDim.withValues(alpha: 0.18)
        ..strokeWidth = 0.8;
      const dash = 5.0, gap = 4.0;
      double x = 0;
      while (x < size.width) {
        canvas.drawLine(
          Offset(x, y),
          Offset((x + dash).clamp(0, size.width), y),
          p,
        );
        x += dash + gap;
      }
    }

    drawDashed(25);
    drawDashed(-25);

    // ── Centre line (0 cents) ────────────────────────────────────────────────
    canvas.drawLine(
      Offset(0, midY),
      Offset(size.width, midY),
      Paint()
        ..color = AppColors.surfaceLight
        ..strokeWidth = 1.2,
    );

    // ── Tick marks ───────────────────────────────────────────────────────────
    final tickP = Paint()
      ..color = AppColors.textDim.withValues(alpha: 0.4)
      ..strokeWidth = 0.8;
    for (final c in [-50.0, -25.0, 0.0, 25.0, 50.0]) {
      final y = _centsToY(c, size.height);
      canvas.drawLine(Offset(0, y), Offset(5, y), tickP);
      canvas.drawLine(Offset(size.width - 5, y), Offset(size.width, y), tickP);
    }

    // ── Labels ───────────────────────────────────────────────────────────────
    void label(String text, double x, double y) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            color: AppColors.textDim,
            fontSize: 9,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
    }

    label('SHARP', 28, 11);
    label('FLAT', 28, size.height - 11);
    label('0', 10, midY);

    // ── Catmull-Rom spline trace ─────────────────────────────────────────────
    // If there are no non-null points, skip expensive path construction.
    final hasAny = history.any((e) => e != null);
    if (hasAny) {
      final n = history.length;
      final spacing = size.width / _maxPoints;
      final scrollPx = subOffset * spacing;

      final combinedPath = Path();

      // Build contiguous non-null segments and draw each as a Catmull-Rom spline
      int i = 0;
      Offset? latestTip;
      while (i < n) {
        // skip nulls
        while (i < n && history[i] == null) {
          i++;
        }
        if (i >= n) break;

        // start of segment
        final seg = <Offset>[];
        while (i < n && history[i] != null) {
          final age = (n - 1 - i).toDouble();
          seg.add(Offset(
            size.width - age * spacing - scrollPx,
            _centsToY(history[i]!, size.height),
          ));
          latestTip = seg.last;
          i++;
        }

        if (seg.length == 1) {
          combinedPath.moveTo(seg[0].dx, seg[0].dy);
          combinedPath.addOval(Rect.fromCircle(center: seg[0], radius: 0.2));
        } else if (seg.length >= 2) {
          // convert segment pts to smooth cubic path
          final segPath = Path()..moveTo(seg[0].dx, seg[0].dy);
          for (int j = 0; j < seg.length - 1; j++) {
            final p0 = j > 0 ? seg[j - 1] : seg[j];
            final p1 = seg[j];
            final p2 = seg[j + 1];
            final p3 = j + 2 < seg.length ? seg[j + 2] : seg[j + 1];
            segPath.cubicTo(
              p1.dx + (p2.dx - p0.dx) / 6,
              p1.dy + (p2.dy - p0.dy) / 6,
              p2.dx - (p3.dx - p1.dx) / 6,
              p2.dy - (p3.dy - p1.dy) / 6,
              p2.dx,
              p2.dy,
            );
          }
          combinedPath.addPath(segPath, Offset.zero);
        }
      }

      if (combinedPath.computeMetrics().isNotEmpty) {
        // Glow and main trace drawn from combinedPath
        canvas.saveLayer(bounds, Paint());
        canvas.drawPath(
          combinedPath,
          Paint()
            ..color = activeColor.withValues(alpha: 0.15)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );

        canvas.drawPath(
          combinedPath,
          Paint()
            ..color = activeColor.withValues(alpha: isListening ? 0.85 : 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );

        canvas.drawRect(
          bounds,
          Paint()
            ..blendMode = BlendMode.dstIn
            ..shader = const LinearGradient(
              colors: [Color(0x00FFFFFF), Color(0xFFFFFFFF)],
              stops: [0.0, 0.15],
            ).createShader(bounds),
        );
        canvas.restore();
      }

      // Live tip: use latest non-null point
      if (isListening && latestTip != null) {
        final tip = latestTip;
        canvas.drawLine(
          Offset(tip.dx, 0),
          Offset(tip.dx, size.height),
          Paint()
            ..color = activeColor.withValues(alpha: 0.15)
            ..strokeWidth = 1,
        );

        canvas.drawCircle(
          tip,
          10,
          Paint()
            ..color = activeColor.withValues(alpha: 0.18)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );

        canvas.drawCircle(
          tip,
          4.5,
          Paint()..color = activeColor.withValues(alpha: 0.5),
        );

        canvas.drawCircle(tip, 2.8, Paint()..color = activeColor);
      }
    }

    canvas.restore(); // end clip
    // ── Border ───────────────────────────────────────────────────────────────
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = AppColors.surfaceLight
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _SeismographPainter old) => true;
}

