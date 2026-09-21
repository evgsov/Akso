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
        return '+{Z_M}';
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
        return 'Ур.ч.п.';
    }
  }
}

/// Стиль графического знака высотной отметки (ГОСТ 21.101 / ISO)
enum ElevationMarkStyle {
  gostOutline, // ГОСТ 21.101 контурный треугольник ▽
  gostFilled,  // ГОСТ 21.101 сплошной залитый треугольник ▼
  compactFlag, // Компактный флажок (стойка без треугольника)
  isoCircle,   // ISO / Revit круглая отметка с перекрестием ⊕
}

extension ElevationMarkStyleExt on ElevationMarkStyle {
  String get displayName {
    switch (this) {
      case ElevationMarkStyle.gostOutline:
        return 'ГОСТ контурный ▽';
      case ElevationMarkStyle.gostFilled:
        return 'ГОСТ залитый ▼';
      case ElevationMarkStyle.compactFlag:
        return 'Компактный флажок';
      case ElevationMarkStyle.isoCircle:
        return 'Круг ISO / Revit ⊕';
    }
  }

  String get shortName {
    switch (this) {
      case ElevationMarkStyle.gostOutline:
        return '▽ Контур';
      case ElevationMarkStyle.gostFilled:
        return '▼ Залитый';
      case ElevationMarkStyle.compactFlag:
        return '⚑ Флажок';
      case ElevationMarkStyle.isoCircle:
        return '⊕ Круг';
    }
  }
  static ElevationMarkStyle fromString(String? name, {ElevationMarkStyle fallback = ElevationMarkStyle.gostOutline}) {
    if (name == null) return fallback;
    return ElevationMarkStyle.values.firstWhere(
      (e) => e.name.toLowerCase() == name.toLowerCase(),
      orElse: () => fallback,
    );
  }
}

/// Ориентация (направление) горизонтальной полочки выноски
enum ShelfDirection {
  auto,  // Автоматически по знаку screenOffsetX
  left,  // Влево (←)
  right, // Вправо (→)
}

extension ShelfDirectionExt on ShelfDirection {
  String get displayName {
    switch (this) {
      case ShelfDirection.auto:
        return 'Авто';
      case ShelfDirection.left:
        return 'Влево ⇦';
      case ShelfDirection.right:
        return 'Вправо ⇨';
    }
  }

  static ShelfDirection fromString(String? name, {ShelfDirection fallback = ShelfDirection.auto}) {
    if (name == null) return fallback;
    return ShelfDirection.values.firstWhere(
      (e) => e.name.toLowerCase() == name.toLowerCase(),
      orElse: () => fallback,
    );
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
  'node': '+{Z_M}',
  'node_bottom': 'Ур.ч.п.',
  'elevation_style': 'gostOutline',
  'elevation_shelf_direction': 'auto',
  'elevation_arrow_on_node': 'true',
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
  final ElevationMarkStyle? elevationStyle;
  final ShelfDirection shelfDirection;
  final bool arrowOnNode;
  final bool isPinned;

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
    this.elevationStyle,
    this.shelfDirection = ShelfDirection.auto,
    this.arrowOnNode = true,
    this.isPinned = false,
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
    ElevationMarkStyle? elevationStyle,
    bool clearElevationStyle = false,
    ShelfDirection? shelfDirection,
    bool? arrowOnNode,
    bool? isPinned,
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
      elevationStyle: clearElevationStyle ? null : (elevationStyle ?? this.elevationStyle),
      shelfDirection: shelfDirection ?? this.shelfDirection,
      arrowOnNode: arrowOnNode ?? this.arrowOnNode,
      isPinned: isPinned ?? this.isPinned,
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
        if (elevationStyle != null) 'elevationStyle': elevationStyle!.name,
        'shelfDirection': shelfDirection.name,
        'arrowOnNode': arrowOnNode,
        'isPinned': isPinned,
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

    ElevationMarkStyle? parsedElevStyle;
    final rawElevStyle = json['elevationStyle'];
    if (rawElevStyle is String) {
      parsedElevStyle = ElevationMarkStyle.values.where((e) => e.name == rawElevStyle).firstOrNull;
    }

    ShelfDirection parsedShelfDir = ShelfDirection.auto;
    final rawShelfDir = json['shelfDirection'];
    if (rawShelfDir is String) {
      parsedShelfDir = ShelfDirection.values.firstWhere(
        (e) => e.name == rawShelfDir,
        orElse: () => ShelfDirection.auto,
      );
    }

    final rawArrowOnNode = json['arrowOnNode'] ?? json['arrow_on_node'];
    final parsedArrowOnNode = rawArrowOnNode is bool ? rawArrowOnNode : true;
    final parsedIsPinned = (json['isPinned'] as bool?) ?? false;

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
      elevationStyle: parsedElevStyle,
      shelfDirection: parsedShelfDir,
      arrowOnNode: parsedArrowOnNode,
      isPinned: parsedIsPinned,
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
          textColor == other.textColor &&
          elevationStyle == other.elevationStyle &&
          shelfDirection == other.shelfDirection &&
          arrowOnNode == other.arrowOnNode &&
          isPinned == other.isPinned;

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
        elevationStyle,
        shelfDirection,
        arrowOnNode,
        isPinned,
      );

  @override
  String toString() =>
      'Callout(id: $id, targetId: $targetId, type: ${targetType.name}, text: ${customText ?? "template"}, bottom: ${customBottomText ?? "-"}, offset: ($screenOffsetX, $screenOffsetY), elevStyle: ${elevationStyle?.name}, shelfDir: ${shelfDirection.name}, arrowOnNode: $arrowOnNode, isPinned: $isPinned)';
}
