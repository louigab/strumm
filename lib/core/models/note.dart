/// Represents a single note with its name, octave, and frequency.
class Note {
  final String name;
  final int octave;
  final double frequency;

  const Note({
    required this.name,
    required this.octave,
    required this.frequency,
  });

  String get displayName => name;
  String get fullName => '$name$octave';

  @override
  String toString() => '$name$octave (${frequency.toStringAsFixed(2)} Hz)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Note &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          octave == other.octave;

  @override
  int get hashCode => name.hashCode ^ octave.hashCode;
}
