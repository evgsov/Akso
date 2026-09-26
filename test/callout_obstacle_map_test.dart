import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/valve.dart';
import 'package:akso/domain/models/equipment.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/models/sheet_format.dart';
import 'package:akso/domain/enums/sheet_format_type.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/services/callout_layout_engine.dart';
import 'package:akso/domain/services/viewport_transform_service.dart';

void main() {
  group('CalloutObstacleMap.buildSheetMap', () {
    const projector = AxonometryProjector();

    test('registers stamp (185x55 mm) in bottom-right corner with 2mm safety margin', () {
      final sheet = DrawingSheet(
        id: 'sheet_1',
        name: 'Sheet 1',
        sheetNumber: 1,
        format: const SheetFormat(type: SheetFormatType.a3, orientation: SheetOrientation.landscape),
        viewport: const SheetViewport(viewScale: 0.02),
      );
      final net = PipingNetwork();

      final map = CalloutObstacleMap.buildSheetMap(
        sheet: sheet,
        network: net,
        projector: projector,
      );

      final stamp = map.getRect('stamp');
      expect(stamp, isNotNull);

      // A3 landscape: 420x297 mm, frameRight = 5mm, frameBottom = 5mm
      // Stamp: 185x55 mm + 2mm safety margin around -> 189x59 mm
      const expectedLeft = 420.0 - 5.0 - 185.0 - 2.0; // 228.0
      const expectedTop = 297.0 - 5.0 - 55.0 - 2.0; // 235.0
      const expectedWidth = 185.0 + 4.0; // 189.0
      const expectedHeight = 55.0 + 4.0; // 59.0

      expect(stamp!.rect.left, closeTo(expectedLeft, 0.001));
      expect(stamp.rect.top, closeTo(expectedTop, 0.001));
      expect(stamp.rect.width, closeTo(expectedWidth, 0.001));
      expect(stamp.rect.height, closeTo(expectedHeight, 0.001));

      // Overlap test: shelf inside stamp collides
      final shelfInsideStamp = Rect.fromLTWH(expectedLeft + 10.0, expectedTop + 10.0, 50.0, 15.0);
      expect(map.testShelfRectOverlap(shelfInsideStamp), isTrue);
      expect(map.testShelfCollision(shelfInsideStamp), isTrue);

      // Shelf far away outside stamp does not collide
      final shelfOutside = const Rect.fromLTWH(50.0, 50.0, 50.0, 15.0);
      expect(map.testShelfRectOverlap(shelfOutside), isFalse);
    });

    test('registers sheet tables and technical requirements as rectangles with safety margin', () {
      final sheet = DrawingSheet(
        id: 'sheet_tables',
        name: 'Sheet Tables',
        sheetNumber: 1,
        format: const SheetFormat(type: SheetFormatType.a3, orientation: SheetOrientation.landscape),
        viewport: const SheetViewport(viewScale: 0.02),
        tables: const [
          SheetTableItem(
            id: 'spec_table',
            type: SheetTableType.materialsSpecification,
            xMm: 230.0,
            yMm: 120.0,
            widthMm: 185.0,
            heightMm: 70.0,
          ),
        ],
        technicalRequirements: const TechnicalRequirements(
          text: '1. Сварные швы по ГОСТ 16037-80.\n2. Испытания на герметичность.',
          xMm: 230.0,
          yMm: 195.0,
          widthMm: 185.0,
          heightMm: 35.0,
        ),
      );
      final net = PipingNetwork();

      final map = CalloutObstacleMap.buildSheetMap(
        sheet: sheet,
        network: net,
        projector: projector,
      );

      // 1. Table check
      final tableObs = map.getRect('table_spec_table');
      expect(tableObs, isNotNull);
      expect(tableObs!.rect.left, closeTo(230.0 - 2.0, 0.001)); // 228.0
      expect(tableObs.rect.top, closeTo(120.0 - 2.0, 0.001)); // 118.0
      expect(tableObs.rect.width, closeTo(185.0 + 4.0, 0.001)); // 189.0
      expect(tableObs.rect.height, closeTo(70.0 + 4.0, 0.001)); // 74.0

      // 2. Technical requirements check
      final techReqsObs = map.getRect('tech_reqs');
      expect(techReqsObs, isNotNull);
      expect(techReqsObs!.rect.left, closeTo(230.0 - 2.0, 0.001)); // 228.0
      expect(techReqsObs.rect.top, closeTo(195.0 - 2.0, 0.001)); // 193.0
      expect(techReqsObs.rect.width, closeTo(185.0 + 4.0, 0.001)); // 189.0
      expect(techReqsObs.rect.height, closeTo(35.0 + 4.0, 0.001)); // 39.0

      // Collision tests
      final shelfOnTable = const Rect.fromLTWH(235.0, 130.0, 60.0, 12.0);
      expect(map.testShelfRectOverlap(shelfOnTable), isTrue);

      final shelfOnTechReqs = const Rect.fromLTWH(235.0, 200.0, 60.0, 12.0);
      expect(map.testShelfRectOverlap(shelfOnTechReqs), isTrue);
    });

    test('registers visible pipes as SegmentObstacle with scaled outer diameter radius + 2.5mm margin', () {
      const vp = SheetViewport(
        xMm: 25.0,
        yMm: 10.0,
        widthMm: 380.0,
        heightMm: 220.0,
        viewScale: 0.05,
      );
      final sheet = DrawingSheet(
        id: 'sheet_pipes',
        name: 'Sheet Pipes',
        sheetNumber: 1,
        viewport: vp,
      );

      final net = PipingNetwork(
        nodes: const {
          'n1': Node3D(id: 'n1', x: 0, y: 0, z: 0),
          'n2': Node3D(id: 'n2', x: 2000, y: 0, z: 0),
        },
        segments: const {
          's1': PipeSegment(
            id: 's1',
            startNodeId: 'n1',
            endNodeId: 'n2',
            outerDiameterMm: 57.0,
            dn: 50,
          ),
        },
      );

      final map = CalloutObstacleMap.buildSheetMap(
        sheet: sheet,
        network: net,
        projector: projector,
      );

      final pipeObs = map.getPipe('s1');
      expect(pipeObs, isNotNull);

      // Expected radius = max(3.0, (57.0 / 2.0) * 0.05 + 2.5) = max(3.0, 28.5 * 0.05 + 2.5) = max(3.0, 3.925) = 3.925
      const expectedRadius = (57.0 / 2.0) * 0.05 + 2.5; // 3.925
      expect(pipeObs!.radius, closeTo(expectedRadius, 0.001));

      // Endpoints match projected coords
      final p1Mm = ViewportTransformService.model2dToSheetMm(projector.projectRaw(0, 0, 0), vp);
      final p2Mm = ViewportTransformService.model2dToSheetMm(projector.projectRaw(2000, 0, 0), vp);
      expect(pipeObs.p1.dx, closeTo(p1Mm.dx, 0.001));
      expect(pipeObs.p1.dy, closeTo(p1Mm.dy, 0.001));
      expect(pipeObs.p2.dx, closeTo(p2Mm.dx, 0.001));
      expect(pipeObs.p2.dy, closeTo(p2Mm.dy, 0.001));

      // Pipe collision test: shelf intersecting pipe line collides
      final midX = (p1Mm.dx + p2Mm.dx) / 2.0;
      final midY = (p1Mm.dy + p2Mm.dy) / 2.0;
      final shelfCrossingPipe = Rect.fromCenter(center: Offset(midX, midY), width: 30.0, height: 10.0);
      expect(map.testShelfPipeCollision(shelfCrossingPipe), isTrue);
      expect(map.testShelfCollision(shelfCrossingPipe), isTrue);

      // Shelf far away does not collide with pipe
      final shelfClear = Rect.fromCenter(center: Offset(midX, midY + 50.0), width: 30.0, height: 10.0);
      expect(map.testShelfPipeCollision(shelfClear), isFalse);
    });

    test('enforces minimum radius of 3.0mm for thin pipes', () {
      const vp = SheetViewport(viewScale: 0.01);
      final sheet = DrawingSheet(
        id: 'sheet_thin',
        name: 'Sheet Thin Pipe',
        sheetNumber: 1,
        viewport: vp,
      );

      final net = PipingNetwork(
        nodes: const {
          'n1': Node3D(id: 'n1', x: 0, y: 0, z: 0),
          'n2': Node3D(id: 'n2', x: 1000, y: 0, z: 0),
        },
        segments: const {
          's_thin': PipeSegment(
            id: 's_thin',
            startNodeId: 'n1',
            endNodeId: 'n2',
            outerDiameterMm: 15.0,
            dn: 15,
          ),
        },
      );

      final map = CalloutObstacleMap.buildSheetMap(
        sheet: sheet,
        network: net,
        projector: projector,
      );

      final pipeObs = map.getPipe('s_thin');
      expect(pipeObs, isNotNull);
      // (15.0 / 2.0) * 0.01 + 2.5 = 2.575 < 3.0 -> clamped to 3.0
      expect(pipeObs!.radius, equals(3.0));
    });

    test('registers equipment 2D bounding boxes centered at projected center with 6mm margin', () {
      const vp = SheetViewport(
        xMm: 25.0,
        yMm: 10.0,
        widthMm: 380.0,
        heightMm: 220.0,
        viewScale: 0.05,
      );
      final sheet = DrawingSheet(
        id: 'sheet_eq',
        name: 'Sheet Equipment',
        sheetNumber: 1,
        viewport: vp,
      );

      final net = PipingNetwork(
        equipments: const {
          'eq1': Equipment(
            id: 'eq1',
            name: 'Емкость',
            x: 1000.0,
            y: 1000.0,
            z: 0.0,
            width: 400.0,
            length: 400.0,
            height: 800.0,
          ),
        },
      );

      final map = CalloutObstacleMap.buildSheetMap(
        sheet: sheet,
        network: net,
        projector: projector,
      );

      final eqObs = map.getRect('eq_eq1');
      expect(eqObs, isNotNull);

      // Projected center: (x, y, z + height / 2) = (1000, 1000, 400)
      final centerMm = ViewportTransformService.model2dToSheetMm(
        projector.projectRaw(1000.0, 1000.0, 400.0),
        vp,
      );

      // Dimensions:
      // wMm = max(12.0, 400 * 0.05) + 6.0 = 20.0 + 6.0 = 26.0
      // hMm = max(12.0, 800 * 0.05) + 6.0 = 40.0 + 6.0 = 46.0
      expect(eqObs!.rect.center.dx, closeTo(centerMm.dx, 0.001));
      expect(eqObs.rect.center.dy, closeTo(centerMm.dy, 0.001));
      expect(eqObs.rect.width, closeTo(26.0, 0.001));
      expect(eqObs.rect.height, closeTo(46.0, 0.001));

      // Overlap check
      final shelfOverEq = Rect.fromCenter(center: centerMm, width: 20.0, height: 10.0);
      expect(map.testShelfRectOverlap(shelfOverEq), isTrue);
      expect(map.testShelfCollision(shelfOverEq), isTrue);
    });

    test('registers valves with 14x14 mm bounding boxes centered at projected valve position', () {
      const vp = SheetViewport(
        xMm: 25.0,
        yMm: 10.0,
        widthMm: 380.0,
        heightMm: 220.0,
        viewScale: 0.02,
      );
      final sheet = DrawingSheet(
        id: 'sheet_valves',
        name: 'Sheet Valves',
        sheetNumber: 1,
        viewport: vp,
      );

      final net = PipingNetwork(
        nodes: const {
          'n1': Node3D(id: 'n1', x: 0, y: 0, z: 0),
          'n2': Node3D(id: 'n2', x: 2000, y: 0, z: 0),
        },
        segments: const {
          's1': PipeSegment(
            id: 's1',
            startNodeId: 'n1',
            endNodeId: 'n2',
            outerDiameterMm: 57.0,
            dn: 50,
          ),
        },
        valves: const {
          'v1': Valve(
            id: 'v1',
            segmentId: 's1',
            ratio: 0.5,
            name: 'Кран шаровой',
            dn: 50,
            lengthMm: 120.0,
            valveType: ValveType.ballValve,
          ),
        },
      );

      final map = CalloutObstacleMap.buildSheetMap(
        sheet: sheet,
        network: net,
        projector: projector,
      );

      final valveObs = map.getRect('valve_v1');
      expect(valveObs, isNotNull);

      // Valve at ratio 0.5 between (0,0,0) and (2000,0,0) -> (1000, 0, 0)
      final valveMm = ViewportTransformService.model2dToSheetMm(
        projector.projectRaw(1000.0, 0.0, 0.0),
        vp,
      );

      expect(valveObs!.rect.center.dx, closeTo(valveMm.dx, 0.001));
      expect(valveObs.rect.center.dy, closeTo(valveMm.dy, 0.001));
      expect(valveObs.rect.width, equals(14.0));
      expect(valveObs.rect.height, equals(14.0));

      // Overlap check
      final shelfOverValve = Rect.fromCenter(center: valveMm, width: 10.0, height: 10.0);
      expect(map.testShelfRectOverlap(shelfOverValve), isTrue);
      expect(map.testShelfCollision(shelfOverValve), isTrue);
    });

    test('respects visibleSystemIds: hides segments and valves belonging to inactive systems', () {
      const vp = SheetViewport(
        viewScale: 0.02,
        visibleSystemIds: {'sys_active'},
      );
      final sheet = DrawingSheet(
        id: 'sheet_sys_filter',
        name: 'Sheet System Filter',
        sheetNumber: 1,
        viewport: vp,
      );

      final net = PipingNetwork(
        nodes: const {
          'n1': Node3D(id: 'n1', x: 0, y: 0, z: 0),
          'n2': Node3D(id: 'n2', x: 1000, y: 0, z: 0),
          'n3': Node3D(id: 'n3', x: 2000, y: 0, z: 0),
          'n4': Node3D(id: 'n4', x: 3000, y: 0, z: 0),
        },
        segments: const {
          's_active': PipeSegment(
            id: 's_active',
            startNodeId: 'n1',
            endNodeId: 'n2',
            systemId: 'sys_active',
            dn: 50,
          ),
          's_hidden': PipeSegment(
            id: 's_hidden',
            startNodeId: 'n3',
            endNodeId: 'n4',
            systemId: 'sys_hidden',
            dn: 50,
          ),
        },
        valves: const {
          'v_active': Valve(
            id: 'v_active',
            segmentId: 's_active',
            ratio: 0.5,
            name: 'Кран 1',
            dn: 50,
            lengthMm: 100.0,
            valveType: ValveType.ballValve,
          ),
          'v_hidden': Valve(
            id: 'v_hidden',
            segmentId: 's_hidden',
            ratio: 0.5,
            name: 'Кран 2',
            dn: 50,
            lengthMm: 100.0,
            valveType: ValveType.ballValve,
          ),
        },
      );

      final map = CalloutObstacleMap.buildSheetMap(
        sheet: sheet,
        network: net,
        projector: projector,
      );

      // Active segment and valve are present
      expect(map.getPipe('s_active'), isNotNull);
      expect(map.getRect('valve_v_active'), isNotNull);

      // Hidden segment and valve are filtered out
      expect(map.getPipe('s_hidden'), isNull);
      expect(map.getRect('valve_v_hidden'), isNull);
    });
  });
}
