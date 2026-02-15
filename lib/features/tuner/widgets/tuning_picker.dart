import 'package:flutter/material.dart';
import 'package:strumm/core/models/guitar_tuning.dart';
import 'package:strumm/core/theme/app_colors.dart';

/// A dropdown-style button to pick the current tuning.
class TuningPicker extends StatelessWidget {
  final GuitarTuning currentTuning;
  final ValueChanged<GuitarTuning> onTuningSelected;

  const TuningPicker({
    super.key,
    required this.currentTuning,
    required this.onTuningSelected,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showTuningSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.surfaceLight,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              currentTuning.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppColors.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _showTuningSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _TuningSheet(
        currentTuning: currentTuning,
        onTuningSelected: (tuning) {
          onTuningSelected(tuning);
          Navigator.pop(context);
        },
      ),
    );
  }
}

class _TuningSheet extends StatelessWidget {
  final GuitarTuning currentTuning;
  final ValueChanged<GuitarTuning> onTuningSelected;

  const _TuningSheet({
    required this.currentTuning,
    required this.onTuningSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textDim,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Select Tuning',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: GuitarTuning.allTunings.map((tuning) {
                  final isSelected = tuning.name == currentTuning.name;
                  return ListTile(
                    key: ValueKey(tuning.name),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                    onTap: () => onTuningSelected(tuning),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(10),
                        border: isSelected
                            ? Border.all(color: AppColors.primary, width: 1.5)
                            : null,
                      ),
                      child: Icon(
                        Icons.music_note_rounded,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      tuning.name,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      tuning.description,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.primary,
                            size: 22,
                          )
                        : null,
                  );
                }).toList(),
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}
