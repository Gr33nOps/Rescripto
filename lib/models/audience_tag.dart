/// A selectable audience the rewrite can be targeted at, e.g. "coworkers".
class AudienceTag {
  const AudienceTag({
    required this.id,
    required this.label,
    this.isBuiltin = false,
  });

  final String id;

  /// Text interpolated directly into the prompt
  /// (`Audience: written for $label.`) and shown on the selector chip.
  final String label;

  final bool isBuiltin;

  AudienceTag copyWith({String? label}) =>
      AudienceTag(id: id, label: label ?? this.label, isBuiltin: isBuiltin);

  Map<String, Object?> toMap() => {'id': id, 'label': label};

  factory AudienceTag.fromMap(Map<String, Object?> map) => AudienceTag(
    id: map['id'] as String,
    label: map['label'] as String,
    isBuiltin: (map['is_builtin'] as int? ?? 0) != 0,
  );
}

/// The built-in audience list, seeded into `audience_tag` by `ConfigSeeder`.
///
/// Previously hardcoded as `_RewriteScreenState._audiences` in
/// `rewrite_screen.dart`. `id` and `label` are identical for every built-in —
/// the label was already used as the de facto id (`RewriteRequest.audience`
/// stores these strings directly and `PromptBuilder` joins them verbatim) —
/// so seeding them this way is a zero-behavior-change port.
class AudienceLibrary {
  static const List<AudienceTag> builtIns = [
    AudienceTag(id: 'coworkers', label: 'coworkers', isBuiltin: true),
    AudienceTag(id: 'a manager', label: 'a manager', isBuiltin: true),
    AudienceTag(id: 'customers', label: 'customers', isBuiltin: true),
    AudienceTag(id: 'a teacher', label: 'a teacher', isBuiltin: true),
    AudienceTag(id: 'friends', label: 'friends', isBuiltin: true),
    AudienceTag(id: 'recruiters', label: 'recruiters', isBuiltin: true),
  ];
}
