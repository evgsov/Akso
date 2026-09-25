import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/valve.dart';
import 'package:akso/domain/models/fitting.dart';
import 'package:akso/domain/models/pipe_support.dart';
import 'package:akso/domain/models/weld_joint.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/weld_type.dart';
import 'package:akso/domain/services/report_engine.dart';
import 'package:akso/domain/models/report_template.dart';

void main() {
  group('Spool and Element Positional Marks & Grouping', () {
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

    test('identical spools receive the same mark (К-1), different receives (К-2)', () {
      // 1. Two identical segments: DN 80, length 1500mm, wall 4.0, material Сталь 20
      const n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const n2 = Node3D(id: 'n2', x: 1500, y: 0, z: 0);
      const n3 = Node3D(id: 'n3', x: 0, y: 1000, z: 0);
      const n4 = Node3D(id: 'n4', x: 1500, y: 1000, z: 0);

      // 2. Different segment: length 3000mm
      const n5 = Node3D(id: 'n5', x: 0, y: 2000, z: 0);
      const n6 = Node3D(id: 'n6', x: 3000, y: 2000, z: 0);

      for (final n in [n1, n2, n3, n4, n5, n6]) {
        net.nodes[n.id] = n;
      }

      final s1 = PipeSegment(
        id: 's1',
        startNodeId: n1.id,
        endNodeId: n2.id,
        systemId: 'В1',
        dn: 80,
        wallThicknessMm: 4.0,
        material: 'Сталь 20',
      );
      final s2 = PipeSegment(
        id: 's2',
        startNodeId: n3.id,
        endNodeId: n4.id,
        systemId: 'В1',
        dn: 80,
        wallThicknessMm: 4.0,
        material: 'Сталь 20',
      );
      final s3 = PipeSegment(
        id: 's3',
        startNodeId: n5.id,
        endNodeId: n6.id,
        systemId: 'В1',
        dn: 80,
        wallThicknessMm: 4.0,
        material: 'Сталь 20',
      );

      net.addSegment(s1);
      net.addSegment(s2);
      net.addSegment(s3);

      expect(net.spools.length, equals(3));
      final spoolsList = net.spools.values.toList();
      final spool1 = spoolsList.firstWhere((s) => s.segmentId == 's1');
      final spool2 = spoolsList.firstWhere((s) => s.segmentId == 's2');
      final spool3 = spoolsList.firstWhere((s) => s.segmentId == 's3');

      expect(spool1.number, equals('К-1'));
      expect(spool2.number, equals('К-1'));
      expect(spool3.number, equals('К-2'));
    });

    test('identical valves receive the same mark (А-1), different receives (А-2)', () {
      final v1 = Valve(
        id: 'v1',
        segmentId: 's1',
        ratio: 0.5,
        name: 'Кран шаровой фланцевый',
        dn: 80,
        lengthMm: 150,
        valveType: ValveType.ballValve,
        counterFlangeMaterial: 'Сталь 20',
      );
      final v2 = Valve(
        id: 'v2',
        segmentId: 's2',
        ratio: 0.5,
        name: 'Кран шаровой фланцевый',
        dn: 80,
        lengthMm: 150,
        valveType: ValveType.ballValve,
        counterFlangeMaterial: 'Сталь 20',
      );
      final v3 = Valve(
        id: 'v3',
        segmentId: 's3',
        ratio: 0.5,
        name: 'Задвижка клиновая',
        dn: 80,
        lengthMm: 210,
        valveType: ValveType.gateValve,
        counterFlangeMaterial: 'Сталь 20',
      );

      net.valves[v1.id] = v1;
      net.valves[v2.id] = v2;
      net.valves[v3.id] = v3;

      net.recalculateValveMarks();

      expect(net.valves['v1']!.mark, equals('А-1'));
      expect(net.valves['v2']!.mark, equals('А-1'));
      expect(net.valves['v3']!.mark, equals('А-2'));
    });

    test('identical fittings receive the same mark (Ф-1), different receives (Ф-2)', () {
      final f1 = Fitting(
        id: 'f1',
        nodeId: 'n1',
        fittingType: FittingType.elbow90,
        radiusMm: 120,
        name: 'Отвод 90°',
        dn: 80,
        material: 'Сталь 20',
      );
      final f2 = Fitting(
        id: 'f2',
        nodeId: 'n2',
        fittingType: FittingType.elbow90,
        radiusMm: 120,
        name: 'Отвод 90°',
        dn: 80,
        material: 'Сталь 20',
      );
      final f3 = Fitting(
        id: 'f3',
        nodeId: 'n3',
        fittingType: FittingType.tee,
        radiusMm: 120,
        name: 'Тройник равнопроходный',
        dn: 80,
        material: 'Сталь 20',
      );

      net.fittings[f1.id] = f1;
      net.fittings[f2.id] = f2;
      net.fittings[f3.id] = f3;

      net.recalculateFittingMarks();

      expect(net.fittings['f1']!.mark, equals('Ф-1'));
      expect(net.fittings['f2']!.mark, equals('Ф-1'));
      expect(net.fittings['f3']!.mark, equals('Ф-2'));
    });

    test('supports receive category marks based on type (ОП-1, НО-1, etc.)', () {
      final sup1 = PipeSupport(
        id: 'sup1',
        segmentId: 's1',
        distanceRatio: 0.2,
        type: PipeSupportType.sliding,
      );
      final sup2 = PipeSupport(
        id: 'sup2',
        segmentId: 's1',
        distanceRatio: 0.8,
        type: PipeSupportType.fixed,
      );
      final sup3 = PipeSupport(
        id: 'sup3',
        segmentId: 's2',
        distanceRatio: 0.5,
        type: PipeSupportType.sliding,
      );
      final sup4 = PipeSupport(
        id: 'sup4',
        segmentId: 's2',
        distanceRatio: 0.8,
        type: PipeSupportType.sliding,
        name: 'Опора хомутовая',
      );

      net.supports[sup1.id] = sup1;
      net.supports[sup2.id] = sup2;
      net.supports[sup3.id] = sup3;
      net.supports[sup4.id] = sup4;

      net.recalculateSupportMarks();

      expect(net.supports['sup1']!.mark, equals('ОП-1'));
      expect(net.supports['sup2']!.mark, equals('НО-1'));
      expect(net.supports['sup3']!.mark, equals('ОП-1')); // Grouped with identical sup1
      expect(net.supports['sup4']!.mark, equals('ОП-2'));
    });

    test('welds have marks and positional numbers', () {
      final w1 = WeldJoint(
        id: 'w1',
        segmentId: 's1',
        ratio: 0.2,
        number: 1,
        stamp: 'СВ-01',
        weldType: WeldType.c17,
      );
      final w2 = WeldJoint(
        id: 'w2',
        segmentId: 's1',
        ratio: 0.8,
        number: 2,
        stamp: 'СВ-02',
        weldType: WeldType.c17,
      );

      net.weldJoints[w1.id] = w1;
      net.weldJoints[w2.id] = w2;

      final t1 = net.formatCalloutTemplate(CalloutTargetType.weld, 'w1', '{MARK}');
      final t2 = net.formatCalloutTemplate(CalloutTargetType.weld, 'w2', '{POS}');
      expect(t1, equals('С-1'));
      expect(t2, equals('2'));
    });
  });

  group('Callout Templates Formatting & Compact Preset', () {
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

      const n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const n2 = Node3D(id: 'n2', x: 1250, y: 0, z: 0);
      net.nodes[n1.id] = n1;
      net.nodes[n2.id] = n2;

      final s1 = PipeSegment(
        id: 's1',
        startNodeId: n1.id,
        endNodeId: n2.id,
        systemId: 'В1',
        dn: 100,
        wallThicknessMm: 4.5,
        material: '09Г2С',
      );
      net.addSegment(s1);

      final v1 = Valve(
        id: 'v1',
        segmentId: 's1',
        ratio: 0.5,
        name: 'Задвижка',
        dn: 100,
        lengthMm: 230,
        valveType: ValveType.gateValve,
      );
      net.valves[v1.id] = v1;
      net.recalculateAllMarks();
    });

    test('{MARK} and {POS} resolve correctly across elements', () {
      final spool = net.spools.values.first;

      // Targeting spool directly
      final spoolCallout = net.formatCalloutTemplate(
        CalloutTargetType.segment,
        spool.id,
        'Поз.{MARK} (L={CUT_LENGTH})',
      );
      expect(spoolCallout, equals('Поз.К-1 (L=510)'));

      // Targeting segment with fallback to spool
      final segCallout = net.formatCalloutTemplate(
        CalloutTargetType.segment,
        's1',
        '{MARK}',
      );
      expect(segCallout, equals('К-1'));

      // Valve
      final valveCallout = net.formatCalloutTemplate(
        CalloutTargetType.valve,
        'v1',
        '{MARK}: {NAME}',
      );
      expect(valveCallout, equals('А-1: Задвижка'));
    });

    test('generateMissingCallouts targets spools directly and cleanOrphanedCallouts preserves them', () {
      net.generateMissingCallouts();

      expect(net.callouts.isNotEmpty, isTrue);
      final spoolCallouts = net.callouts.values.where((c) => c.targetType == CalloutTargetType.segment).toList();
      expect(spoolCallouts.isNotEmpty, isTrue);

      final spool = net.spools.values.first;
      expect(spoolCallouts.any((c) => c.targetId == spool.id), isTrue);

      // Verify cleanOrphanedCallouts doesn't drop spool callouts
      final cleanedCount = net.cleanOrphanedCallouts();
      expect(cleanedCount, equals(0));
      expect(net.callouts.length, equals(spoolCallouts.length + 1)); // 1 spool + 1 valve
    });
  });

  group('Reports: Spools Cut List & MTO Grouping', () {
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

      // Add two identical spools (DN80, L=2000) and one different (DN80, L=1000)
      const n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      const n3 = Node3D(id: 'n3', x: 0, y: 500, z: 0);
      const n4 = Node3D(id: 'n4', x: 2000, y: 500, z: 0);
      const n5 = Node3D(id: 'n5', x: 0, y: 1000, z: 0);
      const n6 = Node3D(id: 'n6', x: 1000, y: 1000, z: 0);

      for (final n in [n1, n2, n3, n4, n5, n6]) {
        net.nodes[n.id] = n;
      }

      net.addSegment(PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'В1', dn: 80, wallThicknessMm: 4.0, material: 'Сталь 20'));
      net.addSegment(PipeSegment(id: 's2', startNodeId: 'n3', endNodeId: 'n4', systemId: 'В1', dn: 80, wallThicknessMm: 4.0, material: 'Сталь 20'));
      net.addSegment(PipeSegment(id: 's3', startNodeId: 'n5', endNodeId: 'n6', systemId: 'В1', dn: 80, wallThicknessMm: 4.0, material: 'Сталь 20'));

      // Add valves
      net.valves['v1'] = Valve(id: 'v1', segmentId: 's1', ratio: 0.5, name: 'Кран шаровой', dn: 80, lengthMm: 150, valveType: ValveType.ballValve);
      net.valves['v2'] = Valve(id: 'v2', segmentId: 's2', ratio: 0.5, name: 'Кран шаровой', dn: 80, lengthMm: 150, valveType: ValveType.ballValve);

      // Add supports
      net.supports['sup1'] = PipeSupport(id: 'sup1', segmentId: 's1', distanceRatio: 0.5, type: PipeSupportType.sliding);

      net.recalculateAllMarks();
    });

    test('Spools cut list aggregates duplicate spools into single row with qty and total cut length', () {
      final template = ReportTemplate.defaultSpoolsCutListTemplate;
      final rows = ReportEngine.generateTableData(template, net);

      expect(rows.length, equals(2)); // Row for К-1 and row for К-2

      // Check column index in defaultSpoolsCutListTemplate:
      // col 0: s_pos ('№ катушки', template: '{spool_num}')
      // col 1: s_qty ('Кол-во', template: '{qty}', isNumeric: true)
      // col 5: s_cut ('Длина реза (мм)', template: '{cut_length}', isNumeric: true)
      // col 6: s_total_cut ('Общая длина (мм)', template: '{total_cut_length}', isNumeric: true)
      final rowK1 = rows.firstWhere((r) => r[0] == 'К-1');
      expect(rowK1[1], equals(4)); // 4 identical spools around valves
      expect(rowK1[5], equals(925)); // cut_length = 925
      expect(rowK1[6], equals(3700)); // total_cut_length = 3700

      final rowK2 = rows.firstWhere((r) => r[0] == 'К-2');
      expect(rowK2[1], equals(1)); // qty = 1
      expect(rowK2[5], equals(1000)); // cut_length = 1000
      expect(rowK2[6], equals(1000)); // total_cut_length = 1000
    });

    test('MTO report includes marks for valves and supports category', () {
      final template = ReportTemplate.defaultMtoGostTemplate;
      final rows = ReportEngine.generateTableData(template, net);

      // In defaultMtoGostTemplate:
      // col 0: m_pos ('Поз.', template: '{pos}', isNumeric: true)
      // col 1: m_name ('Наименование...', template: '{name}')
      // col 2: m_mark ('Тип, марка', template: '{type_mark}')
      // col 5: m_qty ('Кол-во', template: '{qty}', isNumeric: true)

      // Valves row check
      final valveRow = rows.firstWhere((r) => r[1].toString().contains('Кран шаровой'));
      expect(valveRow[5], equals(2)); // qty
      expect(valveRow[2], equals('А-1')); // type_mark

      // Supports row check
      final supportRow = rows.firstWhere((r) => r[1].toString().contains('Опора') || r[2] == 'ОП-1');
      expect(supportRow[5], equals(1)); // qty
      expect(supportRow[2], equals('ОП-1')); // type_mark
    });
  });
}
