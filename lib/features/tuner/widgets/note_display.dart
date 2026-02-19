import 'package:flutter/material.dart';
import 'package:strumm/core/theme/app_colors.dart';

/// Displays the currently detected note name and frequency.
class NoteDisplay extends StatelessWidget {
  final String noteName;
  final double frequency;
  final bool isListening;
  final Color tuningColor;

  const NoteDisplay({
    super.key,
    required this.noteName,
    required this.frequency,
    required this.isListening,
    required this.tuningColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Note name
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            noteName,
            key: ValueKey('note:$noteName'),
            style: TextStyle(
              fontSize: 80,
              fontWeight: FontWeight.w700,
              color: isListening && frequency > 0
                  ? tuningColor
                  : AppColors.textDim,
              letterSpacing: 2,
              height: 1,
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Frequency
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: Text(
            isListening && frequency > 0
                ? '${frequency.toStringAsFixed(1)} Hz'
                : '-- Hz',
            key: ValueKey(isListening ? 'freq:${frequency.toStringAsFixed(1)}' : 'freq:idle'),
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w400,
              letterSpacing: 1,
            ),
          ),
        ),
      ],
    );
  }
}
