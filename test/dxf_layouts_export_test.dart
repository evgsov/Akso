import 'package:flutter_test/flutter_test.dart';
import 'package:akso/domain/models/drawing_sheet.dart';
import 'package:akso/domain/models/title_block_data.dart';
import 'package:akso/domain/models/piping_network.dart';
import 'package:akso/domain/models/node_3d.dart';
import 'package:akso/domain/models/pipe_segment.dart';
import 'package:akso/data/dxf/dxf_writer.dart';

void main() {
  group('DxfWriter Layouts Export', () {
    test('generates DXF with LAYOUT entities and Paper Space frame', () {
      final network = PipingNetwork();
      final sheet = DrawingSheet.createDefault(id: 'sh_1', name: 'Лист 1 (В1)', sheetNumber: 1);
      final dxf = DxfWriter.generate2dGostAxonometryWithLayoutsDxf(
        network: network,
        sheets: [sheet],
      );

      expect(dxf, contains('LAYOUT'));
      expect(dxf, contains('Лист 1 (В1)'));
      expect(dxf, contains('АКСО_ЛИСТ_РАМКА'));
      expect(dxf, contains('АКСО_ЛИСТ_ШТАМП'));
      expect(dxf, contains('VIEWPORT'));
    });

    test('generates multiple sheets with TT and Act attachment in Paper Space', () {
      final network = PipingNetwork();
      final n1 = Node3D(id: 'n1', x: 0, y: 0, z: 0);
      final n2 = Node3D(id: 'n2', x: 3000, y: 0, z: 0);
      network.nodes[n1.id] = n1;
      network.nodes[n2.id] = n2;
      network.segments['s1'] = const PipeSegment(id: 's1', startNodeId: 'n1', endNodeId: 'n2', dn: 50, systemId: 'sys_1');

      final sheet1 = DrawingSheet.createDefault(id: 'sh_1', name: 'Лист 1', sheetNumber: 1).copyWith(
        technicalRequirements: const TechnicalRequirements(
          text: '1. Трубы по ГОСТ 8732-78.\n2. Контроль ВИК 100%, РК 20%.',
        ),
      );

      final sheet2 = DrawingSheet.createDefault(id: 'sh_2', name: 'Лист 2', sheetNumber: 2).copyWith(
        titleBlockData: TitleBlockData(
          projectName: 'КС Южная',
          drawingTitle: 'Схема продувки',
          documentCode: '05-2026-ТХ',
          topRightCorner: const TopRightCornerBlock(
            mode: TopRightCornerMode.actAttachment,
            text: 'Приложение №2 к Акту № 45',
          ),
        ),
      );

      final dxf = DxfWriter.generate2dGostAxonometryWithLayoutsDxf(
        network: network,
        sheets: [sheet1, sheet2],
      );

      expect(dxf, contains('Лист 1'));
      expect(dxf, contains('Лист 2'));
      expect(dxf, contains('АКСО_ЛИСТ_ТТ'));
      expect(dxf, contains('Технические требования:'));
      expect(dxf, contains('Трубы по ГОСТ 8732-78.'));
      expect(dxf, contains('Приложение №2 к Акту № 45'));
    });
  });
}
