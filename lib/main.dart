import 'package:flutter/material.dart';
import 'core/math/axonometry_projector.dart';
import 'domain/enums/projection_type.dart';
import 'domain/models/piping_network.dart';
import 'ui/canvas/input_controller.dart';
import 'ui/features/editor/editor_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final network = PipingNetwork();
  final projector = const AxonometryProjector(
    projectionType: ProjectionType.gostFrontal45,
    scale: 0.22,
    panOffset: Offset(260, 320),
  );

  final controller = PipingInputController(
    network: network,
    projector: projector,
  );

  runApp(AksoApp(controller: controller));
}

class AksoApp extends StatelessWidget {
  final PipingInputController controller;

  const AksoApp({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Akso — Исполнительные 3D-схемы',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F8FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: EditorScreen(controller: controller),
    );
  }
}
