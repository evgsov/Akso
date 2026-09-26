import 'package:flutter/material.dart';
import 'segment_3d.dart';
import 'callout.dart';

/// Логическая ветка (участок трассы) трубопровода между узлами ветвления/оборудованием
class PipelineBranch {
  final String id;
  final List<Segment3D> segments;
  final List<Callout> callouts;
  final Offset startSheetMm;
  final Offset endSheetMm;
  final Offset branchVector2D; // Единичный вектор направления на листе
  final Rect boundingBoxSheetMm;

  PipelineBranch({
    required this.id,
    required this.segments,
    required this.callouts,
    required this.startSheetMm,
    required this.endSheetMm,
    required this.branchVector2D,
    required this.boundingBoxSheetMm,
  });

  /// Длина проекции ветки на чертежном листе в мм
  double get lengthSheetMm => (endSheetMm - startSheetMm).distance;

  /// Единичная нормаль 1 (+90 градусов)
  Offset get normal1 => Offset(-branchVector2D.dy, branchVector2D.dx);

  /// Единичная нормаль 2 (-90 градусов)
  Offset get normal2 => Offset(branchVector2D.dy, -branchVector2D.dx);
}
