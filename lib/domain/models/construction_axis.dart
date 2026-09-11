import 'node_3d.dart';

/// Строительная ось здания или вспомогательная направляющая линия
class ConstructionAxis {
  final String id;
  final String label; // "1", "2", "А", "Б"
  final Node3D startPoint;
  final Node3D endPoint;
  final bool isBuildingGrid; // true - ось здания с кружками марок по ГОСТ 21.101

  const ConstructionAxis({
    required this.id,
    required this.label,
    required this.startPoint,
    required this.endPoint,
    this.isBuildingGrid = true,
  });

  ConstructionAxis copyWith({
    String? id,
    String? label,
    Node3D? startPoint,
    Node3D? endPoint,
    bool? isBuildingGrid,
  }) {
    return ConstructionAxis(
      id: id ?? this.id,
      label: label ?? this.label,
      startPoint: startPoint ?? this.startPoint,
      endPoint: endPoint ?? this.endPoint,
      isBuildingGrid: isBuildingGrid ?? this.isBuildingGrid,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'startPoint': startPoint.toJson(),
        'endPoint': endPoint.toJson(),
        'isBuildingGrid': isBuildingGrid,
      };

  factory ConstructionAxis.fromJson(Map<String, dynamic> json) => ConstructionAxis(
        id: json['id'] as String,
        label: json['label'] as String,
        startPoint: Node3D.fromJson(json['startPoint'] as Map<String, dynamic>),
        endPoint: Node3D.fromJson(json['endPoint'] as Map<String, dynamic>),
        isBuildingGrid: json['isBuildingGrid'] as bool? ?? true,
      );
}
