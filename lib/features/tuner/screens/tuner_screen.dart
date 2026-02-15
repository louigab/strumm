import 'dart:async';
import 'package:flutter/material.dart';
import 'package:strumm/core/models/guitar_tuning.dart';
import 'package:strumm/core/services/audio_service.dart';
import 'package:strumm/core/theme/app_colors.dart';
import 'package:strumm/core/utils/pitch_utils.dart';
import 'package:strumm/features/tuner/widgets/tuning_gauge.dart';
import 'package:strumm/features/tuner/widgets/string_selector.dart';
import 'package:strumm/features/tuner/widgets/note_display.dart';
import 'package:strumm/features/tuner/widgets/tuning_picker.dart';

class TunerScreen extends StatefulWidget {
  const TunerScreen({super.key});

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen>
    with SingleTickerProviderStateMixin {
  final AudioService _audioService = AudioService();
  StreamSubscription? _noteSubscription;

  GuitarTuning _currentTuning = GuitarTuning.standard;
  int _selectedStringIndex = 0;
  double _currentFrequency = 0;
  double _centsDiff = 0;
  String _detectedNoteName = '-';
  ListenMode _listenMode = ListenMode.automatic;
  bool _isListening = false;
  bool _hasError = false;
  String _errorMessage = '';
  // Tracks which string indexes have been "locked" (confirmed tuned)
  final Set<int> _lockedStrings = {};

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    // Start listening automatically when the screen mounts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startListeningAutomatically();
    });
  }

  Future<void> _startListeningAutomatically() async {
    try {
      await _audioService.init();
      await _audioService.startListening();

      // Subscribe to noteStream (provides name, frequency, cents)
      _noteSubscription = _audioService.noteStream.listen(
        (note) {
          if (!mounted) return;

          try {
            final frequency = (note as dynamic).frequency as double;
            final closestNote = PitchUtils.findClosestString(
              frequency,
              _currentTuning.strings,
            );

            final targetFreq = closestNote?.frequency ??
                _currentTuning.strings[_selectedStringIndex].frequency;

            final cents = PitchUtils.centsDifference(frequency, targetFreq);

            setState(() {
              _currentFrequency = frequency;
              _centsDiff = cents.clamp(-50.0, 50.0);

              if (_listenMode == ListenMode.automatic && closestNote != null) {
                final idx = _currentTuning.strings.indexOf(closestNote);
                if (idx != -1) _selectedStringIndex = idx;
              }

              _detectedNoteName = (note as dynamic).name as String? ?? '-';
            });
          } catch (e) {
            debugPrint('Error processing note: $e');
          }
        },
        onError: (error) {
          debugPrint('Note stream error: $error');
          if (mounted) {
            setState(() {
              _hasError = true;
              _errorMessage = 'Audio processing error';
            });
          }
        },
        cancelOnError: false,
      );

      setState(() {
        _isListening = true;
        _hasError = false;
        _errorMessage = '';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _noteSubscription?.cancel();
    _audioService.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _audioService.stopListening();
      _noteSubscription?.cancel();
      setState(() {
        _isListening = false;
        _currentFrequency = 0;
        _centsDiff = 0;
        _detectedNoteName = '-';
      });
    } else {
      try {
        await _audioService.init();
        await _audioService.startListening();
        // Subscribe to noteStream (provides name, frequency, cents)
        _noteSubscription = _audioService.noteStream.listen(
          (note) {
            if (!mounted) return;

            try {
              final frequency = (note as dynamic).frequency as double;
              final closestNote = PitchUtils.findClosestString(
                frequency,
                _currentTuning.strings,
              );

              final targetFreq = closestNote?.frequency ??
                  _currentTuning.strings[_selectedStringIndex].frequency;

              final cents = PitchUtils.centsDifference(frequency, targetFreq);

              setState(() {
                _currentFrequency = frequency;
                _centsDiff = cents.clamp(-50.0, 50.0);

                // Auto-select the closest string when in automatic mode
                if (_listenMode == ListenMode.automatic && closestNote != null) {
                  final idx = _currentTuning.strings.indexOf(closestNote);
                  if (idx != -1) _selectedStringIndex = idx;
                }

                _detectedNoteName = (note as dynamic).name as String? ?? '-';
              });
            } catch (e) {
              debugPrint('Error processing note: $e');
            }
          },
          onError: (error) {
            debugPrint('Note stream error: $error');
            if (mounted) {
              setState(() {
                _hasError = true;
                _errorMessage = 'Audio processing error';
              });
            }
          },
          cancelOnError: false,
        );

        setState(() {
          _isListening = true;
          _hasError = false;
          _errorMessage = '';
        });
      } catch (e) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _selectString(int index) {
    setState(() {
      _selectedStringIndex = index;
    });
    // If in manual mode, set the manual target to this string's note name.
    if (_listenMode == ListenMode.manual) {
      final noteName = _currentTuning.strings[index].displayName;
      _audioService.setManualTargetByName(noteName);
    }
  }

  void _selectTuning(GuitarTuning tuning) {
    setState(() {
      _currentTuning = tuning;
      _selectedStringIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tuningColor = _isListening && _currentFrequency > 0
        ? AppColors.getTuningColor(_centsDiff)
        : AppColors.textDim;
    final isInTune = _centsDiff.abs() <= 5 && _currentFrequency > 0;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.background,
              Color(0xFF0D1130),
              AppColors.background,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // App bar
              _buildAppBar(),

              const Spacer(flex: 1),

              // Note display (detected note + status)
              NoteDisplay(
                noteName: _isListening ? _detectedNoteName : '-',
                frequency: _currentFrequency,
                centsDiff: _centsDiff,
                isListening: _isListening,
                tuningColor: tuningColor,
                stringIndex: _selectedStringIndex,
                onLocked: (index) {
                  setState(() {
                    _lockedStrings.add(index);
                  });
                },
                matchesSelected: _detectedNoteName != '-' &&
                    _detectedNoteName ==
                        _currentTuning.strings[_selectedStringIndex]
                            .displayName,
              ),

              const SizedBox(height: 32),

              // Horizontal tuning gauge
              TuningGauge(
                centsDiff: _centsDiff,
                isListening: _isListening,
                isInTune: isInTune,
                tuningColor: tuningColor,
              ),

              const SizedBox(height: 12),

              // Frequency readout
              _buildFrequencyLabel(),

              const Spacer(flex: 1),

              // String selector
              StringSelector(
                tuning: _currentTuning,
                selectedIndex: _selectedStringIndex,
                onStringSelected: _selectString,
                activeColor: tuningColor,
                lockedIndices: _lockedStrings,
              ),

              const SizedBox(height: 24),

              // Auto/Manual toggle (replaces mic button)
              Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: ToggleButtons(
                    isSelected: [
                      _listenMode == ListenMode.automatic,
                      _listenMode == ListenMode.manual,
                    ],
                    onPressed: (index) {
                      setState(() {
                        _listenMode = index == 0 ? ListenMode.automatic : ListenMode.manual;
                        _audioService.setMode(_listenMode);
                        if (_listenMode == ListenMode.manual) {
                          final noteName = _currentTuning.strings[_selectedStringIndex].displayName;
                          _audioService.setManualTargetByName(noteName);
                        } else {
                          _audioService.clearManualTarget();
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    children: const [
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Text('Auto'),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Text('Manual'),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Error message
              if (_hasError)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    _errorMessage,
                    style: const TextStyle(
                      color: AppColors.flat,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'strumm',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
              letterSpacing: 1.5,
            ),
          ),
          TuningPicker(
            currentTuning: _currentTuning,
            onTuningSelected: _selectTuning,
          ),
        ],
      ),
    );
  }

  Widget _buildFrequencyLabel() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      child: Text(
        _isListening && _currentFrequency > 0
            ? '${_currentFrequency.toStringAsFixed(0)} Hz'
            : '-- Hz',
        key: ValueKey(
            _isListening ? _currentFrequency.toStringAsFixed(0) : 'idle'),
        style: const TextStyle(
          fontSize: 14,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w400,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildListenButton(bool isInTune) {
    return GestureDetector(
      onTap: _toggleListening,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final scale =
              _isListening ? 1.0 + (_pulseController.value * 0.05) : 1.0;
          return Transform.scale(
            scale: scale,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: _isListening
                      ? [AppColors.flat, AppColors.flat.withValues(alpha: 0.7)]
                      : [AppColors.primary, AppColors.accent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (_isListening ? AppColors.flat : AppColors.primary)
                        .withValues(alpha: 0.4),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                color: AppColors.textPrimary,
                size: 32,
              ),
            ),
          );
        },
      ),
    );
  }
}
