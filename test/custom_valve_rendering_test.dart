import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/custom_valve_definition.dart';
import 'package:akso/ui/canvas/valve_symbol_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ValveSymbolPainter.drawCustomValve Tests', () {
    test('renders default custom valve without error', () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      const config = ValveSymbolConfig();
      ValveSymbolPainter.drawCustomValve(
        canvas,
        center: const Offset(100, 100),
        angleRad: 0.0,
        symbolConfig: config,
        color: Colors.black,
        size: 24.0,
      );

      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });

    test('renders all wing fill styles without error', () {
      for (final style in ValveWingFillStyle.values) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);

        final config = ValveSymbolConfig(
          leftWingStyle: style,
          rightWingStyle: style,
          hasBodyFlanges: true,
        );

        ValveSymbolPainter.drawCustomValve(
          canvas,
          center: const Offset(50, 50),
          angleRad: 0.785,
          symbolConfig: config,
          color: Colors.blue,
          size: 20.0,
        );

        final picture = recorder.endRecording();
        expect(picture, isNotNull);
      }
    });

    test('renders all divider types without error', () {
      for (final div in ValveDividerType.values) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);

        final config = ValveSymbolConfig(
          dividerType: div,
        );

        ValveSymbolPainter.drawCustomValve(
          canvas,
          center: const Offset(50, 50),
          angleRad: 0.0,
          symbolConfig: config,
          color: Colors.red,
          size: 20.0,
        );

        final picture = recorder.endRecording();
        expect(picture, isNotNull);
      }
    });

    test('renders all stem types with text without error', () {
      for (final stem in ValveStemSymbolType.values) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);

        final config = ValveSymbolConfig(
          stemType: stem,
          stemText: 'АВ',
        );

        ValveSymbolPainter.drawCustomValve(
          canvas,
          center: const Offset(50, 50),
          angleRad: 1.57,
          symbolConfig: config,
          color: Colors.green,
          size: 20.0,
          isReversed: true,
        );

        final picture = recorder.endRecording();
        expect(picture, isNotNull);
      }
    });
  });
}
