import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/enums/fitting_type.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/piping_system.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/features/editor/widgets/desktop_cad_layout.dart';

void main() {
  group('End Fittings & Inspector Quick Actions Tests', () {
    late PipingNetwork network;
    late AxonometryProjector projector;
    late PipingInputController controller;

    setUp(() {
      network = PipingNetwork();
      projector = const AxonometryProjector();
      controller = PipingInputController(network: network, projector: projector);

      network.systems['sys1'] = const PipingSystem(
        id: 'sys1',
        name: 'Техническая вода',
        code: 'В3',
        colorValue: 0xFF0000FF,
        dxfAciColor: 5,
      );
      network.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      network.nodes['n2'] = const Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      network.segments['seg1'] = const PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        systemId: 'sys1',
        dn: 100,
      );
      network.recalculateSpools();
    });

    tearDown(() {
      controller.dispose();
    });

    test('CanvasTool.insertCap attaches cap directly when clicking open end node', () {
      controller.setTool(CanvasTool.insertCap);
      final p2 = projector.project(network.nodes['n2']!);

      controller.handlePointerDown(p2);
      controller.handlePointerUp();

      final cap = network.fittings['n2'];
      expect(cap, isNotNull);
      expect(cap!.fittingType, equals(FittingType.cap));
      expect(cap.dn, equals(100));
      expect(network.weldJoints.length, equals(0));
    });

    test('CanvasTool.insertFlange attaches terminal flange when clicking open end node', () {
      controller.setTool(CanvasTool.insertFlange);
      final p1 = projector.project(network.nodes['n1']!);

      controller.handlePointerDown(p1);
      controller.handlePointerUp();

      final flange = network.fittings['n1'];
      expect(flange, isNotNull);
      expect(flange!.fittingType, equals(FittingType.flange));
      expect(flange.dn, equals(100));
      expect(flange.isFlangePair, isFalse);
      expect(network.weldJoints.length, equals(0));
    });

    testWidgets('DesktopCadLayout inspector displays install buttons on end node and installs cap', (tester) async {
      controller.setTool(CanvasTool.select);
      controller.selectedNodeId = 'n2';
      controller.selectedNodeIds.add('n2');

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

      // Должны отображаться кнопки быстрой установки для концевого узла
      expect(find.text('Установить днище (заглушку)'), findsOneWidget);
      expect(find.text('Установить концевой фланец'), findsOneWidget);

      // Нажимаем кнопку "Установить днище (заглушку)"
      await tester.tap(find.text('Установить днище (заглушку)'));
      await tester.pumpAndSettle();

      // Проверяем, что днище установлено
      expect(network.fittings['n2'], isNotNull);
      expect(network.fittings['n2']!.fittingType, equals(FittingType.cap));

      // В инспекторе теперь отображается карточка установленного элемента и кнопка "Снять"
      expect(find.text('Снять'), findsOneWidget);
      expect(find.text('Свойства'), findsOneWidget);

      // Нажимаем "Снять"
      await tester.tap(find.text('Снять'));
      await tester.pumpAndSettle();

      // Проверяем, что днище снято и кнопки установки снова доступны
      expect(network.fittings['n2'], isNull);
      expect(find.text('Установить днище (заглушку)'), findsOneWidget);
    });

    testWidgets('DesktopCadLayout inspector installs end flange on end node', (tester) async {
      controller.setTool(CanvasTool.select);
      controller.selectedNodeId = 'n1';
      controller.selectedNodeIds.add('n1');

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

      expect(find.text('Установить концевой фланец'), findsOneWidget);

      // Нажимаем кнопку "Установить концевой фланец"
      await tester.tap(find.text('Установить концевой фланец'));
      await tester.pumpAndSettle();

      expect(network.fittings['n1'], isNotNull);
      expect(network.fittings['n1']!.fittingType, equals(FittingType.flange));
      expect(network.fittings['n1']!.isFlangePair, isFalse);

      expect(find.text('Снять'), findsOneWidget);
    });
  });
}
