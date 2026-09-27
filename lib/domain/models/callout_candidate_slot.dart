import 'dart:ui';

/// Геометрический кандидат (слот) положения выноски на листе бумаги (в мм)
class CalloutCandidateSlot {
  /// Точка привязки к объекту на листе (анкер) в мм
  final Offset anchor;

  /// Точка излома (начало горизонтальной полочки) в мм
  final Offset entryShelf;

  /// Конец горизонтальной полочки в мм
  final Offset shelfEnd;

  /// Направление полочки (true = вправо, false = влево)
  final bool isRight;

  /// Габаритный прямоугольник всей выноски (полочка, текст сверху и снизу + зазор) в мм
  final Rect boundingBox;

  /// Длина наклонной линии-выноски (ножки) в мм
  final double radius;

  /// Угол наклона ножки в радианах
  final double angleRad;

  /// Локальная статическая стоимость (дальность, отклонение от 45°, направление трубы)
  final double localStaticCost;

  const CalloutCandidateSlot({
    required this.anchor,
    required this.entryShelf,
    required this.shelfEnd,
    required this.isRight,
    required this.boundingBox,
    required this.radius,
    required this.angleRad,
    required this.localStaticCost,
  });

  @override
  String toString() =>
      'CalloutCandidateSlot(r: ${radius.toStringAsFixed(1)}, angle: ${(angleRad * 180 / 3.14159).toStringAsFixed(0)}°, isRight: $isRight, cost: ${localStaticCost.toStringAsFixed(1)})';
}
