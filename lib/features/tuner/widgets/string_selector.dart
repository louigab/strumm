import 'package:flutter/material.dart';
import 'package:strumm/core/models/guitar_tuning.dart';
import 'package:strumm/core/theme/app_colors.dart';

/// Horizontal row of guitar string buttons for selection.
class StringSelector extends StatelessWidget {
  final GuitarTuning tuning;
  final int selectedIndex;
  final ValueChanged<int> onStringSelected;
  final Color activeColor;
  final Set<int> lockedIndices;

  const StringSelector({
    super.key,
    required this.tuning,
    required this.selectedIndex,
    required this.onStringSelected,
    required this.activeColor,
    this.lockedIndices = const {},
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // String number labels
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(tuning.strings.length, (index) {
              final stringNum = tuning.strings.length - index;
              return Padding(
                key: ValueKey('string-label-$index'),
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
              final note = tuning.strings[index];
              final isSelected = index == selectedIndex;
              final isLocked = lockedIndices.contains(index);

              return Padding(
                key: ValueKey('string-button-$index'),
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: GestureDetector(
                  onTap: () => onStringSelected(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isLocked
                          ? AppColors.inTune.withValues(alpha: 0.9)
                          : (isSelected
                              ? activeColor.withValues(alpha: 0.15)
                              : AppColors.surface),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isLocked ? AppColors.inTune : (isSelected
                            ? activeColor
                            : AppColors.surfaceLight),
                        width: isLocked || isSelected ? 2 : 1,
                      ),
                      boxShadow: (isSelected || isLocked)
                          ? [
                              BoxShadow(
                                color: (isLocked ? AppColors.inTune : activeColor)
                                    .withValues(alpha: 0.2),
                                blurRadius: 12,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        note.displayName,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: isSelected || isLocked
                            ? FontWeight.bold
                            : FontWeight.w500,
                          color: isLocked ? AppColors.surface : (isSelected
                            ? activeColor
                            : AppColors.textSecondary),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
