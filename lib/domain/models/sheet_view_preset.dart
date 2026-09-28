import 'dart:math' as math;
import '../enums/projection_type.dart';
import '../services/viewport_transform_service.dart';

/// Именованный пресет ракурса и масштаба видового экрана для чертежного листа.
/// Сохраняет ориентацию 3D-пространства (тип проекции, азимут и возвышение орбиты),
/// масштаб отображения и центр модели, позволяя мгновенно переключаться между
/// сохраненными ракурсами (например, "Общий план М 1:50", "Аксонометрия ISO 1:25", "Узел 1:10").
class SheetViewPreset {
  final String id;
  final String name;
  final DateTime createdAt;

  /// Масштаб видового экрана (например, 0.02 для 1:50, 0.04 для 1:25)
  final double viewScale;

  /// Центр проецируемой модели (мм модели)
  final double modelCenterX;
  final double modelCenterY;
  final double modelCenterZ;

  /// Тип проекции (ГОСТ 45°, Зеркальная 45°, ISO 30°, План 2D, 3D Орбита)
  final ProjectionType projectionType;

  /// Углы вращения для 3D-орбиты (в радианах)
  final double orbitAzimuth;
  final double orbitElevation;

  const SheetViewPreset({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.viewScale,
    required this.modelCenterX,
    required this.modelCenterY,
    this.modelCenterZ = 0.0,
    this.projectionType = ProjectionType.gostFrontal45,
    this.orbitAzimuth = -math.pi / 4,
    this.orbitElevation = math.pi / 6,
  });

  /// Текстовое описание масштаба (например, "М 1:50")
  String get scaleText => ViewportTransformService.formatScaleText(viewScale);

  /// Текстовое наименование типа проекции
  String get projectionTitle {
    switch (projectionType) {
      case ProjectionType.gostFrontal45:
        return 'ГОСТ 45° (Фронтальная)';
      case ProjectionType.gostMirrored45:
        return 'Зеркальная 45°';
      case ProjectionType.iso30:
        return 'ISO 30° (Изометрия)';
      case ProjectionType.topPlan2d:
        return 'План 2D';
      case ProjectionType.orbit3d:
        return '3D Орбита';
    }
  }

  SheetViewPreset copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    double? viewScale,
    double? modelCenterX,
    double? modelCenterY,
    double? modelCenterZ,
    ProjectionType? projectionType,
    double? orbitAzimuth,
    double? orbitElevation,
  }) {
    return SheetViewPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      viewScale: viewScale ?? this.viewScale,
      modelCenterX: modelCenterX ?? this.modelCenterX,
      modelCenterY: modelCenterY ?? this.modelCenterY,
      modelCenterZ: modelCenterZ ?? this.modelCenterZ,
      projectionType: projectionType ?? this.projectionType,
      orbitAzimuth: orbitAzimuth ?? this.orbitAzimuth,
      orbitElevation: orbitElevation ?? this.orbitElevation,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'viewScale': viewScale,
    'modelCenterX': modelCenterX,
    'modelCenterY': modelCenterY,
    'modelCenterZ': modelCenterZ,
    'projectionType': projectionType.name,
    'orbitAzimuth': orbitAzimuth,
    'orbitElevation': orbitElevation,
  };

  factory SheetViewPreset.fromJson(Map<String, dynamic> json) {
    return SheetViewPreset(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Пресет вида',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      viewScale: (json['viewScale'] as num?)?.toDouble() ?? 0.02,
      modelCenterX: (json['modelCenterX'] as num?)?.toDouble() ?? 0.0,
      modelCenterY: (json['modelCenterY'] as num?)?.toDouble() ?? 0.0,
      modelCenterZ: (json['modelCenterZ'] as num?)?.toDouble() ?? 0.0,
      projectionType: ProjectionType.values.firstWhere(
        (e) => e.name == json['projectionType'],
        orElse: () => ProjectionType.gostFrontal45,
      ),
      orbitAzimuth: (json['orbitAzimuth'] as num?)?.toDouble() ?? (-math.pi / 4),
      orbitElevation: (json['orbitElevation'] as num?)?.toDouble() ?? (math.pi / 6),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SheetViewPreset &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          createdAt == other.createdAt;

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ createdAt.hashCode;
}
