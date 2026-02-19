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

  /// Sticky string detection with hysteresis.
  ///
  /// When [currentNote] is provided (the currently selected string), this
  /// method checks whether the detected [frequency] is close enough to the
  /// current note's fundamental or one of its harmonics. If it is, the
  /// current note is kept — preventing the tuner from jumping to the wrong
  /// string when a note is very flat/sharp or the pitch detector locks onto
  /// a harmonic.
  ///
  /// A different string is only selected when the raw frequency is
  /// significantly closer to that other string (by at least [hysteresisCents]
  /// more than the current note).
  static Note? findClosestStringSticky(
    double frequency,
    List<Note> tuningNotes, {
    Note? currentNote,
    double hysteresisCents = 200,
  }) {
    if (frequency <= 0 || tuningNotes.isEmpty) return null;

    // If no current note, fall back to basic closest-match
    if (currentNote == null) {
      return findClosestString(frequency, tuningNotes);
    }

    // Check whether the frequency might be a harmonic of the current string.
    // If the detected frequency is near 2×, 3×, or 4× the target fundamental,
    // treat it as the same string (pitch detector picking up an overtone).
    final fund = currentNote.frequency;
    for (final multiplier in [1.0, 2.0, 3.0, 4.0]) {
      final harmonicFreq = fund * multiplier;
      final centsToHarmonic = centsDifference(frequency, harmonicFreq).abs();
      if (centsToHarmonic < 150) {
        // Close to a harmonic → stay on the current string
        return currentNote;
      }
    }

    // Find the absolute closest string
    Note? closest;
    double minCentsDiff = double.infinity;
    for (final note in tuningNotes) {
      final cents = centsDifference(frequency, note.frequency).abs();
      if (cents < minCentsDiff) {
        minCentsDiff = cents;
        closest = note;
      }
    }

    // How far is the frequency from the current note?
    final currentCents = centsDifference(frequency, fund).abs();

    // Only switch if the new string is closer by at least [hysteresisCents].
    // This prevents the tuner from bouncing between adjacent strings when
    // the player's note is very flat (e.g. low E at ~76 Hz near D).
    if (closest != currentNote && (currentCents - minCentsDiff) < hysteresisCents) {
      return currentNote; // stick to current
    }

    return closest;
  }
}
