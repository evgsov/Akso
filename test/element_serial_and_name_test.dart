import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/equipment.dart';
import 'package:akso/domain/models/fitting.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/piping_system.dart';
import 'package:akso/domain/models/valve.dart';

void main() {
  group('Domain Models: name and serialNumber tests', () {
    test('PipeSegment serialization and copyWith with name & serialNumber', () {
      const seg = PipeSegment(
        id: 'seg_1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 500,
        outerDiameterMm: 530.0,
        wallThicknessMm: 8.0,
        material: '09Г2С',
        name: 'Т1-1',
        serialNumber: 'ПАРТИЯ-84920',
      );

      expect(seg.name, equals('Т1-1'));
      expect(seg.serialNumber, equals('ПАРТИЯ-84920'));

      final json = seg.toJson();
      expect(json['name'], equals('Т1-1'));
      expect(json['serialNumber'], equals('ПАРТИЯ-84920'));

      final restored = PipeSegment.fromJson(json);
      expect(restored.name, equals('Т1-1'));
      expect(restored.serialNumber, equals('ПАРТИЯ-84920'));

      final updated = seg.copyWith(
        name: 'Т1-2',
        serialNumber: '№500-01',
      );
      expect(updated.name, equals('Т1-2'));
      expect(updated.serialNumber, equals('№500-01'));
    });

    test('Valve serialization and copyWith with serialNumber', () {
      const valve = Valve(
        id: 'v_1',
        segmentId: 'seg_1',
        ratio: 0.5,
        valveType: ValveType.gateValve,
        name: 'Задвижка 30с41нж',
        dn: 100,
        lengthMm: 230,
        serialNumber: 'ЗАВ-48192',
      );

      expect(valve.name, equals('Задвижка 30с41нж'));
      expect(valve.serialNumber, equals('ЗАВ-48192'));

      final json = valve.toJson();
      expect(json['serialNumber'], equals('ЗАВ-48192'));

      final restored = Valve.fromJson(json);
      expect(restored.name, equals('Задвижка 30с41нж'));
      expect(restored.serialNumber, equals('ЗАВ-48192'));

      final updated = valve.copyWith(serialNumber: 'ЗАВ-99999');
      expect(updated.serialNumber, equals('ЗАВ-99999'));
    });

    test('Equipment serialization and copyWith with serialNumber', () {
      const eq = Equipment(
        id: 'eq_1',
        name: 'Емкость Е-1',
        x: 0,
        y: 0,
        z: 0,
        width: 1200,
        length: 2400,
        height: 1500,
        serialNumber: 'Е-0482',
      );

      expect(eq.name, equals('Емкость Е-1'));
      expect(eq.serialNumber, equals('Е-0482'));

      final json = eq.toJson();
      expect(json['serialNumber'], equals('Е-0482'));

      final restored = Equipment.fromJson(json);
      expect(restored.serialNumber, equals('Е-0482'));

      final updated = eq.copyWith(serialNumber: 'Е-9999');
      expect(updated.serialNumber, equals('Е-9999'));
    });

    test('Fitting serialization and copyWith with serialNumber', () {
      const fit = Fitting(
        id: 'fit_1',
        nodeId: 'n1',
        fittingType: FittingType.elbow90,
        dn: 500,
        radiusMm: 750,
        name: 'Отвод 90-530х8',
        serialNumber: 'ПЛ-10492',
      );

      expect(fit.name, equals('Отвод 90-530х8'));
      expect(fit.serialNumber, equals('ПЛ-10492'));

      final json = fit.toJson();
      expect(json['serialNumber'], equals('ПЛ-10492'));

      final restored = Fitting.fromJson(json);
      expect(restored.serialNumber, equals('ПЛ-10492'));

      final updated = fit.copyWith(serialNumber: 'ПЛ-777');
      expect(updated.serialNumber, equals('ПЛ-777'));
    });
  });

  group('Callout Resolution with {NAME}, {TAG}, {SERIAL}, {BATCH}', () {
    late PipingNetwork network;

    setUp(() {
      network = PipingNetwork();
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 3000, y: 0, z: 0);

      network.systems['sys_tx'] = const PipingSystem(
        id: 'sys_tx',
        name: 'ТХ Технологический',
        code: 'ТХ',
        colorValue: 0xFF00AAFF,
        dxfAciColor: 4,
      );

      network.segments['seg_large'] = const PipeSegment(
        id: 'seg_large',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys_tx',
        dn: 500,
        outerDiameterMm: 530.0,
        wallThicknessMm: 8.0,
        material: '09Г2С',
        name: 'ТХ1-01',
        serialNumber: 'ПЛ-530-891',
      );

      network.valves['v_tech'] = const Valve(
        id: 'v_tech',
        segmentId: 'seg_large',
        ratio: 0.5,
        valveType: ValveType.gateValve,
        name: 'Задвижка 10с9бк',
        dn: 500,
        lengthMm: 700,
        serialNumber: '№ 48219',
      );

      network.equipments['eq_pump'] = const Equipment(
        id: 'eq_pump',
        name: 'Насос Н-1',
        x: 0,
        y: 0,
        z: 0,
        width: 600,
        length: 1200,
        height: 800,
        serialNumber: 'ЗАВ-1029',
      );
    });

    test('Segment callout resolves {NAME}, {TAG}, {SERIAL}, {BATCH}', () {
      const callout = Callout(
        id: 'c1',
        targetId: 'seg_large',
        targetType: CalloutTargetType.segment,
      );

      final templates = {
        'segment': '{NAME} (Ø{OD}x{S})',
        'segment_bottom': 'Зав. №{SERIAL} Партия: {BATCH}',
      };

      final top = network.generateCalloutText(callout, templates);
      final bottom = network.generateCalloutBottomText(callout, templates);

      expect(top, equals('ТХ1-01 (Ø530x8)'));
      expect(bottom, equals('Зав. №ПЛ-530-891 Партия: ПЛ-530-891'));
    });

    test('Valve callout resolves {SERIAL} and {NAME}', () {
      const callout = Callout(
        id: 'c2',
        targetId: 'v_tech',
        targetType: CalloutTargetType.valve,
      );

      final templates = {
        'valve': '{NAME} Ду{DN}',
        'valve_bottom': 'Зав. {SERIAL}',
      };

      final top = network.generateCalloutText(callout, templates);
      final bottom = network.generateCalloutBottomText(callout, templates);

      expect(top, equals('Задвижка 10с9бк Ду500'));
      expect(bottom, equals('Зав. № 48219'));
    });

    test('Equipment callout resolves {NAME} and {SERIAL}', () {
      const callout = Callout(
        id: 'c3',
        targetId: 'eq_pump',
        targetType: CalloutTargetType.equipment,
      );

      final templates = {
        'equipment': '{NAME}',
        'equipment_bottom': 'Зав. №{SERIAL}',
      };

      final top = network.generateCalloutText(callout, templates);
      final bottom = network.generateCalloutBottomText(callout, templates);

      expect(top, equals('Насос Н-1'));
      expect(bottom, equals('Зав. №ЗАВ-1029'));
    });

    test('Empty name or serial substitutes empty string without errors', () {
      network.segments['seg_empty'] = const PipeSegment(
        id: 'seg_empty',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys_tx',
        dn: 100,
      );

      const callout = Callout(
        id: 'c_empty',
        targetId: 'seg_empty',
        targetType: CalloutTargetType.segment,
      );

      final templates = {
        'segment': '{NAME} Ду{DN}',
        'segment_bottom': '{SERIAL}',
      };

      final top = network.generateCalloutText(callout, templates);
      final bottom = network.generateCalloutBottomText(callout, templates);

      expect(top, equals(' Ду100'));
      expect(bottom, isNull); // empty bottom text yields null
    });
  });
}
