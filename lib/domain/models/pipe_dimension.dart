/// Типоразмер трубы: номинальный диаметр DN, наружный диаметр Dн, ряд толщин стенок S и стандарт
class PipeDimension {
  final int dn;
  final double outerDiameterMm;
  final List<double> wallThicknesses;
  final double defaultWallThicknessMm;
  final String standard;
  final bool isCustom;

  const PipeDimension({
    required this.dn,
    required this.outerDiameterMm,
    required this.wallThicknesses,
    required this.defaultWallThicknessMm,
    this.standard = 'ГОСТ 8732-78',
    this.isCustom = false,
  });

  /// Форматированное обозначение (например, "⌀159×4.5 (Ду150)")
  String formatLabel([double? specificWall]) {
    final s = specificWall ?? defaultWallThicknessMm;
    final dStr = outerDiameterMm.truncateToDouble() == outerDiameterMm
        ? outerDiameterMm.toStringAsFixed(0)
        : outerDiameterMm.toStringAsFixed(1);
    final sStr = s.truncateToDouble() == s
        ? s.toStringAsFixed(0)
        : s.toStringAsFixed(1);
    return '⌀$dStr×$sStr (Ду$dn)';
  }

  /// Краткая выноска диаметра (например, "⌀159×4.5")
  String shortCallout([double? specificWall]) {
    final s = specificWall ?? defaultWallThicknessMm;
    final dStr = outerDiameterMm.truncateToDouble() == outerDiameterMm
        ? outerDiameterMm.toStringAsFixed(0)
        : outerDiameterMm.toStringAsFixed(1);
    final sStr = s.truncateToDouble() == s
        ? s.toStringAsFixed(0)
        : s.toStringAsFixed(1);
    return '⌀$dStr×$sStr';
  }

  PipeDimension copyWith({
    int? dn,
    double? outerDiameterMm,
    List<double>? wallThicknesses,
    double? defaultWallThicknessMm,
    String? standard,
    bool? isCustom,
  }) {
    return PipeDimension(
      dn: dn ?? this.dn,
      outerDiameterMm: outerDiameterMm ?? this.outerDiameterMm,
      wallThicknesses: wallThicknesses ?? this.wallThicknesses,
      defaultWallThicknessMm: defaultWallThicknessMm ?? this.defaultWallThicknessMm,
      standard: standard ?? this.standard,
      isCustom: isCustom ?? this.isCustom,
    );
  }

  Map<String, dynamic> toJson() => {
        'dn': dn,
        'outerDiameterMm': outerDiameterMm,
        'wallThicknesses': wallThicknesses,
        'defaultWallThicknessMm': defaultWallThicknessMm,
        'standard': standard,
        'isCustom': isCustom,
      };

  factory PipeDimension.fromJson(Map<String, dynamic> json) => PipeDimension(
        dn: json['dn'] as int,
        outerDiameterMm: (json['outerDiameterMm'] as num).toDouble(),
        wallThicknesses: (json['wallThicknesses'] as List<dynamic>)
            .map((e) => (e as num).toDouble())
            .toList(),
        defaultWallThicknessMm:
            (json['defaultWallThicknessMm'] as num).toDouble(),
        standard: json['standard'] as String? ?? 'ГОСТ 8732-78',
        isCustom: json['isCustom'] as bool? ?? false,
      );
}

/// Каталог сортамента труб: стандартные ряды (ГОСТ 8732/10704/20295) + пользовательские размеры
class PipeAssortmentCatalog {
  final Map<int, PipeDimension> _dimensions = {};

  PipeAssortmentCatalog() {
    _initStandardAssortment();
  }

  void _initStandardAssortment() {
    final standards = <PipeDimension>[
      const PipeDimension(
        dn: 15,
        outerDiameterMm: 21.3,
        wallThicknesses: [2.0, 2.5, 2.8, 3.2],
        defaultWallThicknessMm: 2.8,
        standard: 'ГОСТ 8732-78',
      ),
      const PipeDimension(
        dn: 20,
        outerDiameterMm: 26.8,
        wallThicknesses: [2.0, 2.5, 2.8, 3.2],
        defaultWallThicknessMm: 2.8,
        standard: 'ГОСТ 8732-78',
      ),
      const PipeDimension(
        dn: 25,
        outerDiameterMm: 32.0,
        wallThicknesses: [2.5, 3.0, 3.2, 4.0],
        defaultWallThicknessMm: 3.2,
        standard: 'ГОСТ 8732-78',
      ),
      const PipeDimension(
        dn: 32,
        outerDiameterMm: 38.0,
        wallThicknesses: [2.5, 3.0, 3.5, 4.0],
        defaultWallThicknessMm: 3.5,
        standard: 'ГОСТ 8732-78',
      ),
      const PipeDimension(
        dn: 40,
        outerDiameterMm: 45.0,
        wallThicknesses: [2.5, 3.0, 3.5, 4.0, 4.5],
        defaultWallThicknessMm: 3.5,
        standard: 'ГОСТ 8732-78',
      ),
      const PipeDimension(
        dn: 50,
        outerDiameterMm: 57.0,
        wallThicknesses: [3.0, 3.5, 4.0, 4.5, 5.0, 6.0],
        defaultWallThicknessMm: 3.5,
        standard: 'ГОСТ 8732-78',
      ),
      const PipeDimension(
        dn: 65,
        outerDiameterMm: 76.0,
        wallThicknesses: [3.5, 4.0, 4.5, 5.0, 6.0],
        defaultWallThicknessMm: 4.0,
        standard: 'ГОСТ 8732-78',
      ),
      const PipeDimension(
        dn: 80,
        outerDiameterMm: 89.0,
        wallThicknesses: [3.5, 4.0, 4.5, 5.0, 6.0, 8.0],
        defaultWallThicknessMm: 4.0,
        standard: 'ГОСТ 8732-78',
      ),
      const PipeDimension(
        dn: 100,
        outerDiameterMm: 108.0,
        wallThicknesses: [3.5, 4.0, 4.5, 5.0, 6.0, 8.0],
        defaultWallThicknessMm: 4.5,
        standard: 'ГОСТ 8732-78',
      ),
      const PipeDimension(
        dn: 125,
        outerDiameterMm: 133.0,
        wallThicknesses: [4.0, 4.5, 5.0, 6.0, 8.0],
        defaultWallThicknessMm: 4.5,
        standard: 'ГОСТ 8732-78',
      ),
      const PipeDimension(
        dn: 150,
        outerDiameterMm: 159.0,
        wallThicknesses: [4.5, 5.0, 6.0, 7.0, 8.0, 10.0],
        defaultWallThicknessMm: 4.5,
        standard: 'ГОСТ 8732-78',
      ),
      const PipeDimension(
        dn: 200,
        outerDiameterMm: 219.0,
        wallThicknesses: [6.0, 7.0, 8.0, 9.0, 10.0, 12.0],
        defaultWallThicknessMm: 6.0,
        standard: 'ГОСТ 8732-78',
      ),
      const PipeDimension(
        dn: 250,
        outerDiameterMm: 273.0,
        wallThicknesses: [6.0, 7.0, 8.0, 9.0, 10.0, 12.0, 14.0],
        defaultWallThicknessMm: 7.0,
        standard: 'ГОСТ 8732-78',
      ),
      const PipeDimension(
        dn: 300,
        outerDiameterMm: 325.0,
        wallThicknesses: [6.0, 7.0, 8.0, 9.0, 10.0, 12.0, 14.0, 16.0],
        defaultWallThicknessMm: 8.0,
        standard: 'ГОСТ 8732-78',
      ),
      const PipeDimension(
        dn: 350,
        outerDiameterMm: 377.0,
        wallThicknesses: [7.0, 8.0, 9.0, 10.0, 12.0, 14.0],
        defaultWallThicknessMm: 8.0,
        standard: 'ГОСТ 10704-91',
      ),
      const PipeDimension(
        dn: 400,
        outerDiameterMm: 426.0,
        wallThicknesses: [7.0, 8.0, 9.0, 10.0, 12.0, 14.0, 16.0, 18.0],
        defaultWallThicknessMm: 9.0,
        standard: 'ГОСТ 10704-91',
      ),
      const PipeDimension(
        dn: 500,
        outerDiameterMm: 530.0,
        wallThicknesses: [7.0, 8.0, 9.0, 10.0, 12.0, 14.0, 16.0, 18.0, 20.0],
        defaultWallThicknessMm: 9.0,
        standard: 'ГОСТ 10704-91',
      ),
      const PipeDimension(
        dn: 600,
        outerDiameterMm: 630.0,
        wallThicknesses: [8.0, 9.0, 10.0, 12.0, 14.0, 16.0, 18.0],
        defaultWallThicknessMm: 10.0,
        standard: 'ГОСТ 10704-91',
      ),
      const PipeDimension(
        dn: 700,
        outerDiameterMm: 720.0,
        wallThicknesses: [8.0, 9.0, 10.0, 12.0, 14.0, 16.0],
        defaultWallThicknessMm: 10.0,
        standard: 'ГОСТ 20295-85',
      ),
      const PipeDimension(
        dn: 800,
        outerDiameterMm: 820.0,
        wallThicknesses: [9.0, 10.0, 12.0, 14.0, 16.0, 18.0],
        defaultWallThicknessMm: 10.0,
        standard: 'ГОСТ 20295-85',
      ),
      const PipeDimension(
        dn: 1000,
        outerDiameterMm: 1020.0,
        wallThicknesses: [10.0, 12.0, 14.0, 16.0, 18.0, 20.0],
        defaultWallThicknessMm: 12.0,
        standard: 'ГОСТ 20295-85',
      ),
      const PipeDimension(
        dn: 1200,
        outerDiameterMm: 1220.0,
        wallThicknesses: [12.0, 14.0, 16.0, 18.0, 20.0],
        defaultWallThicknessMm: 14.0,
        standard: 'ГОСТ 20295-85',
      ),
      const PipeDimension(
        dn: 1400,
        outerDiameterMm: 1420.0,
        wallThicknesses: [14.0, 16.0, 18.0, 20.0, 22.0],
        defaultWallThicknessMm: 16.0,
        standard: 'ГОСТ 20295-85',
      ),
    ];

    for (final dim in standards) {
      _dimensions[dim.dn] = dim;
    }
  }

  /// Получить типоразмер по условному проходу DN
  PipeDimension? getDimension(int dn) => _dimensions[dn];

  /// Список всех доступных DN, отсортированный по возрастанию
  List<int> getAllDns() {
    final list = _dimensions.keys.toList()..sort();
    return list;
  }

  /// Все зарегистрированные типоразмеры
  Map<int, PipeDimension> get dimensions => Map.unmodifiable(_dimensions);

  /// Добавление нового пользовательского типоразмера
  void addCustomDimension(PipeDimension dimension) {
    _dimensions[dimension.dn] = dimension;
  }

  /// Добавление дополнительной толщины стенки к существующему или новому DN
  void addWallThickness(int dn, double thicknessMm) {
    final existing = _dimensions[dn];
    if (existing != null) {
      final updatedWalls = List<double>.from(existing.wallThicknesses);
      if (!updatedWalls.any((w) => (w - thicknessMm).abs() < 0.05)) {
        updatedWalls.add(thicknessMm);
        updatedWalls.sort();
        _dimensions[dn] = existing.copyWith(wallThicknesses: updatedWalls);
      }
    } else {
      // Если такого DN еще не было, регистрируем с ориентировочным Dн = DN * 1.08
      final outerD = dn <= 50 ? (dn * 1.25 + 5.0) : (dn * 1.08);
      _dimensions[dn] = PipeDimension(
        dn: dn,
        outerDiameterMm: outerD,
        wallThicknesses: [thicknessMm],
        defaultWallThicknessMm: thicknessMm,
        isCustom: true,
      );
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'dimensions': _dimensions.map(
        (key, value) => MapEntry(key.toString(), value.toJson()),
      ),
    };
  }

  factory PipeAssortmentCatalog.fromJson(Map<String, dynamic> json) {
    final catalog = PipeAssortmentCatalog();
    if (json['dimensions'] != null) {
      final map = json['dimensions'] as Map<String, dynamic>;
      map.forEach((k, v) {
        final dn = int.tryParse(k);
        if (dn != null && v is Map<String, dynamic>) {
          catalog._dimensions[dn] = PipeDimension.fromJson(v);
        }
      });
    }
    return catalog;
  }
}
