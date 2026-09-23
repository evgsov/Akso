import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/models/custom_valve_definition.dart';
import 'package:akso/domain/models/valve.dart';
import 'package:akso/domain/models/project_model.dart';
import 'package:akso/domain/models/piping_network.dart';

void main() {
  group('CustomValveDefinition Model & Serialization Tests', () {
    test('creates CustomValveDefinition with expected default values', () {
      const def = CustomValveDefinition(
        id: 'anti_vib_1',
        name: 'Клапан антивибрационный',
      );

      expect(def.id, 'anti_vib_1');
      expect(def.name, 'Клапан антивибрационный');
      expect(def.description, isEmpty);
      expect(def.defaultLengthFactor, 1.5);
      expect(def.minLengthMm, 80.0);
      expect(def.isBuiltin, isFalse);

      expect(def.symbol2d.leftWingStyle, ValveWingFillStyle.outline);
      expect(def.symbol2d.rightWingStyle, ValveWingFillStyle.outline);
      expect(def.symbol2d.dividerType, ValveDividerType.none);
      expect(def.symbol2d.stemType, ValveStemSymbolType.handwheel);
      expect(def.symbol2d.stemText, 'Э');
      expect(def.symbol2d.hasBodyFlanges, isFalse);

      expect(def.geometry3d.bodyShape, Valve3dBodyShape.doubleCones);
      expect(def.geometry3d.actuatorType, Valve3dActuatorType.handwheel);
      expect(def.geometry3d.stemHeightRatio, 2.2);
      expect(def.geometry3d.actuatorSizeRatio, 1.4);
    });

    test('CustomValveDefinition JSON round-trip serialization preserves all fields', () {
      const def = CustomValveDefinition(
        id: 'vibro_damper',
        name: 'Виброкомпенсатор сильфонный',
        description: 'ТУ 3700-001',
        defaultLengthFactor: 1.2,
        minLengthMm: 95.0,
        isBuiltin: true,
        symbol2d: ValveSymbolConfig(
          leftWingStyle: ValveWingFillStyle.hatched,
          rightWingStyle: ValveWingFillStyle.solid,
          dividerType: ValveDividerType.zigzag,
          stemType: ValveStemSymbolType.boxWithText,
          stemText: 'АВ',
          hasBodyFlanges: true,
        ),
        geometry3d: ValveGeometry3dConfig(
          bodyShape: Valve3dBodyShape.bellows,
          actuatorType: Valve3dActuatorType.actuatorBox,
          stemHeightRatio: 2.5,
          actuatorSizeRatio: 1.8,
        ),
      );

      final json = def.toJson();
      final parsed = CustomValveDefinition.fromJson(json);

      expect(parsed.id, def.id);
      expect(parsed.name, def.name);
      expect(parsed.description, def.description);
      expect(parsed.defaultLengthFactor, def.defaultLengthFactor);
      expect(parsed.minLengthMm, def.minLengthMm);
      expect(parsed.isBuiltin, def.isBuiltin);

      expect(parsed.symbol2d.leftWingStyle, ValveWingFillStyle.hatched);
      expect(parsed.symbol2d.rightWingStyle, ValveWingFillStyle.solid);
      expect(parsed.symbol2d.dividerType, ValveDividerType.zigzag);
      expect(parsed.symbol2d.stemType, ValveStemSymbolType.boxWithText);
      expect(parsed.symbol2d.stemText, 'АВ');
      expect(parsed.symbol2d.hasBodyFlanges, isTrue);

      expect(parsed.geometry3d.bodyShape, Valve3dBodyShape.bellows);
      expect(parsed.geometry3d.actuatorType, Valve3dActuatorType.actuatorBox);
      expect(parsed.geometry3d.stemHeightRatio, 2.5);
      expect(parsed.geometry3d.actuatorSizeRatio, 1.8);
    });

    test('copyWith updates properties correctly', () {
      const def = CustomValveDefinition(
        id: 'def_1',
        name: 'Original',
      );

      final updated = def.copyWith(
        name: 'Renamed',
        description: 'New desc',
        symbol2d: def.symbol2d.copyWith(stemText: 'М'),
      );

      expect(updated.id, 'def_1');
      expect(updated.name, 'Renamed');
      expect(updated.description, 'New desc');
      expect(updated.symbol2d.stemText, 'М');
    });
  });

  group('Valve Model customDefinitionId Integration Tests', () {
    test('Valve stores customDefinitionId and preserves it across serialization', () {
      const valve = Valve(
        id: 'v1',
        segmentId: 'seg1',
        ratio: 0.5,
        valveType: ValveType.gateValve,
        name: 'Клапан антивибрационный',
        dn: 100,
        lengthMm: 150.0,
        customDefinitionId: 'vibro_damper',
      );

      expect(valve.customDefinitionId, 'vibro_damper');

      final json = valve.toJson();
      final parsed = Valve.fromJson(json);

      expect(parsed.customDefinitionId, 'vibro_damper');
    });

    test('Valve backward compatibility: legacy json without customDefinitionId deserializes to null', () {
      final legacyJson = {
        'id': 'v_legacy',
        'segmentId': 'seg1',
        'ratio': 0.3,
        'valveType': 'gateValve',
        'name': 'Задвижка',
        'dn': 50,
        'lengthMm': 120.0,
      };

      final valve = Valve.fromJson(legacyJson);
      expect(valve.customDefinitionId, isNull);
    });

    test('Valve copyWith handles customDefinitionId and clearCustomDefinition flag', () {
      const valve = Valve(
        id: 'v1',
        segmentId: 'seg1',
        ratio: 0.5,
        valveType: ValveType.gateValve,
        name: 'Valve',
        dn: 80,
        lengthMm: 160.0,
      );

      final withCustom = valve.copyWith(customDefinitionId: 'custom_1');
      expect(withCustom.customDefinitionId, 'custom_1');

      final cleared = withCustom.copyWith(clearCustomDefinition: true);
      expect(cleared.customDefinitionId, isNull);
    });
  });

  group('ProjectModel customValves Library Tests', () {
    test('ProjectModel serializes and restores customValves library map', () {
      const customDef = CustomValveDefinition(
        id: 'anti_vib_special',
        name: 'Клапан АВ специальный',
        symbol2d: ValveSymbolConfig(stemText: 'АВ'),
      );

      final project = ProjectModel(
        id: 'proj1',
        title: 'Тестовый проект',
        network: PipingNetwork(),
        customValves: {'anti_vib_special': customDef},
      );

      final json = project.toJson();
      final parsed = ProjectModel.fromJson(json);

      expect(parsed.customValves.containsKey('anti_vib_special'), isTrue);
      expect(parsed.customValves['anti_vib_special']!.name, 'Клапан АВ специальный');
      expect(parsed.customValves['anti_vib_special']!.symbol2d.stemText, 'АВ');
    });
  });
}
