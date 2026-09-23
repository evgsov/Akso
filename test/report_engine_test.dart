import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/enums/weld_type.dart';
import 'package:akso/domain/models/equipment.dart';
import 'package:akso/domain/models/fitting.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/report_template.dart';
import 'package:akso/domain/models/valve.dart';
import 'package:akso/domain/services/report_engine.dart';

void main() {
  group('ReportEngine token evaluation', () {
    test('evaluateTemplateString replaces tokens correctly', () {
      final context = {
        'elem1_name': 'Труба',
        'elem1_dn': 100,
        'elem1_wall': 4.0,
        'connection_type': 'труба-деталь',
      };

      final res = ReportEngine.evaluateTemplateString(
        '{elem1_name} Ду{elem1_dn}x{elem1_wall} [{connection_type}]',
        context,
      );

      expect(res, 'Труба Ду100x4.0 [труба-деталь]');
    });

    test('evaluateTemplateString leaves unknown tokens empty or handles gracefully', () {
      final res = ReportEngine.evaluateTemplateString(
        'Prefix {unknown_token} Postfix',
        {'known': '123'},
      );
      expect(res, 'Prefix  Postfix');
    });
  });

  group('ReportEngine topological connection resolution', () {
    late PipingNetwork network;

    setUp(() {
      network = PipingNetwork();
    });

    test('resolves pipe-to-elbow connection as труба-деталь', () {
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 1000);
      final n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 1000);
      final n3 = Node3D(id: 'n3', x: 2000, y: 2000, z: 1000);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.nodes['n3'] = n3;

      final s1 = PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 100, systemId: 'T1');
      final s2 = PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', dn: 100, systemId: 'T1');
      network.addSegment(s1);
      network.addSegment(s2);

      // Add elbow at n2
      network.fittings['n2'] = Fitting(
        id: 'fit_elbow',
        nodeId: 'n2',
        fittingType: FittingType.elbow90,
        dn: 100,
        radiusMm: 150.0,
        name: 'Отвод 90° 108х4.0 ГОСТ 17375-2001',
      );

      final weld = network.addWeldJoint(segmentId: s1.id, ratio: 0.95, weldType: WeldType.c17);

      final context = ReportEngine.resolveWeldContext(weld, network, 1);

      expect(context['connection_type'], 'труба-деталь');
      expect(context['elem1_name'], 'Труба');
      expect(context['elem1_dn'], 100);
      expect(context['elem2_name'], contains('Отвод 90°'));
      expect(context['elem2_dn'], 100);
      expect(context['z_coord'], '1000');
      expect(context['elevation'], '+1.000');
    });

    test('resolves pipe-to-pipe coaxial connection as труба-труба', () {
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 1500, y: 0, z: 0);
      final n3 = Node3D(id: 'n3', x: 3000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.nodes['n3'] = n3;

      final s1 = PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 150, systemId: 'T1');
      final s2 = PipeSegment(id: 's2', startNodeId: 'n2', endNodeId: 'n3', dn: 150, systemId: 'T1');
      network.addSegment(s1);
      network.addSegment(s2);

      final weld = network.addWeldJoint(segmentId: s1.id, ratio: 1.0, weldType: WeldType.c17);

      final context = ReportEngine.resolveWeldContext(weld, network, 1);

      expect(context['connection_type'], 'труба-труба');
      expect(context['elem1_name'], 'Труба');
      expect(context['elem2_name'], 'Труба');
      expect(context['elem1_dn'], 150);
      expect(context['elem2_dn'], 150);
    });

    test('resolves pipe-to-valve connection as труба-арматура', () {
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 500);
      final n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 500);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      final s1 = PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 80, systemId: 'T1');
      network.addSegment(s1);

      final v = Valve(
        id: 'v1',
        segmentId: s1.id,
        ratio: 0.5,
        valveType: ValveType.gateValve,
        dn: 80,
        lengthMm: 160.0,
        name: 'Задвижка 30с41нж Ду80 Ру16',
      );
      network.valves[v.id] = v;

      final weld = network.addWeldJoint(segmentId: s1.id, ratio: 0.45, weldType: WeldType.c17);

      final context = ReportEngine.resolveWeldContext(weld, network, 1);

      expect(context['connection_type'], 'труба-арматура');
      expect(context['elem1_name'], 'Труба');
      expect(context['elem2_name'], contains('Задвижка'));
      expect(context['elem2_dn'], 80);
    });

    test('resolves pipe-to-equipment connection as труба-оборудование', () {
      final n1 = Node3D(id: 'n1', x: 500, y: 500, z: 0);
      final n2 = Node3D(id: 'n2', x: 2500, y: 500, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      final s1 = PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 100, systemId: 'T1');
      network.addSegment(s1);

      final eq = Equipment(
        id: 'eq_1',
        name: 'Емкость Е-1',
        type: EquipmentType.cylinderHorizontal,
        x: 0,
        y: 500,
        z: 0,
        width: 1000,
        length: 2000,
        height: 1000,
        nozzles: const [
          Nozzle(
            id: 'noz_1',
            equipmentId: 'eq_1',
            name: 'Ш-1',
            localX: 500,
            localY: 0,
            localZ: 0,
            dn: 100,
          ),
        ],
      );
      network.equipments[eq.id] = eq;

      final weld = network.addWeldJoint(segmentId: s1.id, ratio: 0.0, weldType: WeldType.c17);
      final context = ReportEngine.resolveWeldContext(weld, network, 1);

      expect(context['connection_type'], 'труба-оборудование');
      expect(context['elem2_name'], contains('Штуцер Ш-1 аппарата Емкость Е-1'));
    });
  });

  group('ReportEngine generateTableData', () {
    test('generates table data with Transneft template', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      final s1 = PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 100, systemId: 'T1');
      network.addSegment(s1);
      network.addWeldJoint(segmentId: s1.id, ratio: 1.0, stamp: 'А1');

      final template = ReportTemplate.defaultWeldJournalTransneftTemplate;
      final rows = ReportEngine.generateTableData(template, network);

      expect(rows.length, 1);
      expect(rows[0].length, template.columns.length);

      final colStampIdx = template.columns.indexWhere((c) => c.template == '{stamp}');
      expect(rows[0][colStampIdx], 'А1');
    });

    test('generates table data for materials specification', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.addSegment(PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 100, systemId: 'T1'));

      final template = ReportTemplate.defaultMtoGostTemplate;
      final rows = ReportEngine.generateTableData(template, network);

      expect(rows.isNotEmpty, true);
      final colNameIdx = template.columns.indexWhere((c) => c.template == '{name}');
      expect(rows[0][colNameIdx].toString(), contains('Труба'));
    });

    test('generates table data for spools list', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 3000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.addSegment(PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 100, systemId: 'T1'));
      network.recalculateSpools();

      final template = ReportTemplate.defaultSpoolsCutListTemplate;
      final rows = ReportEngine.generateTableData(template, network);

      expect(rows.isNotEmpty, true);
      final colCutIdx = template.columns.indexWhere((c) => c.template == '{cut_length}');
      expect(rows[0][colCutIdx], isNotNull);
    });

    test('generateSampleData produces rows for all report templates', () {
      final weldTemplate = ReportTemplate.defaultWeldJournalTransneftTemplate;
      final weldSampleRows = ReportEngine.generateSampleData(weldTemplate);
      expect(weldSampleRows.length, greaterThanOrEqualTo(2));
      expect(weldSampleRows.first.length, weldTemplate.columns.length);

      final mtoTemplate = ReportTemplate.defaultMtoGostTemplate;
      final mtoSampleRows = ReportEngine.generateSampleData(mtoTemplate);
      expect(mtoSampleRows.length, greaterThanOrEqualTo(2));
      expect(mtoSampleRows.first.length, mtoTemplate.columns.length);

      final spoolsTemplate = ReportTemplate.defaultSpoolsCutListTemplate;
      final spoolsSampleRows = ReportEngine.generateSampleData(spoolsTemplate);
      expect(spoolsSampleRows.length, greaterThanOrEqualTo(2));
      expect(spoolsSampleRows.first.length, spoolsTemplate.columns.length);
    });
  });
}

