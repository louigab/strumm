import 'note.dart';

/// Represents a guitar tuning configuration.
class GuitarTuning {
  final String name;
  final String description;
  final List<Note> strings;

  const GuitarTuning({
    required this.name,
    required this.description,
    required this.strings,
  });

  /// Standard tuning: E2 A2 D3 G3 B3 E4
  static const GuitarTuning standard = GuitarTuning(
    name: 'Standard',
    description: 'E A D G B E',
    strings: [
      Note(name: 'E', octave: 2, frequency: 82.41),
      Note(name: 'A', octave: 2, frequency: 110.00),
      Note(name: 'D', octave: 3, frequency: 146.83),
      Note(name: 'G', octave: 3, frequency: 196.00),
      Note(name: 'B', octave: 3, frequency: 246.94),
      Note(name: 'E', octave: 4, frequency: 329.63),
    ],
  );

  /// Drop D tuning: D2 A2 D3 G3 B3 E4
  static const GuitarTuning dropD = GuitarTuning(
    name: 'Drop D',
    description: 'D A D G B E',
    strings: [
      Note(name: 'D', octave: 2, frequency: 73.42),
      Note(name: 'A', octave: 2, frequency: 110.00),
      Note(name: 'D', octave: 3, frequency: 146.83),
      Note(name: 'G', octave: 3, frequency: 196.00),
      Note(name: 'B', octave: 3, frequency: 246.94),
      Note(name: 'E', octave: 4, frequency: 329.63),
    ],
  );

  /// Open G tuning: D2 G2 D3 G3 B3 D4
  static const GuitarTuning openG = GuitarTuning(
    name: 'Open G',
    description: 'D G D G B D',
    strings: [
      Note(name: 'D', octave: 2, frequency: 73.42),
      Note(name: 'G', octave: 2, frequency: 98.00),
      Note(name: 'D', octave: 3, frequency: 146.83),
      Note(name: 'G', octave: 3, frequency: 196.00),
      Note(name: 'B', octave: 3, frequency: 246.94),
      Note(name: 'D', octave: 4, frequency: 293.66),
    ],
  );

  /// DADGAD tuning
  static const GuitarTuning dadgad = GuitarTuning(
    name: 'DADGAD',
    description: 'D A D G A D',
    strings: [
      Note(name: 'D', octave: 2, frequency: 73.42),
      Note(name: 'A', octave: 2, frequency: 110.00),
      Note(name: 'D', octave: 3, frequency: 146.83),
      Note(name: 'G', octave: 3, frequency: 196.00),
      Note(name: 'A', octave: 3, frequency: 220.00),
      Note(name: 'D', octave: 4, frequency: 293.66),
    ],
  );

  /// Half-step down: Eb Ab Db Gb Bb Eb
  static const GuitarTuning halfStepDown = GuitarTuning(
    name: 'Half-Step Down',
    description: 'E♭ A♭ D♭ G♭ B♭ E♭',
    strings: [
      Note(name: 'E♭', octave: 2, frequency: 77.78),
      Note(name: 'A♭', octave: 2, frequency: 103.83),
      Note(name: 'D♭', octave: 3, frequency: 138.59),
      Note(name: 'G♭', octave: 3, frequency: 185.00),
      Note(name: 'B♭', octave: 3, frequency: 233.08),
      Note(name: 'E♭', octave: 4, frequency: 311.13),
    ],
  );

  /// All available tunings.
  static const List<GuitarTuning> allTunings = [
    standard,
    dropD,
    openG,
    dadgad,
    halfStepDown,
  ];
}
