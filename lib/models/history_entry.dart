/// A saved rewrite stored only on the device.
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.original,
    required this.rewritten,
    required this.toneId,
    required this.createdAt,
    this.intensityLabel,
    this.lengthLabel,
  });

  final int id;
  final String original;
  final String rewritten;
  final String toneId;
  final DateTime createdAt;
  final String? intensityLabel;
  final String? lengthLabel;

  Map<String, dynamic> toMap({bool includeId = true}) {
    return {
      if (includeId) 'id': id,
      'original': original,
      'rewritten': rewritten,
      'tone_id': toneId,
      'intensity': intensityLabel,
      'length': lengthLabel,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory HistoryEntry.fromMap(Map<String, dynamic> map) {
    return HistoryEntry(
      id: map['id'] as int,
      original: map['original'] as String,
      rewritten: map['rewritten'] as String,
      toneId: map['tone_id'] as String,
      intensityLabel: map['intensity'] as String?,
      lengthLabel: map['length'] as String?,
      createdAt:
          DateTime.tryParse(map['created_at'] as String) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
