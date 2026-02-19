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

class _TunerScreenState extends State<TunerScreen> {
  final AudioService _audioService = AudioService();
  StreamSubscription<double>? _pitchSubscription;

  GuitarTuning _currentTuning = GuitarTuning.standard;
  int _selectedStringIndex = 0;
  double _currentFrequency = 0;
  double _centsDiff = 0;
  String _detectedNoteName = '-';
  bool _isListening = false;
  bool _hasError = false;
  bool _isManualMode = false; // false = Auto, true = Manual
  DateTime? _lastPitchAt;
  final ValueNotifier<DateTime?> _lastPitchNotifier = ValueNotifier<DateTime?>(null);

  // ── Smoothing ────────────────────────────────────────────────────────────
  // Light frequency EMA — only for auto string detection, NOT for display.
  static const double _freqAlpha = 0.5;
  double _smoothedFrequency = 0;

  // Adaptive display EMA: fast when far from target, stable when close.
  static const double _displayAlphaFar = 0.55;
  static const double _displayAlphaClose = 0.12;
  double _displayCents = 0;

  // Very slow EMA for lock/countdown — resists jitter.
  static const double _stableAlpha = 0.10;
  double _stableCents = 0;

  // UI at 60 fps for butter-smooth seismograph rendering.
  final Stopwatch _uiThrottle = Stopwatch()..start();
  static const int _uiThrottleMs = 16;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    // Start listening automatically when screen appears
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _toggleListening();
    });
  }

  @override
  void dispose() {
    _pitchSubscription?.cancel();
    _audioService.dispose();
    _lastPitchNotifier.dispose();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _audioService.stopListening();
      _pitchSubscription?.cancel();
      setState(() {
        _isListening = false;
        _currentFrequency = 0;
        _centsDiff = 0;
        _detectedNoteName = '-';
        _smoothedFrequency = 0;
        _displayCents = 0;
        _stableCents = 0;
        _uiThrottle.reset();
        _lastPitchAt = null;
        _lastPitchNotifier.value = null;
      });
    } else {
      try {
        await _audioService.init();
        await _audioService.startListening();

        _pitchSubscription = _audioService.pitchStream.listen(
          (frequency) {
            if (!mounted) return;

            // mark timestamp of last received pitch so UI can detect
            // whether a recent pitch exists (used to cut the seismograph)
            _lastPitchAt = DateTime.now();
            _lastPitchNotifier.value = _lastPitchAt;

            try {
              // ── Light frequency EMA (string detection only) ──────────────
              if (_smoothedFrequency > 0 &&
                  (frequency - _smoothedFrequency).abs() /
                          _smoothedFrequency >
                      0.25) {
                // Large jump → new string plucked — snap smoothing
                _smoothedFrequency = frequency;
                _displayCents = 0;
                _stableCents = 0;
                // On a big jump, do a fresh closest-string lookup so the
                // sticky logic doesn't keep us on the old string.
                final freshClosest = PitchUtils.findClosestString(
                    frequency, _currentTuning.strings);
                if (freshClosest != null) {
                  final idx = _currentTuning.strings.indexOf(freshClosest);
                  if (idx != -1) _selectedStringIndex = idx;
                }
              } else {
                _smoothedFrequency = _smoothedFrequency == 0
                    ? frequency
                    : (_freqAlpha * frequency +
                        (1 - _freqAlpha) * _smoothedFrequency);
              }

              // ── Target selection ───────────────────────────────────────
              // Use sticky detection: the current string is preferred unless
              // the frequency is clearly closer to a different string. This
              // prevents the tuner from jumping (e.g. showing D when tuning
              // a very flat low E). Also handles pitch-detector harmonics.
              final currentNote = _currentTuning.strings[_selectedStringIndex];
              final closestNote = _isManualMode
                  ? currentNote
                  : PitchUtils.findClosestStringSticky(
                      _smoothedFrequency,
                      _currentTuning.strings,
                      currentNote: currentNote,
                    );

              final targetFreq = closestNote?.frequency ??
                  _currentTuning.strings[_selectedStringIndex].frequency;

              // ── Raw cents from RAW frequency (no double-smoothing!) ────
              final rawCents =
                  PitchUtils.centsDifference(frequency, targetFreq);

              // ── Adaptive display EMA ───────────────────────────────────
              // Fast when far from centre → snappy pluck response.
              // Slow when close → rock-stable near zero, minimal jitter.
              final absRaw = rawCents.abs();
              final t = ((absRaw - 3) / 20).clamp(0.0, 1.0);
              final alpha =
                  _displayAlphaClose + t * (_displayAlphaFar - _displayAlphaClose);
              _displayCents =
                  alpha * rawCents + (1 - alpha) * _displayCents;

              // ── Slow stable EMA for lock/countdown ─────────────────────
              _stableCents =
                  _stableAlpha * rawCents + (1 - _stableAlpha) * _stableCents;

              // ── Throttled setState (60 fps) ───────────────────────────
              if (_uiThrottle.elapsedMilliseconds < _uiThrottleMs) return;
              _uiThrottle.reset();

              setState(() {
                _currentFrequency = _smoothedFrequency;
                _centsDiff = _displayCents.clamp(-50.0, 50.0);
                _detectedNoteName = closestNote?.displayName ??
                    _currentTuning.strings[_selectedStringIndex].displayName;

                // Auto mode: snap selection to closest string
                if (!_isManualMode && closestNote != null) {
                  final idx = _currentTuning.strings.indexOf(closestNote);
                  if (idx != -1) _selectedStringIndex = idx;
                }
              });
            } catch (e) {
              debugPrint('Error processing pitch: $e');
            }
          },
          onError: (error) {
            debugPrint('Pitch stream error: $error');
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
          _lastPitchAt = null;
          _lastPitchNotifier.value = null;
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
  }

  void _selectTuning(GuitarTuning tuning) {
    setState(() {
      _currentTuning = tuning;
      _selectedStringIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasRecentPitch = _isListening && _lastPitchAt != null &&
        DateTime.now().difference(_lastPitchAt!).inMilliseconds < 250;

    final tuningColor = hasRecentPitch
      ? AppColors.getTuningColor(_centsDiff)
      : AppColors.textDim;
    // Fast in-tune used for needle color/motion (responsive)
    final isInTuneFast = _displayCents.abs() <= 3 && hasRecentPitch;
    // Stable in-tune used for countdown/locking (accurate)
    final isInTuneStable = _stableCents.abs() <= 3 && hasRecentPitch;

    return Scaffold(
      resizeToAvoidBottomInset: false,
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  children: [
              // App bar
              _buildAppBar(), // Fixed height ~50

              // Flexible space instead of Spacer (safer in some contexts)
              const Expanded(child: SizedBox()),

              // Note display (detected note + frequency)
              NoteDisplay(
                noteName: _isListening ? _detectedNoteName : '-',
                frequency: _currentFrequency,
                isListening: _isListening,
                tuningColor: tuningColor,
              ),

              const SizedBox(height: 32),

              // Tuning gauge / needle - explicit constraint here to be safe
              SizedBox(
                height: 140, // Ensure constraint is passed down
                child: RepaintBoundary(
                  child: TuningGauge(
                    centsDiff: _centsDiff,
                    isListening: _isListening,
                    isInTune: isInTuneFast,
                    hasPitch: hasRecentPitch,
                    lastPitchNotifier: _lastPitchNotifier,
                    tuningColor: tuningColor,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Cents indicator
              _buildCentsIndicator(tuningColor),

              const Expanded(child: SizedBox()),

              // String selector
              StringSelector(
                tuning: _currentTuning,
                selectedIndex: _selectedStringIndex,
                onStringSelected: _selectString,
                activeColor: tuningColor,
                isInTuneFast: isInTuneFast,
                isInTuneStable: isInTuneStable,
                isListening: _isListening,
              ),

              const SizedBox(height: 24),

              // Mode toggle: Auto / Manual (manual = user selects string)
              _buildModeToggle(),

              const SizedBox(height: 16),

              // Error message (fixed height container to avoid layout shift)
              SizedBox(
                height: 20,
                child: _hasError
                    ? Center(
                        child: Text(
                          _errorMessage,
                          style: const TextStyle(
                            color: AppColors.flat,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : null,
              ),

              const SizedBox(height: 24),
                  ],
                ),
              );
            },
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

  Widget _buildCentsIndicator(Color color) {
    if (!_isListening || _currentFrequency <= 0) {
      return const SizedBox(
        height: 28,
        child: Text(
          'Listening...',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
      );
    }

    final centsInt = _centsDiff.round();
    String display;
    if (centsInt == 0) {
      display = '0';
    } else if (centsInt > 0) {
      display = '+$centsInt';
    } else {
      display = '$centsInt';
    }

    return SizedBox(
      height: 28,
      child: Text(
        display,
        style: TextStyle(
          color: color,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildModeToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ToggleButtons(
            isSelected: [_isManualMode == false, _isManualMode == true],
            onPressed: (index) {
              setState(() {
                _isManualMode = index == 1;
              });
            },
            borderRadius: BorderRadius.circular(8),
            selectedBorderColor: AppColors.surfaceLight,
            fillColor: AppColors.surfaceLight.withValues(alpha: 0.06),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                child: const Text('Auto', style: TextStyle(color: AppColors.textPrimary)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                child: const Text('Manual', style: TextStyle(color: AppColors.textPrimary)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildListenButton(bool isInTune) {
    // Removed: replaced by Auto/Manual toggle.
    // Previously returned a widget; left intentionally removed to avoid
    // unused private declaration warnings.
    return const SizedBox.shrink();
  }
}
