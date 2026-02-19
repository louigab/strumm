import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_audio_capture/flutter_audio_capture.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service that handles microphone audio capture and pitch detection.
class AudioService {
  FlutterAudioCapture? _audioCapture;
  PitchDetector? _pitchDetector;

  final StreamController<double> _pitchController =
      StreamController<double>.broadcast();

  bool _isListening = false;
  bool _isProcessing = false;
  // Smoothed recent confidence to ignore one-off transients
  double _confidenceAvg = 0.0;
  // Higher smoothing -> requires sustained confidence before accepting
  static const double _confidenceSmoothing = 0.85;
  // Raised gate to be stricter about emitting pitches
  static const double _confidenceThreshold = 0.75;
  int _frameCount = 0;
  static const int _sampleRate = 44100;
  static const int _bufferSize = 2048;
  static const int _frameSkip = 1; // Every frame — max detection rate for best sensitivity

  /// Stream of detected pitch frequencies.
  Stream<double> get pitchStream => _pitchController.stream;

  /// Whether the service is currently capturing audio.
  bool get isListening => _isListening;

  /// Request microphone permission. Returns true if granted.
  Future<bool> requestPermission() async {
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

  /// Clean audio data with noise gate and O(n) IIR low-pass filter.
  /// Returns empty list if signal is below threshold (to prevent ghost tuning).
  List<double> cleanAudioData(List<double> buffer) {
    if (buffer.isEmpty) return [];

    // 1. Calculate RMS for noise gate (single pass)
    double sumSquares = 0;
    for (final sample in buffer) {
      sumSquares += sample * sample;
    }
    final rms = sqrt(sumSquares / buffer.length);

    // Noise gate: return empty if signal is too weak
    // Raised slightly to ignore faint background noise while keeping
    // genuine string sustain audible.
    if (rms < 0.015) {
      return [];
    }

    // 2. Gentle low-pass to remove ultrasonic noise but preserve harmonics
    const double alpha = 0.7;
    final filtered = List<double>.filled(buffer.length, 0.0);
    filtered[0] = buffer[0];
    for (int i = 1; i < buffer.length; i++) {
      filtered[i] = alpha * buffer[i] + (1.0 - alpha) * filtered[i - 1];
    }

    // 3. Apply a lightweight band-pass (HP then LP) to focus on guitar range
    // Tightened to typical guitar range to reject rumble and high hiss.
    final bp = _applyBandpass(filtered, _sampleRate.toDouble(), 82.0, 880.0);

    // 4. Quick energy check on bandpassed signal
    double filteredSumSquares = 0;
    for (final sample in bp) {
      filteredSumSquares += sample * sample;
    }
    if (sqrt(filteredSumSquares / bp.length) < 0.012) {
      return [];
    }

    return bp;
  }

  // Simple first-order HP and LP cascade (not perfect, but cheap).
  List<double> _applyBandpass(List<double> input, double sampleRate, double hpCut, double lpCut) {
    final outHp = List<double>.filled(input.length, 0.0);
    // High-pass one-pole
    final rcHp = 1.0 / (2 * pi * hpCut);
    final dt = 1.0 / sampleRate;
    final alphaHp = rcHp / (rcHp + dt);
    double prevOut = 0.0;
    double prevIn = input[0];
    for (int i = 0; i < input.length; i++) {
      final x = input[i];
      final y = alphaHp * (prevOut + x - prevIn);
      outHp[i] = y;
      prevOut = y;
      prevIn = x;
    }

    final outLp = List<double>.filled(input.length, 0.0);
    // Low-pass one-pole
    final rcLp = 1.0 / (2 * pi * lpCut);
    final alphaLp = dt / (rcLp + dt);
    double s = outHp[0];
    for (int i = 0; i < outHp.length; i++) {
      s = s + alphaLp * (outHp[i] - s);
      outLp[i] = s;
    }

    return outLp;
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
      // Quick DSP confidence checks (autocorrelation, zero-crossing, sustain)
      double conf = _computePitchConfidence(cleanedBuffer, _sampleRate.toDouble());

      // Peakiness check: knocks are very peaky (high max/RMS). Penalize strongly.
      double peak = 0.0;
      for (final v in cleanedBuffer) {
        peak = max(peak, v.abs());
      }
      final rms = sqrt(cleanedBuffer.map((e) => e * e).reduce((a, b) => a + b) / cleanedBuffer.length + 1e-12);
      final peakiness = peak / (rms + 1e-12);
      if (peakiness > 22.0) {
        conf -= 0.5; // stronger penalty for impulse-like sounds
      }

      // Smooth confidence over recent buffers to avoid one-off detections
      _confidenceAvg = _confidenceSmoothing * _confidenceAvg + (1 - _confidenceSmoothing) * conf;
      if (_confidenceAvg < _confidenceThreshold) {
        _isProcessing = false;
        return;
      }

      final result = await _pitchDetector!.getPitchFromFloatBuffer(cleanedBuffer);
      if (result.pitched && _isListening) {
        _pitchController.add(result.pitch);
      }
    } catch (e) {
      debugPrint('Error detecting pitch: $e');
    } finally {
      _isProcessing = false;
    }
  }

  double _computePitchConfidence(List<double> buf, double sampleRate) {
    // Autocorrelation peak relative to energy
    final n = buf.length;
    double sum = 0.0;
    for (final v in buf) {
      sum += v * v;
    }
    final energy = sum / n + 1e-12;

    // Zero-crossing rate
    int zc = 0;
    for (int i = 1; i < n; i++) {
      if ((buf[i - 1] >= 0 && buf[i] < 0) || (buf[i - 1] < 0 && buf[i] >= 0)) {
        zc++;
      }
    }
    final zcr = zc / (n - 1);

    // Autocorrelation in guitar pitch range
    final minFreq = 80.0;
    final maxFreq = 1100.0;
    final maxLag = (sampleRate / minFreq).floor().clamp(1, n - 1);
    final minLag = (sampleRate / maxFreq).floor().clamp(1, n - 1);

    double bestCorr = 0.0;
    for (int lag = minLag; lag <= maxLag; lag++) {
      double c = 0.0;
      for (int i = 0; i < n - lag; i++) {
        c += buf[i] * buf[i + lag];
      }
      final norm = c / (energy * (n - lag));
      if (norm > bestCorr) {
        bestCorr = norm;
      }
    }

    final autocorrScore = bestCorr.clamp(0.0, 1.0);

    // Simple sustain check: RMS tail vs head
    final headLen = (n * 0.12).floor().clamp(1, n - 1);
    final tailStart = (n * 0.5).floor();
    double headSum = 0.0, tailSum = 0.0;
    for (int i = 0; i < headLen; i++) {
      headSum += buf[i] * buf[i];
    }
    for (int i = tailStart; i < n; i++) {
      tailSum += buf[i] * buf[i];
    }
    final headRms = sqrt(headSum / headLen + 1e-12);
    final tailRms = sqrt(tailSum / (n - tailStart) + 1e-12);
    final sustainRatio = (tailRms / (headRms + 1e-12)).clamp(0.0, 1.0);

    // If autocorrelation peak is very low, bail early (likely noise/impulse)
    if (autocorrScore < 0.5) return 0.0;

    // Confidence: give heavier weight to autocorrelation (harmonic periodicity)
    final conf = 0.75 * autocorrScore + 0.15 * (1 - zcr) + 0.10 * sustainRatio;
    return conf.clamp(0.0, 1.0);
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
  }
}
