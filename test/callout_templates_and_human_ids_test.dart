import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/weld_joint.dart';
import 'package:akso/domain/models/equipment.dart';
import 'package:akso/domain/models/pipe_support.dart';
import 'package:akso/domain/enums/weld_type.dart';
import 'package:akso/ui/canvas/painters/callout_painter.dart';

void main() {
  group('CalloutTargetType & Default Templates', () {
    test('all 8 target types have valid display names and non-empty default top templates', () {
      expect(CalloutTargetType.values.length, equals(8));
      expect(CalloutTargetType.nozzle.displayName, equals('Штуцер'));

      for (final type in CalloutTargetType.values) {
        expect(type.displayName.isNotEmpty, isTrue);
        expect(type.defaultTemplate.isNotEmpty, isTrue);
        expect(defaultCalloutTemplates.containsKey(type.name), isTrue);
      }
    });

    test('all target types have default bottom templates defined (or expected non-null)', () {
      expect(CalloutTargetType.segment.defaultBottomTemplate, isNotNull);
      expect(CalloutTargetType.weld.defaultBottomTemplate, contains('{DATE}'));
      expect(CalloutTargetType.valve.defaultBottomTemplate, isNotNull);
      expect(CalloutTargetType.fitting.defaultBottomTemplate, isNotNull);
      expect(CalloutTargetType.equipment.defaultBottomTemplate, isNotNull);
      expect(CalloutTargetType.nozzle.defaultBottomTemplate, isNotNull);
      expect(CalloutTargetType.support.defaultBottomTemplate, isNotNull);
      expect(CalloutTargetType.node.defaultBottomTemplate, isNotNull);
    });
  });

  group('Human-friendly IDs and Placeholders', () {
    late PipingNetwork net;

    setUp(() {
      net = PipingNetwork(
        nodes: {},
        segments: {},
        valves: {},
        weldJoints: {},
        fittings: {},
        supports: {},
        equipments: {},
      );
    });

    test('pipe segment/spool replaces {SPOOL}, {ID}, {NUM} with human mark (e.g. К-1) and never with raw UUID', () {
      const n1 = Node3D(id: 'node_1', x: 0, y: 0, z: 0);
      const n2 = Node3D(id: 'node_2', x: 2000, y: 0, z: 0);
      net.nodes[n1.id] = n1;
      net.nodes[n2.id] = n2;

      final seg = PipeSegment(
        id: 'seg_technical_uuid_9999',
        startNodeId: n1.id,
        endNodeId: n2.id,
        systemId: 'sys_1',
        dn: 80,
      );
      net.addSegment(seg);

      // Сгенерировалась катушка с number: "К-1"
      expect(net.spools.isNotEmpty, isTrue);

      final calloutText = net.formatCalloutTemplate(
        CalloutTargetType.segment,
        seg.id,
        'Поз.{SPOOL} ID={ID} №{NUM} L={CUT_LENGTH}',
      );

      // Ни в коем случае не должно быть технического "seg_technical_uuid_9999" или "spool_seg_..."
      expect(calloutText, isNot(contains('seg_technical_uuid_9999')));
      expect(calloutText, isNot(contains('spool_seg')));
      expect(calloutText, contains('Поз.К-1'));
      expect(calloutText, contains('ID=К-1'));
      expect(calloutText, contains('№К-1'));
      expect(calloutText, contains('L=2000'));
    });

    test('custom spool name is prioritized by {SPOOL} and {NAME}', () {
      const n1 = Node3D(id: 'node_1', x: 0, y: 0, z: 0);
      const n2 = Node3D(id: 'node_2', x: 2000, y: 0, z: 0);
      net.nodes[n1.id] = n1;
      net.nodes[n2.id] = n2;

      final seg = PipeSegment(
        id: 'seg_1',
        startNodeId: n1.id,
        endNodeId: n2.id,
        systemId: 'sys_1',
        dn: 80,
      );
      net.addSegment(seg);

      final spoolId = net.spools.keys.first;
      net.spools[spoolId] = net.spools[spoolId]!.copyWith(name: 'Уч-10');

      final text = net.formatCalloutTemplate(
        CalloutTargetType.segment,
        seg.id,
        '{SPOOL} / {NAME}',
      );
      expect(text, equals('Уч-10 / Уч-10'));
    });

    test('weld joint template includes {DATE} and human {NUM}', () {
      const n1 = Node3D(id: 'node_1', x: 0, y: 0, z: 0);
      const n2 = Node3D(id: 'node_2', x: 2000, y: 0, z: 0);
      net.nodes[n1.id] = n1;
      net.nodes[n2.id] = n2;

      final seg = PipeSegment(
        id: 'seg_1',
        startNodeId: n1.id,
        endNodeId: n2.id,
        systemId: 'sys_1',
        dn: 80,
      );
      net.addSegment(seg);

      const weld = WeldJoint(
        id: 'weld_tech_uuid_111',
        segmentId: 'seg_1',
        ratio: 0.5,
        number: 7,
        stamp: 'СВ-12',
        date: '18.09.2024',
        weldType: WeldType.c17,
      );
      net.weldJoints[weld.id] = weld;

      final textTop = net.formatCalloutTemplate(
        CalloutTargetType.weld,
        weld.id,
        'Стык №{NUM}',
      );
      expect(textTop, equals('Стык №7'));

      final textBottom = net.formatCalloutTemplate(
        CalloutTargetType.weld,
        weld.id,
        '{TYPE} {STAMP} {DATE}',
      );
      expect(textBottom, equals('С17 СВ-12 18.09.2024'));
    });

    test('equipment template replaces {TAG} and {ID} with clean position tag (e.g. Е-1) instead of eq_uuid', () {
      final eq = Equipment(
        id: 'eq_tech_uuid_888',
        name: 'Емкость дренажная Е-1',
        type: EquipmentType.cylinderHorizontal,
        x: 1000,
        y: 2000,
        z: 0,
        width: 1200,
        length: 3000,
        height: 1500,
      );
      net.addEquipment(eq);

      final textTop = net.formatCalloutTemplate(
        CalloutTargetType.equipment,
        eq.id,
        '{TAG}',
      );
      expect(textTop, equals('Е-1'));

      final textId = net.formatCalloutTemplate(
        CalloutTargetType.equipment,
        eq.id,
        '{ID}',
      );
      expect(textId, equals('Е-1'));

      final textBottom = net.formatCalloutTemplate(
        CalloutTargetType.equipment,
        eq.id,
        '{TYPE} {DIMENSIONS}',
      );
      expect(textBottom, equals('Цилиндр гор. 1200x3000x1500'));
    });

    test('nozzle template formats name, DN and parent equipment name', () {
      final eq = Equipment(
        id: 'eq_1',
        name: 'Емкость Е-1',
        type: EquipmentType.cylinderVertical,
        x: 0,
        y: 0,
        z: 0,
        width: 1000,
        length: 1000,
        height: 2000,
      );
      net.addEquipment(eq);

      net.attachNozzleAtWorldPoint(
        eq.id,
        const Node3D(id: '', x: 500, y: 0, z: 1000),
        dn: 100,
      );

      final noz = net.equipments[eq.id]!.nozzles.first;

      final textTop = net.formatCalloutTemplate(
        CalloutTargetType.nozzle,
        noz.id,
        'Шт. {NAME} Ду{DN}',
      );
      expect(textTop, equals('Шт. Ш-1 Ду100'));

      final textBottom = net.formatCalloutTemplate(
        CalloutTargetType.nozzle,
        noz.id,
        '{EQUIPMENT}',
      );
      expect(textBottom, equals('Емкость Е-1'));
    });

    test('CalloutPainter.getTarget3DPoint returns world coordinates of nozzle', () {
      final eq = Equipment(
        id: 'eq_1',
        name: 'Емкость Е-1',
        type: EquipmentType.cylinderVertical,
        x: 1000,
        y: 2000,
        z: 500,
        width: 1000,
        length: 1000,
        height: 2000,
      );
      net.addEquipment(eq);

      net.attachNozzleAtWorldPoint(
        eq.id,
        const Node3D(id: '', x: 1500, y: 2000, z: 1500),
        dn: 100,
      );

      final noz = net.equipments[eq.id]!.nozzles.first;
      final callout = Callout(
        id: 'callout_noz_1',
        targetId: noz.id,
        targetType: CalloutTargetType.nozzle,
      );

      final pt = CalloutPainter.getTarget3DPoint(net, callout);
      expect(pt, isNotNull);
      expect(pt!.x, closeTo(1500, 1e-3));
      expect(pt.y, closeTo(2000, 1e-3));
      expect(pt.z, closeTo(1500, 1e-3));
    });

    test('support template formats name and type', () {
      const n1 = Node3D(id: 'node_1', x: 0, y: 0, z: 0);
      const n2 = Node3D(id: 'node_2', x: 2000, y: 0, z: 0);
      net.nodes[n1.id] = n1;
      net.nodes[n2.id] = n2;

      final seg = PipeSegment(
        id: 'seg_1',
        startNodeId: n1.id,
        endNodeId: n2.id,
        systemId: 'sys_1',
        dn: 80,
      );
      net.addSegment(seg);

      const sup = PipeSupport(
        id: 'sup_tech_uuid_123',
        segmentId: 'seg_1',
        distanceRatio: 0.5,
        type: PipeSupportType.sliding,
        name: 'ОП-1',
      );
      net.supports[sup.id] = sup;

      final textTop = net.formatCalloutTemplate(
        CalloutTargetType.support,
        sup.id,
        '{NAME}',
      );
      expect(textTop, equals('ОП-1'));

      final textBottom = net.formatCalloutTemplate(
        CalloutTargetType.support,
        sup.id,
        '{TYPE}',
      );
      expect(textBottom, equals('Скользящая'));
    });
  });
}
