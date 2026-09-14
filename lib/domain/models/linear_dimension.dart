import 'node_3d.dart';

/// Линейный размер по ГОСТ 2.307 / СПДС (выносные линии, размерная линия, засечки, размерный текст)
class LinearDimension {
  final String id;
  final String? startNodeId;
  final String? endNodeId;
  final Node3D startPoint;
  final Node3D endPoint;

  /// Смещение размерной линии от измеряемого отрезка
  final double offsetDistance;

  /// Произвольный пользовательский текст (если задан, отображается вместо расчетной длины)
  final String? customText;

  const LinearDimension({
    required this.id,
    required this.startPoint,
    required this.endPoint,
    this.startNodeId,
    this.endNodeId,
    this.offsetDistance = 40.0,
    this.customText,
  });

  /// Реальная 3D-длина между точками
  double get measuredLength => startPoint.distanceTo(endPoint);

  /// Отображаемый текст размера (в миллиметрах)
  String get displayText => (customText != null && customText!.trim().isNotEmpty)
      ? customText!
      : '${measuredLength.round()}';

  LinearDimension copyWith({
    String? id,
    Node3D? startPoint,
    Node3D? endPoint,
    String? startNodeId,
    String? endNodeId,
    double? offsetDistance,
    String? customText,
  }) {
    return LinearDimension(
      id: id ?? this.id,
      startPoint: startPoint ?? this.startPoint,
      endPoint: endPoint ?? this.endPoint,
      startNodeId: startNodeId ?? this.startNodeId,
      endNodeId: endNodeId ?? this.endNodeId,
      offsetDistance: offsetDistance ?? this.offsetDistance,
      customText: customText ?? this.customText,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'startPoint': startPoint.toJson(),
        'endPoint': endPoint.toJson(),
        if (startNodeId != null) 'startNodeId': startNodeId,
        if (endNodeId != null) 'endNodeId': endNodeId,
        'offsetDistance': offsetDistance,
        if (customText != null) 'customText': customText,
      };

  factory LinearDimension.fromJson(Map<String, dynamic> json) => LinearDimension(
        id: json['id'] as String,
        startPoint: Node3D.fromJson(json['startPoint'] as Map<String, dynamic>),
        endPoint: Node3D.fromJson(json['endPoint'] as Map<String, dynamic>),
        startNodeId: json['startNodeId'] as String?,
        endNodeId: json['endNodeId'] as String?,
        offsetDistance: (json['offsetDistance'] as num?)?.toDouble() ?? 40.0,
        customText: json['customText'] as String?,
      );
}
