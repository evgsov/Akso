import 'dart:math' as math;
import '../enums/fitting_type.dart';
import '../enums/weld_type.dart';

/// Соединительная деталь (фитинг), расположенная в узле сети
class Fitting {
  final String id;
  final String nodeId;
  final FittingType fittingType;
  final int dn;
  final int? dnSecondary;
  final double radiusMm;

  /// Ссылка на определение в каталоге фитингов (если задано)
  final String? definitionId;

  /// Пользовательское или каталожное наименование (например: "Отвод 90-80 ГОСТ 17375")
  final String? name;

  /// Нормативный стандарт (ГОСТ / ТУ / ОСТ)
  final String? standard;

  /// Марка стали (материал), например: "Сталь 20", "09Г2С", "12Х18Н10Т"
  final String material;

  /// Тип сварного соединения по ГОСТ 16037
  final WeldType weldType;

  /// Разрезает ли деталь магистральную трубу (true для тройников, false для прямых врезок)
  final bool cutsMainPipe;

  /// Номинальное давление PN/Ру (для фланцев и арматуры, например 16 или 25 бар)
  final int pressurePn;

  /// Для фланцев: true = ответная фланцевая пара с прокладкой, false = одиночный фланец
  final bool isFlangePair;

  /// Режим фланцевого соединения (к оборудованию, межтрубное, заглушка)
  final FlangeConnectionType flangeConnectionType;

  /// Явное пользовательское переопределение количества сварных стыков
  final int? customWeldCount;

  /// Строительная длина детали L (мм)
  final double? buildingLengthMm;

  /// Высота / вылет ответвления H (мм) для тройника
  final double? branchLengthMm;

  /// Пользовательский радиус гиба (мм) для отвода
  final double? customRadiusMm;

  /// Угол пространственного поворота детали вокруг оси трубы в градусах (0..360°)
  final double rotationAngleDeg;

  /// Разворот привалочной плоскости (зеркала) фланца на 180° вдоль оси трубы
  final bool isFlipped;

  /// Заводской номер или номер партии/плавки детали
  final String? serialNumber;

  const Fitting({
    required this.id,
    required this.nodeId,
    required this.fittingType,
    required this.dn,
    this.dnSecondary,
    required this.radiusMm,
    this.definitionId,
    this.name,
    this.standard,
    this.material = 'Сталь 20',
    this.weldType = WeldType.c17,
    this.cutsMainPipe = true,
    this.pressurePn = 16,
    this.isFlangePair = true,
    this.flangeConnectionType = FlangeConnectionType.toEquipment,
    this.customWeldCount,
    this.buildingLengthMm,
    this.branchLengthMm,
    this.customRadiusMm,
    this.rotationAngleDeg = 0.0,
    this.isFlipped = false,
    this.serialNumber,
  });

  /// Отображаемое имя фитинга
  String get displayName => name ?? fittingType.displayName;

  /// Эффективный радиус гиба с учетом переопределения
  double get effectiveRadiusMm => customRadiusMm ?? radiusMm;

  /// Эффективная строительная длина L (мм) с учетом типа и диаметров
  double get effectiveBuildingLengthMm {
    if (buildingLengthMm != null && buildingLengthMm! > 0) {
      return buildingLengthMm!;
    }
    switch (fittingType) {
      case FittingType.reducerConcentric:
      case FittingType.reducerEccentric:
        return math.max(80.0, dn * 1.5);
      case FittingType.tee:
        return math.max(100.0, dn * 2.0);
      case FittingType.cross:
        return math.max(120.0, dn * 2.2);
      case FittingType.flange:
        return isFlangePair ? 32.0 : 16.0;
      case FittingType.cap:
        return math.max(40.0, dn * 0.4);
      case FittingType.elbow90:
      case FittingType.elbow45:
      case FittingType.directBranch:
        return 0.0;
    }
  }

  /// Эффективная высота/вылет патрубка ответвления H (мм) для тройника
  double get effectiveBranchLengthMm {
    if (branchLengthMm != null && branchLengthMm! > 0) {
      return branchLengthMm!;
    }
    if (buildingLengthMm != null && buildingLengthMm! > 0) {
      return buildingLengthMm! / 2.0;
    }
    return dn * 1.0;
  }

  /// Расчетное количество сварных стыков
  int get effectiveWeldCount {
    if (customWeldCount != null) return customWeldCount!;
    switch (fittingType) {
      case FittingType.elbow90:
      case FittingType.elbow45:
        return 2;
      case FittingType.tee:
        return 3;
      case FittingType.cross:
        return 4;
      case FittingType.directBranch:
        return 1;
      case FittingType.reducerConcentric:
      case FittingType.reducerEccentric:
        return 2;
      case FittingType.flange:
        return flangeConnectionType.defaultWeldCount;
      case FittingType.cap:
        return 1;
    }
  }

  Fitting copyWith({
    String? id,
    String? nodeId,
    FittingType? fittingType,
    int? dn,
    int? dnSecondary,
    double? radiusMm,
    String? definitionId,
    String? name,
    String? standard,
    String? material,
    WeldType? weldType,
    bool? cutsMainPipe,
    int? pressurePn,
    bool? isFlangePair,
    FlangeConnectionType? flangeConnectionType,
    int? customWeldCount,
    double? buildingLengthMm,
    double? branchLengthMm,
    double? customRadiusMm,
    double? rotationAngleDeg,
    bool? isFlipped,
    String? serialNumber,
    bool clearSerialNumber = false,
  }) {
    return Fitting(
      id: id ?? this.id,
      nodeId: nodeId ?? this.nodeId,
      fittingType: fittingType ?? this.fittingType,
      dn: dn ?? this.dn,
      dnSecondary: dnSecondary ?? this.dnSecondary,
      radiusMm: radiusMm ?? this.radiusMm,
      definitionId: definitionId ?? this.definitionId,
      name: name ?? this.name,
      standard: standard ?? this.standard,
      material: material ?? this.material,
      weldType: weldType ?? this.weldType,
      cutsMainPipe: cutsMainPipe ?? this.cutsMainPipe,
      pressurePn: pressurePn ?? this.pressurePn,
      isFlangePair: isFlangePair ?? this.isFlangePair,
      flangeConnectionType: flangeConnectionType ?? this.flangeConnectionType,
      customWeldCount: customWeldCount ?? this.customWeldCount,
      buildingLengthMm: buildingLengthMm ?? this.buildingLengthMm,
      branchLengthMm: branchLengthMm ?? this.branchLengthMm,
      customRadiusMm: customRadiusMm ?? this.customRadiusMm,
      rotationAngleDeg: rotationAngleDeg ?? this.rotationAngleDeg,
      isFlipped: isFlipped ?? this.isFlipped,
      serialNumber: clearSerialNumber ? null : (serialNumber ?? this.serialNumber),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nodeId': nodeId,
        'fittingType': fittingType.index,
        'dn': dn,
        if (dnSecondary != null) 'dnSecondary': dnSecondary,
        'radiusMm': radiusMm,
        if (definitionId != null) 'definitionId': definitionId,
        if (name != null) 'name': name,
        if (standard != null) 'standard': standard,
        'material': material,
        'weldType': weldType.index,
        'cutsMainPipe': cutsMainPipe,
        'pressurePn': pressurePn,
        'isFlangePair': isFlangePair,
        'flangeConnectionType': flangeConnectionType.index,
        if (customWeldCount != null) 'customWeldCount': customWeldCount,
        if (buildingLengthMm != null) 'buildingLengthMm': buildingLengthMm,
        if (branchLengthMm != null) 'branchLengthMm': branchLengthMm,
        if (customRadiusMm != null) 'customRadiusMm': customRadiusMm,
        if (rotationAngleDeg != 0.0) 'rotationAngleDeg': rotationAngleDeg,
        if (isFlipped) 'isFlipped': true,
        if (serialNumber != null) 'serialNumber': serialNumber,
      };

  factory Fitting.fromJson(Map<String, dynamic> json) {
    FlangeConnectionType fcType = FlangeConnectionType.toEquipment;
    if (json.containsKey('flangeConnectionType')) {
      fcType = FlangeConnectionType.values[(json['flangeConnectionType'] as int).clamp(0, FlangeConnectionType.values.length - 1)];
    } else if (json['isFlangePair'] == true) {
      fcType = FlangeConnectionType.pipeToPipe;
    }

    return Fitting(
      id: json['id'] as String,
      nodeId: json['nodeId'] as String,
      fittingType: FittingType.values[json['fittingType'] as int? ?? 0],
      dn: json['dn'] as int,
      dnSecondary: json['dnSecondary'] as int?,
      radiusMm: (json['radiusMm'] as num).toDouble(),
      definitionId: json['definitionId'] as String?,
      name: json['name'] as String?,
      standard: json['standard'] as String?,
      material: json['material'] as String? ?? 'Сталь 20',
      weldType: WeldType.values[json['weldType'] as int? ?? 0],
      cutsMainPipe: json['cutsMainPipe'] as bool? ?? true,
      pressurePn: json['pressurePn'] as int? ?? 16,
      isFlangePair: json['isFlangePair'] as bool? ?? true,
      flangeConnectionType: fcType,
      customWeldCount: json['customWeldCount'] as int?,
      buildingLengthMm: (json['buildingLengthMm'] as num?)?.toDouble(),
      branchLengthMm: (json['branchLengthMm'] as num?)?.toDouble(),
      customRadiusMm: (json['customRadiusMm'] as num?)?.toDouble(),
      rotationAngleDeg: (json['rotationAngleDeg'] as num?)?.toDouble() ?? 0.0,
      isFlipped: json['isFlipped'] as bool? ?? false,
      serialNumber: json['serialNumber'] as String?,
    );
  }
}
