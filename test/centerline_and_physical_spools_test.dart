import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/pipe_spool.dart';
import 'package:akso/domain/models/piping_system.dart';
import 'package:akso/domain/models/weld_joint.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/services/fitting_detector.dart';

void main() {
  group('Task 1: PipeSpool Domain Model and Physical Spool Generation Tests', () {
    late PipingNetwork net;

    setUp(() {
      net = PipingNetwork();
      net.systems['sys1'] = const PipingSystem(
        id: 'sys1',
        name: 'Водоснабжение',
        code: 'В1',
        colorValue: 0xFF2196F3,
        dxfAciColor: 5,
      );
    });

    test('PipeSpool serialization and copyWith with 3D endpoints, name and serialNumber', () {
      const startPt = Node3D(id: 'pt1', x: 0, y: 150, z: 0);
      const endPt = Node3D(id: 'pt2', x: 0, y: 1850, z: 0);

      final spool = PipeSpool(
        id: 'spool_1',
        segmentId: 'seg_1',
        number: 'К-1',
        cutLengthMm: 1700.0,
        dn: 100,
        wallThickness: 4.5,
        material: '09Г2С',
        startPoint: startPt,
        endPoint: endPt,
        name: 'Катушка Т1-1',
        serialNumber: 'ПЛ-90234',
        startWeldId: 'weld_1',
        endWeldId: 'weld_2',
      );

      expect(spool.startPoint, equals(startPt));
      expect(spool.endPoint, equals(endPt));
      expect(spool.name, 'Катушка Т1-1');
      expect(spool.serialNumber, 'ПЛ-90234');
      expect(spool.cutLengthMm, 1700.0);

      final json = spool.toJson();
      final fromJson = PipeSpool.fromJson(json);

      expect(fromJson.id, spool.id);
      expect(fromJson.segmentId, spool.segmentId);
      expect(fromJson.cutLengthMm, spool.cutLengthMm);
      expect(fromJson.name, spool.name);
      expect(fromJson.serialNumber, spool.serialNumber);
      expect(fromJson.startPoint?.y, 150.0);
      expect(fromJson.endPoint?.y, 1850.0);

      final updated = spool.copyWith(
        cutLengthMm: 2000.0,
        name: 'Катушка обновленная',
        clearSerialNumber: true,
      );
      expect(updated.cutLengthMm, 2000.0);
      expect(updated.name, 'Катушка обновленная');
      expect(updated.serialNumber, isNull);
    });

    test('Single straight pipe generates 1 physical spool with exact startPoint and endPoint', () {
      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      net.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);

      net.recalculateSpools();

      expect(net.spools.length, 1);
      final spool = net.spools.values.first;
      expect(spool.cutLengthMm, 2000.0);
      expect(spool.startPoint, isNotNull);
      expect(spool.endPoint, isNotNull);
      expect(spool.startPoint!.x, 0.0);
      expect(spool.startPoint!.y, 0.0);
      expect(spool.endPoint!.x, 2000.0);
      expect(spool.endPoint!.y, 0.0);
    });

    test('Elbow-to-Elbow butt joint (distance = T1 + T2) generates EXACTLY 0 spools (no phantom pipe)', () {
      // П-образный или Z-образный участок: два отвода по 90°
      // Ду100, R=150 мм => тангенс каждого отвода T = 150 мм.
      // Расстояние между узлами n2 и n3 ровно T1 + T2 = 300 мм.
      net.nodes['n1'] = const Node3D(id: 'n1', x: -1000, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 0, y: 0, z: 0);
      net.nodes['n3'] = const Node3D(id: 'n3', x: 0, y: 300, z: 0);
      net.nodes['n4'] = const Node3D(id: 'n4', x: 1000, y: 300, z: 0);

      net.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);
      net.segments['s2'] = const PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys1', dn: 100);
      net.segments['s3'] = const PipeSegment(id: 's3', startNodeId: 'n3', endNodeId: 'n4', systemId: 'sys1', dn: 100);

      net.recalculateSpools();

      // Проверяем: для s2 (стык отвод-отвод) катушек 0!
      final s2Spools = net.spools.values.where((sp) => sp.segmentId == 's2').toList();
      expect(s2Spools.length, 0, reason: 'На стыке отвод-отвод не должно создаваться катушек трубы');

      // Для s1 и s3 катушки созданы (длина 1000 - 150 = 850 мм)
      final s1Spools = net.spools.values.where((sp) => sp.segmentId == 's1').toList();
      expect(s1Spools.length, 1);
      expect(s1Spools.first.cutLengthMm, 850.0);
      expect(s1Spools.first.endPoint!.x, -150.0); // вычет отвода в n2
    });

    test('Inline Valve on pipe segment honestly splits pipe into 2 physical spools with cutouts', () {
      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 3000, y: 0, z: 0);
      net.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);

      // Добавляем задвижку по центру (ratio: 0.5, L = 200 мм)
      net.addValve(
        segmentId: 's1',
        ratio: 0.5,
        valveType: ValveType.gateValve,
        customLengthMm: 200.0,
      );

      net.recalculateSpools();

      final s1Spools = net.spools.values.where((sp) => sp.segmentId == 's1').toList();
      expect(s1Spools.length, 2, reason: 'Задвижка должна честно разделять отрезок трубы на 2 физические катушки');

      // Центр задвижки = 1500 мм. При L=200 мм корпус задвижки занимает от 1400 до 1600 мм.
      // Катушка 1: от 0 до 1400 мм (длина 1400 мм)
      final spool1 = s1Spools[0];
      expect(spool1.cutLengthMm, 1400.0);
      expect(spool1.startPoint!.x, 0.0);
      expect(spool1.endPoint!.x, 1400.0);

      // Катушка 2: от 1600 до 3000 мм (длина 1400 мм)
      final spool2 = s1Spools[1];
      expect(spool2.cutLengthMm, 1400.0);
      expect(spool2.startPoint!.x, 1600.0);
      expect(spool2.endPoint!.x, 3000.0);
    });

    test('Pipe-to-pipe WeldJoint honestly splits pipe into 2 physical spools', () {
      net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      net.nodes['n2'] = const Node3D(id: 'n2', x: 4000, y: 0, z: 0);
      net.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys1', dn: 100);

      // Добавляем монтажный сварной шов на 1500 мм (ratio = 1500 / 4000 = 0.375)
      net.weldJoints['w1'] = const WeldJoint(
        id: 'w1',
        segmentId: 's1',
        ratio: 0.375,
        number: 1,
        stamp: 'ИВ-1',
      );

      net.recalculateSpools();

      final s1Spools = net.spools.values.where((sp) => sp.segmentId == 's1').toList();
      expect(s1Spools.length, 2, reason: 'Стык труба-труба должен делить трубу на 2 физические катушки');

      final sp1 = s1Spools[0];
      expect(sp1.cutLengthMm, closeTo(1500.0, 0.1));
      expect(sp1.startPoint!.x, 0.0);
      expect(sp1.endPoint!.x, closeTo(1500.0, 0.1));

      final sp2 = s1Spools[1];
      expect(sp2.cutLengthMm, closeTo(2500.0, 0.1));
      expect(sp2.startPoint!.x, closeTo(1500.0, 0.1));
      expect(sp2.endPoint!.x, 4000.0);
    });
  });
}
