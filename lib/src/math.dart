import 'dart:math' as math;

/// Lightweight 3D vector for pure-Dart room acoustics math.
final class ReverbVec3 {
  final double x;
  final double y;
  final double z;

  const ReverbVec3(this.x, this.y, this.z);

  static const zero = ReverbVec3(0.0, 0.0, 0.0);

  ReverbVec3 operator +(ReverbVec3 o) => ReverbVec3(x + o.x, y + o.y, z + o.z);
  ReverbVec3 operator -(ReverbVec3 o) => ReverbVec3(x - o.x, y - o.y, z - o.z);
  ReverbVec3 operator *(double s) => ReverbVec3(x * s, y * s, z * s);

  double get lengthSquared => x * x + y * y + z * z;
  double get length => math.sqrt(lengthSquared);

  ReverbVec3 get normalized {
    final l = length;
    return l > 1e-9 ? ReverbVec3(x / l, y / l, z / l) : zero;
  }

  double distanceTo(ReverbVec3 o) => (this - o).length;
}

/// Axis-aligned bounding volume used to model enclosed acoustic rooms.
final class ReverbAabb {
  final ReverbVec3 min;
  final ReverbVec3 max;

  const ReverbAabb(this.min, this.max);

  double get width => math.max(0.0, max.x - min.x);
  double get height => math.max(0.0, max.y - min.y);
  double get depth => math.max(0.0, max.z - min.z);

  double get volume => width * height * depth;
  double get surfaceArea => 2.0 * (width * height + height * depth + width * depth);

  ReverbVec3 get center => ReverbVec3(
        (min.x + max.x) * 0.5,
        (min.y + max.y) * 0.5,
        (min.z + max.z) * 0.5,
      );

  bool contains(ReverbVec3 p) =>
      p.x >= min.x &&
      p.x <= max.x &&
      p.y >= min.y &&
      p.y <= max.y &&
      p.z >= min.z &&
      p.z <= max.z;

  ReverbVec3 closestPoint(ReverbVec3 p) => ReverbVec3(
        p.x.clamp(min.x, max.x).toDouble(),
        p.y.clamp(min.y, max.y).toDouble(),
        p.z.clamp(min.z, max.z).toDouble(),
      );
}
