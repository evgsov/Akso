import 'dart:ui';

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

/// Компактные шаблоны выносок (только буквенно-цифровые марки позиций для плотных чертежей)
const Map<String, String> compactCalloutTemplates = {
  'segment': '{MARK}',
  'segment_bottom': '',
  'weld': '№{ID}',
  'weld_bottom': '',
  'valve': '{MARK}',
  'valve_bottom': '',
  'fitting': '{MARK}',
  'fitting_bottom': '',
  'equipment': '{TAG}',
  'equipment_bottom': '',
  'nozzle': '{NAME}',
  'nozzle_bottom': '',
  'support': '{MARK}',
  'support_bottom': '',
  'node': '+{Z_M}',
  'node_bottom': '',
  'elevation_style': 'gostOutline',
  'elevation_shelf_direction': 'auto',
  'elevation_arrow_on_node': 'true',
};

typedef ElevationCalloutStyle = ElevationMarkStyle;

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

  /// Индивидуальные смещения выноски для конкретных листов чертежа (sheetId -> Offset(dx, dy))
  final Map<String, Offset> sheetOffsets;

  /// Индивидуальная фиксация выноски для конкретных листов чертежа (sheetId -> bool).
  /// Защищает выноску от авто-расстановки на данном листе, не блокируя другие листы.
  final Map<String, bool> sheetPinned;

  /// Дополнительные ID объектов сети, на которые ссылается данная выноска
  /// (для объединенных вилочных выносок типа "Ласточкин хвост / Звезда" по ГОСТ 2.316 п. 4.4)
  final List<String> additionalTargetIds;

  /// Отображать ли суффикс количества "(N шт.)" в тексте выноски
  final bool showQuantity;

  /// Скрыта ли данная выноска пользователем (без удаления самой выноски и её настроек)
  final bool isHidden;

  const Callout({
    required this.id,
    required this.targetId,
    required this.targetType,
    String? text,
    String? customText,
    this.customBottomText,
    this.screenOffsetX = 50.0,
    this.screenOffsetY = -50.0,
    this.textHeight = 2.5,
    this.textColor = 0xFF1E293B,
    this.elevationStyle,
    this.shelfDirection = ShelfDirection.auto,
    this.arrowOnNode = true,
    this.isPinned = false,
    this.sheetOffsets = const {},
    this.sheetPinned = const {},
    this.additionalTargetIds = const [],
    this.showQuantity = true,
    this.isHidden = false,
  }) : customText = text ?? customText;

  /// Алиас для customText
  String? get text => customText;

  /// Флаг: использует ли выноска пользовательский текст или шаблон
  bool get isCustom =>
      (customText != null && customText!.trim().isNotEmpty) ||
      (customBottomText != null && customBottomText!.trim().isNotEmpty);

  /// Проверяет, задано ли индивидуальное смещение для конкретного листа
  bool hasSheetOffset(String sheetId) => sheetOffsets.containsKey(sheetId);

  /// Проверяет, зафиксирована ли выноска от перемещения алгоритмами авторасстановки.
  /// Если передан [sheetId], проверяет индивидуальную фиксацию листа [sheetPinned],
  /// откатываясь к глобальной [isPinned], если лист не настроен индивидуально.
  bool isPinnedOnSheet(String? sheetId) {
    if (sheetId != null && sheetPinned.containsKey(sheetId)) {
      return sheetPinned[sheetId]!;
    }
    return isPinned;
  }

  /// Возвращает эффективное смещение выноски с учетом указанного листа чертежа
  Offset getEffectiveOffset(String? sheetId) {
    if (sheetId != null && sheetOffsets.containsKey(sheetId)) {
      return sheetOffsets[sheetId]!;
    }
    return Offset(screenOffsetX, screenOffsetY);
  }

  /// Эффективный X для указанного листа
  double getEffectiveOffsetX(String? sheetId) => getEffectiveOffset(sheetId).dx;

  /// Эффективный Y для указанного листа
  double getEffectiveOffsetY(String? sheetId) => getEffectiveOffset(sheetId).dy;

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
    Map<String, Offset>? sheetOffsets,
    Map<String, bool>? sheetPinned,
    List<String>? additionalTargetIds,
    bool? showQuantity,
    bool? isHidden,
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
      sheetOffsets: sheetOffsets ?? this.sheetOffsets,
      sheetPinned: sheetPinned ?? this.sheetPinned,
      additionalTargetIds: additionalTargetIds ?? this.additionalTargetIds,
      showQuantity: showQuantity ?? this.showQuantity,
      isHidden: isHidden ?? this.isHidden,
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
        if (sheetOffsets.isNotEmpty)
          'sheetOffsets': sheetOffsets.map((k, v) => MapEntry(k, {'dx': v.dx, 'dy': v.dy})),
        if (sheetPinned.isNotEmpty) 'sheetPinned': sheetPinned,
        if (additionalTargetIds.isNotEmpty) 'additionalTargetIds': additionalTargetIds,
        'showQuantity': showQuantity,
        if (isHidden) 'isHidden': isHidden,
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

    final rawAddTargets = json['additionalTargetIds'];
    final parsedAddTargets = <String>[];
    if (rawAddTargets is List) {
      for (final t in rawAddTargets) {
        if (t is String && t.isNotEmpty) parsedAddTargets.add(t);
      }
    }
    final parsedShowQuantity = (json['showQuantity'] as bool?) ?? true;
    final parsedIsHidden = (json['isHidden'] as bool?) ?? false;

    final rawSheetOffsets = json['sheetOffsets'];
    final parsedSheetOffsets = <String, Offset>{};
    if (rawSheetOffsets is Map) {
      for (final entry in rawSheetOffsets.entries) {
        final val = entry.value;
        if (val is Map) {
          final dx = (val['dx'] as num?)?.toDouble() ?? 0.0;
          final dy = (val['dy'] as num?)?.toDouble() ?? 0.0;
          parsedSheetOffsets[entry.key.toString()] = Offset(dx, dy);
        }
      }
    }

    final rawSheetPinned = json['sheetPinned'];
    final parsedSheetPinned = <String, bool>{};
    if (rawSheetPinned is Map) {
      for (final entry in rawSheetPinned.entries) {
        if (entry.value is bool) {
          parsedSheetPinned[entry.key.toString()] = entry.value as bool;
        }
      }
    }

    return Callout(
      id: json['id'] as String,
      targetId: json['targetId'] as String,
      targetType: parsedType,
      customText: json['customText'] as String?,
      customBottomText: json['customBottomText'] as String? ?? json['bottomText'] as String?,
      screenOffsetX: (json['screenOffsetX'] as num?)?.toDouble() ?? 50.0,
      screenOffsetY: (json['screenOffsetY'] as num?)?.toDouble() ?? -50.0,
      textHeight: () {
        final val = (json['textHeight'] as num?)?.toDouble();
        if (val == null || val >= 10.0) return 2.5;
        return val;
      }(),
      textColor: (json['textColor'] as num?)?.toInt() ?? 0xFF1E293B,
      elevationStyle: parsedElevStyle,
      shelfDirection: parsedShelfDir,
      arrowOnNode: parsedArrowOnNode,
      isPinned: parsedIsPinned,
      sheetOffsets: parsedSheetOffsets,
      sheetPinned: parsedSheetPinned,
      additionalTargetIds: parsedAddTargets,
      showQuantity: parsedShowQuantity,
      isHidden: parsedIsHidden,
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
          isPinned == other.isPinned &&
          showQuantity == other.showQuantity &&
          isHidden == other.isHidden &&
          _listEquals(additionalTargetIds, other.additionalTargetIds) &&
          _mapEquals(sheetPinned, other.sheetPinned);

  static bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || b[key] != a[key]) return false;
    }
    return true;
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

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
        showQuantity,
        isHidden,
        Object.hashAll(additionalTargetIds),
        Object.hashAll(sheetPinned.entries.map((e) => Object.hash(e.key, e.value))),
      );

  @override
  String toString() =>
      'Callout(id: $id, targetId: $targetId, type: ${targetType.name}, text: ${customText ?? "template"}, bottom: ${customBottomText ?? "-"}, offset: ($screenOffsetX, $screenOffsetY), elevStyle: ${elevationStyle?.name}, shelfDir: ${shelfDirection.name}, arrowOnNode: $arrowOnNode, isPinned: $isPinned, sheetPinned: ${sheetPinned.length}, addTargets: ${additionalTargetIds.length}, showQty: $showQuantity, isHidden: $isHidden)';
}
