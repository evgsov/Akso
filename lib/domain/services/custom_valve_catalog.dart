import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/custom_valve_definition.dart';

/// Каталог пользовательских семейств арматуры и встроенных расширенных пресетов ГОСТ.
///
/// Предоставляет стандартные шаблоны (антивибрационный клапан, задвижка с электроприводом,
/// обратный клапан со сплошной заливкой, редуктор давления) и сохраняет созданные
/// пользователем типы арматуры на диск устройства в `custom_valves.json`.
class CustomValveCatalog {
  static const String _fileName = 'custom_valves.json';
  static CustomValveCatalog instance = CustomValveCatalog();

  Future<Directory> Function()? _getStorageDir;

  CustomValveCatalog({
    Future<Directory> Function()? getStorageDir,
  }) : _getStorageDir = getStorageDir;

  void setStorageDir(Future<Directory> Function()? getStorageDir) {
    _getStorageDir = getStorageDir;
  }

  static final List<CustomValveDefinition> _builtInPresets = [
    const CustomValveDefinition(
      id: 'preset_anti_vibration_valve',
      name: 'Клапан антивибрационный',
      description:
          'Антивибрационный клапан с зигзагообразной разделительной линией и сильфонным компенсатором',
      isBuiltin: true,
      defaultLengthFactor: 1.5,
      minLengthMm: 120.0,
      symbol2d: ValveSymbolConfig(
        bodyShape: Valve3dBodyShape.bellows,
        leftWingStyle: ValveWingFillStyle.hatched,
        rightWingStyle: ValveWingFillStyle.hatched,
        dividerType: ValveDividerType.zigzag,
        stemType: ValveStemSymbolType.boxWithText,
        stemText: 'АВ',
        hasBodyFlanges: true,
      ),
      geometry3d: ValveGeometry3dConfig(
        bodyShape: Valve3dBodyShape.bellows,
        actuatorType: Valve3dActuatorType.none,
      ),
    ),
    const CustomValveDefinition(
      id: 'preset_electric_actuator_valve',
      name: 'Задвижка с электроприводом',
      description: 'Задвижка клиновая с электроприводом (обозначение Э на штоке)',
      isBuiltin: true,
      defaultLengthFactor: 1.8,
      minLengthMm: 140.0,
      symbol2d: ValveSymbolConfig(
        bodyShape: Valve3dBodyShape.doubleCones,
        leftWingStyle: ValveWingFillStyle.outline,
        rightWingStyle: ValveWingFillStyle.outline,
        dividerType: ValveDividerType.slantedDisc,
        stemType: ValveStemSymbolType.boxWithText,
        stemText: 'Э',
        hasBodyFlanges: true,
      ),
      geometry3d: ValveGeometry3dConfig(
        bodyShape: Valve3dBodyShape.doubleCones,
        actuatorType: Valve3dActuatorType.actuatorBox,
        actuatorSizeRatio: 1.6,
      ),
    ),
    const CustomValveDefinition(
      id: 'preset_solid_check_valve',
      name: 'Клапан обратный (заливка)',
      description: 'Обратный клапан с закрашенным треугольником направления потока',
      isBuiltin: true,
      defaultLengthFactor: 1.2,
      minLengthMm: 100.0,
      symbol2d: ValveSymbolConfig(
        bodyShape: Valve3dBodyShape.doubleCones,
        leftWingStyle: ValveWingFillStyle.outline,
        rightWingStyle: ValveWingFillStyle.solid,
        dividerType: ValveDividerType.arrow,
        stemType: ValveStemSymbolType.none,
        hasBodyFlanges: false,
      ),
      geometry3d: ValveGeometry3dConfig(
        bodyShape: Valve3dBodyShape.doubleCones,
        actuatorType: Valve3dActuatorType.none,
      ),
    ),
    const CustomValveDefinition(
      id: 'preset_strainer_valve',
      name: 'Фильтр сетчатый (грязевик)',
      description: 'Фильтр сетчатый в цилиндрическом корпусе с наклонной сеткой',
      isBuiltin: true,
      defaultLengthFactor: 1.4,
      minLengthMm: 110.0,
      symbol2d: ValveSymbolConfig(
        bodyShape: Valve3dBodyShape.cylinder,
        leftWingStyle: ValveWingFillStyle.outline,
        rightWingStyle: ValveWingFillStyle.hatched,
        dividerType: ValveDividerType.slantedDisc,
        stemType: ValveStemSymbolType.none,
        hasBodyFlanges: true,
      ),
      geometry3d: ValveGeometry3dConfig(
        bodyShape: Valve3dBodyShape.cylinder,
        actuatorType: Valve3dActuatorType.none,
      ),
    ),
    const CustomValveDefinition(
      id: 'preset_pressure_reducing_valve',
      name: 'Редуктор давления',
      description: 'Регулятор давления прямого действия с мембранным блоком (М)',
      isBuiltin: true,
      defaultLengthFactor: 1.6,
      minLengthMm: 130.0,
      symbol2d: ValveSymbolConfig(
        bodyShape: Valve3dBodyShape.doubleCones,
        leftWingStyle: ValveWingFillStyle.outline,
        rightWingStyle: ValveWingFillStyle.outline,
        dividerType: ValveDividerType.none,
        stemType: ValveStemSymbolType.diaphragm,
        stemText: 'М',
        hasBodyFlanges: false,
      ),
      geometry3d: ValveGeometry3dConfig(
        bodyShape: Valve3dBodyShape.doubleCones,
        actuatorType: Valve3dActuatorType.diaphragm,
        actuatorSizeRatio: 1.5,
      ),
    ),
  ];

  final Map<String, CustomValveDefinition> _userDefinitions = {};

  List<CustomValveDefinition> get builtInPresets => List.unmodifiable(_builtInPresets);
  List<CustomValveDefinition> get userDefinitions => List.unmodifiable(_userDefinitions.values);
  List<CustomValveDefinition> get allDefinitions => [
        ..._builtInPresets,
        ..._userDefinitions.values,
      ];

  CustomValveDefinition? getById(String id) {
    if (_userDefinitions.containsKey(id)) {
      return _userDefinitions[id];
    }
    for (final preset in _builtInPresets) {
      if (preset.id == id) {
        return preset;
      }
    }
    return null;
  }

  Future<File?> _getConfigFile() async {
    if (kIsWeb) return null;
    try {
      Directory dir;
      final getDir = _getStorageDir;
      if (getDir != null) {
        dir = await getDir();
      } else {
        try {
          dir = await getApplicationSupportDirectory().timeout(const Duration(milliseconds: 300));
        } catch (_) {
          try {
            dir = await getApplicationDocumentsDirectory().timeout(const Duration(milliseconds: 300));
          } catch (_) {
            return null;
          }
        }
      }
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return File('${dir.path}${Platform.pathSeparator}$_fileName');
    } catch (_) {
      return null;
    }
  }

  Future<void> load() async {
    final file = await _getConfigFile();
    if (file == null || !file.existsSync()) {
      return;
    }

    try {
      final content = file.readAsStringSync();
      if (content.trim().isEmpty) return;

      final decoded = jsonDecode(content);
      if (decoded is! List) return;

      _userDefinitions.clear();
      for (final item in decoded) {
        if (item is Map) {
          final def = CustomValveDefinition.fromJson(Map<String, dynamic>.from(item));
          _userDefinitions[def.id] = def;
        }
      }
    } catch (e) {
      debugPrint('CustomValveCatalog load error: $e');
    }
  }

  Future<void> persist() async {
    final file = await _getConfigFile();
    if (file == null) return;

    try {
      final list = _userDefinitions.values.map((d) => d.toJson()).toList();
      final content = const JsonEncoder.withIndent('  ').convert(list);
      file.writeAsStringSync(content);
    } catch (e) {
      debugPrint('CustomValveCatalog persist error: $e');
    }
  }

  Future<void> saveDefinition(CustomValveDefinition definition) async {
    final toSave = definition.copyWith(isBuiltin: false);
    _userDefinitions[toSave.id] = toSave;
    await persist();
  }

  Future<void> deleteDefinition(String id) async {
    if (_builtInPresets.any((p) => p.id == id)) {
      // Cannot delete built-in presets
      return;
    }
    if (_userDefinitions.containsKey(id)) {
      _userDefinitions.remove(id);
      await persist();
    }
  }

  /// Регистрирует пользовательские арматуры, загруженные из файла проекта.
  /// Это необходимо для того, чтобы при открытии проекта с другого компьютера,
  /// арматуры добавлялись в глобальный каталог пользователя и корректно отрисовывались.
  Future<void> registerProjectDefinitions(Map<String, CustomValveDefinition> projectValves) async {
    bool hasNew = false;
    for (final def in projectValves.values) {
      if (!_userDefinitions.containsKey(def.id) && !_builtInPresets.any((p) => p.id == def.id)) {
        _userDefinitions[def.id] = def.copyWith(isBuiltin: false);
        hasNew = true;
      }
    }
    if (hasNew) {
      await persist();
    }
  }
}
