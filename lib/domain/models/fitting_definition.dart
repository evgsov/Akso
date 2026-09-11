import '../enums/fitting_type.dart';
import '../enums/weld_type.dart';

/// Базовый архетип соединительной детали
enum FittingArchetype {
  /// Отводы (повороты трассы: крутоизогнутые, гнутые, секторные)
  elbow,

  /// Тройники (фасонные детали ответвления)
  tee,

  /// Прямая врезка (труба в трубу, штуцер без тройника)
  directBranch,

  /// Переходы диаметров (концентрические, эксцентрические)
  reducer,

  /// Фланцы (воротниковые, плоские, фланцевые пары)
  flange,

  /// Заглушки (эллиптические, фланцевые глухие)
  cap,

  /// Крестовины
  cross,
}

extension FittingArchetypeExt on FittingArchetype {
  String get displayName {
    switch (this) {
      case FittingArchetype.elbow:
        return 'Отвод';
      case FittingArchetype.tee:
        return 'Тройник';
      case FittingArchetype.directBranch:
        return 'Прямая врезка';
      case FittingArchetype.reducer:
        return 'Переход';
      case FittingArchetype.flange:
        return 'Фланец';
      case FittingArchetype.cap:
        return 'Заглушка';
      case FittingArchetype.cross:
        return 'Крестовина';
    }
  }
}

/// Параметрическое определение (типоразмер / семейство) соединительной детали в каталоге
class FittingDefinition {
  final String id;
  final String name;
  final FittingArchetype archetype;
  final FittingType fittingType;
  final String standard;
  final String defaultMaterial;

  /// Коэффициент радиуса гиба k (R = k * DN), например: 1.5 (ГОСТ 17375), 1.0 (ГОСТ 30753), 3.0...5.0 (ГОСТ 24950)
  final double? radiusFactor;

  /// Фиксированная строительная длина (мм), если задана вместо коэффициента
  final double? fixedLengthMm;

  /// Тип сварного шва подключения по ГОСТ 16037
  final WeldType weldType;

  /// Разрезает ли деталь магистральную трубу на 2 катушки (true для тройников, false для прямых врезок)
  final bool cutsMainPipe;

  /// Создан ли элемент пользователем через функцию «Создать на основе»
  final bool isCustom;

  /// Количество сварных стыков по умолчанию для этого типа детали
  final int? defaultWeldCount;

  /// Для фланцев: режим подключения по умолчанию
  final FlangeConnectionType? flangeConnectionType;

  /// Вылет ответвления H (мм) для тройников
  final double? branchLengthMm;

  const FittingDefinition({
    required this.id,
    required this.name,
    required this.archetype,
    required this.fittingType,
    required this.standard,
    this.defaultMaterial = 'Сталь 20',
    this.radiusFactor,
    this.fixedLengthMm,
    this.weldType = WeldType.c17,
    this.cutsMainPipe = true,
    this.isCustom = false,
    this.defaultWeldCount,
    this.flangeConnectionType,
    this.branchLengthMm,
  });

  /// Вычисление строительного вычета из катушки для заданного DN
  double calculateDeduction(int dn) {
    if (fixedLengthMm != null && fixedLengthMm! > 0) {
      return fixedLengthMm!;
    }
    if (radiusFactor != null && radiusFactor! > 0) {
      return dn * radiusFactor!;
    }
    return fittingType.defaultDeductionMm(dn);
  }

  FittingDefinition copyWith({
    String? id,
    String? name,
    FittingArchetype? archetype,
    FittingType? fittingType,
    String? standard,
    String? defaultMaterial,
    double? radiusFactor,
    double? fixedLengthMm,
    WeldType? weldType,
    bool? cutsMainPipe,
    bool? isCustom,
    int? defaultWeldCount,
    FlangeConnectionType? flangeConnectionType,
    double? branchLengthMm,
  }) {
    return FittingDefinition(
      id: id ?? this.id,
      name: name ?? this.name,
      archetype: archetype ?? this.archetype,
      fittingType: fittingType ?? this.fittingType,
      standard: standard ?? this.standard,
      defaultMaterial: defaultMaterial ?? this.defaultMaterial,
      radiusFactor: radiusFactor ?? this.radiusFactor,
      fixedLengthMm: fixedLengthMm ?? this.fixedLengthMm,
      weldType: weldType ?? this.weldType,
      cutsMainPipe: cutsMainPipe ?? this.cutsMainPipe,
      isCustom: isCustom ?? this.isCustom,
      defaultWeldCount: defaultWeldCount ?? this.defaultWeldCount,
      flangeConnectionType: flangeConnectionType ?? this.flangeConnectionType,
      branchLengthMm: branchLengthMm ?? this.branchLengthMm,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'archetype': archetype.index,
        'fittingType': fittingType.index,
        'standard': standard,
        'defaultMaterial': defaultMaterial,
        if (radiusFactor != null) 'radiusFactor': radiusFactor,
        if (fixedLengthMm != null) 'fixedLengthMm': fixedLengthMm,
        'weldType': weldType.index,
        'cutsMainPipe': cutsMainPipe,
        'isCustom': isCustom,
        if (defaultWeldCount != null) 'defaultWeldCount': defaultWeldCount,
        if (flangeConnectionType != null) 'flangeConnectionType': flangeConnectionType!.index,
        if (branchLengthMm != null) 'branchLengthMm': branchLengthMm,
      };

  factory FittingDefinition.fromJson(Map<String, dynamic> json) => FittingDefinition(
        id: json['id'] as String,
        name: json['name'] as String,
        archetype: FittingArchetype.values[json['archetype'] as int? ?? 0],
        fittingType: FittingType.values[json['fittingType'] as int? ?? 0],
        standard: json['standard'] as String? ?? 'ГОСТ',
        defaultMaterial: json['defaultMaterial'] as String? ?? 'Сталь 20',
        radiusFactor: (json['radiusFactor'] as num?)?.toDouble(),
        fixedLengthMm: (json['fixedLengthMm'] as num?)?.toDouble(),
        weldType: WeldType.values[json['weldType'] as int? ?? 0],
        cutsMainPipe: json['cutsMainPipe'] as bool? ?? true,
        isCustom: json['isCustom'] as bool? ?? false,
        defaultWeldCount: json['defaultWeldCount'] as int?,
        flangeConnectionType: json.containsKey('flangeConnectionType')
            ? FlangeConnectionType.values[(json['flangeConnectionType'] as int).clamp(0, FlangeConnectionType.values.length - 1)]
            : null,
        branchLengthMm: (json['branchLengthMm'] as num?)?.toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FittingDefinition && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
