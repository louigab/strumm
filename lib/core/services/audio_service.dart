import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_audio_capture/flutter_audio_capture.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service that handles microphone audio capture and pitch detection.
/// Mode for listening behavior: automatic detects which note is being played,
/// manual listens only for a single forced target note set by the UI.
enum ListenMode { automatic, manual }

/// Simple container representing a detected note and tuning offset.
class DetectedNote {
  final String name;
  final double frequency;
  final double cents; // positive = sharp, negative = flat

  DetectedNote({required this.name, required this.frequency, required this.cents});
}

class AudioService {
  FlutterAudioCapture? _audioCapture;
  PitchDetector? _pitchDetector;

  final StreamController<double> _pitchController =
      StreamController<double>.broadcast();
  final StreamController<DetectedNote> _noteController =
      StreamController<DetectedNote>.broadcast();

  bool _isListening = false;
  bool _isProcessing = false;
  int _frameCount = 0;
  static const int _sampleRate = 44100;
  static const int _bufferSize = 2048;
  static const int _frameSkip = 2; // Process every 2nd frame to reduce load

  // Listening mode (automatic by default)
  ListenMode _mode = ListenMode.automatic;

  // Manual target MIDI note (0-127). If null, manual mode won't emit.
  int? _manualTargetMidi;

  // Threshold in cents for manual accepting a detection (default 50 cents)
  double _manualThresholdCents = 50.0;

  /// Stream of detected pitch frequencies.
  Stream<double> get pitchStream => _pitchController.stream;
  /// Stream of detected notes (name + cents offset).
  Stream<DetectedNote> get noteStream => _noteController.stream;

  /// Whether the service is currently capturing audio.
  bool get isListening => _isListening;

  /// Request microphone permission. Returns true if granted.
  Future<bool> requestPermission() async {
    if (kIsWeb) return true; // Web handles permissions through browser API
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Initialize the audio capture and pitch detector.
  Future<void> init() async {
    _audioCapture = FlutterAudioCapture();
    await _audioCapture!.init();
    _pitchDetector = PitchDetector(
      audioSampleRate: _sampleRate.toDouble(),
      bufferSize: _bufferSize,
    );
  }

  /// Start listening to microphone input and detecting pitch.
  Future<void> startListening() async {
    if (_isListening) return;

    final hasPermission = await requestPermission();
    if (!hasPermission) {
      throw Exception('Microphone permission denied');
    }

    if (_audioCapture == null || _pitchDetector == null) {
      await init();
    }

    _isListening = true;

    await _audioCapture!.start(
      (Float32List buffer) {
        // Skip frames to reduce processing load
        _frameCount++;
        if (_frameCount % _frameSkip != 0) return;
        
        // Skip if already processing previous buffer
        if (_isProcessing) return;
        
        _isProcessing = true;
        
        // Copy buffer data to avoid reference issues
        try {
          final bufferCopy = List<double>.from(
            buffer.map((e) => e.toDouble()),
            growable: false,
          );
          
          // Process pitch detection asynchronously without blocking
          _detectPitch(bufferCopy);
        } catch (e) {
          _isProcessing = false;
          debugPrint('Buffer copy error: $e');
        }
      },
      (Object error) {
        debugPrint('Audio capture error: $error');
      },
      sampleRate: _sampleRate,
      bufferSize: _bufferSize,
    );
  }

  /// Clean audio data with noise gate and low-pass filter.
  /// Returns empty list if signal is below threshold (to prevent ghost tuning).
  List<double> cleanAudioData(List<double> buffer) {
    if (buffer.isEmpty) return [];

    // 1. Calculate RMS (Root Mean Square) for noise gate
    double sumSquares = 0;
    for (final sample in buffer) {
      sumSquares += sample * sample;
    }
    final rms = sqrt(sumSquares / buffer.length);

    // Noise gate: return empty if signal is too weak (0.05 threshold)
    if (rms < 0.05) {
      return [];
    }

    // 2. Apply simple Low-Pass Filter (cut frequencies above 1200Hz)
    // Using a basic moving average filter as a low-pass approximation
    // Cutoff calculation: for 44100Hz sample rate, 1200Hz cutoff
    final cutoffFreq = 1200.0;
    final windowSize = (_sampleRate / cutoffFreq / 2).round().clamp(2, 10);
    
    final filtered = <double>[];
    for (int i = 0; i < buffer.length; i++) {
      double sum = 0;
      int count = 0;
      
      // Moving average window
      for (int j = max(0, i - windowSize); j <= min(buffer.length - 1, i + windowSize); j++) {
        sum += buffer[j];
        count++;
      }
      
      filtered.add(sum / count);
    }

    // 3. Verify cleaned signal still has sufficient energy
    double filteredSumSquares = 0;
    for (final sample in filtered) {
      filteredSumSquares += sample * sample;
    }
    final filteredRms = sqrt(filteredSumSquares / filtered.length);

    // Return empty if filtered signal is too weak (prevents ghost tuning)
    if (filteredRms < 0.03) {
      return [];
    }

    return filtered;
  }

  /// Detect pitch from audio buffer (fire-and-forget).
  void _detectPitch(List<double> buffer) {
    // Use unawaited to fire and forget the async operation
    _detectPitchAsync(buffer);
  }

  /// Async pitch detection helper.
  Future<void> _detectPitchAsync(List<double> buffer) async {
    try {
      // Clean audio data before pitch detection
      final cleanedBuffer = cleanAudioData(buffer);
      
      // Skip if buffer is empty (signal too weak or noisy)
      if (cleanedBuffer.isEmpty) {
        _isProcessing = false;
        return;
      }
      
      final result = await _pitchDetector!.getPitchFromFloatBuffer(cleanedBuffer);
      if (result.pitched && _isListening) {
        final freq = result.pitch;

        if (_mode == ListenMode.manual) {
          // Only emit if a manual target is set and within threshold
          if (_manualTargetMidi != null) {
            final targetFreq = _midiToFreq(_manualTargetMidi!);
            final cents = _freqToCentsRelative(freq, targetFreq);
            if (cents.abs() <= _manualThresholdCents) {
              _pitchController.add(freq);
              _noteController.add(DetectedNote(
                name: _midiToNoteName(_manualTargetMidi!),
                frequency: freq,
                cents: cents,
              ));
            }
          }
        } else {
          // Automatic mode: always emit pitch and best-approx note
          _pitchController.add(freq);
          final midi = _freqToMidiNearest(freq);
          final noteName = _midiToNoteName(midi);
          final targetFreq = _midiToFreq(midi);
          final cents = _freqToCentsRelative(freq, targetFreq);
          _noteController.add(DetectedNote(name: noteName, frequency: freq, cents: cents));
        }
      }
    } catch (e) {
      debugPrint('Error detecting pitch: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Set listening mode.
  void setMode(ListenMode mode) {
    _mode = mode;
  }

  /// Set manual target by note name, e.g. "A4", "E2".
  void setManualTargetByName(String noteName) {
    final midi = _noteNameToMidi(noteName);
    if (midi != null) _manualTargetMidi = midi;
  }

  /// Clear manual target.
  void clearManualTarget() {
    _manualTargetMidi = null;
  }

  /// Set manual threshold in cents.
  void setManualThresholdCents(double cents) {
    _manualThresholdCents = cents;
  }

  double _midiToFreq(int midi) => 440.0 * pow(2, (midi - 69) / 12);

  int _freqToMidiNearest(double freq) => (69 + 12 * (log(freq / 440.0) / ln2)).round();

  double _freqToCentsRelative(double freq, double targetFreq) =>
      1200 * (log(freq / targetFreq) / ln2);

  String _midiToNoteName(int midi) {
    const names = [
      'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
    ];
    final octave = (midi ~/ 12) - 1;
    final name = names[midi % 12];
    return '$name$octave';
  }

  int? _noteNameToMidi(String name) {
    final regex = RegExp(r'^([A-Ga-g])(#?)(-?\d+)$');
    final m = regex.firstMatch(name.replaceAll(' ', ''));
    if (m == null) return null;
    final letter = m.group(1)!.toUpperCase();
    final sharp = m.group(2) == '#';
    final octave = int.tryParse(m.group(3)!);
    if (octave == null) return null;
    final base = {
      'C': 0,
      'D': 2,
      'E': 4,
      'F': 5,
      'G': 7,
      'A': 9,
      'B': 11,
    }[letter]!;
    var semitone = base + (sharp ? 1 : 0);
    final midi = (octave + 1) * 12 + semitone;
    if (midi < 0 || midi > 127) return null;
    return midi;
  }

  /// Stop listening.
  Future<void> stopListening() async {
    if (!_isListening) return;
    _isListening = false;
    _isProcessing = false;
    _frameCount = 0;

    try {
      await _audioCapture?.stop();
    } catch (e) {
      debugPrint('Error stopping audio capture: $e');
    }
  }

  /// Dispose of resources.
  void dispose() {
    stopListening();
    _pitchController.close();
    _noteController.close();
  }
}
