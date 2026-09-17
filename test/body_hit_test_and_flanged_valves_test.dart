import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/data/dxf/dxf_writer.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/projection_type.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/enums/weld_type.dart';
import 'package:akso/domain/models/fitting.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/valve.dart';
import 'package:akso/domain/services/element_3d_geometry.dart';
import 'package:akso/domain/services/fitting_detector.dart';
import 'package:akso/domain/services/spool_calculator.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/canvas/painters/pipe_painter.dart';

void main() {
  group('Body Hit-Testing and Selection Priority', () {
    late PipingNetwork network;
    late PipingInputController controller;
    late AxonometryProjector projector;

    setUp(() {
      network = PipingNetwork();
      projector = const AxonometryProjector(projectionType: ProjectionType.gostFrontal45);
      controller = PipingInputController(network: network, projector: projector);
    });

    test('Elbow body hit-testing detects tap on curved arc away from node vertex', () {
      // Создаем L-образную трассу: (0,0,0) -> (1000,0,0) -> (1000,1000,0)
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final nCorner = Node3D(id: 'nCorner', x: 1000, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 1000, y: 1000, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[nCorner.id] = nCorner;
      network.nodes[n2.id] = n2;

      network.addSegment(const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'nCorner', dn: 100, systemId: 'sys1'));
      network.addSegment(const PipeSegment(id: 's2', startNodeId: 'nCorner', endNodeId: 'n2', dn: 100, systemId: 'sys1'));

      // В угловом узле автоматически создается отвод 90°
      final fit = network.fittings['nCorner'];
      expect(fit, isNotNull);
      expect(fit!.fittingType, equals(FittingType.elbow90));

      final cornerScreen = projector.project(nCorner);
      final p1Screen = projector.project(n1);
      final p2Screen = projector.project(n2);

      final pOut1 = PipePainter.calcPipeTrimmedPoint(
        network: network,
        nodeId: 'nCorner',
        otherNodeId: 'n1',
        nodeScreen: cornerScreen,
        otherScreen: p1Screen,
        seg: network.segments['s1']!,
      );
      final pOut2 = PipePainter.calcPipeTrimmedPoint(
        network: network,
        nodeId: 'nCorner',
        otherNodeId: 'n2',
        nodeScreen: cornerScreen,
        otherScreen: p2Screen,
        seg: network.segments['s2']!,
      );

      // Точка на дуге Безье при t=0.5 (смещена от вершины угла)
      final arcMidScreen = pOut1 * 0.25 + cornerScreen * 0.5 + pOut2 * 0.25;

      // Клик по ней корректно находит фитинг
      final hitFitId = controller.findFittingAtScreenPos(arcMidScreen);
      expect(hitFitId, equals('nCorner'));

      // Вызов handlePointerDown в режиме select должен выделить именно отвод (selectedNodeId = 'nCorner')
      controller.setTool(CanvasTool.select);
      controller.handlePointerDown(arcMidScreen);
      expect(controller.selectedNodeId, equals('nCorner'));
    });

    test('Valve body hit-testing detects tap on wireframe / handwheel', () {
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;
      final seg = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 100, systemId: 'sys1');
      network.addSegment(seg);

      final valve = network.addValve(
        segmentId: seg.id,
        ratio: 0.5,
        valveType: ValveType.gateValve,
        dn: 100,
        customLengthMm: 300,
      );

      // Получаем каркасные отрезки тела/штока/маховика задвижки
      final wireSegments = Element3dGeometry.generateValveWireframe(
        valve,
        n1,
        n2,
        pipeOuterDiameter: seg.outerDiameterMm,
      );
      expect(wireSegments, isNotEmpty);

      // Берем отрезок штока (шпинделя) или корпуса и вычисляем точку на нем
      final wire = wireSegments.first;
      final p1 = projector.project(wire.startNode);
      final p2 = projector.project(wire.endNode);
      final wirePoint = (p1 + p2) * 0.5;

      final hitValveId = controller.findValveAtScreenPos(wirePoint);
      expect(hitValveId, equals(valve.id));

      // handlePointerDown должен выделить задвижку
      controller.setTool(CanvasTool.select);
      controller.handlePointerDown(wirePoint);
      expect(controller.selectedValveId, equals(valve.id));
    });
  });

  group('Terminal Valve Mounting at Pipe End', () {
    late PipingNetwork network;

    setUp(() {
      network = PipingNetwork();
    });

    test('attachEndValveToNode places valve at open end node (degree 1) with correct offset', () {
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;
      final seg = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 100, systemId: 'sys1');
      network.addSegment(seg);

      // Монтаж на конечный узел n2 (L_valve = 200 мм)
      final valve = network.attachEndValveToNode(
        'n2',
        valveType: ValveType.gateValve,
        customLengthMm: 200,
      );

      expect(valve, isNotNull);
      expect(valve!.segmentId, equals(seg.id));
      // halfRatio = 100 / 1000 = 0.1 => ratio = 1.0 - 0.1 = 0.9
      expect(valve.ratio, closeTo(0.9, 0.001));

      // Проверка сварных стыков: со стороны трубы создается ровно 1 стык С17,
      // а на свободном срезе (1.0) шов отсутствует
      network.generateElementWeldJoints();
      final welds = network.weldJoints.values.where((w) => w.segmentId == seg.id).toList();
      expect(welds.length, equals(1));
      // Стык должен быть на внутреннем крае задвижки: 0.9 - 0.1 = 0.8
      expect(welds.first.ratio, closeTo(0.8, 0.001));
      expect(welds.first.weldType, equals(WeldType.c17));
    });

    test('attachEndValveToNode at start node (n1) places valve near ratio 0.1 with 1 weld at 0.2', () {
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;
      final seg = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 100, systemId: 'sys1');
      network.addSegment(seg);

      // Монтаж на начальный узел n1
      final valve = network.attachEndValveToNode(
        'n1',
        valveType: ValveType.gateValve,
        customLengthMm: 200,
      );

      expect(valve, isNotNull);
      // halfRatio = 100 / 1000 = 0.1 => ratio = 0.1
      expect(valve!.ratio, closeTo(0.1, 0.001));

      network.generateElementWeldJoints();
      final welds = network.weldJoints.values.where((w) => w.segmentId == seg.id).toList();
      expect(welds.length, equals(1));
      // Внутренний стык: 0.1 + 0.1 = 0.2
      expect(welds.first.ratio, closeTo(0.2, 0.001));
    });
  });

  group('Flanged Valve Settings and MTO', () {
    late PipingNetwork network;

    setUp(() {
      network = PipingNetwork();
    });

    test('Flanged valve settings are properly serialized and reflected in MTO CSV', () {
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;
      final seg = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 80, systemId: 'sys1');
      network.addSegment(seg);

      final valve = network.addValve(
        segmentId: seg.id,
        ratio: 0.5,
        valveType: ValveType.gateValve,
        dn: 80,
        isFlanged: true,
        flangePressurePn: 25,
        includeCounterFlanges: true,
        counterFlangeType: 'ГОСТ 33259-2015 тип 11',
      );

      expect(valve.isFlanged, isTrue);
      expect(valve.flangePressurePn, equals(25));
      expect(valve.includeCounterFlanges, isTrue);
      expect(valve.counterFlangeType, equals('ГОСТ 33259-2015 тип 11'));

      // Проверяем JSON сериализацию
      final json = valve.toJson();
      final fromJson = Valve.fromJson(json);
      expect(fromJson.flangePressurePn, equals(25));
      expect(fromJson.includeCounterFlanges, isTrue);
      expect(fromJson.counterFlangeType, equals('ГОСТ 33259-2015 тип 11'));

      // В ведомости материалов (MTO CSV) должны появиться ответные фланцы Ру25 и прокладки
      final csv = DxfWriter.generateMtoCsv(network);
      expect(csv, contains('Фланец ответный Ду80 Ру25'));
      expect(csv, contains('ГОСТ 33259-2015 тип 11'));
      expect(csv, contains('Прокладка межфланцевая ПОН-Б'));
    });

    test('If includeCounterFlanges is false, no welds or counter-flanges in MTO', () {
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;
      final seg = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 80, systemId: 'sys1');
      network.addSegment(seg);

      network.addValve(
        segmentId: seg.id,
        ratio: 0.5,
        valveType: ValveType.gateValve,
        dn: 80,
        isFlanged: true,
        includeCounterFlanges: false,
      );

      network.generateElementWeldJoints();
      final welds = network.weldJoints.values.where((w) => w.segmentId == seg.id).toList();
      expect(welds.isEmpty, isTrue);

      final csv = DxfWriter.generateMtoCsv(network);
      expect(csv.contains('Фланец ответный'), isFalse);
    });
  });

  group('Single Flange 180° Flip (isFlipped)', () {
    test('isFlipped inverts the orientation vector in generateFlangeWireframe', () {
      final nPipe = Node3D(id: 'nPipe', x: 0, y: 0, z: 0);
      final nFlange = Node3D(id: 'nFlange', x: 1000, y: 0, z: 0);

      // Стандартный фланец (не инвертированный)
      const flangeNormal = Fitting(
        id: 'f1',
        nodeId: 'nFlange',
        fittingType: FittingType.flange,
        dn: 100,
        radiusMm: 22.0,
        isFlangePair: false,
        flangeConnectionType: FlangeConnectionType.toEquipment,
        isFlipped: false,
      );

      // Инвертированный фланец (развернутый на 180°)
      const flangeFlipped = Fitting(
        id: 'f2',
        nodeId: 'nFlange',
        fittingType: FittingType.flange,
        dn: 100,
        radiusMm: 22.0,
        isFlangePair: false,
        flangeConnectionType: FlangeConnectionType.toEquipment,
        isFlipped: true,
      );

      final linesNormal = Element3dGeometry.generateFlangeWireframe(flangeNormal, nFlange, nPipe);
      final linesFlipped = Element3dGeometry.generateFlangeWireframe(flangeFlipped, nFlange, nPipe);

      expect(linesNormal, isNotEmpty);
      expect(linesFlipped, isNotEmpty);

      // Для toEquipment:
      // в нормальном режиме pE1 имеет координату X больше 1000 (наружу от трубы: 1000 + 12 = 1012)
      // в инвертированном режиме pE1 смещается в сторону -X (внутрь к трубе: 1000 - 12 = 988)
      final maxXNormal = linesNormal.map((l) => [l.startNode.x, l.endNode.x]).expand((x) => x).reduce((a, b) => a > b ? a : b);
      final minXFlipped = linesFlipped.map((l) => [l.startNode.x, l.endNode.x]).expand((x) => x).reduce((a, b) => a < b ? a : b);

      expect(maxXNormal, greaterThan(1000.0));
      expect(minXFlipped, lessThan(1000.0));
    });
  });

  group('Null-Safety during tracing and transitional states', () {
    test('autoDetectFittingsForNode does not crash when connected nodes are missing', () {
      final network = PipingNetwork();
      final nCorner = Node3D(id: 'nCorner', x: 1000, y: 0, z: 0);
      network.nodes[nCorner.id] = nCorner;
      // s1 and s2 reference nodes n1 and n2 that are not in network.nodes
      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'nCorner', dn: 100, systemId: 'sys1');
      network.segments['s2'] = const PipeSegment(id: 's2', startNodeId: 'nCorner', endNodeId: 'n2', dn: 100, systemId: 'sys1');

      expect(() => FittingDetector.autoDetectFittingsForNode(network, 'nCorner'), returnsNormally);
      expect(network.fittings.containsKey('nCorner'), isFalse);
    });

    test('SpoolCalculator does not crash when segment references missing nodes', () {
      final network = PipingNetwork();
      network.nodes['n1'] = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      // n2 missing from network.nodes
      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 100, systemId: 'sys1');

      expect(() => SpoolCalculator.recalculateSpools(network), returnsNormally);
    });
  });
}
