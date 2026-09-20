import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/data/services/quick_bridge_service.dart';
import 'package:akso/domain/models/project_model.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/features/editor/widgets/project_properties_dialog.dart';
import 'package:akso/ui/features/editor/widgets/quick_bridge_dialog.dart';
import 'package:akso/ui/features/editor/widgets/desktop_cad_layout.dart';
import 'package:akso/ui/features/editor/widgets/top_bar.dart';

void main() {
  group('Project UI Widget Tests', () {
    late PipingInputController controller;

    setUp(() {
      controller = PipingInputController();
      controller.currentProject = ProjectModel(
        id: 'ui_p1',
        title: 'Узел котельной',
        projectCode: 'ТХ-01',
        objectAddress: 'ул. Заводская 5',
        engineerName: 'Петров П.П.',
        notes: 'Исходная заметка',
      );
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets('ProjectPropertiesDialog renders fields and saves modifications', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => ProjectPropertiesDialog(controller: controller),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Свойства проекта'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Узел котельной'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'ТХ-01'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'ул. Заводская 5'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Петров П.П.'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Исходная заметка'), findsOneWidget);

      // Change title
      final titleFinder = find.widgetWithText(TextField, 'Узел котельной');
      await tester.enterText(titleFinder, 'Узел котельной (РД)');
      await tester.pumpAndSettle();

      // Tap Save
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();

      expect(controller.currentProject.title, equals('Узел котельной (РД)'));
      expect(controller.hasUnsavedChanges, isTrue);
    });

    testWidgets('QuickBridgeDialog renders tabs and switches between Send and Receive', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => QuickBridgeDialog(
                      controller: controller,
                      enableBeacon: false,
                      initialSession: QuickBridgeSession(
                        localIp: '192.168.1.55',
                        port: 54321,
                        pin: '8899',
                      ),
                    ),
                  );
                },
                child: const Text('Open QuickBridge'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open QuickBridge'));
      await tester.pumpAndSettle();

      expect(find.text('Быстрый обмен Wi-Fi (QuickBridge)'), findsOneWidget);
      expect(find.text('Поделиться чертежом'), findsOneWidget);
      expect(find.text('Получить чертеж'), findsOneWidget);

      // By default in Send mode: should display PIN code and server URL
      expect(find.text('PIN-код подключения:'), findsOneWidget);

      // Switch to Receive tab
      await tester.tap(find.text('Получить чертеж'));
      await tester.pumpAndSettle();

      expect(find.text('Поиск устройств в сети Wi-Fi...'), findsOneWidget);
      expect(find.text('Быстрое подключение по коду / адресу:'), findsOneWidget);
    });

    testWidgets('DesktopCadLayout renders header with title, code, dirty indicator, and file menu', (tester) async {
      controller.markDirty();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopCadLayout(
              controller: controller,
              canvasWidget: const SizedBox(),
            ),
          ),
        ),
      );

      // Verify title and project code are rendered
      expect(find.text('Узел котельной'), findsOneWidget);
      expect(find.text('[ТХ-01]'), findsOneWidget);
      expect(find.text(' *'), findsOneWidget);

      // Verify tapping project title opens ProjectPropertiesDialog
      await tester.tap(find.text('Узел котельной'));
      await tester.pumpAndSettle();

      expect(find.text('Свойства проекта'), findsOneWidget);

      // Close dialog
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();

      // Verify File menu button exists and opens menu
      final fileMenuFinder = find.byTooltip('Меню проекта');
      expect(fileMenuFinder, findsOneWidget);
      await tester.tap(fileMenuFinder);
      await tester.pumpAndSettle();

      expect(find.text('Новый проект'), findsOneWidget);
      expect(find.text('Открыть...'), findsOneWidget);
      expect(find.text('Недавние проекты'), findsOneWidget);
      expect(find.text('Сохранить'), findsOneWidget);
      expect(find.text('Сохранить как...'), findsOneWidget);
      expect(find.text('Свойства проекта...'), findsOneWidget);
      expect(find.text('Wi-Fi QuickBridge...'), findsOneWidget);
      expect(find.text('Поделиться файлом...'), findsOneWidget);
    });

    testWidgets('EditorTopBar renders project title with dirty indicator and Wi-Fi button', (tester) async {
      controller.markDirty();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorTopBar(
              controller: controller,
            ),
          ),
        ),
      );

      expect(find.text('Узел котельной'), findsOneWidget);
      expect(find.text('[ТХ-01]'), findsOneWidget);
      expect(find.text(' *'), findsOneWidget);
      expect(find.text('Wi-Fi обмен'), findsOneWidget);
      expect(find.text('Сохранить *'), findsOneWidget);
    });
  });
}
