import 'dart:math' as math;
import '../enums/valve_type.dart';
import '../enums/weld_type.dart';
import '../services/custom_valve_catalog.dart';
import 'node_3d.dart';

/// Трубопроводная арматура, установленная на участке трубы
class Valve {
  /// Стандартная строительная длина L (мм) по типу арматуры и диаметру DN
  static double defaultLengthFor(ValveType type, int dn) {
    switch (type) {
      case ValveType.gateValve:
        return math.max(140.0, dn * 2.0);
      case ValveType.butterflyValve:
        return math.max(45.0, dn * 0.6);
      case ValveType.ballValve:
        return math.max(90.0, dn * 1.4);
      case ValveType.checkValve:
        return math.max(120.0, dn * 1.6);
      case ValveType.strainer:
        return math.max(130.0, dn * 1.8);
      case ValveType.balancingValve:
        return math.max(160.0, dn * 2.2);
      case ValveType.drainValve:
        return math.max(80.0, dn * 1.2);
      case ValveType.waterMeter:
        return math.max(150.0, dn * 2.0);
      case ValveType.pressureGauge:
      case ValveType.thermometer:
      case ValveType.airVent:
        return math.max(60.0, dn * 0.5);
    }
  }

  final String id;
  final String segmentId;

  /// Позиция арматуры вдоль трубы (от 0.0 до 1.0)
  final double ratio;

  /// Тип арматуры
  final ValveType valveType;

  /// Наименование / марка изделия
  final String name;

  /// Условный проход (диаметр) DN
  final int dn;

  /// Строительная длина корпуса L (мм)
  final double lengthMm;

  /// Угол поворота маховика / рукоятки вокруг оси трубы (в градусах)
  final double handleAngleDeg;

  /// Инвертировать ли направление потока (для обратных клапанов, фильтров, счетчиков)
  final bool isReversed;

  /// Фланцевое исполнение (требует ответных фланцев на трубах) vs под приварку
  final bool isFlanged;

  /// Номинальное давление Ру (Pn) для фланцев (10, 16, 25, 40)
  final int flangePressurePn;

  /// Включать ли ответные приварные фланцы на трубах (true) или только арматура с прокладками (false)
  final bool includeCounterFlanges;

  /// Исполнение ответных фланцев (тип 11 воротниковый, тип 01 плоский)
  final String counterFlangeType;

  /// Строительная длина одного ответного фланца (мм) (если null — берется из типа: 45 мм для тип 11, 35 мм для тип 01)
  final double? counterFlangeLengthMm;

  /// Марка стали ответных фланцев
  final String counterFlangeMaterial;

  /// Заводской номер арматуры (индивидуальный номер изделия)
  final String? serialNumber;

  /// Идентификатор пользовательского семейства арматуры (CustomValveDefinition)
  final String? customDefinitionId;

  /// Марка / позиционное обозначение на схеме (например, "А-1", "А-2")
  final String? mark;

  const Valve({
    required this.id,
    required this.segmentId,
    required this.ratio,
    required this.valveType,
    required this.name,
    required this.dn,
    required this.lengthMm,
    this.handleAngleDeg = 90.0,
    this.isReversed = false,
    this.isFlanged = false,
    this.flangePressurePn = 16,
    this.includeCounterFlanges = true,
    this.counterFlangeType = 'ГОСТ 33259-2015 тип 11',
    this.counterFlangeLengthMm,
    this.counterFlangeMaterial = 'Сталь 20',
    this.serialNumber,
    this.customDefinitionId,
    this.mark,
  });

  /// Является ли арматура фланцевой (с учетом пользовательского семейства арматуры)
  bool get effectiveIsFlanged {
    if (isFlanged) return true;
    if (customDefinitionId != null) {
      final def = CustomValveCatalog.instance.getById(customDefinitionId!);
      if (def != null) return def.symbol2d.hasBodyFlanges;
    }
    return false;
  }

  /// Является ли ответный фланец плоским (тип 01)
  bool get isFlatCounterFlange =>
      counterFlangeType.contains('тип 01') ||
      (counterFlangeType.contains('01') && !counterFlangeType.contains('11'));

  /// Эффективная строительная длина одного ответного фланца (воротника/шейки)
  double get effectiveCounterFlangeLengthMm {
    if (!effectiveIsFlanged || !includeCounterFlanges) return 0.0;
    if (counterFlangeLengthMm != null && counterFlangeLengthMm! > 0) {
      return counterFlangeLengthMm!;
    }
    if (isFlatCounterFlange) {
      return 35.0;
    }
    return 45.0;
  }

  /// Полный строительно-монтажный габарит узла (корпус арматуры + ответные фланцы)
  double get effectiveTotalLengthMm {
    if (!effectiveIsFlanged || !includeCounterFlanges) {
      return lengthMm;
    }
    return lengthMm + effectiveCounterFlangeLengthMm * 2.0;
  }

  /// Полудлина от центра арматуры до наружного торца воротника ответного фланца
  double get effectiveHalfLengthMm => effectiveTotalLengthMm / 2.0;

  /// Эффективная марка стали ответных фланцев
  String get effectiveCounterFlangeMaterial =>
      counterFlangeMaterial.isNotEmpty ? counterFlangeMaterial : 'Сталь 20';

  /// Тип сварного шва приварки ответного фланца к трубе (С17 для воротниковых, С2 для плоских)
  WeldType get counterFlangeWeldType =>
      isFlatCounterFlange ? WeldType.c2 : WeldType.c17;

  /// Вычисление 3D координат центра арматуры в пространстве
  Node3D calculatePosition(Node3D startNode, Node3D endNode) {
    final x = startNode.x + (endNode.x - startNode.x) * ratio;
    final y = startNode.y + (endNode.y - startNode.y) * ratio;
    final z = startNode.z + (endNode.z - startNode.z) * ratio;
    return Node3D(id: 'valve_pos_$id', x: x, y: y, z: z);
  }

  Valve copyWith({
    String? id,
    String? segmentId,
    double? ratio,
    ValveType? valveType,
    String? name,
    int? dn,
    double? lengthMm,
    double? handleAngleDeg,
    bool? isReversed,
    bool? isFlanged,
    int? flangePressurePn,
    bool? includeCounterFlanges,
    String? counterFlangeType,
    double? counterFlangeLengthMm,
    bool clearCounterFlangeLength = false,
    String? counterFlangeMaterial,
    String? serialNumber,
    bool clearSerialNumber = false,
    String? customDefinitionId,
    bool clearCustomDefinition = false,
    String? mark,
    bool clearMark = false,
  }) {
    return Valve(
      id: id ?? this.id,
      segmentId: segmentId ?? this.segmentId,
      ratio: ratio ?? this.ratio,
      valveType: valveType ?? this.valveType,
      name: name ?? this.name,
      dn: dn ?? this.dn,
      lengthMm: lengthMm ?? this.lengthMm,
      handleAngleDeg: handleAngleDeg ?? this.handleAngleDeg,
      isReversed: isReversed ?? this.isReversed,
      isFlanged: isFlanged ?? this.isFlanged,
      flangePressurePn: flangePressurePn ?? this.flangePressurePn,
      includeCounterFlanges: includeCounterFlanges ?? this.includeCounterFlanges,
      counterFlangeType: counterFlangeType ?? this.counterFlangeType,
      counterFlangeLengthMm:
          clearCounterFlangeLength ? null : (counterFlangeLengthMm ?? this.counterFlangeLengthMm),
      counterFlangeMaterial: counterFlangeMaterial ?? this.counterFlangeMaterial,
      serialNumber: clearSerialNumber ? null : (serialNumber ?? this.serialNumber),
      customDefinitionId: clearCustomDefinition ? null : (customDefinitionId ?? this.customDefinitionId),
      mark: clearMark ? null : (mark ?? this.mark),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'segmentId': segmentId,
        'ratio': ratio,
        'valveType': valveType.index,
        'name': name,
        'dn': dn,
        'lengthMm': lengthMm,
        'handleAngleDeg': handleAngleDeg,
        'isReversed': isReversed,
        'isFlanged': isFlanged,
        'flangePressurePn': flangePressurePn,
        'includeCounterFlanges': includeCounterFlanges,
        'counterFlangeType': counterFlangeType,
        if (counterFlangeLengthMm != null) 'counterFlangeLengthMm': counterFlangeLengthMm,
        'counterFlangeMaterial': counterFlangeMaterial,
        if (serialNumber != null) 'serialNumber': serialNumber,
        if (customDefinitionId != null) 'customDefinitionId': customDefinitionId,
        if (mark != null) 'mark': mark,
      };

  factory Valve.fromJson(Map<String, dynamic> json) {
    ValveType parsedType = ValveType.gateValve;
    final vt = json['valveType'];
    if (vt is int && vt >= 0 && vt < ValveType.values.length) {
      parsedType = ValveType.values[vt];
    } else if (vt is String) {
      parsedType = ValveType.values.firstWhere(
        (e) => e.name == vt,
        orElse: () => ValveType.gateValve,
      );
    }

    return Valve(
      id: json['id'] as String,
      segmentId: json['segmentId'] as String,
      ratio: (json['ratio'] as num).toDouble(),
      valveType: parsedType,
      name: json['name'] as String,
      dn: json['dn'] as int,
      lengthMm: (json['lengthMm'] as num).toDouble(),
      handleAngleDeg: (json['handleAngleDeg'] as num?)?.toDouble() ?? 90.0,
      isReversed: json['isReversed'] as bool? ?? false,
      isFlanged: json['isFlanged'] as bool? ?? false,
      flangePressurePn: json['flangePressurePn'] as int? ?? 16,
      includeCounterFlanges: json['includeCounterFlanges'] as bool? ?? true,
      counterFlangeType: json['counterFlangeType'] as String? ?? 'ГОСТ 33259-2015 тип 11',
      counterFlangeLengthMm: (json['counterFlangeLengthMm'] as num?)?.toDouble(),
      counterFlangeMaterial: json['counterFlangeMaterial'] as String? ?? 'Сталь 20',
      serialNumber: json['serialNumber'] as String?,
      customDefinitionId: json['customDefinitionId'] as String?,
      mark: json['mark'] as String?,
    );
  }
}
