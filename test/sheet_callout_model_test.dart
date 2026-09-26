import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/models/piping_network.dart';

void main() {
  group('Callout.sheetOffsets and getEffectiveOffset', () {
    test('returns base screenOffset when sheetId is null or not in sheetOffsets', () {
      const callout = Callout(
        id: 'c1',
        targetId: 't1',
        targetType: CalloutTargetType.segment,
        screenOffsetX: 30.0,
        screenOffsetY: -20.0,
        sheetOffsets: {'sheet_2': Offset(75.0, -90.0)},
      );

      // Без sheetId
      expect(callout.getEffectiveOffset(null), equals(const Offset(30.0, -20.0)));
      expect(callout.getEffectiveOffsetX(null), equals(30.0));
      expect(callout.getEffectiveOffsetY(null), equals(-20.0));

      // Для листа sheet_1 (нет в оверрайдах) -> базовый
      expect(callout.getEffectiveOffset('sheet_1'), equals(const Offset(30.0, -20.0)));

      // Для листа sheet_2 (есть в оверрайдах) -> переопределенный
      expect(callout.getEffectiveOffset('sheet_2'), equals(const Offset(75.0, -90.0)));
      expect(callout.getEffectiveOffsetX('sheet_2'), equals(75.0));
      expect(callout.getEffectiveOffsetY('sheet_2'), equals(-90.0));
    });

    test('serializes and deserializes sheetOffsets correctly in JSON', () {
      const original = Callout(
        id: 'c_test',
        targetId: 'weld_1',
        targetType: CalloutTargetType.weld,
        screenOffsetX: 15.0,
        screenOffsetY: -15.0,
        sheetOffsets: {
          'sheet_mounting': Offset(25.0, -35.0),
          'sheet_welding': Offset(10.0, 10.0),
        },
      );

      final json = original.toJson();
      final restored = Callout.fromJson(json);

      expect(restored.id, equals('c_test'));
      expect(restored.sheetOffsets.length, equals(2));
      expect(restored.sheetOffsets['sheet_mounting'], equals(const Offset(25.0, -35.0)));
      expect(restored.sheetOffsets['sheet_welding'], equals(const Offset(10.0, 10.0)));
      expect(restored.getEffectiveOffset('sheet_mounting'), equals(const Offset(25.0, -35.0)));
      expect(restored.getEffectiveOffset('other'), equals(const Offset(15.0, -15.0)));
    });

    test('backward compatibility: parses legacy JSON without sheetOffsets as empty map', () {
      final legacyJson = {
        'id': 'c_legacy',
        'targetId': 'pipe_1',
        'targetType': 'segment',
        'screenOffsetX': 40.0,
        'screenOffsetY': -40.0,
        'textHeight': 2.5,
      };

      final restored = Callout.fromJson(legacyJson);
      expect(restored.sheetOffsets, isEmpty);
      expect(restored.getEffectiveOffset('any_sheet'), equals(const Offset(40.0, -40.0)));
    });
  });

  group('DrawingSheet callout visibility and dynamic filtering', () {
    test('all callouts visible by default (enabledCalloutTypes == null, showElevationCallouts == true)', () {
      const sheet = DrawingSheet(id: 's1', name: 'Лист 1', sheetNumber: 1);

      const pipeCallout = Callout(id: 'c1', targetId: 'p1', targetType: CalloutTargetType.segment);
      const weldCallout = Callout(id: 'c2', targetId: 'w1', targetType: CalloutTargetType.weld);
      const elevCallout = Callout(
        id: 'c3',
        targetId: 'n1',
        targetType: CalloutTargetType.node,
        elevationStyle: ElevationMarkStyle.gostOutline,
      );

      expect(sheet.isCalloutVisible(pipeCallout), isTrue);
      expect(sheet.isCalloutVisible(weldCallout), isTrue);
      expect(sheet.isCalloutVisible(elevCallout), isTrue);
    });

    test('filters by enabledCalloutTypes (e.g. welding scheme only shows welds)', () {
      const weldSheet = DrawingSheet(
        id: 's_welds',
        name: 'Схема стыков',
        sheetNumber: 2,
        enabledCalloutTypes: {CalloutTargetType.weld},
      );

      const pipeCallout = Callout(id: 'c1', targetId: 'p1', targetType: CalloutTargetType.segment);
      const weldCallout = Callout(id: 'c2', targetId: 'w1', targetType: CalloutTargetType.weld);
      const valveCallout = Callout(id: 'c3', targetId: 'v1', targetType: CalloutTargetType.valve);

      expect(weldSheet.isCalloutVisible(pipeCallout), isFalse);
      expect(weldSheet.isCalloutVisible(weldCallout), isTrue);
      expect(weldSheet.isCalloutVisible(valveCallout), isFalse);
    });

    test('filters elevation callouts when showElevationCallouts is false', () {
      const noElevSheet = DrawingSheet(
        id: 's_no_elev',
        name: 'Без отметок',
        sheetNumber: 3,
        showElevationCallouts: false,
      );

      const normalNodeCallout = Callout(id: 'c1', targetId: 'n1', targetType: CalloutTargetType.node);
      const elevCallout = Callout(
        id: 'c2',
        targetId: 'n1',
        targetType: CalloutTargetType.node,
        elevationStyle: ElevationMarkStyle.gostFilled,
      );

      expect(noElevSheet.isCalloutVisible(normalNodeCallout), isTrue);
      expect(noElevSheet.isCalloutVisible(elevCallout), isFalse);
    });

    test('DrawingSheet serializes and deserializes enabledCalloutTypes and showElevationCallouts in JSON', () {
      const original = DrawingSheet(
        id: 's_custom',
        name: 'Монтажная',
        sheetNumber: 1,
        enabledCalloutTypes: {CalloutTargetType.segment, CalloutTargetType.valve},
        showElevationCallouts: false,
      );

      final json = original.toJson();
      final restored = DrawingSheet.fromJson(json);

      expect(restored.enabledCalloutTypes, equals({CalloutTargetType.segment, CalloutTargetType.valve}));
      expect(restored.showElevationCallouts, isFalse);
    });
  });

  group('PipingNetwork.getExistingCalloutCategories()', () {
    test('dynamically extracts only existing categories with counts', () {
      final net = PipingNetwork(
        nodes: {},
        segments: {},
        valves: {},
        weldJoints: {},
        fittings: {},
        supports: {},
        equipments: {},
        callouts: {
          'c1': const Callout(id: 'c1', targetId: 'p1', targetType: CalloutTargetType.segment),
          'c2': const Callout(id: 'c2', targetId: 'p2', targetType: CalloutTargetType.segment),
          'c3': const Callout(id: 'c3', targetId: 'p3', targetType: CalloutTargetType.segment),
          'c4': const Callout(id: 'c4', targetId: 'w1', targetType: CalloutTargetType.weld),
          'c5': const Callout(id: 'c5', targetId: 'w2', targetType: CalloutTargetType.weld),
          'c6': const Callout(
            id: 'c6',
            targetId: 'n1',
            targetType: CalloutTargetType.node,
            elevationStyle: ElevationMarkStyle.gostOutline,
          ),
        },
      );

      final stats = net.getExistingCalloutCategories();
      expect(stats.length, equals(3));

      // Сортировка по убыванию количества
      expect(stats[0].type, equals(CalloutTargetType.segment));
      expect(stats[0].count, equals(3));

      expect(stats[1].type, equals(CalloutTargetType.weld));
      expect(stats[1].count, equals(2));

      expect(stats[2].type, equals(CalloutTargetType.node));
      expect(stats[2].count, equals(1));
      expect(stats[2].elevationCount, equals(1));

      expect(net.totalElevationCalloutsCount, equals(1));
    });
  });
}
