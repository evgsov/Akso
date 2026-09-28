import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/detail_node.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/models/linear_dimension.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/vector_scene.dart';
import 'package:akso/domain/services/sheet_geometry_builder.dart';

void main() {
  group('DetailNode (ГОСТ Выносной укрупненный узел)', () {
    late PipingNetwork network;

    setUp(() {
      network = PipingNetwork(
        nodes: {
          'n1': const Node3D(id: 'n1', x: 0, y: 0, z: 0),
          'n2': const Node3D(id: 'n2', x: 2000, y: 0, z: 0),
          'n3': const Node3D(id: 'n3', x: 4000, y: 0, z: 0),
          'n_branch_1': const Node3D(id: 'n_branch_1', x: 2000, y: 500, z: 0),
          'n_branch_2': const Node3D(id: 'n_branch_2', x: 2000, y: 500, z: 600),
        },
        segments: {
          's_main_1': const PipeSegment(
            id: 's_main_1',
            startNodeId: 'n1',
            endNodeId: 'n2',
            dn: 100,
          ),
          's_main_2': const PipeSegment(
            id: 's_main_2',
            startNodeId: 'n2',
            endNodeId: 'n3',
            dn: 100,
          ),
          's_branch_1': const PipeSegment(
            id: 's_branch_1',
            startNodeId: 'n2',
            endNodeId: 'n_branch_1',
            dn: 50,
          ),
          's_branch_2': const PipeSegment(
            id: 's_branch_2',
            startNodeId: 'n_branch_1',
            endNodeId: 'n_branch_2',
            dn: 50,
          ),
        },
        callouts: {
          'c_main': const Callout(
            id: 'c_main',
            targetType: CalloutTargetType.segment,
            targetId: 's_main_1',
            screenOffsetX: 20,
            screenOffsetY: -20,
          ),
          'c_branch': const Callout(
            id: 'c_branch',
            targetType: CalloutTargetType.segment,
            targetId: 's_branch_1',
            screenOffsetX: 20,
            screenOffsetY: -20,
          ),
        },
        dimensions: {
          'dim_main': const LinearDimension(
            id: 'dim_main',
            startNodeId: 'n1',
            endNodeId: 'n2',
            startPoint: Node3D(id: 'n1', x: 0, y: 0, z: 0),
            endPoint: Node3D(id: 'n2', x: 2000, y: 0, z: 0),
            offsetDistance: 300,
          ),
          'dim_branch': const LinearDimension(
            id: 'dim_branch',
            startNodeId: 'n2',
            endNodeId: 'n_branch_1',
            startPoint: Node3D(id: 'n2', x: 2000, y: 0, z: 0),
            endPoint: Node3D(id: 'n_branch_1', x: 2000, y: 500, z: 0),
            offsetDistance: 200,
          ),
        },
      );
    });

    test('generateNextDetailNodeMark generates Russian GOST letters excluding Ё, Й, Ъ, Ы, Ь', () {
      expect(network.generateNextDetailNodeMark(), 'А');

      const dnA = DetailNode(
        id: 'dn_1',
        mark: 'А',
        segmentIds: {'s_branch_1', 's_branch_2'},
        targetSheetId: 'sheet_2',
        targetSheetNumber: 2,
      );
      network.detailNodes['dn_1'] = dnA;

      expect(network.generateNextDetailNodeMark(), 'Б');
    });

    test('suppresses callouts and dimensions inside DetailNode on overview sheets', () {
      const dn = DetailNode(
        id: 'dn_1',
        mark: 'А',
        segmentIds: {'s_branch_1', 's_branch_2'},
        targetSheetId: 'sheet_2',
        targetSheetNumber: 2,
        suppressCalloutsOnOverview: true,
      );
      network.detailNodes['dn_1'] = dn;

      final overviewSheet = DrawingSheet.createDefault(
        id: 'sheet_1',
        name: 'Лист 1',
        sheetNumber: 1,
      );
      final detailSheet = DrawingSheet.createDefault(
        id: 'sheet_2',
        name: 'Узел А',
        sheetNumber: 2,
      ).copyWith(
        detailNodeId: 'dn_1',
      );

      final cMain = network.callouts['c_main']!;
      final cBranch = network.callouts['c_branch']!;

      // На обзорном листе выноска магистрали видна, а выноска внутри узла скрыта
      expect(overviewSheet.isCalloutVisible(cMain, network), isTrue);
      expect(overviewSheet.isCalloutVisible(cBranch, network), isFalse);

      // На детальном листе узла выноска узла видна, а выноска внешней магистрали скрыта
      expect(detailSheet.isCalloutVisible(cBranch, network), isTrue);
      expect(detailSheet.isCalloutVisible(cMain, network), isFalse);

      // Эффективная сеть обзорного листа скрывает внутренний размер узла (dim_branch), но оставляет dim_main
      final effectiveOverview = overviewSheet.getEffectiveNetwork(network);
      expect(effectiveOverview.dimensions.containsKey('dim_main'), isTrue);
      expect(effectiveOverview.dimensions.containsKey('dim_branch'), isFalse);

      // Эффективная сеть детального листа оставляет только сегменты и размеры узла
      final effectiveDetail = detailSheet.getEffectiveNetwork(network);
      expect(effectiveDetail.segments.keys, containsAll(['s_branch_1', 's_branch_2']));
      expect(effectiveDetail.segments.containsKey('s_main_1'), isFalse);
      expect(effectiveDetail.dimensions.containsKey('dim_branch'), isTrue);
      expect(effectiveDetail.dimensions.containsKey('dim_main'), isFalse);
    });

    test('computes adjacent context stubs (Variant 1) where main line connects to DetailNode', () {
      const dn = DetailNode(
        id: 'dn_1',
        mark: 'А',
        segmentIds: {'s_branch_1', 's_branch_2'},
        targetSheetId: 'sheet_2',
        targetSheetNumber: 2,
        showContextStubs: true,
        contextStubLengthMm: 450.0,
      );
      network.detailNodes['dn_1'] = dn;

      final stubs = network.getDetailNodeAdjacentStubs(dn);
      // Узел n2 принадлежит выносному узлу, к нему примыкают s_main_1 и s_main_2
      expect(stubs.length, 2);

      final stub1 = stubs.firstWhere((s) => s.segmentId == 's_main_1');
      expect(stub1.startX, closeTo(2000.0, 1e-3));
      expect(stub1.startY, closeTo(0.0, 1e-3));
      // Длина обрезка 450 мм вдоль направления от n2(2000,0,0) к n1(0,0,0) -> (1550, 0, 0)
      expect(stub1.endX, closeTo(1550.0, 1e-3));
      expect(stub1.endY, closeTo(0.0, 1e-3));

      final stub2 = stubs.firstWhere((s) => s.segmentId == 's_main_2');
      expect(stub2.startX, closeTo(2000.0, 1e-3));
      expect(stub2.endX, closeTo(2450.0, 1e-3));
    });

    test('computes free polygon hull and serializes DetailNode to/from JSON', () {
      const projector = AxonometryProjector();
      const dnBase = DetailNode(
        id: 'dn_poly',
        mark: 'В',
        title: 'Узел В',
        segmentIds: {'s_branch_1', 's_branch_2'},
        targetSheetId: 'sheet_3',
        targetSheetNumber: 3,
        boundaryShape: DetailBoundaryShape.polygon,
        paddingMm: 12.0,
      );

      final poly = dnBase.computeDefaultPolygonModel2d(network, projector);
      expect(poly.length, greaterThanOrEqualTo(4));

      final dn = dnBase.copyWith(
        polygonVerticesModel2d: poly,
        shelfPositionModel2d: const Offset(150, -60),
      );

      final json = dn.toJson();
      final restored = DetailNode.fromJson(json);

      expect(restored.id, 'dn_poly');
      expect(restored.mark, 'В');
      expect(restored.boundaryShape, DetailBoundaryShape.polygon);
      expect(restored.polygonVerticesModel2d.length, poly.length);
      expect(restored.shelfPositionModel2d, const Offset(150, -60));
    });

    test('SheetGeometryBuilder generates detailNode boundaries on overview and context stubs on detail sheet', () {
      const dn = DetailNode(
        id: 'dn_1',
        mark: 'А',
        segmentIds: {'s_branch_1', 's_branch_2'},
        targetSheetId: 'sheet_2',
        targetSheetNumber: 2,
        boundaryShape: DetailBoundaryShape.polygon,
      );
      network.detailNodes['dn_1'] = dn;

      final overviewSheet = DrawingSheet.createDefault(
        id: 'sheet_1',
        name: 'Лист 1',
        sheetNumber: 1,
      );
      final detailSheet = DrawingSheet.createDefault(
        id: 'sheet_2',
        name: 'Узел А',
        sheetNumber: 2,
      ).copyWith(
        detailNodeId: 'dn_1',
      );

      const projector = AxonometryProjector();
      final dnGeo = SheetGeometryBuilder.computeDetailNodeSheetGeometry(
        detailNode: dn,
        network: network,
        viewport: overviewSheet.viewport,
        projector: projector,
      );
      expect(dnGeo, isNotNull);
      expect(dnGeo!.polygonVerticesMm.length, greaterThanOrEqualTo(4));
      expect(dnGeo.topText, 'Узел А');
      expect(dnGeo.bottomText, 'Лист 2');

      final overviewScene = SheetGeometryBuilder.buildScene(
        sheet: overviewSheet,
        network: network,
      );
      final calloutTexts = overviewScene.items
          .where((it) => it.layer == VectorSceneLayer.callouts && it.primitive is VectorText)
          .map((it) => (it.primitive as VectorText).text)
          .toList();
      expect(calloutTexts, contains('Узел А'));
      expect(calloutTexts, contains('Лист 2'));

      final detailScene = SheetGeometryBuilder.buildScene(
        sheet: detailSheet,
        network: network,
      );
      final dashedStubs = detailScene.items
          .where((it) =>
              it.layer == VectorSceneLayer.pipes &&
              it.primitive is VectorPolyline &&
              (it.primitive as VectorPolyline).dashPattern != null)
          .toList();
      // 2 примыкающих пунктирных участка магистрали (Вариант 1)
      expect(dashedStubs.length, 2);
    });
  });
}
