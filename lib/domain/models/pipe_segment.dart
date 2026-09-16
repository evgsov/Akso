import 'dart:math' as math;
import 'node_3d.dart';

/// Отрезок трубы между двумя узлами топологического графа сети
class PipeSegment {
  final String id;
  final String startNodeId;
  final String endNodeId;
  final String systemId;

  /// Номинальный диаметр (условный проход) DN (мм)
  final int dn;

  /// Наружный диаметр трубы (мм)
  final double outerDiameterMm;

  /// Толщина стенки трубы S (мм)
  final double wallThicknessMm;

  /// Заданный уклон трубы (i = h / L, например 0.002 или 0.02). 0.0 если без уклона
  final double slope;

  /// Марка стали / материал трубы (например, "Сталь 20", "09Г2С", "12Х18Н10Т", "ППУ-ПЭ")
  final String material;

  /// Пользовательское наименование / маркировка участка трубы (например, "Т1-1")
  final String? name;

  /// Заводской номер трубы или номер партии/плавки (актуально для тех. трубопроводов и от Ду500)
  final String? serialNumber;

  const PipeSegment({
    required this.id,
    required this.startNodeId,
    required this.endNodeId,
    required this.systemId,
    required this.dn,
    double? outerDiameterMm,
    this.wallThicknessMm = 3.5,
    this.slope = 0.0,
    this.material = 'Сталь 20',
    this.name,
    this.serialNumber,
  }) : outerDiameterMm = outerDiameterMm ??
            (dn == 15
                ? 21.3
                : dn == 20
                    ? 26.8
                    : dn == 25
                        ? 32.0
                        : dn == 32
                            ? 38.0
                            : dn == 40
                                ? 45.0
                                : dn == 50
                                    ? 57.0
                                    : dn == 65
                                        ? 76.0
                                        : dn == 80
                                            ? 89.0
                                            : dn == 100
                                                ? 108.0
                                                : dn == 125
                                                    ? 133.0
                                                    : dn == 150
                                                        ? 159.0
                                                        : dn == 200
                                                            ? 219.0
                                                            : dn == 250
                                                                ? 273.0
                                                                : dn == 300
                                                                    ? 325.0
                                                                    : dn == 350
                                                                        ? 377.0
                                                                        : dn == 400
                                                                            ? 426.0
                                                                            : dn == 500
                                                                                ? 530.0
                                                                                : dn == 600
                                                                                    ? 630.0
                                                                                    : dn == 700
                                                                                        ? 720.0
                                                                                        : dn == 800
                                                                                            ? 820.0
                                                                                            : dn == 1000
                                                                                                ? 1020.0
                                                                                                : dn == 1200
                                                                                                    ? 1220.0
                                                                                                    : dn == 1400
                                                                                                        ? 1420.0
                                                                                                        : (dn <= 50 ? (dn * 1.25 + 5.0) : (dn * 1.08)));

  /// Форматированное обозначение трубы (например, "⌀159×4.5 (Ду150)")
  String get formattedSize {
    final dStr = outerDiameterMm.truncateToDouble() == outerDiameterMm
        ? outerDiameterMm.toStringAsFixed(0)
        : outerDiameterMm.toStringAsFixed(1);
    final sStr = wallThicknessMm.truncateToDouble() == wallThicknessMm
        ? wallThicknessMm.toStringAsFixed(0)
        : wallThicknessMm.toStringAsFixed(1);
    return '⌀$dStr×$sStr (Ду$dn)';
  }

  /// Краткая выноска размера трубы (например, "⌀159×4.5")
  String get shortCallout {
    final dStr = outerDiameterMm.truncateToDouble() == outerDiameterMm
        ? outerDiameterMm.toStringAsFixed(0)
        : outerDiameterMm.toStringAsFixed(1);
    final sStr = wallThicknessMm.truncateToDouble() == wallThicknessMm
        ? wallThicknessMm.toStringAsFixed(0)
        : wallThicknessMm.toStringAsFixed(1);
    return '⌀$dStr×$sStr';
  }

  /// Длина оси трубы между узлами (мм)
  double calculateLength(Node3D start, Node3D end) {
    return start.distanceTo(end);
  }

  /// Является ли участок вертикальным стояком (опуском/подъемом)
  bool isVertical(Node3D start, Node3D end) {
    final dx = (end.x - start.x).abs();
    final dy = (end.y - start.y).abs();
    final dz = (end.z - start.z).abs();
    return dx < 1.0 && dy < 1.0 && dz > 1.0;
  }

  /// Автоматический расчет уклона по разнице отметок Z и горизонтальной длине
  double calculateActualSlope(Node3D start, Node3D end) {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final horizontalDist = math.sqrt(dx * dx + dy * dy);
    if (horizontalDist < 1.0) return 0.0;
    return (end.z - start.z).abs() / horizontalDist;
  }

  PipeSegment copyWith({
    String? id,
    String? startNodeId,
    String? endNodeId,
    String? systemId,
    int? dn,
    double? outerDiameterMm,
    double? wallThicknessMm,
    double? slope,
    String? material,
    String? name,
    String? serialNumber,
    bool clearName = false,
    bool clearSerialNumber = false,
  }) {
    return PipeSegment(
      id: id ?? this.id,
      startNodeId: startNodeId ?? this.startNodeId,
      endNodeId: endNodeId ?? this.endNodeId,
      systemId: systemId ?? this.systemId,
      dn: dn ?? this.dn,
      outerDiameterMm: outerDiameterMm ??
          (dn != null && dn != this.dn ? null : this.outerDiameterMm),
      wallThicknessMm: wallThicknessMm ?? this.wallThicknessMm,
      slope: slope ?? this.slope,
      material: material ?? this.material,
      name: clearName ? null : (name ?? this.name),
      serialNumber: clearSerialNumber ? null : (serialNumber ?? this.serialNumber),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'startNodeId': startNodeId,
        'endNodeId': endNodeId,
        'systemId': systemId,
        'dn': dn,
        'outerDiameterMm': outerDiameterMm,
        'wallThicknessMm': wallThicknessMm,
        'slope': slope,
        'material': material,
        if (name != null) 'name': name,
        if (serialNumber != null) 'serialNumber': serialNumber,
      };

  factory PipeSegment.fromJson(Map<String, dynamic> json) => PipeSegment(
        id: json['id'] as String,
        startNodeId: json['startNodeId'] as String,
        endNodeId: json['endNodeId'] as String,
        systemId: json['systemId'] as String,
        dn: json['dn'] as int,
        outerDiameterMm: (json['outerDiameterMm'] as num).toDouble(),
        wallThicknessMm: (json['wallThicknessMm'] as num?)?.toDouble() ?? 3.5,
        slope: (json['slope'] as num?)?.toDouble() ?? 0.0,
        material: json['material'] as String? ?? 'Сталь 20',
        name: json['name'] as String?,
        serialNumber: json['serialNumber'] as String?,
      );
}
