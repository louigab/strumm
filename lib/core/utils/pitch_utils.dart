import 'dart:math';

import 'package:strumm/core/models/note.dart';

/// Utility class for pitch/note detection and math.
class PitchUtils {
  PitchUtils._();

  /// All chromatic note names.
  static const List<String> noteNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F',
    'F#', 'G', 'G#', 'A', 'A#', 'B',
  ];

  /// Reference frequency for A4.
  static const double a4Frequency = 440.0;

  /// Converts a frequency to the nearest note.
  static Note frequencyToNote(double frequency) {
    if (frequency <= 0) {
      return const Note(name: '-', octave: 0, frequency: 0);
    }

    // Number of half steps from A4
    final halfSteps = 12 * log(frequency / a4Frequency) / ln2;
    final roundedHalfSteps = halfSteps.round();

    // A4 is note index 9 (A) in octave 4
    // MIDI note number for A4 is 69
    final midiNote = 69 + roundedHalfSteps;
    final noteIndex = midiNote % 12;
    final octave = (midiNote ~/ 12) - 1;

    final noteName = noteNames[noteIndex];
    final exactFrequency = a4Frequency * pow(2, roundedHalfSteps / 12);

    return Note(
      name: noteName,
      octave: octave,
      frequency: exactFrequency,
    );
  }

  /// Calculates the difference in cents between detected frequency and target.
  static double centsDifference(double detectedFreq, double targetFreq) {
    if (detectedFreq <= 0 || targetFreq <= 0) return 0;
    return 1200 * log(detectedFreq / targetFreq) / ln2;
  }

  /// Finds the closest string note from a tuning for a given frequency.
  static Note? findClosestString(double frequency, List<Note> tuningNotes) {
    if (frequency <= 0 || tuningNotes.isEmpty) return null;

    Note? closest;
    double minCentsDiff = double.infinity;

    for (final note in tuningNotes) {
      final cents = centsDifference(frequency, note.frequency).abs();
      if (cents < minCentsDiff) {
        minCentsDiff = cents;
        closest = note;
      }
    }

    return closest;
  }
}
