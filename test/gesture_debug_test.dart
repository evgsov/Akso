import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Listener handles LMB down, move, and up with 0ms delay', (tester) async {
    final events = <String>[];

    DateTime? lastPrimaryClickTime;
    Offset? lastPrimaryDownPos;
    int zoomToFitCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) {
                if (event.buttons & kPrimaryMouseButton != 0) {
                  final now = DateTime.now();
                  if (lastPrimaryClickTime != null &&
                      now.difference(lastPrimaryClickTime!).inMilliseconds < 350 &&
                      lastPrimaryDownPos != null &&
                      (event.localPosition - lastPrimaryDownPos!).distance < 10.0) {
                    zoomToFitCount++;
                    lastPrimaryClickTime = null;
                    lastPrimaryDownPos = null;
                    events.add('doubleClick');
                    return;
                  }
                  lastPrimaryClickTime = now;
                  lastPrimaryDownPos = event.localPosition;
                  events.add('down(${event.localPosition.dx}, ${event.localPosition.dy})');
                }
              },
              onPointerMove: (event) {
                if (event.buttons & kPrimaryMouseButton != 0) {
                  events.add('move(${event.localPosition.dx}, ${event.localPosition.dy})');
                }
              },
              onPointerUp: (event) {
                events.add('up');
              },
              child: Container(color: Colors.blue),
            ),
          ),
        ),
      ),
    );

    // 1. Single click
    final gesture = await tester.startGesture(const Offset(100, 100), kind: PointerDeviceKind.mouse);
    expect(events, equals(['down(100.0, 100.0)']));
    await gesture.up();
    expect(events, equals(['down(100.0, 100.0)', 'up']));

    events.clear();

    // 2. Drag
    final dragGesture = await tester.startGesture(const Offset(50, 50), kind: PointerDeviceKind.mouse);
    await dragGesture.moveTo(const Offset(70, 70));
    await dragGesture.up();
    expect(events, contains('down(50.0, 50.0)'));
    expect(events, contains('move(70.0, 70.0)'));
    expect(events.last, equals('up'));
    expect(zoomToFitCount, equals(0));
  });
}
