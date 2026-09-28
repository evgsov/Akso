import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/enums/projection_type.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/models/project_model.dart';
import 'package:akso/domain/models/sheet_view_preset.dart';
import 'package:akso/ui/canvas/input_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SheetViewPreset Domain Model', () {
    test('Correctly computes scaleText and projectionTitle', () {
      final preset50 = SheetViewPreset(
        id: 'p1',
        name: 'План М 1:50',
        createdAt: DateTime(2026, 9, 28, 12, 0),
        viewScale: 0.02,
        modelCenterX: 500,
        modelCenterY: 1000,
        projectionType: ProjectionType.gostFrontal45,
      );

      expect(preset50.scaleText, equals('1:50'));
      expect(preset50.projectionTitle, equals('ГОСТ 45° (Фронтальная)'));

      final preset25Iso = SheetViewPreset(
        id: 'p2',
        name: 'Изометрия М 1:25',
        createdAt: DateTime(2026, 9, 28, 12, 5),
        viewScale: 0.04,
        modelCenterX: 200,
        modelCenterY: 300,
        projectionType: ProjectionType.iso30,
      );

      expect(preset25Iso.scaleText, equals('1:25'));
      expect(preset25Iso.projectionTitle, equals('ISO 30° (Изометрия)'));

      final presetOrbit = SheetViewPreset(
        id: 'p3',
        name: 'Ракурс 3D',
        createdAt: DateTime(2026, 9, 28, 12, 10),
        viewScale: 0.01,
        modelCenterX: 0,
        modelCenterY: 0,
        projectionType: ProjectionType.orbit3d,
      );

      expect(presetOrbit.projectionTitle, equals('3D Орбита'));
    });

    test('toJson and fromJson preserves all fields', () {
      final original = SheetViewPreset(
        id: 'preset_test_123',
        name: 'Финальный ракурс узла',
        createdAt: DateTime(2026, 9, 28, 15, 30, 45),
        viewScale: 0.05,
        modelCenterX: 1250.5,
        modelCenterY: -450.0,
        modelCenterZ: 100.0,
        projectionType: ProjectionType.orbit3d,
        orbitAzimuth: -0.75,
        orbitElevation: 0.52,
      );

      final json = original.toJson();
      final restored = SheetViewPreset.fromJson(json);

      expect(restored.id, equals(original.id));
      expect(restored.name, equals(original.name));
      expect(restored.createdAt, equals(original.createdAt));
      expect(restored.viewScale, equals(original.viewScale));
      expect(restored.modelCenterX, equals(original.modelCenterX));
      expect(restored.modelCenterY, equals(original.modelCenterY));
      expect(restored.modelCenterZ, equals(original.modelCenterZ));
      expect(restored.projectionType, equals(original.projectionType));
      expect(restored.orbitAzimuth, closeTo(original.orbitAzimuth, 1e-6));
      expect(restored.orbitElevation, closeTo(original.orbitElevation, 1e-6));
    });

    test('SheetViewport serialization preserves projectionType and orbit angles', () {
      const vp = SheetViewport(
        xMm: 20,
        yMm: 15,
        widthMm: 300,
        heightMm: 200,
        viewScale: 0.025,
        projectionType: ProjectionType.gostMirrored45,
        orbitAzimuth: -1.2,
        orbitElevation: 0.45,
      );

      final json = vp.toJson();
      final restored = SheetViewport.fromJson(json);

      expect(restored.projectionType, equals(ProjectionType.gostMirrored45));
      expect(restored.orbitAzimuth, closeTo(-1.2, 1e-6));
      expect(restored.orbitElevation, closeTo(0.45, 1e-6));
      expect(restored.viewScale, equals(0.025));
    });

    test('DrawingSheet serialization preserves viewPresets list', () {
      final sheet = DrawingSheet.createDefault(
        id: 'sheet_1',
        name: 'Лист 1',
        sheetNumber: 1,
      ).copyWith(
        viewPresets: [
          SheetViewPreset(
            id: 'vp1',
            name: 'Вид 1',
            createdAt: DateTime(2026, 9, 28, 10, 0),
            viewScale: 0.02,
            modelCenterX: 100,
            modelCenterY: 200,
            projectionType: ProjectionType.gostFrontal45,
          ),
          SheetViewPreset(
            id: 'vp2',
            name: 'Вид 2',
            createdAt: DateTime(2026, 9, 28, 11, 0),
            viewScale: 0.04,
            modelCenterX: 300,
            modelCenterY: 400,
            projectionType: ProjectionType.iso30,
          ),
        ],
      );

      final json = sheet.toJson();
      final restored = DrawingSheet.fromJson(json);

      expect(restored.viewPresets.length, equals(2));
      expect(restored.viewPresets[0].name, equals('Вид 1'));
      expect(restored.viewPresets[0].viewScale, equals(0.02));
      expect(restored.viewPresets[1].name, equals('Вид 2'));
      expect(restored.viewPresets[1].projectionType, equals(ProjectionType.iso30));
    });
  });

  group('PipingInputController View Preset and Projection Management', () {
    late PipingInputController controller;

    setUp(() {
      controller = PipingInputController();
      final s1 = DrawingSheet.createDefault(id: 's1', name: 'Лист 1', sheetNumber: 1).copyWith(
        viewport: const SheetViewport(
          viewScale: 0.02,
          projectionType: ProjectionType.gostFrontal45,
          orbitAzimuth: -math.pi / 4,
          orbitElevation: math.pi / 6,
        ),
      );
      final s2 = DrawingSheet.createDefault(id: 's2', name: 'Лист 2', sheetNumber: 2).copyWith(
        viewport: const SheetViewport(
          viewScale: 0.04,
          projectionType: ProjectionType.iso30,
          orbitAzimuth: -math.pi / 3,
          orbitElevation: math.pi / 4,
        ),
      );

      controller.currentProject = ProjectModel(
        id: 'test_proj',
        title: 'Тестовый проект',
        sheets: [s1, s2],
        activeSheetId: 's1',
      );
      controller.selectSheet('s1');
    });

    test('selectSheet synchronizes projector with active sheet viewport', () {
      expect(controller.activeSheetId, equals('s1'));
      expect(controller.activeSheet!.viewport.projectionType, equals(ProjectionType.gostFrontal45));
      expect(controller.projector.projectionType, equals(ProjectionType.gostFrontal45));

      controller.selectSheet('s2');

      expect(controller.activeSheetId, equals('s2'));
      expect(controller.activeSheet!.viewport.projectionType, equals(ProjectionType.iso30));
      expect(controller.projector.projectionType, equals(ProjectionType.iso30));
      expect(controller.projector.orbitAzimuth, closeTo(-math.pi / 3, 1e-6));
    });

    test('setSheetViewScale isolates scale to target sheet', () {
      controller.setSheetViewScale('s1', 0.01);

      final s1 = controller.sheets.firstWhere((s) => s.id == 's1');
      final s2 = controller.sheets.firstWhere((s) => s.id == 's2');

      expect(s1.viewport.viewScale, equals(0.01));
      expect(s2.viewport.viewScale, equals(0.04)); // Unchanged!
    });

    test('setSheetProjectionType isolates projection to target sheet', () {
      controller.setSheetProjectionType('s1', ProjectionType.topPlan2d);

      final s1 = controller.sheets.firstWhere((s) => s.id == 's1');
      final s2 = controller.sheets.firstWhere((s) => s.id == 's2');

      expect(s1.viewport.projectionType, equals(ProjectionType.topPlan2d));
      expect(controller.projector.projectionType, equals(ProjectionType.topPlan2d));
      expect(s2.viewport.projectionType, equals(ProjectionType.iso30)); // Unchanged!
    });

    test('saveCurrentSheetViewPreset saves current scale and projection and can be applied', () {
      controller.setSheetViewScale('s1', 0.025);
      controller.setSheetProjectionType('s1', ProjectionType.gostMirrored45);

      controller.saveCurrentSheetViewPreset('s1', 'Зеркальный 1:40');

      var s1 = controller.sheets.firstWhere((s) => s.id == 's1');
      expect(s1.viewPresets.length, equals(1));
      final preset = s1.viewPresets.first;
      expect(preset.name, equals('Зеркальный 1:40'));
      expect(preset.viewScale, equals(0.025));
      expect(preset.projectionType, equals(ProjectionType.gostMirrored45));

      // Modify sheet 1 to something else
      controller.setSheetViewScale('s1', 0.01);
      controller.setSheetProjectionType('s1', ProjectionType.topPlan2d);
      s1 = controller.sheets.firstWhere((s) => s.id == 's1');
      expect(s1.viewport.viewScale, equals(0.01));
      expect(s1.viewport.projectionType, equals(ProjectionType.topPlan2d));

      // Apply the preset
      controller.applySheetViewPreset('s1', preset.id);

      s1 = controller.sheets.firstWhere((s) => s.id == 's1');
      expect(s1.viewport.viewScale, equals(0.025));
      expect(s1.viewport.projectionType, equals(ProjectionType.gostMirrored45));
      expect(controller.projector.projectionType, equals(ProjectionType.gostMirrored45));

      // Delete preset
      controller.deleteSheetViewPreset('s1', preset.id);
      s1 = controller.sheets.firstWhere((s) => s.id == 's1');
      expect(s1.viewPresets, isEmpty);
    });

    test('orbit updates active sheet viewport when viewport is focused', () {
      controller.isViewportFocused = true;
      controller.orbit(const Offset(50, 20));

      final s1 = controller.sheets.firstWhere((s) => s.id == 's1');
      expect(s1.viewport.projectionType, equals(ProjectionType.orbit3d));
      expect(controller.projector.projectionType, equals(ProjectionType.orbit3d));

      final s2 = controller.sheets.firstWhere((s) => s.id == 's2');
      expect(s2.viewport.projectionType, equals(ProjectionType.iso30)); // Sheet 2 remained unchanged!
    });
  });
}
