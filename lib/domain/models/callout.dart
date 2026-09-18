/// Тип объекта, к которому привязана умная выноска
enum CalloutTargetType {
  segment,
  valve,
  weld,
  fitting,
  equipment,
  nozzle,
  support,
  node,
}

extension CalloutTargetTypeExt on CalloutTargetType {
  /// Человекочитаемое название типа на русском языке
  String get displayName {
    switch (this) {
      case CalloutTargetType.segment:
        return 'Труба';
      case CalloutTargetType.valve:
        return 'Арматура';
      case CalloutTargetType.weld:
        return 'Сварной стык';
      case CalloutTargetType.fitting:
        return 'Фасонный элемент';
      case CalloutTargetType.equipment:
        return 'Оборудование';
      case CalloutTargetType.nozzle:
        return 'Штуцер';
      case CalloutTargetType.support:
        return 'Опора / подвеска';
      case CalloutTargetType.node:
        return 'Узел';
    }
  }

  /// Стандартный шаблон по умолчанию для данного типа
  String get defaultTemplate {
    switch (this) {
      case CalloutTargetType.segment:
        return 'Ø{DN}x{WALL} {MATERIAL}';
      case CalloutTargetType.weld:
        return 'Стык №{ID}';
      case CalloutTargetType.valve:
        return '{NAME} Ду{DN}';
      case CalloutTargetType.fitting:
        return '{NAME}';
      case CalloutTargetType.equipment:
        return '{NAME}';
      case CalloutTargetType.nozzle:
        return 'Шт. {NAME} Ду{DN}';
      case CalloutTargetType.support:
        return '{NAME}';
      case CalloutTargetType.node:
        return 'Узел {ID}';
    }
  }

  /// Стандартный шаблон нижней полки по умолчанию для данного типа
  String? get defaultBottomTemplate {
    switch (this) {
      case CalloutTargetType.segment:
        return '{SYSTEM}';
      case CalloutTargetType.weld:
        return '{TYPE} {STAMP} {DATE}';
      case CalloutTargetType.valve:
        return '{SYSTEM} {MATERIAL}';
      case CalloutTargetType.fitting:
        return '{STANDARD} {MATERIAL}';
      case CalloutTargetType.equipment:
        return '{TYPE}';
      case CalloutTargetType.nozzle:
        return '{EQUIPMENT}';
      case CalloutTargetType.support:
        return '{TYPE}';
      case CalloutTargetType.node:
        return 'Отм. {Z}';
    }
  }
}

/// Стандартные шаблоны выносок для проекта
const Map<String, String> defaultCalloutTemplates = {
  'segment': 'Ø{DN}x{WALL} {MATERIAL}',
  'segment_bottom': '{SYSTEM}',
  'weld': 'Стык №{ID}',
  'weld_bottom': '{TYPE} {STAMP} {DATE}',
  'valve': '{NAME} Ду{DN}',
  'valve_bottom': '{SYSTEM} {MATERIAL}',
  'fitting': '{NAME}',
  'fitting_bottom': '{STANDARD} {MATERIAL}',
  'equipment': '{NAME}',
  'equipment_bottom': '{TYPE}',
  'nozzle': 'Шт. {NAME} Ду{DN}',
  'nozzle_bottom': '{EQUIPMENT}',
  'support': '{NAME}',
  'support_bottom': '{TYPE}',
  'node': 'Узел {ID}',
  'node_bottom': 'Отм. {Z}',
};

/// Умная выноска (Screen-Aligned Billboard Annotation),
/// привязанная к 3D-объекту сети, но со смещением на 2D-экране.
class Callout {
  final String id;
  final String targetId;
  final CalloutTargetType targetType;
  final String? customText;
  final String? customBottomText;
  final double screenOffsetX;
  final double screenOffsetY;
  final double textHeight;
  final int textColor;

  const Callout({
    required this.id,
    required this.targetId,
    required this.targetType,
    this.customText,
    this.customBottomText,
    this.screenOffsetX = 50.0,
    this.screenOffsetY = -50.0,
    this.textHeight = 12.0,
    this.textColor = 0xFF1E293B,
  });

  /// Флаг: использует ли выноска пользовательский текст или шаблон
  bool get isCustom =>
      (customText != null && customText!.trim().isNotEmpty) ||
      (customBottomText != null && customBottomText!.trim().isNotEmpty);

  Callout copyWith({
    String? id,
    String? targetId,
    CalloutTargetType? targetType,
    String? customText,
    String? customBottomText,
    bool clearCustomText = false,
    bool clearCustomBottomText = false,
    double? screenOffsetX,
    double? screenOffsetY,
    double? textHeight,
    int? textColor,
  }) {
    return Callout(
      id: id ?? this.id,
      targetId: targetId ?? this.targetId,
      targetType: targetType ?? this.targetType,
      customText: clearCustomText ? null : (customText ?? this.customText),
      customBottomText: clearCustomBottomText ? null : (customBottomText ?? this.customBottomText),
      screenOffsetX: screenOffsetX ?? this.screenOffsetX,
      screenOffsetY: screenOffsetY ?? this.screenOffsetY,
      textHeight: textHeight ?? this.textHeight,
      textColor: textColor ?? this.textColor,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'targetId': targetId,
        'targetType': targetType.name,
        if (customText != null) 'customText': customText,
        if (customBottomText != null) 'customBottomText': customBottomText,
        'screenOffsetX': screenOffsetX,
        'screenOffsetY': screenOffsetY,
        'textHeight': textHeight,
        'textColor': textColor,
      };

  factory Callout.fromJson(Map<String, dynamic> json) {
    CalloutTargetType parsedType;
    final rawType = json['targetType'];
    if (rawType is int && rawType >= 0 && rawType < CalloutTargetType.values.length) {
      parsedType = CalloutTargetType.values[rawType];
    } else if (rawType is String) {
      parsedType = CalloutTargetType.values.firstWhere(
        (e) => e.name == rawType,
        orElse: () => CalloutTargetType.segment,
      );
    } else {
      parsedType = CalloutTargetType.segment;
    }

    return Callout(
      id: json['id'] as String,
      targetId: json['targetId'] as String,
      targetType: parsedType,
      customText: json['customText'] as String?,
      customBottomText: json['customBottomText'] as String? ?? json['bottomText'] as String?,
      screenOffsetX: (json['screenOffsetX'] as num?)?.toDouble() ?? 50.0,
      screenOffsetY: (json['screenOffsetY'] as num?)?.toDouble() ?? -50.0,
      textHeight: (json['textHeight'] as num?)?.toDouble() ?? 12.0,
      textColor: (json['textColor'] as num?)?.toInt() ?? 0xFF1E293B,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Callout &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          targetId == other.targetId &&
          targetType == other.targetType &&
          customText == other.customText &&
          customBottomText == other.customBottomText &&
          screenOffsetX == other.screenOffsetX &&
          screenOffsetY == other.screenOffsetY &&
          textHeight == other.textHeight &&
          textColor == other.textColor;

  @override
  int get hashCode => Object.hash(
        id,
        targetId,
        targetType,
        customText,
        customBottomText,
        screenOffsetX,
        screenOffsetY,
        textHeight,
        textColor,
      );

  @override
  String toString() =>
      'Callout(id: $id, targetId: $targetId, type: ${targetType.name}, text: ${customText ?? "template"}, bottom: ${customBottomText ?? "-"}, offset: ($screenOffsetX, $screenOffsetY))';
}
