import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/sheet_callout_preset.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/valve.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/services/callout_layout_engine.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/ui/canvas/input_controller.dart';

void main() {
  group('Per-sheet Callout Pinning', () {
    test('isPinnedOnSheet respects sheet-specific pinning and falls back to global isPinned', () {
      const callout = Callout(
        id: 'c1',
        targetId: 't1',
        targetType: CalloutTargetType.segment,
        isPinned: false,
        sheetPinned: {'sheet_1': true, 'sheet_2': false},
      );

      // Sheet 1 is pinned
      expect(callout.isPinnedOnSheet('sheet_1'), isTrue);

      // Sheet 2 is unpinned
      expect(callout.isPinnedOnSheet('sheet_2'), isFalse);

      // Sheet 3 (not in sheetPinned) falls back to isPinned (false)
      expect(callout.isPinnedOnSheet('sheet_3'), isFalse);

      // null sheetId falls back to global isPinned (false)
      expect(callout.isPinnedOnSheet(null), isFalse);

      // When global isPinned is true but sheetPinned overrides it
      const calloutPinnedGlobal = Callout(
        id: 'c2',
        targetId: 't2',
        targetType: CalloutTargetType.segment,
        isPinned: true,
        sheetPinned: {'sheet_1': false},
      );

      expect(calloutPinnedGlobal.isPinnedOnSheet('sheet_1'), isFalse);
      expect(calloutPinnedGlobal.isPinnedOnSheet('sheet_2'), isTrue);
      expect(calloutPinnedGlobal.isPinnedOnSheet(null), isTrue);
    });

    test('calculateSheetLayout isolates pinning to individual sheets', () {
      const projector = AxonometryProjector();
      final net = PipingNetwork(
        nodes: {
          'n1': const Node3D(id: 'n1', x: 1000, y: 1000, z: 0),
          'n2': const Node3D(id: 'n2', x: 3000, y: 1000, z: 0),
        },
        segments: {
          's1': const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 50, systemId: 'T1'),
        },
        valves: {
          'v1': const Valve(id: 'v1', segmentId: 's1', ratio: 0.5, name: 'Кран 1', dn: 50, lengthMm: 100, valveType: ValveType.ballValve),
        },
        callouts: {
          'c1': const Callout(
            id: 'c1',
            targetType: CalloutTargetType.valve,
            targetId: 'v1',
            textHeight: 3.5,
            screenOffsetX: 100,
            screenOffsetY: 100,
            sheetOffsets: {
              'sheet_1': Offset(120, 120),
            },
            sheetPinned: {
              'sheet_1': true, // Pinned on sheet_1
              'sheet_2': false, // Unpinned on sheet_2
            },
          ),
        },
      );

      final sheet1 = DrawingSheet.createDefault(id: 'sheet_1', name: 'Лист 1', sheetNumber: 1);
      final sheet2 = DrawingSheet.createDefault(id: 'sheet_2', name: 'Лист 2', sheetNumber: 2);

      // On Sheet 1 (pinned), calculateSheetLayout with onlyUnpinned: true preserves the fixed offset
      final layout1 = CalloutLayoutEngine.calculateSheetLayout(
        sheet: sheet1,
        network: net,
        projector: projector,
        onlyUnpinned: true,
      );
      expect(layout1['c1'], equals(const Offset(120, 120)));

      // On Sheet 2 (unpinned), calculateSheetLayout recalculates offset
      final layout2 = CalloutLayoutEngine.calculateSheetLayout(
        sheet: sheet2,
        network: net,
        projector: projector,
        onlyUnpinned: true,
      );
      expect(layout2['c1'], isNotNull);
      // Auto-layout calculates branch-side offset (not the 120, 120 pinned position)
      expect(layout2['c1'], isNot(equals(const Offset(120, 120))));
    });
  });

  group('SheetCalloutPreset Model & Serialization', () {
    test('roundtrip serialization of SheetCalloutPreset', () {
      final now = DateTime(2026, 9, 28, 12, 30);
      final preset = SheetCalloutPreset(
        id: 'preset_1',
        name: 'Финальный вид',
        createdAt: now,
        offsets: {
          'c1': const Offset(45.5, -30.2),
          'c2': const Offset(10.0, 50.0),
        },
        pinnedCalloutIds: {'c1'},
      );

      final json = preset.toJson();
      final restored = SheetCalloutPreset.fromJson(json);

      expect(restored.id, equals('preset_1'));
      expect(restored.name, equals('Финальный вид'));
      expect(restored.createdAt, equals(now));
      expect(restored.offsets.length, equals(2));
      expect(restored.offsets['c1']?.dx, closeTo(45.5, 0.001));
      expect(restored.offsets['c1']?.dy, closeTo(-30.2, 0.001));
      expect(restored.pinnedCalloutIds, contains('c1'));
      expect(restored.pinnedCalloutIds, isNot(contains('c2')));
    });

    test('DrawingSheet stores and serializes calloutPresets', () {
      final preset = SheetCalloutPreset(
        id: 'p1',
        name: 'Пресет 1',
        createdAt: DateTime.now(),
        offsets: {'c1': const Offset(10, 20)},
        pinnedCalloutIds: {'c1'},
      );

      final sheet = DrawingSheet.createDefault(
        id: 'sheet_1',
        name: 'Лист 1',
        sheetNumber: 1,
      ).copyWith(calloutPresets: [preset]);

      expect(sheet.calloutPresets.length, equals(1));
      expect(sheet.calloutPresets.first.name, equals('Пресет 1'));

      final json = sheet.toJson();
      expect(json['calloutPresets'], isNotNull);

      final restored = DrawingSheet.fromJson(json);
      expect(restored.calloutPresets.length, equals(1));
      expect(restored.calloutPresets.first.id, equals('p1'));
      expect(restored.calloutPresets.first.name, equals('Пресет 1'));
      expect(restored.calloutPresets.first.offsets['c1'], equals(const Offset(10, 20)));
    });
  });

  group('PipingInputController Preset Operations', () {
    test('save, apply, and delete callout presets on a sheet', () {
      final controller = PipingInputController();
      final sheet = controller.addSheet(name: 'Лист с пресетами');

      // Populate nodes, segments, valves, and callout in network
      controller.network = controller.network.copyWith(
        nodes: {
          'n1': const Node3D(id: 'n1', x: 0, y: 0, z: 0),
          'n2': const Node3D(id: 'n2', x: 2000, y: 0, z: 0),
        },
        segments: {
          's1': const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 50, systemId: 'T1'),
        },
        valves: {
          'v1': const Valve(id: 'v1', segmentId: 's1', ratio: 0.5, name: 'Кран 1', dn: 50, lengthMm: 100, valveType: ValveType.ballValve),
        },
        callouts: {
          'c1': const Callout(
            id: 'c1',
            targetType: CalloutTargetType.valve,
            targetId: 'v1',
            screenOffsetX: 50,
            screenOffsetY: -50,
          ),
        },
      );

      // Select the sheet
      controller.selectSheet(sheet.id);

      // Pin callout on sheet and set custom sheet offset
      controller.updateCalloutSheetOffset('c1', sheet.id, const Offset(77.0, -88.0));
      controller.toggleCalloutPinning('c1', sheetId: sheet.id);

      expect(controller.network.callouts['c1']?.isPinnedOnSheet(sheet.id), isTrue);
      expect(controller.network.callouts['c1']?.getEffectiveOffset(sheet.id), equals(const Offset(77.0, -88.0)));

      // 1. Save preset
      controller.saveCurrentSheetCalloutPreset(sheet.id, 'Мой Пресет');

      final updatedSheet = controller.currentProject.sheets.firstWhere((s) => s.id == sheet.id);
      expect(updatedSheet.calloutPresets.length, equals(1));
      expect(updatedSheet.calloutPresets.first.name, equals('Мой Пресет'));
      expect(updatedSheet.calloutPresets.first.offsets['c1'], equals(const Offset(77.0, -88.0)));
      expect(updatedSheet.calloutPresets.first.pinnedCalloutIds, contains('c1'));

      final presetId = updatedSheet.calloutPresets.first.id;

      // 2. Modify position and unpin
      controller.updateCalloutSheetOffset('c1', sheet.id, const Offset(10.0, 10.0));
      controller.toggleCalloutPinning('c1', sheetId: sheet.id); // unpins it
      expect(controller.network.callouts['c1']?.isPinnedOnSheet(sheet.id), isFalse);
      expect(controller.network.callouts['c1']?.getEffectiveOffset(sheet.id), equals(const Offset(10.0, 10.0)));

      // 3. Apply preset -> restores saved offset and pin state
      controller.applySheetCalloutPreset(sheet.id, presetId);
      expect(controller.network.callouts['c1']?.isPinnedOnSheet(sheet.id), isTrue);
      expect(controller.network.callouts['c1']?.getEffectiveOffset(sheet.id), equals(const Offset(77.0, -88.0)));

      // 4. Delete preset
      controller.deleteSheetCalloutPreset(sheet.id, presetId);
      final sheetAfterDelete = controller.currentProject.sheets.firstWhere((s) => s.id == sheet.id);
      expect(sheetAfterDelete.calloutPresets.isEmpty, isTrue);
    });
  });
}
