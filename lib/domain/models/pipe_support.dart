import 'node_3d.dart';

/// Тип опоры или подвески трубопровода
enum PipeSupportType {
  /// Неподвижная опора (фиксирует трубу от всех перемещений)
  fixed('Неподвижная', 'НО'),

  /// Скользящая опора (допускает продольные перемещения при тепловом расширении)
  sliding('Скользящая', 'ОП'),

  /// Пружинная подвеска или опора (компенсирует вертикальные перемещения)
  spring('Пружинная', 'ПП'),

  /// Направляющая опора (допускает только осевое перемещение, ограничивая боковые)
  guide('Направляющая', 'ОН');

  final String displayName;
  final String shortCode;

  const PipeSupportType(this.displayName, this.shortCode);
}

/// Опора или подвеска, привязанная к участку трубопровода
class PipeSupport {
  final String id;
  final String segmentId;
  final PipeSupportType type;

  /// Относительная позиция вдоль сегмента трубы (от 0.0 до 1.0)
  final double distanceRatio;

  /// Маркировка или наименование опоры (напр. "ОП-1", "НО-2")
  final String name;

  const PipeSupport({
    required this.id,
    required this.segmentId,
    required this.distanceRatio,
    this.type = PipeSupportType.sliding,
    this.name = '',
  });

  /// Вычисление 3D координат центра опоры в пространстве
  Node3D calculatePosition(Node3D startNode, Node3D endNode) {
    final clampedRatio = distanceRatio.clamp(0.0, 1.0);
    final x = startNode.x + (endNode.x - startNode.x) * clampedRatio;
    final y = startNode.y + (endNode.y - startNode.y) * clampedRatio;
    final z = startNode.z + (endNode.z - startNode.z) * clampedRatio;
    return Node3D(id: 'support_pos_$id', x: x, y: y, z: z);
  }

  PipeSupport copyWith({
    String? id,
    String? segmentId,
    PipeSupportType? type,
    double? distanceRatio,
    String? name,
  }) {
    return PipeSupport(
      id: id ?? this.id,
      segmentId: segmentId ?? this.segmentId,
      type: type ?? this.type,
      distanceRatio: distanceRatio ?? this.distanceRatio,
      name: name ?? this.name,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'segmentId': segmentId,
        'type': type.index,
        'distanceRatio': distanceRatio,
        'name': name,
      };

  factory PipeSupport.fromJson(Map<String, dynamic> json) {
    final typeIndex = json['type'] as int? ?? 1;
    final supportType = (typeIndex >= 0 && typeIndex < PipeSupportType.values.length)
        ? PipeSupportType.values[typeIndex]
        : PipeSupportType.sliding;

    return PipeSupport(
      id: json['id'] as String,
      segmentId: json['segmentId'] as String,
      distanceRatio: (json['distanceRatio'] as num).toDouble(),
      type: supportType,
      name: json['name'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PipeSupport &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          segmentId == other.segmentId &&
          type == other.type &&
          distanceRatio == other.distanceRatio &&
          name == other.name;

  @override
  int get hashCode => Object.hash(id, segmentId, type, distanceRatio, name);

  @override
  String toString() =>
      'PipeSupport(id: $id, segmentId: $segmentId, type: ${type.name}, ratio: $distanceRatio, name: $name)';
}
