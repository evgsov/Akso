import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/custom_valve_definition.dart';
import 'package:akso/domain/services/custom_valve_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CustomValveCatalog catalog;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('akso_valves_test_');
    catalog = CustomValveCatalog(getStorageDir: () async => tempDir);
    await catalog.load();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('CustomValveCatalog Presets & Querying', () {
    test('contains built-in presets by default', () {
      final builtIns = catalog.builtInPresets;
      expect(builtIns.isNotEmpty, isTrue);

      final antiVib = catalog.getById('preset_anti_vibration_valve');
      expect(antiVib, isNotNull);
      expect(antiVib!.name, contains('антивибрационный'));
      expect(antiVib.symbol2d.dividerType, equals(ValveDividerType.zigzag));
      expect(antiVib.symbol2d.leftWingStyle, equals(ValveWingFillStyle.hatched));
      expect(antiVib.symbol2d.stemText, equals('АВ'));
      expect(antiVib.geometry3d.bodyShape, equals(Valve3dBodyShape.bellows));

      final electric = catalog.getById('preset_electric_actuator_valve');
      expect(electric, isNotNull);
      expect(electric!.symbol2d.stemType, equals(ValveStemSymbolType.boxWithText));
      expect(electric.symbol2d.stemText, equals('Э'));
      expect(electric.geometry3d.actuatorType, equals(Valve3dActuatorType.actuatorBox));

      final solidCheck = catalog.getById('preset_solid_check_valve');
      expect(solidCheck, isNotNull);
      expect(solidCheck!.symbol2d.rightWingStyle, equals(ValveWingFillStyle.solid));
      expect(solidCheck.symbol2d.dividerType, equals(ValveDividerType.arrow));

      final reducer = catalog.getById('preset_pressure_reducing_valve');
      expect(reducer, isNotNull);
      expect(reducer!.symbol2d.stemType, equals(ValveStemSymbolType.diaphragm));
      expect(reducer.symbol2d.stemText, equals('М'));
      expect(reducer.geometry3d.actuatorType, equals(Valve3dActuatorType.diaphragm));
    });

    test('allDefinitions contains both built-in and user definitions', () async {
      final initialCount = catalog.allDefinitions.length;

      final customDef = CustomValveDefinition(
        id: 'user_valve_1',
        name: 'Пользовательский клапан',
        symbol2d: const ValveSymbolConfig(
          stemText: 'ПК',
          dividerType: ValveDividerType.circle,
        ),
      );

      await catalog.saveDefinition(customDef);
      expect(catalog.allDefinitions.length, equals(initialCount + 1));
      expect(catalog.getById('user_valve_1')?.name, equals('Пользовательский клапан'));
    });
  });

  group('CustomValveCatalog Persistence', () {
    test('persists user definitions to disk and reloads them', () async {
      final customDef = CustomValveDefinition(
        id: 'user_valve_persisted',
        name: 'Сохраненный клапан',
        symbol2d: const ValveSymbolConfig(
          leftWingStyle: ValveWingFillStyle.crossHatched,
          stemText: 'СК',
        ),
      );

      await catalog.saveDefinition(customDef);

      // Create a fresh catalog instance pointing to the same directory
      final reloadedCatalog = CustomValveCatalog(getStorageDir: () async => tempDir);
      await reloadedCatalog.load();

      final loaded = reloadedCatalog.getById('user_valve_persisted');
      expect(loaded, isNotNull);
      expect(loaded!.name, equals('Сохраненный клапан'));
      expect(loaded.symbol2d.leftWingStyle, equals(ValveWingFillStyle.crossHatched));
      expect(loaded.symbol2d.stemText, equals('СК'));
    });

    test('deletes user definition and updates disk file', () async {
      final customDef = CustomValveDefinition(
        id: 'user_valve_to_delete',
        name: 'Клапан на удаление',
      );
      await catalog.saveDefinition(customDef);
      expect(catalog.getById('user_valve_to_delete'), isNotNull);

      await catalog.deleteDefinition('user_valve_to_delete');
      expect(catalog.getById('user_valve_to_delete'), isNull);

      // Verify reloaded doesn't have it either
      final reloadedCatalog = CustomValveCatalog(getStorageDir: () async => tempDir);
      await reloadedCatalog.load();
      expect(reloadedCatalog.getById('user_valve_to_delete'), isNull);
    });

    test('cannot delete built-in presets', () async {
      await catalog.deleteDefinition('preset_anti_vibration_valve');
      expect(catalog.getById('preset_anti_vibration_valve'), isNotNull);
    });
  });
}
