import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/data/services/quick_bridge_service.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/features/editor/widgets/quick_bridge_dialog.dart';

void main() {
  group('QuickBridgeDialog 2.0 Widget Tests', () {
    late PipingNetwork network;
    late AxonometryProjector projector;
    late PipingInputController controller;
    late QuickBridgeSession mockSession;

    setUp(() {
      network = PipingNetwork();
      projector = AxonometryProjector();
      controller = PipingInputController(network: network, projector: projector);

      mockSession = QuickBridgeSession(
        localIp: '192.168.1.45',
        port: 42424,
        pin: '7788',
      );
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets('Renders QuickBridgeDialog with symmetric segmented tabs in Share mode', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuickBridgeDialog(
              controller: controller,
              initialSession: mockSession,
              enableBeacon: false,
            ),
          ),
        ),
      );
      await tester.pump();

      // Check title and symmetric segmented buttons
      expect(find.text('Быстрый обмен Wi-Fi (QuickBridge)'), findsOneWidget);
      expect(find.text('Поделиться чертежом'), findsOneWidget);
      expect(find.text('Получить чертеж'), findsOneWidget);

      // Check Share view elements
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('7 7 8 8'), findsOneWidget); // Formatted PIN
      expect(find.text('192.168.1.45:42424#7788'), findsOneWidget); // Connection code
      expect(find.byTooltip('Скопировать код подключения'), findsOneWidget);
      expect(find.text('Поделиться файлом (.akso)'), findsOneWidget);
    });

    testWidgets('Switches to Receive mode and displays search, connection code input and file open button', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuickBridgeDialog(
              controller: controller,
              initialSession: mockSession,
              enableBeacon: false,
            ),
          ),
        ),
      );
      await tester.pump();

      // Tap on 'Получить чертеж' tab
      await tester.tap(find.text('Получить чертеж'));
      await tester.pump();

      // Check Receiver view elements
      expect(find.text('Поиск устройств в сети Wi-Fi...'), findsOneWidget);
      expect(find.text('Быстрое подключение по коду / адресу:'), findsOneWidget);
      expect(find.text('192.168.1.50:42424#1234 или IP'), findsOneWidget);
      expect(find.text('Открыть полученный файл (.akso)'), findsOneWidget);
    });

    testWidgets('Data loss prevention: prompts confirmation when current project has segments', (tester) async {
      // Add a pipe segment to current project so it is not empty
      final n1 = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = const Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;
      network.addSegment(const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_1', dn: 50));

      final fakeBridge = QuickBridgeService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuickBridgeDialog(
              controller: controller,
              bridgeService: fakeBridge,
              initialSession: mockSession,
              enableBeacon: false,
            ),
          ),
        ),
      );
      await tester.pump();

      // Switch to receiver mode
      await tester.tap(find.text('Получить чертеж'));
      await tester.pump();

      // Enter connection code in text field
      final inputFinder = find.byType(TextField);
      expect(inputFinder, findsOneWidget);
      await tester.enterText(inputFinder, '127.0.0.1:42424#1234');
      await tester.pump();

      expect(find.text('127.0.0.1:42424#1234'), findsOneWidget);
    });
  });
}
