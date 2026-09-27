import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/enums/projection_type.dart';
import 'package:akso/domain/enums/valve_type.dart';
import 'package:akso/domain/models/callout.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/valve.dart';
import 'package:akso/ui/canvas/input_controller.dart';
import 'package:akso/ui/canvas/painters/callout_painter.dart';

void main() {
  group('Forked Callout («Ласточкин хвост / Звезда») Model Tests', () {
    test('Default values for additionalTargetIds and showQuantity', () {
      const callout = Callout(
        id: 'c1',
        targetId: 't1',
        targetType: CalloutTargetType.valve,
      );

      expect(callout.additionalTargetIds, isEmpty);
      expect(callout.showQuantity, isTrue);
    });

    test('JSON serialization round-trip preserves additionalTargetIds and showQuantity', () {
      const callout = Callout(
        id: 'c1',
        targetId: 'valve_1',
        targetType: CalloutTargetType.valve,
        additionalTargetIds: ['valve_2', 'valve_3'],
        showQuantity: true,
        customText: 'А-1',
      );

      final json = callout.toJson();
      expect(json['additionalTargetIds'], equals(['valve_2', 'valve_3']));
      expect(json['showQuantity'], isTrue);

      final reconstructed = Callout.fromJson(json);
      expect(reconstructed.id, equals('c1'));
      expect(reconstructed.targetId, equals('valve_1'));
      expect(reconstructed.additionalTargetIds, equals(['valve_2', 'valve_3']));
      expect(reconstructed.showQuantity, isTrue);
      expect(reconstructed.customText, equals('А-1'));
      expect(reconstructed, equals(callout));
    });

    test('copyWith updates additionalTargetIds and showQuantity correctly', () {
      const callout = Callout(
        id: 'c1',
        targetId: 'v1',
        targetType: CalloutTargetType.valve,
      );

      final updated = callout.copyWith(
        additionalTargetIds: ['v2', 'v3', 'v4'],
        showQuantity: false,
      );

      expect(updated.additionalTargetIds, equals(['v2', 'v3', 'v4']));
      expect(updated.showQuantity, isFalse);
    });
  });

  group('PipingNetwork.generateCalloutText Quantity Formatting Tests', () {
    late PipingNetwork network;
    const templates = defaultCalloutTemplates;

    setUp(() {
      network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 1000, y: 0, z: 0);
      network.nodes['n1'] = n1;
      network.nodes['n2'] = n2;

      final seg = PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        dn: 50,
      );
      network.segments['seg1'] = seg;

      final v1 = Valve(
        id: 'v1',
        segmentId: 'seg1',
        ratio: 0.2,
        name: 'Кран шаровой',
        dn: 50,
        lengthMm: 100.0,
        valveType: ValveType.ballValve,
      );
      final v2 = Valve(
        id: 'v2',
        segmentId: 'seg1',
        ratio: 0.5,
        name: 'Кран шаровой',
        dn: 50,
        lengthMm: 100.0,
        valveType: ValveType.ballValve,
      );
      final v3 = Valve(
        id: 'v3',
        segmentId: 'seg1',
        ratio: 0.8,
        name: 'Кран шаровой',
        dn: 50,
        lengthMm: 100.0,
        valveType: ValveType.ballValve,
      );
      network.valves['v1'] = v1;
      network.valves['v2'] = v2;
      network.valves['v3'] = v3;
    });

    test('Single target does not show quantity suffix', () {
      const callout = Callout(
        id: 'c1',
        targetId: 'v1',
        targetType: CalloutTargetType.valve,
      );

      final text = network.generateCalloutText(callout, templates);
      expect(text, equals('Кран шаровой Ду50'));
    });

    test('Forked callout with 3 targets formats as "Текст (3 шт.)"', () {
      const callout = Callout(
        id: 'c1',
        targetId: 'v1',
        targetType: CalloutTargetType.valve,
        additionalTargetIds: ['v2', 'v3'],
        showQuantity: true,
      );

      final text = network.generateCalloutText(callout, templates);
      expect(text, equals('Кран шаровой Ду50 (3 шт.)'));
    });

    test('Forked callout with showQuantity: false omits quantity suffix', () {
      const callout = Callout(
        id: 'c1',
        targetId: 'v1',
        targetType: CalloutTargetType.valve,
        additionalTargetIds: ['v2', 'v3'],
        showQuantity: false,
      );

      final text = network.generateCalloutText(callout, templates);
      expect(text, equals('Кран шаровой Ду50'));
    });

    test('Custom text with forked callout formats as "А-1 (3 шт.)"', () {
      const callout = Callout(
        id: 'c1',
        targetId: 'v1',
        targetType: CalloutTargetType.valve,
        customText: 'А-1',
        additionalTargetIds: ['v2', 'v3'],
        showQuantity: true,
      );

      final text = network.generateCalloutText(callout, templates);
      expect(text, equals('А-1 (3 шт.)'));
    });
  });

  group('PipingInputController Callout Merge and Unmerge Operations', () {
    late PipingInputController controller;

    setUp(() {
      controller = PipingInputController();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 2000, y: 0, z: 0);
      controller.network.nodes['n1'] = n1;
      controller.network.nodes['n2'] = n2;

      final seg = PipeSegment(
        id: 'seg1',
        startNodeId: 'n1',
        endNodeId: 'n2',
        dn: 50,
      );
      controller.network.segments['seg1'] = seg;

      final v1 = Valve(
        id: 'v1',
        segmentId: 'seg1',
        ratio: 0.2,
        name: 'Задвижка',
        dn: 50,
        lengthMm: 100.0,
        valveType: ValveType.gateValve,
      );
      final v2 = Valve(
        id: 'v2',
        segmentId: 'seg1',
        ratio: 0.5,
        name: 'Задвижка',
        dn: 50,
        lengthMm: 100.0,
        valveType: ValveType.gateValve,
      );
      final v3 = Valve(
        id: 'v3',
        segmentId: 'seg1',
        ratio: 0.8,
        name: 'Задвижка',
        dn: 50,
        lengthMm: 100.0,
        valveType: ValveType.gateValve,
      );
      controller.network.valves['v1'] = v1;
      controller.network.valves['v2'] = v2;
      controller.network.valves['v3'] = v3;

      controller.network.callouts['c1'] = const Callout(
        id: 'c1',
        targetId: 'v1',
        targetType: CalloutTargetType.valve,
        screenOffsetX: 30,
        screenOffsetY: -40,
      );
      controller.network.callouts['c2'] = const Callout(
        id: 'c2',
        targetId: 'v2',
        targetType: CalloutTargetType.valve,
        screenOffsetX: 30,
        screenOffsetY: -40,
      );
      controller.network.callouts['c3'] = const Callout(
        id: 'c3',
        targetId: 'v3',
        targetType: CalloutTargetType.valve,
        screenOffsetX: 30,
        screenOffsetY: -40,
      );
    });

    test('mergeCallouts combines multiple callouts into one with additionalTargetIds', () {
      controller.mergeCallouts(['c1', 'c2', 'c3']);

      expect(controller.network.callouts.containsKey('c1'), isTrue);
      expect(controller.network.callouts.containsKey('c2'), isFalse);
      expect(controller.network.callouts.containsKey('c3'), isFalse);

      final merged = controller.network.callouts['c1']!;
      expect(merged.additionalTargetIds, containsAll(['v2', 'v3']));
      expect(merged.showQuantity, isTrue);

      final text = controller.getCalloutText(merged);
      expect(text, contains('(3 шт.)'));
    });

    test('unmergeCallout restores separate callouts for each target', () {
      controller.mergeCallouts(['c1', 'c2', 'c3']);
      expect(controller.network.callouts.length, equals(1));

      controller.unmergeCallout('c1');
      expect(controller.network.callouts.length, equals(3));

      final primary = controller.network.callouts['c1']!;
      expect(primary.additionalTargetIds, isEmpty);

      final text = controller.getCalloutText(primary);
      expect(text, isNot(contains('шт.')));
    });

    test('toggleCalloutShowQuantity switches showQuantity flag', () {
      controller.mergeCallouts(['c1', 'c2']);
      final merged = controller.network.callouts['c1']!;
      expect(merged.showQuantity, isTrue);

      controller.toggleCalloutShowQuantity('c1');
      expect(controller.network.callouts['c1']!.showQuantity, isFalse);

      controller.toggleCalloutShowQuantity('c1');
      expect(controller.network.callouts['c1']!.showQuantity, isTrue);
    });

    test('findSimilarCalloutsNearby finds matching identical callouts within range', () {
      final similar = controller.findSimilarCalloutsNearby('c1', maxDistanceMm: 100.0);
      expect(similar.map((c) => c.id), containsAll(['c2', 'c3']));
    });

    test('autoMergeIdenticalCallouts automatically groups nearby identical callouts', () {
      final mergedGroups = controller.autoMergeIdenticalCallouts(maxDistanceMm: 100.0);
      expect(mergedGroups, equals(1));
      expect(controller.network.callouts.length, equals(1));
      final merged = controller.network.callouts.values.first;
      expect(merged.additionalTargetIds.length, equals(2));
    });
  });

  group('CalloutPainter Hit-Test Details', () {
    test('Hit-testing checks leader lines and shelf segment with tolerance', () {
      final network = PipingNetwork();
      network.nodes['n1'] = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      const callout = Callout(
        id: 'c1',
        targetId: 'n1',
        targetType: CalloutTargetType.node,
        screenOffsetX: 50,
        screenOffsetY: -50,
      );
      network.callouts['c1'] = callout;

      final projector = AxonometryProjector(projectionType: ProjectionType.iso30);
      final anchorScreen = projector.project(network.nodes['n1']!);
      final textPos = Offset(anchorScreen.dx + 50, anchorScreen.dy - 50);

      // Point exactly on the leader line midpoint
      final midPoint = Offset((anchorScreen.dx + textPos.dx) / 2.0, (anchorScreen.dy + textPos.dy) / 2.0);
      final hitId = CalloutPainter.hitTest(
        midPoint,
        network,
        projector,
        hitTolerance: 6.0,
      );

      expect(hitId, equals('c1'));
    });
  });
}
