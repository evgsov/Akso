import 'dart:math' as math;
import '../../domain/models/node_3d.dart';

/// 3D вектор для математических и пространственных расчетов CAD-геометрии
class Vector3D {
  final double x;
  final double y;
  final double z;

  const Vector3D(this.x, this.y, this.z);

  factory Vector3D.fromNode(Node3D n) => Vector3D(n.x, n.y, n.z);

  Vector3D operator +(Vector3D o) => Vector3D(x + o.x, y + o.y, z + o.z);
  Vector3D operator -(Vector3D o) => Vector3D(x - o.x, y - o.y, z - o.z);
  Vector3D operator -() => Vector3D(-x, -y, -z);
  Vector3D operator *(double s) => Vector3D(x * s, y * s, z * s);
  Vector3D operator /(double s) => Vector3D(x / s, y / s, z / s);

  double dot(Vector3D o) => x * o.x + y * o.y + z * o.z;

  Vector3D cross(Vector3D o) => Vector3D(
        y * o.z - z * o.y,
        z * o.x - x * o.z,
        x * o.y - y * o.x,
      );

  double get length => math.sqrt(x * x + y * y + z * z);

  Vector3D normalized() {
    final l = length;
    if (l < 1e-9) return const Vector3D(0, 0, 1);
    return this / l;
  }

  Node3D toNode({String id = ''}) => Node3D(id: id, x: x, y: y, z: z);
}
