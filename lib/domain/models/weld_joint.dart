import '../enums/inspection_method.dart';
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

  /// Метод неразрушающего контроля
  final InspectionMethod inspectionMethod;

  /// Дата выполнения шва
  final String date;

  /// Марка стали свариваемых элементов (например, "Сталь 20", "09Г2С", "12Х18Н10Т")
  final String steelGrade;

  /// Марка сварочных материалов (например, "УОНИ 13/55", "LB-52U", "Св-08Г2С")
  final String electrodeGrade;

  /// Примечания / результат контроля ("Годен", толщина, зазор)
  final String notes;

  const WeldJoint({
    required this.id,
    required this.segmentId,
    required this.ratio,
    required this.number,
    required this.stamp,
    this.weldType = WeldType.c17,
    this.inspectionMethod = InspectionMethod.vik,
    this.date = '',
    this.steelGrade = 'Сталь 20',
    this.electrodeGrade = 'УОНИ 13/55',
    this.notes = 'Годен',
  });

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
    String? date,
    String? steelGrade,
    String? electrodeGrade,
    String? notes,
  }) {
    return WeldJoint(
      id: id ?? this.id,
      segmentId: segmentId ?? this.segmentId,
      ratio: ratio ?? this.ratio,
      number: number ?? this.number,
      stamp: stamp ?? this.stamp,
      weldType: weldType ?? this.weldType,
      inspectionMethod: inspectionMethod ?? this.inspectionMethod,
      date: date ?? this.date,
      steelGrade: steelGrade ?? this.steelGrade,
      electrodeGrade: electrodeGrade ?? this.electrodeGrade,
      notes: notes ?? this.notes,
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
        'date': date,
        'steelGrade': steelGrade,
        'electrodeGrade': electrodeGrade,
        'notes': notes,
      };

  factory WeldJoint.fromJson(Map<String, dynamic> json) => WeldJoint(
        id: json['id'] as String,
        segmentId: json['segmentId'] as String,
        ratio: (json['ratio'] as num).toDouble(),
        number: json['number'] as int,
        stamp: json['stamp'] as String,
        weldType: WeldType.values[json['weldType'] as int? ?? 0],
        inspectionMethod: InspectionMethod.values[json['inspectionMethod'] as int? ?? 0],
        date: json['date'] as String? ?? '',
        steelGrade: json['steelGrade'] as String? ?? 'Сталь 20',
        electrodeGrade: json['electrodeGrade'] as String? ?? 'УОНИ 13/55',
        notes: json['notes'] as String? ?? 'Годен',
      );
}
