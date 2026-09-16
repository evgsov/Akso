import 'node_3d.dart';

/// Катушка (заготовка прямолинейного участка трубы между швами/фитингами)
class PipeSpool {
  final String id;
  final String segmentId;

  /// Номер / марка катушки на схеме (например, "К-1", "К-2", "Уч-1")
  final String number;

  /// Фактическая строительная длина реза заготовки (мм) с вычетом арматуры и зазоров
  final double cutLengthMm;

  /// Диаметр условный DN
  final int dn;

  /// Толщина стенки S (мм)
  final double wallThickness;

  /// Марка материала / ГОСТ трубы (например, "Сталь 20 ГОСТ 10704-91")
  final String material;

  /// ID начального сварного шва или фитинга
  final String? startWeldId;

  /// ID конечного сварного шва или фитинга
  final String? endWeldId;

  /// Точная 3D точка начала катушки (после вычета фитингов/арматуры/швов)
  final Node3D? startPoint;

  /// Точная 3D точка конца катушки
  final Node3D? endPoint;

  /// Маркировка / название катушки (например, "Линия Т1-1 / Катушка 1")
  final String? name;

  /// Заводской номер / номер плавки/партии
  final String? serialNumber;

  const PipeSpool({
    required this.id,
    required this.segmentId,
    required this.number,
    required this.cutLengthMm,
    required this.dn,
    this.wallThickness = 3.5,
    this.material = 'Сталь 20 ГОСТ 10704',
    this.startWeldId,
    this.endWeldId,
    this.startPoint,
    this.endPoint,
    this.name,
    this.serialNumber,
  });

  PipeSpool copyWith({
    String? id,
    String? segmentId,
    String? number,
    double? cutLengthMm,
    int? dn,
    double? wallThickness,
    String? material,
    String? startWeldId,
    String? endWeldId,
    Node3D? startPoint,
    Node3D? endPoint,
    String? name,
    bool clearName = false,
    String? serialNumber,
    bool clearSerialNumber = false,
  }) {
    return PipeSpool(
      id: id ?? this.id,
      segmentId: segmentId ?? this.segmentId,
      number: number ?? this.number,
      cutLengthMm: cutLengthMm ?? this.cutLengthMm,
      dn: dn ?? this.dn,
      wallThickness: wallThickness ?? this.wallThickness,
      material: material ?? this.material,
      startWeldId: startWeldId ?? this.startWeldId,
      endWeldId: endWeldId ?? this.endWeldId,
      startPoint: startPoint ?? this.startPoint,
      endPoint: endPoint ?? this.endPoint,
      name: clearName ? null : (name ?? this.name),
      serialNumber: clearSerialNumber ? null : (serialNumber ?? this.serialNumber),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'segmentId': segmentId,
        'number': number,
        'cutLengthMm': cutLengthMm,
        'dn': dn,
        'wallThickness': wallThickness,
        'material': material,
        if (startWeldId != null) 'startWeldId': startWeldId,
        if (endWeldId != null) 'endWeldId': endWeldId,
        if (startPoint != null) 'startPoint': startPoint!.toJson(),
        if (endPoint != null) 'endPoint': endPoint!.toJson(),
        if (name != null) 'name': name,
        if (serialNumber != null) 'serialNumber': serialNumber,
      };

  factory PipeSpool.fromJson(Map<String, dynamic> json) => PipeSpool(
        id: json['id'] as String,
        segmentId: json['segmentId'] as String,
        number: json['number'] as String,
        cutLengthMm: (json['cutLengthMm'] as num).toDouble(),
        dn: json['dn'] as int,
        wallThickness: (json['wallThickness'] as num?)?.toDouble() ?? 3.5,
        material: json['material'] as String? ?? 'Сталь 20 ГОСТ 10704',
        startWeldId: json['startWeldId'] as String?,
        endWeldId: json['endWeldId'] as String?,
        startPoint: json['startPoint'] != null
            ? Node3D.fromJson(json['startPoint'] as Map<String, dynamic>)
            : null,
        endPoint: json['endPoint'] != null
            ? Node3D.fromJson(json['endPoint'] as Map<String, dynamic>)
            : null,
        name: json['name'] as String?,
        serialNumber: json['serialNumber'] as String?,
      );
}
