import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/enums/weld_type.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/equipment.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/pipe_support.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/piping_system.dart';
import 'package:akso/domain/models/valve.dart';
import 'package:akso/domain/models/weld_joint.dart';
import 'package:akso/ui/canvas/input_controller.dart';

void main() {
  group('Callout Domain Model Tests', () {
    test('Callout JSON serialization and copyWith', () {
      const callout = Callout(
        id: 'callout_1',
        targetId: 'seg_1',
        targetType: CalloutTargetType.segment,
        customText: 'Custom Text 1',
        screenOffsetX: 80.0,
        screenOffsetY: -60.0,
        textHeight: 14.0,
        textColor: 0xFF0000FF,
      );

      final json = callout.toJson();
      final restored = Callout.fromJson(json);

      expect(restored.id, equals('callout_1'));
      expect(restored.targetId, equals('seg_1'));
      expect(restored.targetType, equals(CalloutTargetType.segment));
      expect(restored.customText, equals('Custom Text 1'));
      expect(restored.screenOffsetX, equals(80.0));
      expect(restored.screenOffsetY, equals(-60.0));
      expect(restored.textHeight, equals(14.0));
      expect(restored.textColor, equals(0xFF0000FF));
      expect(restored.isCustom, isTrue);

      // Test copyWith with clearCustomText
      final resetCallout = restored.copyWith(clearCustomText: true);
      expect(resetCallout.customText, isNull);
      expect(resetCallout.isCustom, isFalse);
    });

    test('Callout handles legacy or fallback JSON format', () {
      final json = {
        'id': 'legacy_1',
        'targetId': 'v_1',
        'targetType': 'valve',
      };
      final callout = Callout.fromJson(json);
      expect(callout.id, equals('legacy_1'));
      expect(callout.targetId, equals('v_1'));
      expect(callout.targetType, equals(CalloutTargetType.valve));
      expect(callout.screenOffsetX, equals(50.0));
      expect(callout.screenOffsetY, equals(-50.0));
      expect(callout.isCustom, isFalse);
    });
  });

  group('Callout Templating Engine Tests', () {
    late PipingNetwork network;
    late Map<String, String> templates;

    setUp(() {
      network = PipingNetwork();
      templates = Map.from(defaultCalloutTemplates);

      // Create test network entities
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2500, y: 0, z: 0);

      network.systems['sys_t3'] = const PipingSystem(
        id: 'sys_t3',
        name: 'Т3 ГВС Подающий',
        code: 'Т3',
        colorValue: 0xFFFF0000,
        dxfAciColor: 1,
      );

      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys_t3',
        dn: 80,
        outerDiameterMm: 89.0,
        wallThicknessMm: 3.5,
        slope: 0.002,
        material: '09Г2С',
      );

      network.valves['val1'] = const Valve(
        id: 'val1',
        segmentId: 'seg1',
        ratio: 0.5,
        valveType: ValveType.gateValve,
        name: 'Задвижка клиновая',
        dn: 80,
        lengthMm: 210,
      );

      network.weldJoints['weld1'] = const WeldJoint(
        id: 'weld1',
        segmentId: 'seg1',
        ratio: 0.2,
        number: 42,
        stamp: 'СВ-07',
        weldType: WeldType.factoryWeld,
        steelGrade: '09Г2С',
        electrodeGrade: 'УОНИ-13/55',
      );

      network.equipments['eq1'] = const Equipment(
        id: 'eq1',
        name: 'Насос 1К',
        type: EquipmentType.cylinderHorizontal,
        x: 0,
        y: 0,
        z: 0,
        width: 500,
        length: 800,
        height: 600,
      );

      network.supports['sup1'] = const PipeSupport(
        id: 'sup1',
        segmentId: 'seg1',
        distanceRatio: 0.8,
        type: PipeSupportType.sliding,
        name: 'Опора ОПБ2',
      );
    });

    test('Segment template substitution', () {
      const callout = Callout(
        id: 'c_seg',
        targetId: 'seg1',
        targetType: CalloutTargetType.segment,
      );

      final text = network.generateCalloutText(callout, templates);
      // default template: 'Ø{DN}x{WALL} {MATERIAL}'
      expect(text, equals('Ø80x3.5 09Г2С'));

      // Custom template with length, system and outer diameter
      final customTemplates = {
        'segment': '{SYSTEM}: Ø{OD}x{S} L={LENGTH} ({MATERIAL})',
      };
      final customText = network.generateCalloutText(callout, customTemplates);
      expect(customText, equals('Т3: Ø89x3.5 L=2500 (09Г2С)'));
    });

    test('Valve template substitution', () {
      const callout = Callout(
        id: 'c_val',
        targetId: 'val1',
        targetType: CalloutTargetType.valve,
      );

      final text = network.generateCalloutText(callout, templates);
      // default template: '{NAME} Ду{DN}'
      expect(text, equals('Задвижка клиновая Ду80'));

      // Custom template with length and type
      final customTemplates = {
        'valve': '{TYPE} {NAME} DN{DN} L={L}mm',
      };
      final customText = network.generateCalloutText(callout, customTemplates);
      expect(customText, equals('Задвижка клиновая Задвижка клиновая DN80 L=210mm'));
    });

    test('WeldJoint template substitution', () {
      const callout = Callout(
        id: 'c_weld',
        targetId: 'weld1',
        targetType: CalloutTargetType.weld,
      );

      final text = network.generateCalloutText(callout, templates);
      // default template: 'Стык №{ID}'
      expect(text, equals('Стык №42'));

      // Custom template with stamp and electrode
      final customTemplates = {
        'weld': 'Стык №{NUMBER} [{STAMP}] {ELECTRODE}',
      };
      final customText = network.generateCalloutText(callout, customTemplates);
      expect(customText, equals('Стык №42 [СВ-07] УОНИ-13/55'));
    });

    test('Equipment and Support template substitution', () {
      const eqCallout = Callout(
        id: 'c_eq',
        targetId: 'eq1',
        targetType: CalloutTargetType.equipment,
      );
      expect(network.generateCalloutText(eqCallout, templates), equals('Насос 1К'));

      const supCallout = Callout(
        id: 'c_sup',
        targetId: 'sup1',
        targetType: CalloutTargetType.support,
      );
      expect(network.generateCalloutText(supCallout, templates), equals('Опора ОПБ2'));
    });

    test('Custom text override and ignoreCustomText option', () {
      const callout = Callout(
        id: 'c_override',
        targetId: 'seg1',
        targetType: CalloutTargetType.segment,
        customText: 'Участок врезки датчика давления',
      );

      expect(network.generateCalloutText(callout, templates), equals('Участок врезки датчика давления'));
      expect(
        network.generateCalloutText(callout, templates, ignoreCustomText: true),
        equals('Ø80x3.5 09Г2С'),
      );
    });
  });

  group('Missing Callouts Auto-generation Tests', () {
    test('generateMissingCallouts generates annotations for un-annotated entities', () {
      final network = PipingNetwork();
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.segments['s1'] = const PipeSegment(
        id: 's1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys_1',
        dn: 50,
      );
      network.valves['v1'] = const Valve(
        id: 'v1',
        segmentId: 's1',
        ratio: 0.5,
        valveType: ValveType.gateValve,
        name: 'Задвижка',
        dn: 50,
        lengthMm: 150,
      );
      network.weldJoints['w1'] = const WeldJoint(
        id: 'w1',
        segmentId: 's1',
        ratio: 0.2,
        number: 1,
        stamp: 'СВ-1',
      );

      expect(network.callouts.isEmpty, isTrue);

      final addedCount = network.generateMissingCallouts(offsetX: 40.0, offsetY: -40.0);
      expect(addedCount, equals(3));
      expect(network.callouts.length, equals(3));

      // Verify all 3 targets have callouts
      final targetTypes = network.callouts.values.map((c) => c.targetType).toSet();
      expect(targetTypes, containsAll([CalloutTargetType.segment, CalloutTargetType.valve, CalloutTargetType.weld]));

      // Verify second run does not duplicate
      final secondRunAdded = network.generateMissingCallouts();
      expect(secondRunAdded, equals(0));
      expect(network.callouts.length, equals(3));
    });
  });

  group('PipingInputController Callout Management Tests', () {
    test('Controller handles toggleCalloutMode, updateCallout, and deletion cascading', () {
      final controller = PipingInputController();
      final net = controller.network;

      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      net.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys_t1',
        dn: 100,
        outerDiameterMm: 108.0,
        wallThicknessMm: 4.0,
        material: 'Сталь 20',
      );

      // Auto-generate callout
      final added = controller.generateMissingCallouts();
      expect(added, equals(1));
      final callout = controller.network.callouts.values.first;

      // Mode is template by default
      expect(callout.isCustom, isFalse);
      final templateText = controller.getCalloutText(callout);
      expect(templateText, equals('Ø100x4 Сталь 20'));

      // Switch to custom mode
      controller.toggleCalloutMode(callout.id, true);
      var updated = controller.network.callouts[callout.id]!;
      expect(updated.isCustom, isTrue);
      expect(updated.customText, equals(templateText));

      // Edit custom text
      controller.updateCalloutCustomText(callout.id, 'Трубопровод П1 (испытан)');
      updated = controller.network.callouts[callout.id]!;
      expect(controller.getCalloutText(updated), equals('Трубопровод П1 (испытан)'));

      // Switch back to template mode
      controller.toggleCalloutMode(callout.id, false);
      updated = controller.network.callouts[callout.id]!;
      expect(updated.isCustom, isFalse);
      expect(controller.getCalloutText(updated), equals('Ø100x4 Сталь 20'));

      // Test cascade delete when segment is selected and deleted
      controller.selectedSegmentId = 'seg1';
      controller.deleteSelected();
      expect(controller.network.segments.containsKey('seg1'), isFalse);
      expect(controller.network.callouts.containsKey(callout.id), isFalse);
    });

    test('Two-tier callout with customBottomText and bottom text generation', () {
      final network = PipingNetwork();
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.systems['s1'] = const PipingSystem(id: 's1', name: 'Система 1', code: 'В1', colorValue: 0xFF0000FF, dxfAciColor: 1);
      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 's1',
        dn: 150,
        wallThicknessMm: 4.5,
        material: '12Х18Н10Т',
      );

      // 1. Two-tier via newline in customText
      const c1 = Callout(
        id: 'c1',
        targetId: 'seg1',
        targetType: CalloutTargetType.segment,
        customText: 'Ø159x4.5\nГОСТ 9941-81',
      );
      expect(network.generateCalloutText(c1, const {}), equals('Ø159x4.5'));
      expect(network.generateCalloutBottomText(c1, const {}), equals('ГОСТ 9941-81'));

      // 2. Two-tier via customBottomText
      const c2 = Callout(
        id: 'c2',
        targetId: 'seg1',
        targetType: CalloutTargetType.segment,
        customText: 'Ø159x4.5',
        customBottomText: 'L=1000 мм',
      );
      expect(network.generateCalloutText(c2, const {}), equals('Ø159x4.5'));
      expect(network.generateCalloutBottomText(c2, const {}), equals('L=1000 мм'));

      // 3. Two-tier via bottom template
      const c3 = Callout(
        id: 'c3',
        targetId: 'seg1',
        targetType: CalloutTargetType.segment,
      );
      final customTemplates = {
        'segment': 'Ø{DN}x{WALL}',
        'segment_bottom': '{MATERIAL} / {SYSTEM}',
      };
      expect(network.generateCalloutText(c3, customTemplates), equals('Ø150x4.5'));
      expect(network.generateCalloutBottomText(c3, customTemplates), equals('12Х18Н10Т / В1'));

      // 4. JSON serialization roundtrip for customBottomText
      final json = c2.toJson();
      final restored = Callout.fromJson(json);
      expect(restored.customBottomText, equals('L=1000 мм'));
      expect(restored.copyWith(clearCustomBottomText: true).customBottomText, isNull);

      // 5. cleanOrphanedCallouts test
      network.callouts['c1'] = c1;
      network.callouts['c_orphan'] = const Callout(
        id: 'c_orphan',
        targetId: 'non_existent_seg',
        targetType: CalloutTargetType.segment,
      );
      expect(network.callouts.length, equals(2));
      final cleaned = network.cleanOrphanedCallouts();
      expect(cleaned, equals(1));
      expect(network.callouts.containsKey('c_orphan'), isFalse);
      expect(network.callouts.containsKey('c1'), isTrue);
    });
  });
}
