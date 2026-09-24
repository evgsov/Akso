/// Стиль заливки крыла (треугольника) корпуса арматуры в 2D УГО
enum ValveWingFillStyle {
  /// Контурный (белый непрозрачный фон с цветной обводкой)
  outline,

  /// Сплошная заливка цветом системы / слоя
  solid,

  /// Диагональная штриховка под 45 градусов
  hatched,

  /// Перекрестная сетчатая штриховка
  crossHatched;

  String get displayName {
    switch (this) {
      case ValveWingFillStyle.outline:
        return 'Контур';
      case ValveWingFillStyle.solid:
        return 'Сплошная заливка';
      case ValveWingFillStyle.hatched:
        return 'Штриховка 45°';
      case ValveWingFillStyle.crossHatched:
        return 'Сетка (перекрестная)';
    }
  }
}

/// Внутренний центральный разделитель / знак затвора
enum ValveDividerType {
  /// Без разделителя (вершины треугольников сходятся в точке)
  none,

  /// Вертикальная разделительная черта
  line,

  /// Зигзаг / волна (виброкомпенсаторы, сильфонные демпферы, антивибрационные клапаны)
  zigzag,

  /// Стрелка направления потока
  arrow,

  /// Круг шаровой пробки
  circle,

  /// Наклонное седло клапана
  slantedDisc;

  String get displayName {
    switch (this) {
      case ValveDividerType.none:
        return 'Без разделителя';
      case ValveDividerType.line:
        return 'Прямая линия';
      case ValveDividerType.zigzag:
        return 'Зигзаг / вибродемпфер';
      case ValveDividerType.arrow:
        return 'Стрелка потока';
      case ValveDividerType.circle:
        return 'Круг (шар)';
      case ValveDividerType.slantedDisc:
        return 'Наклонный диск';
    }
  }
}

/// Тип органа управления / штока в 2D УГО
enum ValveStemSymbolType {
  /// Без штока и привода (самодействующий, обратный, виброкомпенсатор)
  none,

  /// Шпиндель с маховиком/штурвалом (задвижка, вентиль)
  handwheel,

  /// Поворотный рычаг/рукоятка (шаровой кран, затвор)
  lever,

  /// Квадрат/прямоугольник с произвольным текстом ('Э', 'М', 'АВ', 'РД' и т.д.)
  boxWithText,

  /// Мембранный привод / грибок (МИМ)
  diaphragm,

  /// Пружинный колпак предохранительного клапана
  spring;

  String get displayName {
    switch (this) {
      case ValveStemSymbolType.none:
        return 'Без привода';
      case ValveStemSymbolType.handwheel:
        return 'Маховик / штурвал';
      case ValveStemSymbolType.lever:
        return 'Рычаг / рукоятка';
      case ValveStemSymbolType.boxWithText:
        return 'Коробка с текстом (Э, АВ)';
      case ValveStemSymbolType.diaphragm:
        return 'Мембрана (МИМ)';
      case ValveStemSymbolType.spring:
        return 'Пружина';
    }
  }
}


/// Форма тела корпуса арматуры в 2D УГО и 3D аксонометрии
enum Valve3dBodyShape {
  /// Встречные усеченные конусы (стандарт ГОСТ 21.205)
  doubleCones,

  /// Цилиндрический / прямоугольный корпус
  cylinder,

  /// Цилиндрический корпус с сильфоном / выступающими гофрами (виброкомпенсатор)
  bellows,

  /// Сферический / круглый корпус
  sphere;

  String get displayName {
    switch (this) {
      case Valve3dBodyShape.doubleCones:
        return 'Двойные конусы';
      case Valve3dBodyShape.cylinder:
        return 'Цилиндр';
      case Valve3dBodyShape.bellows:
        return 'Сильфон (гофра)';
      case Valve3dBodyShape.sphere:
        return 'Сфера';
    }
  }
}

/// Конфигурация 2D условного графического обозначения (УГО) арматуры
class ValveSymbolConfig {
  final Valve3dBodyShape bodyShape;
  final ValveWingFillStyle leftWingStyle;
  final ValveWingFillStyle rightWingStyle;
  final ValveDividerType dividerType;
  final ValveStemSymbolType stemType;
  final String stemText;
  final bool hasBodyFlanges;

  const ValveSymbolConfig({
    this.bodyShape = Valve3dBodyShape.doubleCones,
    this.leftWingStyle = ValveWingFillStyle.outline,
    this.rightWingStyle = ValveWingFillStyle.outline,
    this.dividerType = ValveDividerType.none,
    this.stemType = ValveStemSymbolType.handwheel,
    this.stemText = 'Э',
    this.hasBodyFlanges = false,
  });

  ValveSymbolConfig copyWith({
    Valve3dBodyShape? bodyShape,
    ValveWingFillStyle? leftWingStyle,
    ValveWingFillStyle? rightWingStyle,
    ValveDividerType? dividerType,
    ValveStemSymbolType? stemType,
    String? stemText,
    bool? hasBodyFlanges,
  }) {
    return ValveSymbolConfig(
      bodyShape: bodyShape ?? this.bodyShape,
      leftWingStyle: leftWingStyle ?? this.leftWingStyle,
      rightWingStyle: rightWingStyle ?? this.rightWingStyle,
      dividerType: dividerType ?? this.dividerType,
      stemType: stemType ?? this.stemType,
      stemText: stemText ?? this.stemText,
      hasBodyFlanges: hasBodyFlanges ?? this.hasBodyFlanges,
    );
  }

  Map<String, dynamic> toJson() => {
        'bodyShape': bodyShape.name,
        'leftWingStyle': leftWingStyle.name,
        'rightWingStyle': rightWingStyle.name,
        'dividerType': dividerType.name,
        'stemType': stemType.name,
        'stemText': stemText,
        'hasBodyFlanges': hasBodyFlanges,
      };

  factory ValveSymbolConfig.fromJson(Map<String, dynamic> json) {
    return ValveSymbolConfig(
      bodyShape: Valve3dBodyShape.values.byName(
        json['bodyShape'] as String? ?? Valve3dBodyShape.doubleCones.name,
      ),
      leftWingStyle: ValveWingFillStyle.values.byName(
        json['leftWingStyle'] as String? ?? ValveWingFillStyle.outline.name,
      ),
      rightWingStyle: ValveWingFillStyle.values.byName(
        json['rightWingStyle'] as String? ?? ValveWingFillStyle.outline.name,
      ),
      dividerType: ValveDividerType.values.byName(
        json['dividerType'] as String? ?? ValveDividerType.none.name,
      ),
      stemType: ValveStemSymbolType.values.byName(
        json['stemType'] as String? ?? ValveStemSymbolType.handwheel.name,
      ),
      stemText: json['stemText'] as String? ?? 'Э',
      hasBodyFlanges: json['hasBodyFlanges'] as bool? ?? false,
    );
  }
}

/// Тип привода / органа управления в 3D
enum Valve3dActuatorType {
  /// Без привода и штока
  none,

  /// Шпиндель с круглым штурвалом и спицами
  handwheel,

  /// Поворотный рычаг
  lever,

  /// Блок электропривода (редуктор + мотор + штурвал)
  actuatorBox,

  /// Мембранная коробка (пневмопривод МИМ)
  diaphragm,

  /// Вертикальный цилиндрический стакан пружины
  springBonnet;

  String get displayName {
    switch (this) {
      case Valve3dActuatorType.none:
        return 'Без привода';
      case Valve3dActuatorType.handwheel:
        return 'Штурвал';
      case Valve3dActuatorType.lever:
        return 'Рычаг';
      case Valve3dActuatorType.actuatorBox:
        return 'Коробка электропривода';
      case Valve3dActuatorType.diaphragm:
        return 'Мембранная камера';
      case Valve3dActuatorType.springBonnet:
        return 'Стакан пружины';
    }
  }
}


/// Конфигурация пространственной 3D геометрии арматуры
class ValveGeometry3dConfig {
  final Valve3dBodyShape bodyShape;
  final Valve3dActuatorType actuatorType;
  final double stemHeightRatio;
  final double actuatorSizeRatio;

  const ValveGeometry3dConfig({
    this.bodyShape = Valve3dBodyShape.doubleCones,
    this.actuatorType = Valve3dActuatorType.handwheel,
    this.stemHeightRatio = 2.2,
    this.actuatorSizeRatio = 1.4,
  });

  ValveGeometry3dConfig copyWith({
    Valve3dBodyShape? bodyShape,
    Valve3dActuatorType? actuatorType,
    double? stemHeightRatio,
    double? actuatorSizeRatio,
  }) {
    return ValveGeometry3dConfig(
      bodyShape: bodyShape ?? this.bodyShape,
      actuatorType: actuatorType ?? this.actuatorType,
      stemHeightRatio: stemHeightRatio ?? this.stemHeightRatio,
      actuatorSizeRatio: actuatorSizeRatio ?? this.actuatorSizeRatio,
    );
  }

  Map<String, dynamic> toJson() => {
        'bodyShape': bodyShape.name,
        'actuatorType': actuatorType.name,
        'stemHeightRatio': stemHeightRatio,
        'actuatorSizeRatio': actuatorSizeRatio,
      };

  factory ValveGeometry3dConfig.fromJson(Map<String, dynamic> json) {
    return ValveGeometry3dConfig(
      bodyShape: Valve3dBodyShape.values.byName(
        json['bodyShape'] as String? ?? Valve3dBodyShape.doubleCones.name,
      ),
      actuatorType: Valve3dActuatorType.values.byName(
        json['actuatorType'] as String? ?? Valve3dActuatorType.handwheel.name,
      ),
      stemHeightRatio: (json['stemHeightRatio'] as num?)?.toDouble() ?? 2.2,
      actuatorSizeRatio: (json['actuatorSizeRatio'] as num?)?.toDouble() ?? 1.4,
    );
  }
}

/// Паспорт и определение пользовательского семейства арматуры
class CustomValveDefinition {
  final String id;
  final String name;
  final String description;
  final double defaultLengthFactor;
  final double minLengthMm;
  final ValveSymbolConfig symbol2d;
  final ValveGeometry3dConfig geometry3d;
  final bool isBuiltin;

  const CustomValveDefinition({
    required this.id,
    required this.name,
    this.description = '',
    this.defaultLengthFactor = 1.5,
    this.minLengthMm = 80.0,
    this.symbol2d = const ValveSymbolConfig(),
    this.geometry3d = const ValveGeometry3dConfig(),
    this.isBuiltin = false,
  });

  /// Эффективная форма корпуса арматуры (с приоритетом 2D УГО или 3D геометрии)
  Valve3dBodyShape get effectiveBodyShape {
    if (symbol2d.bodyShape != Valve3dBodyShape.doubleCones) {
      return symbol2d.bodyShape;
    }
    return geometry3d.bodyShape;
  }

  CustomValveDefinition copyWith({
    String? id,
    String? name,
    String? description,
    double? defaultLengthFactor,
    double? minLengthMm,
    ValveSymbolConfig? symbol2d,
    ValveGeometry3dConfig? geometry3d,
    bool? isBuiltin,
  }) {
    return CustomValveDefinition(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      defaultLengthFactor: defaultLengthFactor ?? this.defaultLengthFactor,
      minLengthMm: minLengthMm ?? this.minLengthMm,
      symbol2d: symbol2d ?? this.symbol2d,
      geometry3d: geometry3d ?? this.geometry3d,
      isBuiltin: isBuiltin ?? this.isBuiltin,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'defaultLengthFactor': defaultLengthFactor,
        'minLengthMm': minLengthMm,
        'symbol2d': symbol2d.toJson(),
        'geometry3d': geometry3d.toJson(),
        'isBuiltin': isBuiltin,
      };

  factory CustomValveDefinition.fromJson(Map<String, dynamic> json) {
    var symbol = json['symbol2d'] != null
        ? ValveSymbolConfig.fromJson(json['symbol2d'] as Map<String, dynamic>)
        : const ValveSymbolConfig();
    final geom = json['geometry3d'] != null
        ? ValveGeometry3dConfig.fromJson(json['geometry3d'] as Map<String, dynamic>)
        : const ValveGeometry3dConfig();

    // Синхронизация формы корпуса для старых файлов, где bodyShape был только в geometry3d
    if (symbol.bodyShape == Valve3dBodyShape.doubleCones &&
        geom.bodyShape != Valve3dBodyShape.doubleCones) {
      symbol = symbol.copyWith(bodyShape: geom.bodyShape);
    }

    return CustomValveDefinition(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      defaultLengthFactor: (json['defaultLengthFactor'] as num?)?.toDouble() ?? 1.5,
      minLengthMm: (json['minLengthMm'] as num?)?.toDouble() ?? 80.0,
      symbol2d: symbol,
      geometry3d: geom,
      isBuiltin: json['isBuiltin'] as bool? ?? false,
    );
  }
}
