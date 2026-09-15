import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/enums/weld_type.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/piping_system.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/features/editor/widgets/desktop_cad_layout.dart';

void main() {
  group('Dissolve Node & Branch Selector Tests', () {
    late PipingNetwork network;
    late AxonometryProjector projector;
    late PipingInputController controller;

    setUp(() {
      network = PipingNetwork();
      projector = const AxonometryProjector();
      controller = PipingInputController(network: network, projector: projector);

      network.systems['sys1'] = const PipingSystem(
        id: 'sys1',
        name: 'Технологическая',
        code: 'ТХ',
        colorValue: 0xFF0000FF,
        dxfAciColor: 5,
      );
    });

    tearDown(() {
      controller.dispose();
    });

    test('Single node deletion dissolves node and merges two collinear segments', () {
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes['n3'] = const Node3D(id: 'n3', x: 2500, y: 0, z: 0);

      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 100,
      );
      network.segments['seg2'] = const PipeSegment(
        id: 'seg2',
        startNodeId: 'n2',
        endNodeId: 'n3',
        systemId: 'sys1',
        dn: 100,
      );
      network.recalculateSpools();

      // Выделяем промежуточный узел n2
      controller.selectedNodeId = 'n2';
      controller.selectedNodeIds.add('n2');

      // Нажимаем Delete (deleteSelected)
      controller.deleteSelected();

      // Узел n2 удален, а трубы объединены в одну n1 -> n3
      expect(network.nodes.containsKey('n2'), isFalse);
      expect(network.nodes.containsKey('n1'), isTrue);
      expect(network.nodes.containsKey('n3'), isTrue);

      expect(network.segments.length, equals(1));
      final merged = network.segments.values.first;
      expect(merged.startNodeId, equals('n1'));
      expect(merged.endNodeId, equals('n3'));
      expect(merged.dn, equals(100));
    });

    test('Single node deletion on a tee removes branch and merges mainline', () {
      network.nodes['nL'] = const Node3D(id: 'nL', x: 0, y: 1000, z: 0);
      network.nodes['nC'] = const Node3D(id: 'nC', x: 1000, y: 1000, z: 0);
      network.nodes['nR'] = const Node3D(id: 'nR', x: 2000, y: 1000, z: 0);
      network.nodes['nB'] = const Node3D(id: 'nB', x: 1000, y: 2500, z: 0);

      network.segments['sRun1'] = const PipeSegment(id: 'sRun1', startNodeId: 'nL', endNodeId: 'nC', systemId: 'sys1', dn: 100);
      network.segments['sRun2'] = const PipeSegment(id: 'sRun2', startNodeId: 'nC', endNodeId: 'nR', systemId: 'sys1', dn: 100);
      network.segments['sBranch'] = const PipeSegment(id: 'sBranch', startNodeId: 'nC', endNodeId: 'nB', systemId: 'sys1', dn: 50);
      network.recalculateSpools();

      // Выделяем центральный узел тройника nC
      controller.selectedNodeId = 'nC';
      controller.selectedNodeIds.add('nC');

      controller.deleteSelected();

      expect(network.nodes.containsKey('nC'), isFalse);
      expect(network.segments.containsKey('sBranch'), isFalse);
      expect(network.segments.length, equals(1));

      final merged = network.segments.values.first;
      expect(merged.startNodeId, equals('nL'));
      expect(merged.endNodeId, equals('nR'));
    });

    testWidgets('DesktopCadLayout inspector allows toggling between Tee and DirectBranch in 1 click', (tester) async {
      network.nodes['nL'] = const Node3D(id: 'nL', x: 0, y: 1000, z: 0);
      network.nodes['nC'] = const Node3D(id: 'nC', x: 1000, y: 1000, z: 0);
      network.nodes['nR'] = const Node3D(id: 'nR', x: 2000, y: 1000, z: 0);
      network.nodes['nB'] = const Node3D(id: 'nB', x: 1000, y: 2000, z: 0);

      network.segments['sRun1'] = const PipeSegment(id: 'sRun1', startNodeId: 'nL', endNodeId: 'nC', systemId: 'sys1', dn: 100);
      network.segments['sRun2'] = const PipeSegment(id: 'sRun2', startNodeId: 'nC', endNodeId: 'nR', systemId: 'sys1', dn: 100);
      network.segments['sBranch'] = const PipeSegment(id: 'sBranch', startNodeId: 'nC', endNodeId: 'nB', systemId: 'sys1', dn: 50);
      network.autoDetectAllFittings();
      network.recalculateSpools();

      // Выбираем узел тройника
      controller.setTool(CanvasTool.select);
      controller.selectedNodeId = 'nC';
      controller.selectedNodeIds.add('nC');

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => DesktopCadLayout(
              controller: controller,
              canvasWidget: const SizedBox(width: 800, height: 600),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Должен отображаться переключатель типа ответвления
      expect(find.text('Исполнение ответвления:'), findsOneWidget);
      expect(find.text('Тройник (3 стыка)'), findsOneWidget);
      expect(find.text('Врезка У18 (1 шов)'), findsOneWidget);

      // Исходно установлен Тройник
      final fitBefore = network.fittings['nC'];
      expect(fitBefore, isNotNull);
      expect(fitBefore!.fittingType, equals(FittingType.tee));

      // Нажимаем «Врезка У18 (1 шов)»
      await tester.tap(find.text('Врезка У18 (1 шов)'));
      await tester.pumpAndSettle();

      // Фитинг обновился в прямую врезку
      final fitAfterDirect = network.fittings['nC'];
      expect(fitAfterDirect, isNotNull);
      expect(fitAfterDirect!.fittingType, equals(FittingType.directBranch));
      expect(fitAfterDirect.weldType, equals(WeldType.u18));
      expect(fitAfterDirect.cutsMainPipe, isFalse);

      // Нажимаем обратно «Тройник (3 стыка)»
      await tester.tap(find.text('Тройник (3 стыка)'));
      await tester.pumpAndSettle();

      final fitBackToTee = network.fittings['nC'];
      expect(fitBackToTee, isNotNull);
      expect(fitBackToTee!.fittingType, equals(FittingType.tee));
      expect(fitBackToTee.cutsMainPipe, isTrue);
    });
  });
}
