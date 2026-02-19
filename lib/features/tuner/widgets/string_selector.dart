import 'package:flutter/material.dart';
import 'package:strumm/core/models/guitar_tuning.dart';
import 'package:strumm/core/models/note.dart';
import 'package:strumm/core/theme/app_colors.dart';

/// Horizontal row of guitar string buttons with water-fill in-tune animation.
class StringSelector extends StatelessWidget {
  final GuitarTuning tuning;
  final int selectedIndex;
  final ValueChanged<int> onStringSelected;
  final Color activeColor;
  final bool isInTuneFast;
  final bool isInTuneStable;
  final bool isListening;

  const StringSelector({
    super.key,
    required this.tuning,
    required this.selectedIndex,
    required this.onStringSelected,
    required this.activeColor,
    required this.isInTuneFast,
    required this.isInTuneStable,
    required this.isListening,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // String number labels
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(tuning.strings.length, (index) {
              final stringNum = tuning.strings.length - index;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: SizedBox(
                  width: 44,
                  child: Text(
                    '$stringNum',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: index == selectedIndex
                          ? AppColors.textSecondary
                          : AppColors.textDim,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 4),
          // String note buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(tuning.strings.length, (index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _StringButton(
                  key: ValueKey('string-btn-${tuning.name}-$index'),
                  note: tuning.strings[index],
                  isSelected: index == selectedIndex,
                  isInTuneFast: isInTuneFast,
                  isInTuneStable: isInTuneStable,
                  isListening: isListening,
                  activeColor: activeColor,
                  onTap: () => onStringSelected(index),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual animated string button
// ---------------------------------------------------------------------------

class _StringButton extends StatefulWidget {
  final Note note;
  final bool isSelected;
  final bool isInTuneFast;
  final bool isInTuneStable;
  final bool isListening;
  final Color activeColor;
  final VoidCallback onTap;

  const _StringButton({
    super.key,
    required this.note,
    required this.isSelected,
    required this.isInTuneFast,
    required this.isInTuneStable,
    required this.isListening,
    required this.activeColor,
    required this.onTap,
  });

  @override
  State<_StringButton> createState() => _StringButtonState();
}

class _StringButtonState extends State<_StringButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fill;
  bool _locked = false;

  // Time-based in-tune hold: pitch must stay in-tune for 1s before fill starts.
  // This is independent of frame rate so it's always reliable.
  final Stopwatch _inTuneTimer = Stopwatch();
  static const int _holdRequiredMs = 1000;

  static const double _buttonSize = 44;

  @override
  void initState() {
    super.initState();
    _fill = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fill.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted && !_locked) {
        setState(() => _locked = true);
      }
    });
  }

  @override
  void didUpdateWidget(_StringButton old) {
    super.didUpdateWidget(old);

    // Session ended — fully reset so next session starts clean
    if (!widget.isListening && old.isListening) {
      _locked = false;
      _inTuneTimer.reset();
      _inTuneTimer.stop();
      if (_fill.value > 0) {
        _fill.animateTo(
          0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
      return;
    }

    if (_locked) return;

    if (widget.isSelected && widget.isInTuneStable && widget.isListening) {
      // Start timer on first in-tune frame
      if (!_inTuneTimer.isRunning) _inTuneTimer..reset()..start();
      // Begin the fill once pitch has held in-tune for the required duration
      if (_inTuneTimer.elapsedMilliseconds >= _holdRequiredMs &&
          _fill.status != AnimationStatus.forward &&
          _fill.status != AnimationStatus.completed) {
        _fill.forward();
      }
    } else {
      // Reset timer when pitch drifts or string changes
      _inTuneTimer.reset();
      _inTuneTimer.stop();
      // Drain fill if it started
      if (_fill.value > 0) {
        _fill.animateTo(
          0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _fill,
        builder: (context, _) {
          final fillAmount = _locked ? 1.0 : _fill.value;
          final BorderSide border = BorderSide(
            color: _locked
                ? AppColors.inTune
                : widget.isSelected
                    ? widget.activeColor
                    : AppColors.surfaceLight,
            width: (_locked || widget.isSelected) ? 2 : 1,
          );

          return Container(
            width: _buttonSize,
            height: _buttonSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.fromBorderSide(border),
              boxShadow: (_locked || widget.isSelected)
                  ? [
                      BoxShadow(
                        color: border.color.withValues(alpha: 0.28),
                        blurRadius: 14,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: [
                  // Dark base
                  Container(
                    color: widget.isSelected && !_locked
                        ? widget.activeColor.withValues(alpha: 0.08)
                        : AppColors.surface,
                  ),
                  // Water fill rising from the bottom
                  if (fillAmount > 0)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: _buttonSize * fillAmount,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              AppColors.inTune.withValues(
                                  alpha: _locked ? 1.0 : 0.85),
                              AppColors.inTune.withValues(
                                  alpha: _locked ? 0.9 : 0.55),
                            ],
                          ),
                        ),
                      ),
                    ),
                  // Note label always on top
                  Center(
                    child: Text(
                      widget.note.displayName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight:
                            (widget.isSelected || _locked)
                                ? FontWeight.bold
                                : FontWeight.w500,
                        color: _locked
                            ? AppColors.textPrimary
                            : widget.isSelected
                                ? widget.activeColor
                                : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
