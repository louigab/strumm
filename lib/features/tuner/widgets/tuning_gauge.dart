import 'package:flutter/material.dart';
import 'package:strumm/core/theme/app_colors.dart';

/// A horizontal linear gauge with tick marks and a vertical needle.
class TuningGauge extends StatefulWidget {
  final double centsDiff;
  final bool isListening;
  final bool isInTune;
  final Color tuningColor;

  const TuningGauge({
    super.key,
    required this.centsDiff,
    required this.isListening,
    required this.isInTune,
    required this.tuningColor,
  });

  @override
  State<TuningGauge> createState() => _TuningGaugeState();
}

class _TuningGaugeState extends State<TuningGauge>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _needleAnimation;
  double _previousPosition = 0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _needleAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void didUpdateWidget(TuningGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.centsDiff != widget.centsDiff) {
      _animateNeedle();
    }
  }

  void _animateNeedle() {
    // Map cents (-50 to +50) to normalized position (-1 to +1)
    final targetPosition = (widget.centsDiff / 50).clamp(-1.0, 1.0);
    _needleAnimation = Tween<double>(
      begin: _previousPosition,
      end: targetPosition,
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _previousPosition = targetPosition;
    _animController.forward(from: 0);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: SizedBox(
        width: double.infinity,
        height: 80,
        child: AnimatedBuilder(
          animation: _needleAnimation,
          builder: (context, child) {
            return CustomPaint(
              painter: _HorizontalGaugePainter(
                needlePosition:
                    widget.isListening ? _needleAnimation.value : 0,
                isListening: widget.isListening,
                isInTune: widget.isInTune,
                tuningColor: widget.tuningColor,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HorizontalGaugePainter extends CustomPainter {
  /// Normalized needle position: -1 (far left) to +1 (far right), 0 = center.
  final double needlePosition;
  final bool isListening;
  final bool isInTune;
  final Color tuningColor;

  _HorizontalGaugePainter({
    required this.needlePosition,
    required this.isListening,
    required this.isInTune,
    required this.tuningColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    const double padding = 8;
    final gaugeLeft = padding;
    final gaugeRight = size.width - padding;
    final gaugeWidth = gaugeRight - gaugeLeft;
    final centerX = size.width / 2;

    // Draw horizontal baseline
    final linePaint = Paint()
      ..color = AppColors.gaugeTrack
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(gaugeLeft, centerY),
      Offset(gaugeRight, centerY),
      linePaint,
    );

    // Draw tick marks
    _drawTicks(canvas, gaugeLeft, gaugeWidth, centerY);

    // Draw needle
    _drawNeedle(canvas, centerX, gaugeWidth, centerY, size.height);
  }

  void _drawTicks(
      Canvas canvas, double gaugeLeft, double gaugeWidth, double centerY) {
    final tickPaint = Paint()
      ..strokeCap = StrokeCap.round;

    const totalTicks = 40;
    const majorEvery = 5; // Major tick every 5th tick

    for (int i = 0; i <= totalTicks; i++) {
      final x = gaugeLeft + (gaugeWidth * i / totalTicks);
      final isCenter = i == totalTicks ~/ 2;
      final isMajor = i % majorEvery == 0;

      double tickHeight;
      double strokeWidth;
      Color color;

      if (isCenter) {
        tickHeight = 28;
        strokeWidth = 2.0;
        color = AppColors.textSecondary;
      } else if (isMajor) {
        tickHeight = 22;
        strokeWidth = 1.5;
        color = AppColors.textSecondary.withValues(alpha: 0.7);
      } else {
        tickHeight = 14;
        strokeWidth = 1.0;
        color = AppColors.textDim;
      }

      tickPaint
        ..color = color
        ..strokeWidth = strokeWidth;

      canvas.drawLine(
        Offset(x, centerY - tickHeight / 2),
        Offset(x, centerY + tickHeight / 2),
        tickPaint,
      );
    }
  }

  void _drawNeedle(Canvas canvas, double centerX, double gaugeWidth,
      double centerY, double height) {
    // Calculate needle X position from normalized position
    final needleX = centerX + (needlePosition * gaugeWidth / 2);
    final needleColor =
        isListening ? tuningColor : AppColors.needleDefault;

    const needleHeight = 48.0;

    // Glow effect behind needle
    if (isListening) {
      final glowPaint = Paint()
        ..color = needleColor.withValues(alpha: 0.15)
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(needleX, centerY - needleHeight / 2),
        Offset(needleX, centerY + needleHeight / 2),
        glowPaint,
      );
    }

    // Needle line
    final needlePaint = Paint()
      ..color = needleColor
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(needleX, centerY - needleHeight / 2),
      Offset(needleX, centerY + needleHeight / 2),
      needlePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _HorizontalGaugePainter oldDelegate) {
    return oldDelegate.needlePosition != needlePosition ||
        oldDelegate.isListening != isListening ||
        oldDelegate.isInTune != isInTune ||
        oldDelegate.tuningColor != tuningColor;
  }
}
