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
      );
}
