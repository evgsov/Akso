/// Стиль визуального отображения сварного стыка на чертеже и в 3D
enum WeldJointStyle {
  /// Классическая перпендикулярная риска по ГОСТ 21.602 / СПДС
  tick('Засечка ГОСТ'),

  /// Пространственный проволочный валик (3D-кольцо вокруг трубы)
  ring3d('3D-кольцо'),

  /// Окружность (обозначение монтажного стыка в изометрии)
  circle('Кружок'),

  /// Компактная залитая точка
  dot('Точка');

  final String label;
  const WeldJointStyle(this.label);

  static WeldJointStyle fromString(String? val) {
    if (val == null) return WeldJointStyle.tick;
    return WeldJointStyle.values.firstWhere(
      (s) => s.name.toLowerCase() == val.toLowerCase() || s.label.toLowerCase() == val.toLowerCase(),
      orElse: () => WeldJointStyle.tick,
    );
  }
}
