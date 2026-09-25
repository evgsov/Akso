import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/custom_valve_definition.dart';
import 'package:akso/domain/services/custom_valve_catalog.dart';
import 'package:akso/ui/features/editor/widgets/custom_valve_catalog_dialog.dart';
import 'package:akso/ui/features/editor/widgets/custom_valve_editor_dialog.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('akso_valves_ui_test_');
    CustomValveCatalog.instance.setStorageDir(() async => tempDir);
  });

  tearDown(() async {
    CustomValveCatalog.instance.setStorageDir(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('CustomValveEditorDialog Widget Tests', () {
    setUp(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.views.first.physicalSize = const Size(1600, 1000);
      binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
    });

    tearDown(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.views.first.resetPhysicalSize();
      binding.platformDispatcher.views.first.resetDevicePixelRatio();
    });

    testWidgets('renders dialog with 2D and 3D preview canvases and form controls', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomValveEditorDialog(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Редактор семейства арматуры'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);
      expect(find.text('2D УГО (ГОСТ)'), findsOneWidget);
      expect(find.text('3D Геометрия'), findsOneWidget);
    });

    testWidgets('populates initial definition when provided', (tester) async {
      final initialDef = CustomValveCatalog.instance.getById('preset_anti_vibration_valve')!;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomValveEditorDialog(initialDefinition: initialDef),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Клапан антивибрационный'), findsOneWidget);
      expect(find.text('АВ'), findsOneWidget);
    });

    testWidgets('saving returns modified CustomValveDefinition', (tester) async {
      CustomValveDefinition? savedDef;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  savedDef = await showDialog<CustomValveDefinition>(
                    context: context,
                    builder: (_) => const CustomValveEditorDialog(),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Enter name
      await tester.enterText(find.byKey(const Key('valve_name_field')), 'Мой новый клапан');
      await tester.pump();

      // Tap Save
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();

      expect(savedDef, isNotNull);
      expect(savedDef!.name, equals('Мой новый клапан'));
    });
  });

  group('CustomValveCatalogDialog Widget Tests', () {
    testWidgets('lists built-in presets and allows selecting', (tester) async {
      CustomValveDefinition? selectedDef;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selectedDef = await showDialog<CustomValveDefinition>(
                    context: context,
                    builder: (_) => const CustomValveCatalogDialog(),
                  );
                },
                child: const Text('Open Catalog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Catalog'));
      await tester.pumpAndSettle();

      expect(find.text('Каталог семейств арматуры'), findsOneWidget);
      expect(find.text('Клапан антивибрационный'), findsOneWidget);
      expect(find.text('Задвижка с электроприводом'), findsOneWidget);

      // Select first preset
      final selectButtons = find.text('Выбрать');
      expect(selectButtons, findsWidgets);
      await tester.tap(selectButtons.first);
      await tester.pumpAndSettle();

      expect(selectedDef, isNotNull);
    });

    testWidgets('filters presets by search query', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomValveCatalogDialog(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Клапан антивибрационный'), findsOneWidget);
      expect(find.text('Задвижка с электроприводом'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'электро');
      await tester.pumpAndSettle();

      expect(find.text('Задвижка с электроприводом'), findsOneWidget);
      expect(find.text('Клапан антивибрационный'), findsNothing);
    });
  });
}
