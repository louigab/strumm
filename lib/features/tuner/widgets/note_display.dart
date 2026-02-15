import 'package:flutter/material.dart';
import 'package:strumm/core/theme/app_colors.dart';

/// Displays the currently detected note name, tuning status, and a 1s
/// bottom-to-top fill animation when the note stays in tune.
class NoteDisplay extends StatefulWidget {
  final String noteName;
  final double frequency;
  final double centsDiff;
  final bool isListening;
  final Color tuningColor;
  final int stringIndex;
  /// Called when this note becomes locked; provides the index of the locked string.
  final ValueChanged<int>? onLocked;
  /// Whether the currently-detected note matches the selected string.
  final bool matchesSelected;

  const NoteDisplay({
    super.key,
    required this.noteName,
    required this.frequency,
    required this.centsDiff,
    required this.isListening,
    required this.tuningColor,
    required this.stringIndex,
    this.onLocked,
    required this.matchesSelected,
  });

  @override
  State<NoteDisplay> createState() => _NoteDisplayState();
}

class _NoteDisplayState extends State<NoteDisplay>
    with SingleTickerProviderStateMixin {
  late AnimationController _fillController;
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    _fillController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          // Once completed, lock and notify parent with the string index.
          setState(() {
            _locked = true;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onLocked?.call(widget.stringIndex);
          });
        }
      });
  }

  @override
  void didUpdateWidget(covariant NoteDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasInTune = oldWidget.isListening && oldWidget.centsDiff.abs() <= 5 && oldWidget.matchesSelected;
    final isInTune = widget.isListening && widget.centsDiff.abs() <= 5 && widget.matchesSelected;

    // If the selected string changed, reset internal locked state so this
    // NoteDisplay can lock independently for the new string.
    if (oldWidget.stringIndex != widget.stringIndex) {
      if (_locked) {
        setState(() {
          _locked = false;
        });
      }
      _fillController.value = 0;
    }

    if (isInTune && !wasInTune && !_locked) {
      // started being in tune — play forward (only if not already locked)
      _fillController.forward(from: 0);
    } else if (!isInTune && wasInTune && !_locked) {
      // left in-tune — reverse/reset (only if not locked)
      _fillController.reverse();
    } else if (!isInTune && !_locked) {
      // ensure reset when not active (only if not locked)
      _fillController.value = 0;
    }
  }

  @override
  void dispose() {
    _fillController.dispose();
    super.dispose();
  }

  String _getStatusText() {
    if (!widget.isListening || widget.frequency <= 0) return '';
    final absCents = widget.centsDiff.abs();
    if (absCents <= 5) return 'Perfect';
    if (widget.centsDiff > 0) return 'Sharp';
    return 'Flat';
  }

  @override
  Widget build(BuildContext context) {
    final showActive = widget.isListening && widget.frequency > 0;
    final statusText = showActive ? _getStatusText() : '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Note box with animated bottom-to-top fill
        SizedBox(
          width: 160,
          height: 120,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outline/background
              Container(
                width: 160,
                height: 120,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.gaugeTrack),
                ),
              ),

              // Fill overlay animated from bottom to top
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _fillController,
                  builder: (context, child) {
                    final fill = _fillController.value;
                    final fillHeight = 120 * fill;
                    return Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: 160,
                        height: fillHeight,
                        decoration: BoxDecoration(
                          color: (_locked || fill >= 1.0)
                              ? widget.tuningColor
                              : widget.tuningColor.withOpacity(0.15),
                          borderRadius: BorderRadius.vertical(
                              bottom: Radius.circular(12), top: Radius.circular(fill >= 1.0 ? 12 : 0)),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Note text and status
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      widget.noteName,
                      key: ValueKey(widget.noteName),
                      style: TextStyle(
                        fontSize: 64,
                        fontWeight: FontWeight.w700,
                        color: (_locked || (_fillController.value >= 1.0))
                            ? AppColors.surface
                            : (showActive ? widget.tuningColor : AppColors.textDim),
                        letterSpacing: 2,
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 20,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: Text(
                        statusText,
                        key: ValueKey(statusText + (_locked ? 'locked' : '')),
                        style: TextStyle(
                          fontSize: 14,
                          color: (_locked || (_fillController.value >= 1.0))
                              ? AppColors.surface
                              : (showActive ? widget.tuningColor : AppColors.textSecondary),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // Small countdown number shown while filling
              if (_fillController.isAnimating || (_fillController.value > 0 && !_locked))
                Positioned(
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${(1.0 - _fillController.value).clamp(0.0, 1.0).toStringAsFixed(1)}s',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Small frequency label is handled in the screen below the gauge
      ],
    );
  }
}
