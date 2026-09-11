import 'package:flutter_test/flutter_test.dart';
import 'package:akso/core/math/axonometry_projector.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/main.dart';
import 'package:akso/ui/canvas/input_controller.dart';

void main() {
  testWidgets('AksoApp renders TabletTouchLayout on mobile/tablet viewports', (WidgetTester tester) async {
    final controller = PipingInputController(
      network: PipingNetwork(),
      projector: const AxonometryProjector(),
    );
    controller.setLayoutMode(UiLayoutMode.tabletTouch);

    await tester.pumpWidget(AksoApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('AKSO'), findsOneWidget);
    expect(find.text('ГОСТ 45°'), findsOneWidget);
    expect(find.text('Трассировка'), findsOneWidget);
  });

  testWidgets('AksoApp renders DesktopCadLayout on desktop viewports', (WidgetTester tester) async {
    final controller = PipingInputController(
      network: PipingNetwork(),
      projector: const AxonometryProjector(),
    );
    controller.setLayoutMode(UiLayoutMode.desktopCad);

    await tester.pumpWidget(AksoApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('AKSO 3D'), findsOneWidget);
    expect(find.text('ГОСТ 45° (Фронтальная)'), findsOneWidget);
    expect(find.text('Трассировка:'), findsOneWidget);
    expect(find.text('Каталог'), findsOneWidget);
    expect(find.text('Экспорт DXF'), findsOneWidget);
  });
}
