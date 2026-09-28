import 'dart:ui';

/// Именованный пресет (снимок) расстановки выносок для конкретного листа чертежа.
/// Позволяет сохранить результат ручной или автоматической компоновки выносок
/// и в любой момент восстановить его без риска потери взаимного расположения.
class SheetCalloutPreset {
  final String id;
  final String name;
  final DateTime createdAt;

  /// Смещения выносок на листе: calloutId -> Offset(dx, dy)
  final Map<String, Offset> offsets;

  /// ID выносок, которые зафиксированы (pinned) на листе в этом пресете
  final Set<String> pinnedCalloutIds;

  const SheetCalloutPreset({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.offsets,
    this.pinnedCalloutIds = const {},
  });

  SheetCalloutPreset copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    Map<String, Offset>? offsets,
    Set<String>? pinnedCalloutIds,
  }) {
    return SheetCalloutPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      offsets: offsets ?? this.offsets,
      pinnedCalloutIds: pinnedCalloutIds ?? this.pinnedCalloutIds,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'offsets': offsets.map((k, v) => MapEntry(k, {'dx': v.dx, 'dy': v.dy})),
    if (pinnedCalloutIds.isNotEmpty) 'pinnedCalloutIds': pinnedCalloutIds.toList(),
  };

  factory SheetCalloutPreset.fromJson(Map<String, dynamic> json) {
    final rawOffsets = json['offsets'] as Map<String, dynamic>? ?? {};
    final offsets = <String, Offset>{};
    for (final entry in rawOffsets.entries) {
      final val = entry.value;
      if (val is Map) {
        final dx = (val['dx'] as num?)?.toDouble() ?? 0.0;
        final dy = (val['dy'] as num?)?.toDouble() ?? 0.0;
        offsets[entry.key] = Offset(dx, dy);
      }
    }

    final rawPinned = json['pinnedCalloutIds'] as List<dynamic>? ?? [];
    final pinnedCalloutIds = rawPinned.map((e) => e.toString()).toSet();

    return SheetCalloutPreset(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Пресет',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      offsets: offsets,
      pinnedCalloutIds: pinnedCalloutIds,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SheetCalloutPreset &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          createdAt == other.createdAt;

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ createdAt.hashCode;
}
