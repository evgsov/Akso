import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/segment_3d.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/models/equipment.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/services/pipeline_branch_extractor.dart';

void main() {
  group('PipelineBranchExtractor', () {
    test('groups collinear/connected segments into branches and splits at tees', () {
      final net = PipingNetwork(
        nodes: {
          'n1': Node3D(id: 'n1', x: 0, y: 0, z: 0),
          'n2': Node3D(id: 'n2', x: 1000, y: 0, z: 0),
          'n3': Node3D(id: 'n3', x: 2000, y: 0, z: 0),
          'n4': Node3D(id: 'n4', x: 1000, y: 1000, z: 0), // Tee branch
        },
        segments: {
          's1': Segment3D(id: 's1', startNodeId: 'n1', endNodeId: 'n2'),
          's2': Segment3D(id: 's2', startNodeId: 'n2', endNodeId: 'n3'),
          's3': Segment3D(id: 's3', startNodeId: 'n2', endNodeId: 'n4'),
        },
        callouts: {
          'c1': Callout(id: 'c1', targetType: CalloutTargetType.segment, targetId: 's1', text: 'DN50'),
          'c2': Callout(id: 'c2', targetType: CalloutTargetType.segment, targetId: 's3', text: 'DN25'),
          'c_elev': Callout(id: 'c_elev', targetType: CalloutTargetType.node, targetId: 'n2', elevationStyle: ElevationCalloutStyle.gostOutline),
        },
      );

      final sheet = DrawingSheet(
        id: 'sheet_1',
        name: 'Sheet 1',
        viewport: ViewportSettings(scale: 0.1, centerX: 500, centerY: 500),
      );
      final projector = AxonometryProjector();

      final branches = PipelineBranchExtractor.extractBranches(
        network: net,
        sheet: sheet,
        projector: projector,
      );

      expect(branches.isNotEmpty, isTrue);
      // Tee node n2 splits the run into 3 branches
      expect(branches.length, equals(3));
      expect(branches.any((b) => b.segments.any((s) => s.id == 's1')), isTrue);
      expect(branches.any((b) => b.segments.any((s) => s.id == 's2')), isTrue);
      expect(branches.any((b) => b.segments.any((s) => s.id == 's3')), isTrue);

      // Callouts properly assigned
      final b1 = branches.firstWhere((b) => b.segments.any((s) => s.id == 's1'));
      expect(b1.callouts.any((c) => c.id == 'c1'), isTrue);

      final b3 = branches.firstWhere((b) => b.segments.any((s) => s.id == 's3'));
      expect(b3.callouts.any((c) => c.id == 'c2'), isTrue);

      // Elevation callout should not be assigned to any branch
      for (final b in branches) {
        expect(b.callouts.any((c) => c.id == 'c_elev'), isFalse);
      }
    });

    test('combines continuous segments of degree 2 into a single branch', () {
      final net = PipingNetwork(
        nodes: {
          'n1': Node3D(id: 'n1', x: 0, y: 0, z: 0),
          'n2': Node3D(id: 'n2', x: 1000, y: 0, z: 0),
          'n3': Node3D(id: 'n3', x: 2000, y: 0, z: 0),
        },
        segments: {
          's1': Segment3D(id: 's1', startNodeId: 'n1', endNodeId: 'n2'),
          's2': Segment3D(id: 's2', startNodeId: 'n2', endNodeId: 'n3'),
        },
        callouts: {
          'c1': Callout(id: 'c1', targetType: CalloutTargetType.segment, targetId: 's1', text: 'DN50'),
          'c2': Callout(id: 'c2', targetType: CalloutTargetType.segment, targetId: 's2', text: 'DN50'),
        },
      );

      final sheet = DrawingSheet(
        id: 'sheet_1',
        name: 'Sheet 1',
        viewport: ViewportSettings(scale: 0.1, centerX: 1000, centerY: 0),
      );
      final projector = AxonometryProjector();

      final branches = PipelineBranchExtractor.extractBranches(
        network: net,
        sheet: sheet,
        projector: projector,
      );

      expect(branches.length, equals(1));
      final branch = branches.first;
      expect(branch.segments.length, equals(2));
      expect(branch.segments.map((s) => s.id), containsAll(['s1', 's2']));
      expect(branch.callouts.length, equals(2));
      expect(branch.lengthSheetMm, greaterThan(0));

      // Check normals are perpendicular to branchVector2D
      final dot1 = branch.branchVector2D.dx * branch.normal1.dx + branch.branchVector2D.dy * branch.normal1.dy;
      final dot2 = branch.branchVector2D.dx * branch.normal2.dx + branch.branchVector2D.dy * branch.normal2.dy;
      expect(dot1.abs(), lessThan(1e-6));
      expect(dot2.abs(), lessThan(1e-6));
    });

    test('terminates branch at equipment connection node', () {
      final net = PipingNetwork(
        nodes: {
          'n1': Node3D(id: 'n1', x: 0, y: 0, z: 0),
          'n2': Node3D(id: 'n2', x: 1000, y: 0, z: 0, equipmentId: 'pump_1', nozzleId: 'noz_1'),
          'n3': Node3D(id: 'n3', x: 2000, y: 0, z: 0),
        },
        segments: {
          's1': Segment3D(id: 's1', startNodeId: 'n1', endNodeId: 'n2'),
          's2': Segment3D(id: 's2', startNodeId: 'n2', endNodeId: 'n3'),
        },
        equipments: {
          'pump_1': Equipment(
            id: 'pump_1',
            name: 'Насос Н-1',
            type: EquipmentType.box,
            x: 1000,
            y: 0,
            z: 0,
            width: 500,
            length: 800,
            height: 600,
            nozzles: [
              const Nozzle(id: 'noz_1', equipmentId: 'pump_1', name: 'N1', localX: 0, localY: 0, localZ: 0),
            ],
          ),
        },
      );

      final sheet = DrawingSheet(
        id: 'sheet_1',
        name: 'Sheet 1',
        viewport: ViewportSettings(scale: 0.1, centerX: 1000, centerY: 0),
      );
      final projector = AxonometryProjector();

      final branches = PipelineBranchExtractor.extractBranches(
        network: net,
        sheet: sheet,
        projector: projector,
      );

      // Node n2 is connected to equipment nozzle, so it acts as boundary
      expect(branches.length, equals(2));
      expect(branches.any((b) => b.segments.length == 1 && b.segments.first.id == 's1'), isTrue);
      expect(branches.any((b) => b.segments.length == 1 && b.segments.first.id == 's2'), isTrue);
    });

    test('filters out segments of hidden systems', () {
      final net = PipingNetwork(
        nodes: {
          'n1': Node3D(id: 'n1', x: 0, y: 0, z: 0),
          'n2': Node3D(id: 'n2', x: 1000, y: 0, z: 0),
          'n3': Node3D(id: 'n3', x: 2000, y: 0, z: 0),
        },
        segments: {
          's1': Segment3D(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_visible'),
          's2': Segment3D(id: 's2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys_hidden'),
        },
      );

      final sheet = DrawingSheet(
        id: 'sheet_1',
        name: 'Sheet 1',
        viewport: SheetViewport(
          viewScale: 0.1,
          modelCenterX: 500,
          modelCenterY: 0,
          visibleSystemIds: {'sys_visible'},
        ),
      );
      final projector = AxonometryProjector();

      final branches = PipelineBranchExtractor.extractBranches(
        network: net,
        sheet: sheet,
        projector: projector,
      );

      expect(branches.length, equals(1));
      expect(branches.first.segments.single.id, equals('s1'));
    });

    test('splits continuous run at 90-degree bend/elbow into separate straight branches', () {
      final net = PipingNetwork(
        nodes: {
          'n1': Node3D(id: 'n1', x: 0, y: 0, z: 0),
          'n2': Node3D(id: 'n2', x: 1000, y: 0, z: 0),
          'n3': Node3D(id: 'n3', x: 1000, y: 1000, z: 0), // 90 degree turn
        },
        segments: {
          's1': Segment3D(id: 's1', startNodeId: 'n1', endNodeId: 'n2'),
          's2': Segment3D(id: 's2', startNodeId: 'n2', endNodeId: 'n3'),
        },
      );

      final sheet = DrawingSheet(
        id: 'sheet_1',
        name: 'Sheet 1',
        viewport: ViewportSettings(scale: 0.1, centerX: 500, centerY: 500),
      );
      final projector = AxonometryProjector();

      final branches = PipelineBranchExtractor.extractBranches(
        network: net,
        sheet: sheet,
        projector: projector,
      );

      // Node n2 is a bend, so it must split into 2 branches
      expect(branches.length, equals(2));
      expect(branches.any((b) => b.segments.length == 1 && b.segments.first.id == 's1'), isTrue);
      expect(branches.any((b) => b.segments.length == 1 && b.segments.first.id == 's2'), isTrue);
    });
  });
}
