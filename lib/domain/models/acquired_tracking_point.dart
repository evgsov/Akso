import 'package:flutter/material.dart';
import 'node_3d.dart';

class AcquiredTrackingPoint {
  final Node3D worldPoint;
  final Offset screenPoint;
  final String? nodeId;
  final String? segmentId;
  final DateTime acquiredAt;

  const AcquiredTrackingPoint({
    required this.worldPoint,
    required this.screenPoint,
    this.nodeId,
    this.segmentId,
    required this.acquiredAt,
  });
}
