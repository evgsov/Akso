import 'package:uuid/uuid.dart';

import '../enums/fitting_type.dart';
import '../enums/weld_type.dart';
import 'fitting_definition.dart';

const _uuid = Uuid();

/// Каталог стандартных и пользовательских фитингов с правилами трассировки (Routing Preferences)
class FittingCatalog {
  final Map<String, FittingDefinition> definitions = {};

  /// Идентификатор отвода по умолчанию для трассировки
  String defaultElbowId = 'elbow_gost_17375';

  /// Идентификатор ответвления по умолчанию для трассировки
  String defaultBranchId = 'tee_gost_17376';

  /// Идентификатор фланца по умолчанию
  String defaultFlangeId = 'flange_weld_neck_11';

  /// Идентификатор заглушки (днища) по умолчанию
  String defaultCapId = 'cap_elliptic_gost';

  /// Режим фланцевого подключения по умолчанию (к оборудованию или межтрубное)
  FlangeConnectionType defaultFlangeConnectionType = FlangeConnectionType.toEquipment;

  /// Исполнение арматуры по умолчанию (фланцевая или под приварку)
  bool defaultValveIsFlanged = false;

  FittingCatalog() {
    _initStandardLibrary();
  }

  /// Инициализация стандартной библиотеки ГОСТ/СПДС
  void _initStandardLibrary() {
    // --- Отводы ---
    _register(const FittingDefinition(
      id: 'elbow_gost_17375',
      name: 'Отвод 90° крутоизогнутый (R=1.5DN)',
      archetype: FittingArchetype.elbow,
      fittingType: FittingType.elbow90,
      standard: 'ГОСТ 17375-2001 (тип 3D)',
      radiusFactor: 1.5,
      weldType: WeldType.c17,
      defaultMaterial: 'Сталь 20',
    ));

    _register(const FittingDefinition(
      id: 'elbow_gost_30753',
      name: 'Отвод 90° крутоизогнутый 2D (R=1.0DN)',
      archetype: FittingArchetype.elbow,
      fittingType: FittingType.elbow90,
      standard: 'ГОСТ 30753-2001 (тип 2D)',
      radiusFactor: 1.0,
      weldType: WeldType.c17,
      defaultMaterial: 'Сталь 20',
    ));

    _register(const FittingDefinition(
      id: 'elbow_bent_gost_24950',
      name: 'Отвод 90° гнутый гладкий (R=3.0DN)',
      archetype: FittingArchetype.elbow,
      fittingType: FittingType.elbow90,
      standard: 'ГОСТ 24950-81',
      radiusFactor: 3.0,
      weldType: WeldType.c17,
      defaultMaterial: 'Сталь 20',
    ));

    _register(const FittingDefinition(
      id: 'elbow_bent_long',
      name: 'Отвод 90° гнутый радиусный (R=4.0DN)',
      archetype: FittingArchetype.elbow,
      fittingType: FittingType.elbow90,
      standard: 'ТУ / ОСТ',
      radiusFactor: 4.0,
      weldType: WeldType.c17,
      defaultMaterial: 'Сталь 20',
    ));

    _register(const FittingDefinition(
      id: 'elbow_sector_ost',
      name: 'Отвод 90° сварной секторный (ОСТ)',
      archetype: FittingArchetype.elbow,
      fittingType: FittingType.elbow90,
      standard: 'ОСТ 34.10.752-97',
      radiusFactor: 1.5,
      weldType: WeldType.c17,
      defaultMaterial: 'Сталь 20',
    ));

    _register(const FittingDefinition(
      id: 'elbow45_gost_17375',
      name: 'Отвод 45° крутоизогнутый (R=0.625DN)',
      archetype: FittingArchetype.elbow,
      fittingType: FittingType.elbow45,
      standard: 'ГОСТ 17375-2001',
      radiusFactor: 0.625,
      weldType: WeldType.c17,
      defaultMaterial: 'Сталь 20',
    ));

    // --- Тройники и врезки ---
    _register(const FittingDefinition(
      id: 'tee_gost_17376',
      name: 'Тройник равнопроходный бесшовный',
      archetype: FittingArchetype.tee,
      fittingType: FittingType.tee,
      standard: 'ГОСТ 17376-2001',
      radiusFactor: 1.0,
      weldType: WeldType.c17,
      cutsMainPipe: true,
      defaultMaterial: 'Сталь 20',
    ));

    _register(const FittingDefinition(
      id: 'tee_reducing_gost_17376',
      name: 'Тройник переходной бесшовный',
      archetype: FittingArchetype.tee,
      fittingType: FittingType.tee,
      standard: 'ГОСТ 17376-2001',
      radiusFactor: 1.0,
      weldType: WeldType.c17,
      cutsMainPipe: true,
      defaultMaterial: 'Сталь 20',
    ));

    _register(const FittingDefinition(
      id: 'direct_branch_u18',
      name: 'Прямая врезка в тело трубы (шов У18)',
      archetype: FittingArchetype.directBranch,
      fittingType: FittingType.directBranch,
      standard: 'ГОСТ 16037-80 У18',
      radiusFactor: 0.0,
      weldType: WeldType.u18,
      cutsMainPipe: false, // Магистраль цельная!
      defaultMaterial: 'Сталь 20',
    ));

    _register(const FittingDefinition(
      id: 'tee_reinforced_ost',
      name: 'Тройник сварной с усиливающей накладкой',
      archetype: FittingArchetype.tee,
      fittingType: FittingType.tee,
      standard: 'ОСТ 34.10.764-97',
      radiusFactor: 1.2,
      weldType: WeldType.c17,
      cutsMainPipe: true,
      defaultMaterial: '09Г2С',
    ));

    // --- Переходы ---
    _register(const FittingDefinition(
      id: 'reducer_concentric_gost',
      name: 'Переход концентрический ГОСТ 17378',
      archetype: FittingArchetype.reducer,
      fittingType: FittingType.reducerConcentric,
      standard: 'ГОСТ 17378-2001',
      radiusFactor: 1.5,
      weldType: WeldType.c17,
      defaultMaterial: 'Сталь 20',
    ));

    _register(const FittingDefinition(
      id: 'reducer_eccentric_gost',
      name: 'Переход эксцентрический ГОСТ 17378',
      archetype: FittingArchetype.reducer,
      fittingType: FittingType.reducerEccentric,
      standard: 'ГОСТ 17378-2001',
      radiusFactor: 1.5,
      weldType: WeldType.c17,
      defaultMaterial: 'Сталь 20',
    ));

    // --- Фланцы ---
    _register(const FittingDefinition(
      id: 'flange_weld_neck_11',
      name: 'Фланец стальной воротниковый (тип 11)',
      archetype: FittingArchetype.flange,
      fittingType: FittingType.flange,
      standard: 'ГОСТ 33259-2015 тип 11 (встык)',
      fixedLengthMm: 45.0,
      weldType: WeldType.c17,
      defaultMaterial: 'Сталь 20',
    ));

    _register(const FittingDefinition(
      id: 'flange_flat_01',
      name: 'Фланец стальной плоский (тип 01)',
      archetype: FittingArchetype.flange,
      fittingType: FittingType.flange,
      standard: 'ГОСТ 33259-2015 тип 01 (накидной)',
      fixedLengthMm: 35.0,
      weldType: WeldType.c2,
      defaultMaterial: 'Сталь 20',
    ));

    _register(const FittingDefinition(
      id: 'flange_blind',
      name: 'Заглушка фланцевая глухая',
      archetype: FittingArchetype.cap,
      fittingType: FittingType.cap,
      standard: 'АТК 24.218.01-90',
      fixedLengthMm: 25.0,
      weldType: WeldType.c17,
      defaultMaterial: 'Сталь 20',
    ));

    // --- Днища и заглушки ---
    _register(const FittingDefinition(
      id: 'cap_elliptic_gost',
      name: 'Днище эллиптическое отбортованное ГОСТ 6533',
      archetype: FittingArchetype.cap,
      fittingType: FittingType.cap,
      standard: 'ГОСТ 6533-78',
      fixedLengthMm: 35.0,
      weldType: WeldType.c17,
      defaultMaterial: 'Сталь 20',
    ));
  }

  void _register(FittingDefinition def) {
    definitions[def.id] = def;
  }

  /// Добавление или обновление пользовательского элемента
  void addCustomDefinition(FittingDefinition def) {
    definitions[def.id] = def.copyWith(isCustom: true);
  }

  /// Удаление пользовательского элемента
  void removeCustomDefinition(String id) {
    final def = definitions[id];
    if (def != null && def.isCustom) {
      definitions.remove(id);
      if (defaultElbowId == id) defaultElbowId = 'elbow_gost_17375';
      if (defaultBranchId == id) defaultBranchId = 'tee_gost_17376';
    }
  }

  /// Создание нового пользовательского элемента на основе существующего
  FittingDefinition createFromBase({
    required String baseDefinitionId,
    required String newName,
    required String newStandard,
    required String newMaterial,
    double? newRadiusFactor,
    double? newFixedLengthMm,
    WeldType? newWeldType,
    bool? newCutsMainPipe,
  }) {
    final base = definitions[baseDefinitionId] ?? definitions['elbow_gost_17375']!;
    final customId = 'custom_${base.archetype.name}_${_uuid.v4()}';

    final customDef = FittingDefinition(
      id: customId,
      name: newName.trim().isNotEmpty ? newName.trim() : '${base.name} (Копия)',
      archetype: base.archetype,
      fittingType: base.fittingType,
      standard: newStandard.trim().isNotEmpty ? newStandard.trim() : base.standard,
      defaultMaterial: newMaterial.trim().isNotEmpty ? newMaterial.trim() : base.defaultMaterial,
      radiusFactor: newRadiusFactor ?? base.radiusFactor,
      fixedLengthMm: newFixedLengthMm ?? base.fixedLengthMm,
      weldType: newWeldType ?? base.weldType,
      cutsMainPipe: newCutsMainPipe ?? base.cutsMainPipe,
      isCustom: true,
    );

    addCustomDefinition(customDef);
    return customDef;
  }

  FittingDefinition? getDefinition(String? id) {
    if (id == null) return null;
    return definitions[id];
  }

  List<FittingDefinition> getByArchetype(FittingArchetype archetype) {
    return definitions.values.where((d) => d.archetype == archetype).toList();
  }

  List<FittingDefinition> get allDefinitions => definitions.values.toList();
  List<FittingDefinition> get customDefinitions => definitions.values.where((d) => d.isCustom).toList();

  Map<String, dynamic> toJson() => {
        'defaultElbowId': defaultElbowId,
        'defaultBranchId': defaultBranchId,
        'defaultFlangeId': defaultFlangeId,
        'defaultFlangeConnectionType': defaultFlangeConnectionType.index,
        'defaultValveIsFlanged': defaultValveIsFlanged,
        'customDefinitions': customDefinitions.map((d) => d.toJson()).toList(),
      };

  void loadFromJson(Map<String, dynamic> json) {
    if (json.containsKey('defaultElbowId')) {
      defaultElbowId = json['defaultElbowId'] as String;
    }
    if (json.containsKey('defaultBranchId')) {
      defaultBranchId = json['defaultBranchId'] as String;
    }
    if (json.containsKey('defaultFlangeId')) {
      defaultFlangeId = json['defaultFlangeId'] as String;
    }
    if (json.containsKey('defaultFlangeConnectionType')) {
      defaultFlangeConnectionType = FlangeConnectionType.values[(json['defaultFlangeConnectionType'] as int).clamp(0, FlangeConnectionType.values.length - 1)];
    }
    if (json.containsKey('defaultValveIsFlanged')) {
      defaultValveIsFlanged = json['defaultValveIsFlanged'] as bool;
    }
    if (json.containsKey('customDefinitions')) {
      final list = json['customDefinitions'] as List<dynamic>;
      for (final item in list) {
        final def = FittingDefinition.fromJson(item as Map<String, dynamic>);
        addCustomDefinition(def);
      }
    }
  }
}
