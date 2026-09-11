import '../enums/valve_type.dart';
import 'node_3d.dart';

/// Трубопроводная арматура, установленная на участке трубы
class Valve {
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
  });

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
      };

  factory Valve.fromJson(Map<String, dynamic> json) => Valve(
        id: json['id'] as String,
        segmentId: json['segmentId'] as String,
        ratio: (json['ratio'] as num).toDouble(),
        valveType: ValveType.values[json['valveType'] as int? ?? 0],
        name: json['name'] as String,
        dn: json['dn'] as int,
        lengthMm: (json['lengthMm'] as num).toDouble(),
        handleAngleDeg: (json['handleAngleDeg'] as num?)?.toDouble() ?? 90.0,
        isReversed: json['isReversed'] as bool? ?? false,
        isFlanged: json['isFlanged'] as bool? ?? false,
      );
}
