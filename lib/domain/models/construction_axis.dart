import 'dart:ui';
import 'node_3d.dart';

/// Строительная ось здания или вспомогательная направляющая линия
class ConstructionAxis {
  final String id;
  final String label; // "1", "2", "А", "Б"
  final Node3D startPoint;
  final Node3D endPoint;
  final bool isBuildingGrid; // true - ось здания с кружками марок по ГОСТ 21.101

  // Revit-style свойства
  final bool showStartBubble;      // Видимость кружка марки в начале (End 1)
  final bool showEndBubble;        // Видимость кружка марки в конце (End 2)
  final double elevationZ;         // Отметка высоты рабочей плоскости оси
  final Offset? startElbowOffset;  // Смещение излома марки в начале (dx, dy)
  final Offset? endElbowOffset;    // Смещение излома марки в конце (dx, dy)
  final bool isPinned;             // Фиксация от случайного сдвига
  final bool is3dPlaneOriented;    // true: лежачая в 3D плоскости XY, false: 2D к экрану
  final bool isStartLocked;        // Замок цепочки выравнивания в начале
  final bool isEndLocked;          // Замок цепочки выравнивания в конце

  const ConstructionAxis({
    required this.id,
    required this.label,
    required this.startPoint,
    required this.endPoint,
    this.isBuildingGrid = true,
    this.showStartBubble = true,
    this.showEndBubble = false,
    this.elevationZ = 0.0,
    this.startElbowOffset,
    this.endElbowOffset,
    this.isPinned = false,
    this.is3dPlaneOriented = true,
    this.isStartLocked = true,
    this.isEndLocked = true,
  });

  ConstructionAxis copyWith({
    String? id,
    String? label,
    Node3D? startPoint,
    Node3D? endPoint,
    bool? isBuildingGrid,
    bool? showStartBubble,
    bool? showEndBubble,
    double? elevationZ,
    Offset? startElbowOffset,
    Offset? endElbowOffset,
    bool? isPinned,
    bool? is3dPlaneOriented,
    bool? isStartLocked,
    bool? isEndLocked,
    bool clearStartElbow = false,
    bool clearEndElbow = false,
  }) {
    return ConstructionAxis(
      id: id ?? this.id,
      label: label ?? this.label,
      startPoint: startPoint ?? this.startPoint,
      endPoint: endPoint ?? this.endPoint,
      isBuildingGrid: isBuildingGrid ?? this.isBuildingGrid,
      showStartBubble: showStartBubble ?? this.showStartBubble,
      showEndBubble: showEndBubble ?? this.showEndBubble,
      elevationZ: elevationZ ?? this.elevationZ,
      startElbowOffset: clearStartElbow ? null : (startElbowOffset ?? this.startElbowOffset),
      endElbowOffset: clearEndElbow ? null : (endElbowOffset ?? this.endElbowOffset),
      isPinned: isPinned ?? this.isPinned,
      is3dPlaneOriented: is3dPlaneOriented ?? this.is3dPlaneOriented,
      isStartLocked: isStartLocked ?? this.isStartLocked,
      isEndLocked: isEndLocked ?? this.isEndLocked,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'startPoint': startPoint.toJson(),
        'endPoint': endPoint.toJson(),
        'isBuildingGrid': isBuildingGrid,
        'showStartBubble': showStartBubble,
        'showEndBubble': showEndBubble,
        'elevationZ': elevationZ,
        if (startElbowOffset != null)
          'startElbowOffset': {'dx': startElbowOffset!.dx, 'dy': startElbowOffset!.dy},
        if (endElbowOffset != null)
          'endElbowOffset': {'dx': endElbowOffset!.dx, 'dy': endElbowOffset!.dy},
        'isPinned': isPinned,
        'is3dPlaneOriented': is3dPlaneOriented,
        'isStartLocked': isStartLocked,
        'isEndLocked': isEndLocked,
      };

  factory ConstructionAxis.fromJson(Map<String, dynamic> json) => ConstructionAxis(
        id: json['id'] as String,
        label: json['label'] as String,
        startPoint: Node3D.fromJson(json['startPoint'] as Map<String, dynamic>),
        endPoint: Node3D.fromJson(json['endPoint'] as Map<String, dynamic>),
        isBuildingGrid: json['isBuildingGrid'] as bool? ?? true,
        showStartBubble: json['showStartBubble'] as bool? ?? true,
        showEndBubble: json['showEndBubble'] as bool? ?? false,
        elevationZ: (json['elevationZ'] as num?)?.toDouble() ?? 0.0,
        startElbowOffset: json['startElbowOffset'] != null
            ? Offset(
                (json['startElbowOffset']['dx'] as num).toDouble(),
                (json['startElbowOffset']['dy'] as num).toDouble(),
              )
            : null,
        endElbowOffset: json['endElbowOffset'] != null
            ? Offset(
                (json['endElbowOffset']['dx'] as num).toDouble(),
                (json['endElbowOffset']['dy'] as num).toDouble(),
              )
            : null,
        isPinned: json['isPinned'] as bool? ?? false,
        is3dPlaneOriented: json['is3dPlaneOriented'] as bool? ?? true,
        isStartLocked: json['isStartLocked'] as bool? ?? true,
        isEndLocked: json['isEndLocked'] as bool? ?? true,
      );
}
