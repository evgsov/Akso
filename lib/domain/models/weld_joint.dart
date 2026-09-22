import '../enums/inspection_method.dart';
import '../enums/weld_joint_style.dart';
import '../enums/weld_type.dart';
import 'node_3d.dart';

/// Сварное соединение (шов) на трубопроводе
class WeldJoint {
  final String id;
  final String segmentId;

  /// Позиция шва вдоль трубы: 0.0 = начальный узел, 1.0 = конечный узел
  final double ratio;

  /// Порядковый номер шва (сквозной по схеме: 1, 2, 3...)
  final int number;

  /// Персональное клеймо сварщика (например, "ИВ-24", "12-А")
  final String stamp;

  /// Тип сварного шва по ГОСТ
  final WeldType weldType;

  /// Составной список методов неразрушающего контроля
  final List<InspectionMethod>? _inspectionMethods;
  final InspectionMethod? _legacyMethod;

  List<InspectionMethod> get inspectionMethods {
    if (_inspectionMethods != null && _inspectionMethods.isNotEmpty) {
      return _inspectionMethods;
    }
    if (_legacyMethod != null) {
      return [_legacyMethod];
    }
    return const [InspectionMethod.vik];
  }

  /// Основной метод неразрушающего контроля (для обратной совместимости)
  InspectionMethod get inspectionMethod {
    final list = inspectionMethods;
    return list.isNotEmpty ? list.first : InspectionMethod.vik;
  }

  /// Форматированная строка методов контроля (например, "ВИК, РК" или "ВИК, УЗК, ПВК")
  String get formattedInspectionMethods {
    final list = inspectionMethods;
    return list.isEmpty ? '—' : list.map((m) => m.code).join(', ');
  }

  /// Дата выполнения шва
  final String date;

  /// Марка стали свариваемых элементов (например, "Сталь 20", "09Г2С", "12Х18Н10Т")
  final String steelGrade;

  /// Марка сварочных материалов (например, "УОНИ 13/55", "LB-52U", "Св-08Г2С")
  final String electrodeGrade;

  /// Примечания / результат контроля ("Годен", толщина, зазор)
  final String notes;

  /// Индивидуальный стиль отображения (null = использовать стиль по умолчанию из сети)
  final WeldJointStyle? style;

  /// Индивидуальный размер засечки в мм (null = использовать настройку сети или диаметр трубы)
  final double? tickSizeMm;

  /// Идентификатор элемента-источника (арматура, фитинг, сопряжение), создавшего этот стык
  final String? sourceElementId;

  /// Флаг ручного создания шва пользователем (не удаляется и не сдвигается автоматикой)
  final bool isManual;

  const WeldJoint({
    required this.id,
    required this.segmentId,
    required this.ratio,
    required this.number,
    required this.stamp,
    this.weldType = WeldType.c17,
    List<InspectionMethod>? inspectionMethods,
    InspectionMethod? inspectionMethod,
    this.date = '',
    this.steelGrade = 'Сталь 20',
    this.electrodeGrade = 'УОНИ 13/55',
    this.notes = 'Годен',
    this.style,
    this.tickSizeMm,
    this.sourceElementId,
    this.isManual = false,
  })  : _inspectionMethods = inspectionMethods ?? const [InspectionMethod.vik],
        _legacyMethod = inspectionMethod;

  /// Вычисление эффективного стиля отображения с учетом настройки по умолчанию
  WeldJointStyle getEffectiveStyle(WeldJointStyle defaultStyle) => style ?? defaultStyle;

  /// Вычисление эффективного размера засечки (мм) с учетом настройки сети и диаметра трубы
  double getEffectiveTickSize(double? networkDefault, double pipeDiameter) {
    if (tickSizeMm != null && tickSizeMm! > 0) return tickSizeMm!;
    if (networkDefault != null && networkDefault > 0) return networkDefault;
    return pipeDiameter;
  }

  /// Вычисление 3D координат шва в пространстве
  Node3D calculatePosition(Node3D startNode, Node3D endNode) {
    final x = startNode.x + (endNode.x - startNode.x) * ratio;
    final y = startNode.y + (endNode.y - startNode.y) * ratio;
    final z = startNode.z + (endNode.z - startNode.z) * ratio;
    return Node3D(id: 'weld_pos_$id', x: x, y: y, z: z);
  }

  WeldJoint copyWith({
    String? id,
    String? segmentId,
    double? ratio,
    int? number,
    String? stamp,
    WeldType? weldType,
    InspectionMethod? inspectionMethod,
    List<InspectionMethod>? inspectionMethods,
    String? date,
    String? steelGrade,
    String? electrodeGrade,
    String? notes,
    WeldJointStyle? style,
    bool clearStyle = false,
    double? tickSizeMm,
    bool clearTickSize = false,
    String? sourceElementId,
    bool clearSourceElementId = false,
    bool? isManual,
  }) {
    return WeldJoint(
      id: id ?? this.id,
      segmentId: segmentId ?? this.segmentId,
      ratio: ratio ?? this.ratio,
      number: number ?? this.number,
      stamp: stamp ?? this.stamp,
      weldType: weldType ?? this.weldType,
      inspectionMethods: inspectionMethods ??
          (inspectionMethod != null ? [inspectionMethod] : this.inspectionMethods),
      date: date ?? this.date,
      steelGrade: steelGrade ?? this.steelGrade,
      electrodeGrade: electrodeGrade ?? this.electrodeGrade,
      notes: notes ?? this.notes,
      style: clearStyle ? null : (style ?? this.style),
      tickSizeMm: clearTickSize ? null : (tickSizeMm ?? this.tickSizeMm),
      sourceElementId: clearSourceElementId ? null : (sourceElementId ?? this.sourceElementId),
      isManual: isManual ?? this.isManual,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'segmentId': segmentId,
        'ratio': ratio,
        'number': number,
        'stamp': stamp,
        'weldType': weldType.index,
        'inspectionMethod': inspectionMethod.index,
        'inspectionMethods': inspectionMethods.map((m) => m.index).toList(),
        'date': date,
        'steelGrade': steelGrade,
        'electrodeGrade': electrodeGrade,
        'notes': notes,
        if (style != null) 'style': style!.name,
        if (tickSizeMm != null) 'tickSizeMm': tickSizeMm,
        if (sourceElementId != null) 'sourceElementId': sourceElementId,
        if (isManual) 'isManual': isManual,
      };

  factory WeldJoint.fromJson(Map<String, dynamic> json) {
    List<InspectionMethod>? methods;
    if (json['inspectionMethods'] is List) {
      methods = (json['inspectionMethods'] as List)
          .map((e) => (e is int && e >= 0 && e < InspectionMethod.values.length)
              ? InspectionMethod.values[e]
              : InspectionMethod.vik)
          .toList();
    }
    return WeldJoint(
      id: json['id'] as String,
      segmentId: json['segmentId'] as String,
      ratio: (json['ratio'] as num).toDouble(),
      number: json['number'] as int,
      stamp: json['stamp'] as String,
      weldType: WeldType.values[json['weldType'] as int? ?? 0],
      inspectionMethod: json['inspectionMethod'] != null
          ? InspectionMethod.values[json['inspectionMethod'] as int]
          : null,
      inspectionMethods: methods,
      date: json['date'] as String? ?? '',
      steelGrade: json['steelGrade'] as String? ?? 'Сталь 20',
      electrodeGrade: json['electrodeGrade'] as String? ?? 'УОНИ 13/55',
      notes: json['notes'] as String? ?? 'Годен',
      style: json['style'] != null ? WeldJointStyle.fromString(json['style'] as String?) : null,
      tickSizeMm: (json['tickSizeMm'] as num?)?.toDouble(),
      sourceElementId: json['sourceElementId'] as String?,
      isManual: json['isManual'] as bool? ?? false,
    );
  }
}
