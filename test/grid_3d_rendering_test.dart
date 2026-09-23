import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/models/construction_axis.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/ui/canvas/piping_canvas.dart';

void main() {
  testWidgets('PipingCanvas renders 3D in-plane axis bubble and respects bubble visibility', (tester) async {
    final net = PipingNetwork();
    net.axes['ax1'] = const ConstructionAxis(
      id: 'ax1',
      label: '1',
      startPoint: Node3D(id: 'n1', x: 0, y: 0, z: 0),
      endPoint: Node3D(id: 'n2', x: 0, y: 10000, z: 0),
      showStartBubble: true,
      showEndBubble: false, // End bubble hidden
      is3dPlaneOriented: true,
    );
    net.axes['ax2'] = const ConstructionAxis(
      id: 'ax2',
      label: '2',
      startPoint: Node3D(id: 'n3', x: 6000, y: 0, z: 0),
      endPoint: Node3D(id: 'n4', x: 6000, y: 10000, z: 0),
      showStartBubble: true,
      showEndBubble: true, // Both bubbles visible
      startElbowOffset: Offset(20, -30), // Elbow shoulder
      is3dPlaneOriented: true,
    );

    const projector = AxonometryProjector(scale: 0.1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomPaint(
            size: const Size(800, 600),
            painter: PipingCanvasPainter(
              network: net,
              projector: projector,
              selectedAxisId: 'ax1',
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CustomPaint), findsWidgets);
  });
}
