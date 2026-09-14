import 'package:flutter/material.dart';
import '../../../../domain/enums/projection_type.dart';
import '../../../../domain/enums/valve_type.dart';
import '../../../../domain/models/node_3d.dart';
import '../../../../domain/models/pipe_segment.dart';
import '../../../canvas/input_controller.dart';
import 'dxf_export_dialog.dart';
import 'fitting_catalog_dialog.dart';
import 'materials_specification_dialog.dart';
import 'weld_journal_dialog.dart';

class EditorTopBar extends StatelessWidget {
  final PipingInputController controller;

  const EditorTopBar({super.key, required this.controller});

  void _loadDemoNetwork(BuildContext context) {
    final net = controller.network;
    net.nodes.clear();
    net.segments.clear();
    net.valves.clear();
    net.weldJoints.clear();
    net.fittings.clear();
    net.spools.clear();

    // 1. Стояк В1 от отм. 0.000 до +2.800
    net.nodes['n1'] = const Node3D(id: 'n1', x: 0, y: 0, z: 0);
    net.nodes['n2'] = const Node3D(id: 'n2', x: 0, y: 0, z: 2800);
    net.segments['seg1'] = const PipeSegment(id: 'seg1', startNodeId: 'n1', endNodeId: 'n2', systemId: 'sys_b1', dn: 80, material: '09Г2С');

    // 2. Горизонтальная гребенка от стояка вдоль оси Y на 3500 мм
    net.nodes['n3'] = const Node3D(id: 'n3', x: 0, y: 3500, z: 2800);
    net.segments['seg2'] = const PipeSegment(id: 'seg2', startNodeId: 'n2', endNodeId: 'n3', systemId: 'sys_b1', dn: 80, material: '09Г2С');

    // 3. Отвод под 90° вглубь вдоль оси X на 2000 мм
    net.nodes['n4'] = const Node3D(id: 'n4', x: 2000, y: 3500, z: 2800);
    net.segments['seg3'] = const PipeSegment(id: 'seg3', startNodeId: 'n3', endNodeId: 'n4', systemId: 'sys_b1', dn: 50, material: 'Сталь 20');

    // 4. Опуск к прибору с отметки +2.800 до +0.600
    net.nodes['n5'] = const Node3D(id: 'n5', x: 2000, y: 3500, z: 600);
    net.segments['seg4'] = const PipeSegment(id: 'seg4', startNodeId: 'n4', endNodeId: 'n5', systemId: 'sys_b1', dn: 50, material: 'Сталь 20');

    // 5. Врезка фланцевой пары Ду80 Ру16 на гребенке
    net.insertFlange(segmentId: 'seg2', ratio: 0.15, isPair: true, pressurePn: 16, material: '09Г2С');

    // 6. Врезка задвижки клиновой Ду80 на магистрали
    net.addValve(segmentId: 'seg2_b', ratio: 0.25, valveType: ValveType.gateValve, dn: 80);

    // 7. Врезка дискового затвора «баттерфляй»
    net.addValve(segmentId: 'seg2_b', ratio: 0.55, valveType: ValveType.butterflyValve, dn: 80);

    // 8. Врезка сетчатого фильтра
    net.addValve(segmentId: 'seg2_b', ratio: 0.85, valveType: ValveType.strainer, dn: 80);

    // 9. Врезка шарового крана и манометра на опуске
    net.addValve(segmentId: 'seg4', ratio: 0.4, valveType: ValveType.ballValve, dn: 50);
    net.addValve(segmentId: 'seg4', ratio: 0.7, valveType: ValveType.pressureGauge, dn: 50);

    // 10. Прямая врезка ответвления Ду32 (ГОСТ 16037 У18)
    net.nodes['n_branch'] = const Node3D(id: 'n_branch', x: -1200, y: 2500, z: 2800);
    net.connectBranchToSegment(
      hostSegmentId: 'seg2_b',
      ratio: 0.4,
      branchEndNodeId: 'n_branch',
      branchDn: 32,
      useDirectBranch: true,
    );

    net.recalculateSpools();
    controller.refresh();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Демонстрационный узел сети (стояк, гребенка, арматура, сварка) загружен')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentProjection = controller.projector.projectionType;

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Логотип и заголовок
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.indigo.shade700,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.hub, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'AKSO 3D',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Text(
              controller.currentProject.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(width: 16),

            // Переключатель видов
            SegmentedButton<ProjectionType>(
              segments: const [
                ButtonSegment(
                  value: ProjectionType.gostFrontal45,
                  label: Text('ГОСТ 45°'),
                  icon: Icon(Icons.architecture, size: 16),
                ),
                ButtonSegment(
                  value: ProjectionType.gostMirrored45,
                  label: Text('Зеркало 45°'),
                  icon: Icon(Icons.flip, size: 16),
                ),
                ButtonSegment(
                  value: ProjectionType.iso30,
                  label: Text('ISO 30°'),
                  icon: Icon(Icons.crop_rotate, size: 16),
                ),
                ButtonSegment(
                  value: ProjectionType.orbit3d,
                  label: Text('3D Орбита'),
                  icon: Icon(Icons.threed_rotation, size: 16),
                ),
                ButtonSegment(
                  value: ProjectionType.topPlan2d,
                  label: Text('План 2D'),
                  icon: Icon(Icons.view_quilt, size: 16),
                ),
              ],
              selected: {currentProjection},
              onSelectionChanged: (set) {
                controller.setProjectionType(set.first);
              },
            ),

            const SizedBox(width: 16),

            // Сохранить проект
            OutlinedButton.icon(
              icon: controller.isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save, size: 18),
              label: const Text('Сохранить'),
              onPressed: controller.isSaving
                  ? null
                  : () async {
                      try {
                        await controller.saveProject();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Проект успешно сохранён')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Ошибка сохранения: $e')),
                          );
                        }
                      }
                    },
            ),
            const SizedBox(width: 8),

            // Загрузить проект
            OutlinedButton.icon(
              icon: controller.isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.folder_open, size: 18),
              label: const Text('Загрузить'),
              onPressed: controller.isLoading
                  ? null
                  : () async {
                      try {
                        await controller.loadProject();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Проект успешно загружен')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Ошибка загрузки: $e')),
                          );
                        }
                      }
                    },
            ),
            const SizedBox(width: 8),

            // Загрузить демо-сеть
            OutlinedButton.icon(
              icon: const Icon(Icons.playlist_add, size: 18),
              label: const Text('Пример узла'),
              onPressed: () => _loadDemoNetwork(context),
            ),
            const SizedBox(width: 8),

            // Каталог деталей
            OutlinedButton.icon(
              icon: const Icon(Icons.settings_suggest, size: 18, color: Colors.indigo),
              label: const Text('Каталог деталей'),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => FittingCatalogDialog(
                    network: controller.network,
                    onCatalogChanged: () => controller.refresh(),
                  ),
                );
              },
            ),
            const SizedBox(width: 8),

            // Спецификация оборудования, изделий и материалов (СО)
            OutlinedButton.icon(
              icon: const Icon(Icons.list_alt, size: 18, color: Colors.teal),
              label: const Text('Спецификация (СО)'),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => MaterialsSpecificationDialog(network: controller.network),
                );
              },
            ),
            const SizedBox(width: 8),

            // Журнал сварки и катушек
            OutlinedButton.icon(
              icon: const Icon(Icons.table_chart, size: 18, color: Colors.indigo),
              label: Text(
                'Ведомость (${controller.network.weldJoints.length} швов / ${controller.network.spools.length} кат.)',
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => WeldJournalDialog(
                    network: controller.network,
                    controller: controller,
                  ),
                );
              },
            ),
            // Переключатели режимов: Сетка, Привязка, Оси
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.grid_4x4, size: 18),
                    tooltip: 'Сетка (Grid)',
                    color: controller.showGrid ? Colors.indigo.shade700 : Colors.grey.shade600,
                    style: IconButton.styleFrom(
                      backgroundColor: controller.showGrid ? Colors.indigo.shade50 : Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: controller.toggleGrid,
                  ),
                  IconButton(
                    icon: const Icon(Icons.gps_fixed, size: 18),
                    tooltip: 'Привязка (Snap)',
                    color: controller.isSnapEnabled ? Colors.indigo.shade700 : Colors.grey.shade600,
                    style: IconButton.styleFrom(
                      backgroundColor: controller.isSnapEnabled ? Colors.indigo.shade50 : Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: controller.toggleSnap,
                  ),
                  IconButton(
                    icon: const Icon(Icons.straighten, size: 18),
                    tooltip: 'Размерная линия (Dimension / D)',
                    color: controller.currentTool == CanvasTool.dimension ? Colors.indigo.shade700 : Colors.grey.shade600,
                    style: IconButton.styleFrom(
                      backgroundColor: controller.currentTool == CanvasTool.dimension ? Colors.indigo.shade50 : Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: () => controller.setTool(CanvasTool.dimension),
                  ),
                  IconButton(
                    icon: const Icon(Icons.architecture, size: 18),
                    tooltip: 'Осевые линии (Axes)',
                    color: controller.currentTool == CanvasTool.drawAxis ? Colors.indigo.shade700 : Colors.grey.shade600,
                    style: IconButton.styleFrom(
                      backgroundColor: controller.currentTool == CanvasTool.drawAxis ? Colors.indigo.shade50 : Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: () => controller.setTool(CanvasTool.drawAxis),
                  ),
                  IconButton(
                    icon: const Icon(Icons.precision_manufacturing, size: 18),
                    tooltip: 'Оборудование (Equipment)',
                    color: controller.currentTool == CanvasTool.insertEquipment ? Colors.indigo.shade700 : Colors.grey.shade600,
                    style: IconButton.styleFrom(
                      backgroundColor: controller.currentTool == CanvasTool.insertEquipment ? Colors.indigo.shade50 : Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: () => controller.setTool(CanvasTool.insertEquipment),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Экспорт DXF
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.shade700,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Экспорт DXF'),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => DxfExportDialog(
                    network: controller.network,
                    currentProjection: controller.projector.projectionType,
                    activeProjector: controller.projector,
                    calloutTemplates: controller.currentProject.calloutTemplates,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
