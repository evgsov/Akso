import 'dart:math' as math;

/// Пространственный узел трубопроводной сети в координатах (X, Y, Z) в миллиметрах
class Node3D {
  final String id;
  final double x;
  final double y;
  final double z;
  final String? customElevation;

  const Node3D({
    required this.id,
    required this.x,
    required this.y,
    required this.z,
    this.customElevation,
  });

  /// Вычисленная высотная отметка в метрах (например, "+2.500" или "-0.800")
  String get elevationString {
    if (customElevation != null && customElevation!.isNotEmpty) {
      return customElevation!;
    }
    final meters = z / 1000.0;
    if (meters.abs() < 0.0001) {
      return '0.000';
    }
    final sign = meters > 0 ? '+' : '';
    return '$sign${meters.toStringAsFixed(3)}';
  }

  /// Расстояние в 3D пространстве до другого узла (мм)
  double distanceTo(Node3D other) {
    final dx = other.x - x;
    final dy = other.y - y;
    final dz = other.z - z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  Node3D copyWith({
    String? id,
    double? x,
    double? y,
    double? z,
    String? customElevation,
  }) {
    return Node3D(
      id: id ?? this.id,
      x: x ?? this.x,
      y: y ?? this.y,
      z: z ?? this.z,
      customElevation: customElevation ?? this.customElevation,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': x,
        'y': y,
        'z': z,
        if (customElevation != null) 'customElevation': customElevation,
      };

  factory Node3D.fromJson(Map<String, dynamic> json) => Node3D(
        id: json['id'] as String,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        z: (json['z'] as num).toDouble(),
        customElevation: json['customElevation'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Node3D &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          x == other.x &&
          y == other.y &&
          z == other.z;

  @override
  int get hashCode => Object.hash(id, x, y, z);
}
