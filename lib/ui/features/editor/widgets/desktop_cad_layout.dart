import 'package:flutter/material.dart';
import '../../../../domain/enums/fitting_type.dart';
import '../../../../domain/enums/inspection_method.dart';
import '../../../../domain/enums/projection_type.dart';
import '../../../../domain/enums/valve_type.dart';
import '../../../../domain/enums/weld_joint_style.dart';
import '../../../../domain/enums/weld_type.dart';
import '../../../../domain/models/pipe_support.dart';
import '../../../../core/math/snap_engine.dart';
import '../../../canvas/input_controller.dart';
import 'callout_manager_panel.dart';
import 'custom_pipe_dimension_dialog.dart';
import 'dxf_export_dialog.dart';
import 'elevation_panel.dart';
import 'fitting_catalog_dialog.dart';
import 'fitting_properties_sheet.dart';
import '../../../../domain/models/equipment.dart';
import 'equipment_properties_sheet.dart';
import 'materials_specification_dialog.dart';
import 'pipe_assortment_dialog.dart';
import 'piping_systems_dialog.dart';
import 'weld_journal_dialog.dart';
import 'touch_distance_entry_dialog.dart';

class DesktopCadLayout extends StatelessWidget {
  final PipingInputController controller;
  final Widget canvasWidget;

  const DesktopCadLayout({
    super.key,
    required this.controller,
    required this.canvasWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 1. Верхняя командная строка (Header)
        _buildHeader(context),

        // 2. Контекстная строка параметров инструмента (Options Bar)
        _buildOptionsBar(context),

        // 3. Центральная часть: Левый CAD-тулбар + Холст + Плавающий инспектор
        Expanded(
          child: Row(
            children: [
              // Левый вертикальный тулбар инструментов
              _buildLeftToolPalette(context),

              // Холст и плавающие панели
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        color: const Color(0xFFF8F9FA),
                        child: canvasWidget,
                      ),
                    ),

                    // Навигационный блок зума и ориентации (слева вверху холста)
                    Positioned(
                      top: 16,
                      left: 16,
                      child: _buildViewportControls(context),
                    ),

                    // Панель отметок (справа вверху)
                    Positioned(
                      top: 16,
                      right: 16,
                      child: ElevationPanel(controller: controller),
                    ),

                    // Кнопка точного ввода длины (для тач-устройств), появляется при черчении
                    if (controller.traceStartNode != null || controller.axisStartNode != null)
                      Positioned(
                        bottom: 24,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: FilledButton.icon(
                            key: const Key('tablet_exact_length_button'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.amber.shade700,
                              foregroundColor: Colors.white,
                              elevation: 4,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            ),
                            icon: const Icon(Icons.straighten, size: 20),
                            label: const Text(
                              '📐 Точная длина',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            onPressed: () => _showTouchDistanceEntryDialog(context),
                          ),
                        ),
                      ),

                    // Плавающий инспектор свойств выбранного элемента
                    if (controller.selectedNodeId != null ||
                        controller.selectedSegmentId != null ||
                        controller.selectedEquipmentId != null ||
                        controller.selectedDimensionId != null ||
                        controller.selectedAxisId != null ||
                        controller.selectedValveId != null ||
                        controller.selectedSupportId != null ||
                        controller.selectedWeldId != null ||
                        controller.selectedNodeIds.length > 1 ||
                        controller.selectedSegmentIds.length > 1)
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: _buildPropertyInspector(context),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 4. Нижняя строка состояния (Status Bar)
        _buildStatusBar(context),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final net = controller.network;
    final activeSys = net.systems[controller.activeSystemId];

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B), // Dark Slate
        border: const Border(bottom: BorderSide(color: Color(0xFF334155))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Бренд
            const Icon(Icons.hub, color: Colors.cyanAccent, size: 20),
            const SizedBox(width: 8),
            const Text(
              'AKSO 3D',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.0, fontSize: 14),
            ),
            const SizedBox(width: 16),

            // Кнопки Сохранить / Загрузить
            IconButton(
              icon: controller.isSaving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent)) : const Icon(Icons.save, size: 18),
              color: Colors.white,
              tooltip: 'Сохранить проект (Ctrl+S)',
              onPressed: controller.isSaving ? null : () async {
                try {
                  await controller.saveProject();
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Проект сохранён')));
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
                }
              },
            ),
            IconButton(
              icon: controller.isLoading ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent)) : const Icon(Icons.folder_open, size: 18),
              color: Colors.white,
              tooltip: 'Загрузить проект',
              onPressed: controller.isLoading ? null : () async {
                try {
                  await controller.loadProject();
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Проект загружен')));
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка загрузки: $e')));
                }
              },
            ),

            const VerticalDivider(color: Colors.white24, indent: 8, endIndent: 8),

            // Кнопки Undo / Redo
            IconButton(
              icon: const Icon(Icons.undo, size: 18),
              color: controller.canUndo ? Colors.white : Colors.white38,
              tooltip: 'Отменить (Ctrl+Z)',
              onPressed: controller.canUndo ? controller.undo : null,
            ),
            IconButton(
              icon: const Icon(Icons.redo, size: 18),
              color: controller.canRedo ? Colors.white : Colors.white38,
              tooltip: 'Повторить (Ctrl+Y)',
              onPressed: controller.canRedo ? controller.redo : null,
            ),

            const VerticalDivider(color: Colors.white24, indent: 8, endIndent: 8),
            const SizedBox(width: 8),

            // Переключатель проекций
            DropdownButtonHideUnderline(
              child: DropdownButton<ProjectionType>(
                value: controller.projector.projectionType,
                dropdownColor: const Color(0xFF1E293B),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                items: const [
                  DropdownMenuItem(value: ProjectionType.gostFrontal45, child: Text('ГОСТ 45° (Фронтальная)')),
                  DropdownMenuItem(value: ProjectionType.gostMirrored45, child: Text('Зеркало 45°')),
                  DropdownMenuItem(value: ProjectionType.iso30, child: Text('ISO 30° (Изометрия)')),
                  DropdownMenuItem(value: ProjectionType.orbit3d, child: Text('3D Орбита')),
                  DropdownMenuItem(value: ProjectionType.topPlan2d, child: Text('План 2D')),
                ],
                onChanged: (p) {
                  if (p != null) controller.setProjectionType(p);
                },
              ),
            ),

            const SizedBox(width: 24),

          // Выбор инженерной системы
          ActionChip(
            avatar: CircleAvatar(
              backgroundColor: activeSys != null ? Color(activeSys.colorValue) : Colors.blue,
              radius: 6,
            ),
            label: Text(
              activeSys != null ? '${activeSys.code} ${activeSys.name}' : 'Система',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            backgroundColor: const Color(0xFF334155),
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => PipingSystemsDialog(
                  network: controller.network,
                  activeSystemId: controller.activeSystemId,
                  onSystemSelected: (id) => controller.setActiveSystem(id),
                  onSystemsChanged: () => controller.refresh(),
                ),
              );
            },
          ),
          const SizedBox(width: 8),

          // Сортамент труб (ГОСТ 8732/10704/20295)
          Tooltip(
            message: 'Таблица сортамента труб (ГОСТ 8732/10704/20295) и толщины стенок',
            child: TextButton.icon(
              icon: const Icon(Icons.line_weight, size: 16, color: Colors.cyanAccent),
              label: const Text('Сортамент труб', style: TextStyle(color: Colors.white, fontSize: 12)),
              onPressed: () {
                PipeAssortmentDialog.show(
                  context,
                  network: controller.network,
                  controller: controller,
                  onCatalogChanged: () => controller.refresh(),
                );
              },
            ),
          ),
          const SizedBox(width: 8),

          // Каталог фитингов
          Tooltip(
            message: 'Каталог фитингов и правила трассировки',
            child: TextButton.icon(
              icon: const Icon(Icons.settings_suggest, size: 16, color: Colors.cyanAccent),
              label: const Text('Каталог', style: TextStyle(color: Colors.white, fontSize: 12)),
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
          ),

          // Выноски
          Tooltip(
            message: 'Умные выноски и аннотации',
            child: TextButton.icon(
              icon: const Icon(Icons.label_outline, size: 16, color: Colors.amberAccent),
              label: const Text('Выноски', style: TextStyle(color: Colors.white, fontSize: 12)),
              onPressed: () => CalloutManagerPanel.show(context, controller: controller),
            ),
          ),
          const SizedBox(width: 8),

          // Ведомости (Спецификация, Сварка, Выноски)
          PopupMenuButton<String>(
            tooltip: 'Ведомости и спецификации',
            icon: const Icon(Icons.table_chart, size: 18, color: Colors.white70),
            color: const Color(0xFF1E293B),
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'mto', child: Text('Спецификация (СО ГОСТ 21.110)', style: TextStyle(color: Colors.white, fontSize: 13))),
              const PopupMenuItem(value: 'weld', child: Text('Журнал сварки и катушек', style: TextStyle(color: Colors.white, fontSize: 13))),
              const PopupMenuItem(value: 'callouts', child: Text('Менеджер выносок', style: TextStyle(color: Colors.white, fontSize: 13))),
            ],
            onSelected: (val) {
              if (val == 'mto') {
                showDialog(context: context, builder: (_) => MaterialsSpecificationDialog(network: controller.network));
              } else if (val == 'weld') {
                showDialog(context: context, builder: (_) => WeldJournalDialog(network: controller.network, controller: controller));
              } else if (val == 'callouts') {
                CalloutManagerPanel.show(context, controller: controller);
              }
            },
          ),
          const SizedBox(width: 8),

          // Переключатели режимов: Сетка, Привязка, Оси
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF334155),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.grid_4x4, size: 16),
                  tooltip: 'Сетка (Grid)',
                  color: controller.showGrid ? Colors.cyanAccent : Colors.white60,
                  style: IconButton.styleFrom(
                    backgroundColor: controller.showGrid ? Colors.cyan.shade900.withValues(alpha: 0.4) : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  onPressed: controller.toggleGrid,
                ),
                IconButton(
                  icon: const Icon(Icons.gps_fixed, size: 16),
                  tooltip: 'Привязка (Snap)',
                  color: controller.isSnapEnabled ? Colors.cyanAccent : Colors.white60,
                  style: IconButton.styleFrom(
                    backgroundColor: controller.isSnapEnabled ? Colors.cyan.shade900.withValues(alpha: 0.4) : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  onPressed: controller.toggleSnap,
                ),
                IconButton(
                  icon: const Icon(Icons.square_foot, size: 16),
                  tooltip: controller.isAngleLocked ? 'Фиксация углов 90° (ВКЛ)' : 'Фиксация углов 90° (ВЫКЛ)',
                  color: controller.isAngleLocked ? Colors.cyanAccent : Colors.white60,
                  style: IconButton.styleFrom(
                    backgroundColor: controller.isAngleLocked ? Colors.cyan.shade900.withValues(alpha: 0.4) : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  onPressed: controller.toggleAngleLock,
                ),
                IconButton(
                  icon: const Icon(Icons.straighten, size: 16),
                  tooltip: 'Размерная линия (Dimension / D)',
                  color: controller.currentTool == CanvasTool.dimension ? Colors.cyanAccent : Colors.white60,
                  style: IconButton.styleFrom(
                    backgroundColor: controller.currentTool == CanvasTool.dimension ? Colors.cyan.shade900.withValues(alpha: 0.4) : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  onPressed: () => controller.setTool(CanvasTool.dimension),
                ),
                IconButton(
                  icon: const Icon(Icons.architecture, size: 16),
                  tooltip: 'Осевые линии (Axes)',
                  color: controller.currentTool == CanvasTool.drawAxis ? Colors.cyanAccent : Colors.white60,
                  style: IconButton.styleFrom(
                    backgroundColor: controller.currentTool == CanvasTool.drawAxis ? Colors.cyan.shade900.withValues(alpha: 0.4) : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  onPressed: () => controller.setTool(CanvasTool.drawAxis),
                ),
                IconButton(
                  icon: const Icon(Icons.precision_manufacturing, size: 16),
                  tooltip: 'Оборудование (Equipment)',
                  color: controller.currentTool == CanvasTool.insertEquipment ? Colors.cyanAccent : Colors.white60,
                  style: IconButton.styleFrom(
                    backgroundColor: controller.currentTool == CanvasTool.insertEquipment ? Colors.cyan.shade900.withValues(alpha: 0.4) : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  onPressed: () => controller.setTool(CanvasTool.insertEquipment),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Экспорт DXF
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.cyan.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Экспорт DXF', style: TextStyle(fontSize: 12)),
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

          const SizedBox(width: 8),
          // Переключатель 3D Объём / Линии
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF334155),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.line_style, size: 16),
                  tooltip: 'Каркасный вид (Линии)',
                  color: !controller.isVolumeMode ? Colors.cyanAccent : Colors.white60,
                  onPressed: () => controller.setVolumeMode(false),
                ),
                IconButton(
                  icon: const Icon(Icons.view_in_ar, size: 16),
                  tooltip: 'Объёмный вид (Pseudo-3D)',
                  color: controller.isVolumeMode ? Colors.amberAccent : Colors.white60,
                  onPressed: () => controller.setVolumeMode(true),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Переключатель осевой трассы
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF334155),
              borderRadius: BorderRadius.circular(6),
            ),
            child: IconButton(
              icon: const Icon(Icons.timeline, size: 16),
              tooltip: controller.isCenterlineMode
                  ? 'Осевая трасса (ВКЛ) - клик для скрытия'
                  : 'Осевая трасса (ВЫКЛ) - клик для отображения',
              color: controller.isCenterlineMode ? Colors.cyanAccent : Colors.white60,
              onPressed: controller.toggleCenterlineMode,
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildOptionsBar(BuildContext context) {
    final activeSys = controller.network.systems[controller.activeSystemId];
    final allCatalogDns = controller.network.pipeCatalog.getAllDns();
    final systemDns = activeSys?.availableDns ?? allCatalogDns;

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            if (controller.currentTool == CanvasTool.trace) ...[
              const Text('Трассировка:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo)),
              const SizedBox(width: 12),

              const Text('DN:', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(width: 4),
              DropdownButton<int>(
                value: allCatalogDns.contains(controller.activeDn) ? controller.activeDn : allCatalogDns.first,
                isDense: true,
                items: allCatalogDns.map((dn) {
                  final dim = controller.network.pipeCatalog.getDimension(dn);
                  final isSys = systemDns.contains(dn);
                  final label = dim != null
                      ? 'Ду$dn (⌀${dim.outerDiameterMm.truncateToDouble() == dim.outerDiameterMm ? dim.outerDiameterMm.toStringAsFixed(0) : dim.outerDiameterMm.toStringAsFixed(1)})${!isSys ? ' *' : ''}'
                      : 'Ду$dn';
                  return DropdownMenuItem(
                    value: dn,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSys ? FontWeight.bold : FontWeight.normal,
                        color: dn > 200 ? Colors.indigo.shade800 : Colors.black87,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (dn) {
                  if (dn != null) {
                    controller.setActiveDn(dn);
                    final dim = controller.network.pipeCatalog.getDimension(dn);
                    if (dim != null && !dim.wallThicknesses.any((w) => (w - controller.activeWallThicknessMm).abs() < 0.05)) {
                      controller.setActiveWallThickness(dim.defaultWallThicknessMm);
                    }
                  }
                },
              ),
              const SizedBox(width: 10),

              // Толщина стенки S
              () {
                final dim = controller.network.pipeCatalog.getDimension(controller.activeDn);
                final wallOpts = List<double>.from(dim?.wallThicknesses ?? [controller.activeWallThicknessMm]);
                if (!wallOpts.any((w) => (w - controller.activeWallThicknessMm).abs() < 0.05)) {
                  wallOpts.add(controller.activeWallThicknessMm);
                  wallOpts.sort();
                }
                final selectedVal = wallOpts.firstWhere(
                  (w) => (w - controller.activeWallThicknessMm).abs() < 0.05,
                  orElse: () => wallOpts.first,
                );
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('S:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(width: 4),
                    DropdownButton<double>(
                      value: selectedVal,
                      isDense: true,
                      items: wallOpts.map((s) => DropdownMenuItem(
                        value: s,
                        child: Text('${s.truncateToDouble() == s ? s.toStringAsFixed(0) : s.toStringAsFixed(1)} мм'),
                      )).toList(),
                      onChanged: (s) {
                        if (s != null) controller.setActiveWallThickness(s);
                      },
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 18, color: Colors.indigo),
                      tooltip: 'Добавить свой типоразмер трубы...',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () async {
                        final newDim = await CustomPipeDimensionDialog.show(
                          context,
                          initialDn: controller.activeDn,
                          initialOuterD: dim?.outerDiameterMm,
                          initialWallS: controller.activeWallThicknessMm,
                        );
                        if (newDim != null) {
                          controller.addCustomPipeDimension(newDim);
                          controller.setActiveDn(newDim.dn);
                          controller.setActiveWallThickness(newDim.defaultWallThicknessMm);
                        }
                      },
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.line_weight, size: 18, color: Colors.indigo),
                      tooltip: 'Таблица сортамента труб (ГОСТ 8732/10704/20295)...',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => PipeAssortmentDialog.show(
                        context,
                        network: controller.network,
                        controller: controller,
                        onCatalogChanged: () => controller.refresh(),
                      ),
                    ),
                  ],
                );
              }(),
              const SizedBox(width: 16),

              const Text('Сталь:', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(width: 4),
              DropdownButton<String>(
                value: controller.activeMaterial,
                isDense: true,
                items: const [
                  DropdownMenuItem(value: 'Сталь 20', child: Text('Сталь 20')),
                  DropdownMenuItem(value: '09Г2С', child: Text('09Г2С')),
                  DropdownMenuItem(value: '12Х18Н10Т', child: Text('12Х18Н10Т')),
                  DropdownMenuItem(value: '10Г2', child: Text('10Г2')),
                  DropdownMenuItem(value: 'Ст3сп', child: Text('Ст3сп')),
                ],
                onChanged: (m) {
                  if (m != null) controller.setActiveMaterial(m);
                },
              ),
              const SizedBox(width: 16),

              // Режим ответвления: Тройник / Врезка У18
              SegmentedButton<bool>(
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: false, label: Text('Тройник ГОСТ 17376', style: TextStyle(fontSize: 11))),
                  ButtonSegment(value: true, label: Text('Врезка У18', style: TextStyle(fontSize: 11))),
                ],
                selected: {controller.useDirectBranch},
                onSelectionChanged: (set) => controller.setUseDirectBranch(set.first),
              ),
              const SizedBox(width: 16),

              // Углы полярного отслеживания
              const Text('Углы:', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(width: 4),
              DropdownButton<AngleSnapMode>(
                value: controller.angleSnapMode,
                isDense: true,
                items: const [
                  DropdownMenuItem(value: AngleSnapMode.ortho90, child: Text('Орто 90°')),
                  DropdownMenuItem(value: AngleSnapMode.isometric45, child: Text('Шаг 45°')),
                  DropdownMenuItem(value: AngleSnapMode.iso30, child: Text('Шаг 30°')),
                  DropdownMenuItem(value: AngleSnapMode.custom, child: Text('Польз. 15°')),
                  DropdownMenuItem(value: AngleSnapMode.free, child: Text('Свободный')),
                ],
                onChanged: (mode) {
                  if (mode != null) controller.setAngleSnapMode(mode);
                },
              ),

              // Кнопка отмены активного черчения
              if (controller.traceStartNode != null) ...[
                const SizedBox(width: 16),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade50,
                    foregroundColor: Colors.red.shade700,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.close, size: 14),
                  label: const Text('Отменить черчение (Esc)', style: TextStyle(fontSize: 11)),
                  onPressed: controller.cancelCurrentOperation,
                ),
              ],
            ] else if (controller.currentTool == CanvasTool.drawAxis) ...[
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text('Ось здания', style: TextStyle(fontSize: 12)),
                    icon: Icon(Icons.architecture, size: 14),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('Опорная линия', style: TextStyle(fontSize: 12)),
                    icon: Icon(Icons.linear_scale, size: 14),
                  ),
                ],
                selected: {controller.isBuildingGridAxis},
                onSelectionChanged: (s) => controller.setIsBuildingGridAxis(s.first),
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
              const SizedBox(width: 12),
              if (controller.isBuildingGridAxis) ...[
                const Text('Марка:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(width: 6),
                SizedBox(
                  width: 60,
                  child: TextField(
                    controller: TextEditingController(text: controller.currentAxisLabel),
                    decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6), border: OutlineInputBorder()),
                    onSubmitted: (val) => controller.setCurrentAxisLabel(val.trim()),
                  ),
                ),
                const SizedBox(width: 16),
              ],
              Text(
                controller.isBuildingGridAxis
                    ? 'Укажите начальную и конечную точку оси на плане'
                    : 'Укажите начальную и конечную точку опорной линии (сквозная 3D-привязка)',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              if (controller.axisStartNode != null) ...[
                const SizedBox(width: 16),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade50,
                    foregroundColor: Colors.red.shade700,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.close, size: 14),
                  label: const Text('Отмена (Esc)', style: TextStyle(fontSize: 11)),
                  onPressed: controller.cancelCurrentOperation,
                ),
              ],
            ] else if (controller.currentTool == CanvasTool.dimension) ...[
              const Text('Размерная линия (ГОСТ 2.307):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo)),
              const SizedBox(width: 12),
              if (controller.dimensionStartNode == null)
                const Text('Шаг 1/3: Укажите первую точку привязки (кликните на узел сети)', style: TextStyle(fontSize: 12, color: Colors.blueGrey))
              else if (controller.dimensionEndNode == null)
                const Text('Шаг 2/3: Укажите вторую точку привязки (кликните на узел сети)', style: TextStyle(fontSize: 12, color: Colors.indigo))
              else
                const Text('Шаг 3/3: Укажите положение размерной линии кликом на чертеже', style: TextStyle(fontSize: 12, color: Colors.teal)),
              if (controller.dimensionStartNode != null) ...[
                const SizedBox(width: 16),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade50,
                    foregroundColor: Colors.red.shade700,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.close, size: 14),
                  label: const Text('Отмена (Esc)', style: TextStyle(fontSize: 11)),
                  onPressed: controller.cancelCurrentOperation,
                ),
              ],
            ] else if (controller.currentTool == CanvasTool.insertSupport) ...[
              const Text('Опоры и подвески:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo)),
              const SizedBox(width: 12),
              DropdownButton<PipeSupportType>(
                value: controller.selectedSupportType,
                isDense: true,
                items: PipeSupportType.values.map((s) => DropdownMenuItem(value: s, child: Text(s.displayName))).toList(),
                onChanged: (s) {
                  if (s != null) controller.setSelectedSupportType(s);
                },
              ),
              const SizedBox(width: 16),
              const Text('Нажмите на трубу для установки опоры', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ] else if (controller.currentTool == CanvasTool.insertValve) ...[
              const Text('Врезка арматуры:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo)),
              const SizedBox(width: 12),
              DropdownButton<ValveType>(
                value: controller.selectedValveType,
                isDense: true,
                items: ValveType.values.map((v) => DropdownMenuItem(value: v, child: Text(v.displayName))).toList(),
                onChanged: (v) {
                  if (v != null) controller.setSelectedValveType(v);
                },
              ),
              const SizedBox(width: 16),
              const Text('Нажмите на трубу для установки элемента', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ] else if (controller.currentTool == CanvasTool.insertFlange) ...[
              const Text('Врезка фланцев (ГОСТ 33259):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo)),
              const SizedBox(width: 12),
              FilterChip(
                selected: controller.isFlangePair,
                label: const Text('Фланцевая пара', style: TextStyle(fontSize: 11)),
                onSelected: (val) => controller.setIsFlangePair(val),
              ),
              const SizedBox(width: 12),
              DropdownButton<int>(
                value: controller.flangePressurePn,
                isDense: true,
                items: const [
                  DropdownMenuItem(value: 10, child: Text('Ру 10')),
                  DropdownMenuItem(value: 16, child: Text('Ру 16')),
                  DropdownMenuItem(value: 25, child: Text('Ру 25')),
                  DropdownMenuItem(value: 40, child: Text('Ру 40')),
                ],
                onChanged: (pn) {
                  if (pn != null) controller.setFlangePressurePn(pn);
                },
              ),
            ] else if (controller.currentTool == CanvasTool.insertCap) ...[
              const Text('Заглушка / днище (ГОСТ 6533):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo)),
              const SizedBox(width: 12),
              const Text('Нажмите на концевой узел или открытый конец трубы для установки днища', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ] else if (controller.currentTool == CanvasTool.insertWeld) ...[
              const Text('Врезка сварного стыка:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo)),
              const SizedBox(width: 12),
              DropdownButton<WeldType>(
                value: controller.currentWeldType,
                isDense: true,
                items: WeldType.values.map((w) => DropdownMenuItem(value: w, child: Text('${w.shortName} (${w.gostCode})'))).toList(),
                onChanged: (w) {
                  if (w != null) controller.setCurrentWeldType(w);
                },
              ),
              const SizedBox(width: 12),
              const Text('Клеймо:', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(width: 6),
              SizedBox(
                width: 70,
                child: TextField(
                  controller: TextEditingController(text: controller.currentWelderStamp),
                  decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6), border: OutlineInputBorder()),
                  onSubmitted: (val) => controller.setCurrentWelderStamp(val.trim()),
                ),
              ),
            ] else if (controller.currentTool == CanvasTool.insertReducer) ...[
              const Text('Врезка перехода диаметров:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo)),
              const SizedBox(width: 12),
              DropdownButton<int>(
                value: allCatalogDns.contains(controller.targetReducerDn) ? controller.targetReducerDn : allCatalogDns.first,
                isDense: true,
                items: allCatalogDns.map((dn) => DropdownMenuItem(value: dn, child: Text('в Ду$dn'))).toList(),
                onChanged: (dn) {
                  if (dn != null) controller.setTargetReducerDn(dn);
                },
              ),
              const SizedBox(width: 12),
              FilterChip(
                selected: controller.isEccentricReducer,
                label: const Text('Эксцентрический', style: TextStyle(fontSize: 11)),
                onSelected: (val) => controller.setIsEccentricReducer(val),
              ),
            ] else if (controller.currentTool == CanvasTool.insertEquipment) ...[
              const Text('Оборудование:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo)),
              const SizedBox(width: 12),
              const Text('Кликните на чертеже для размещения емкости Е-1 (1000x1000x2000 мм, штуцер Ш-1 Ду50)', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ] else if (controller.currentTool == CanvasTool.move) ...[
              const Text('Перемещение (M):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo)),
              const SizedBox(width: 12),
              Text(
                controller.modifyBasePointWorld == null
                    ? 'Шаг 1/2: Укажите базовую точку (кликните на узел, трубу или маркер)'
                    : 'Шаг 2/2: Укажите вторую точку смещения или введите расстояние с клавиатуры',
                style: TextStyle(
                  fontSize: 12,
                  color: controller.modifyBasePointWorld == null ? Colors.blueGrey : Colors.indigo.shade800,
                  fontWeight: controller.modifyBasePointWorld == null ? FontWeight.normal : FontWeight.bold,
                ),
              ),
              const SizedBox(width: 16),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade50,
                  foregroundColor: Colors.red.shade700,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.close, size: 14),
                label: const Text('Отмена (Esc)', style: TextStyle(fontSize: 11)),
                onPressed: controller.cancelCurrentOperation,
              ),
            ] else if (controller.currentTool == CanvasTool.copy) ...[
              const Text('Копирование (CO):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.teal)),
              const SizedBox(width: 12),
              Text(
                controller.modifyBasePointWorld == null
                    ? 'Шаг 1/2: Укажите базовую точку копирования'
                    : 'Шаг 2/2: Кликните точку вставки (можно кликать многократно) или введите расстояние',
                style: TextStyle(
                  fontSize: 12,
                  color: controller.modifyBasePointWorld == null ? Colors.blueGrey : Colors.teal.shade800,
                  fontWeight: controller.modifyBasePointWorld == null ? FontWeight.normal : FontWeight.bold,
                ),
              ),
              const SizedBox(width: 16),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.grey.shade100,
                  foregroundColor: Colors.grey.shade800,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.check, size: 14),
                label: const Text('Завершить (Esc)', style: TextStyle(fontSize: 11)),
                onPressed: controller.cancelCurrentOperation,
              ),
            ] else if (controller.currentTool == CanvasTool.rotate) ...[
              const Text('Разворот (RO):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.purple)),
              const SizedBox(width: 12),
              Text(
                controller.modifyBasePointWorld == null
                    ? 'Шаг 1/2: Укажите центр вращения (базовую точку)'
                    : 'Шаг 2/2: Укажите угол поворота курсором или выберите быстрый поворот:',
                style: TextStyle(
                  fontSize: 12,
                  color: controller.modifyBasePointWorld == null ? Colors.blueGrey : Colors.purple.shade800,
                  fontWeight: controller.modifyBasePointWorld == null ? FontWeight.normal : FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: () => controller.rotateSelectionAroundZ(-90, customCenter: controller.modifyBasePointWorld),
                child: const Text('↶ -90°', style: TextStyle(fontSize: 11)),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: () => controller.rotateSelectionAroundZ(90, customCenter: controller.modifyBasePointWorld),
                child: const Text('↷ +90°', style: TextStyle(fontSize: 11)),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: () => controller.rotateSelectionAroundZ(180, customCenter: controller.modifyBasePointWorld),
                child: const Text('180°', style: TextStyle(fontSize: 11)),
              ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade50,
                  foregroundColor: Colors.red.shade700,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.close, size: 14),
                label: const Text('Отмена (Esc)', style: TextStyle(fontSize: 11)),
                onPressed: controller.cancelCurrentOperation,
              ),
            ] else ...[
              () {
                final hasSelection = controller.selectedSegmentIds.isNotEmpty ||
                    controller.selectedNodeIds.isNotEmpty ||
                    controller.selectedEquipmentIds.isNotEmpty ||
                    controller.selectedAxisIds.isNotEmpty ||
                    controller.selectedDimensionIds.isNotEmpty ||
                    controller.selectedSegmentId != null ||
                    controller.selectedNodeId != null ||
                    controller.selectedEquipmentId != null ||
                    controller.selectedAxisId != null ||
                    controller.selectedDimensionId != null;

                if (hasSelection) {
                  final totalCount = controller.selectedSegmentIds.length +
                      controller.selectedNodeIds.length +
                      controller.selectedEquipmentIds.length +
                      controller.selectedAxisIds.length +
                      controller.selectedDimensionIds.length +
                      (controller.selectedSegmentId != null && !controller.selectedSegmentIds.contains(controller.selectedSegmentId) ? 1 : 0) +
                      (controller.selectedNodeId != null && !controller.selectedNodeIds.contains(controller.selectedNodeId) ? 1 : 0) +
                      (controller.selectedEquipmentId != null && !controller.selectedEquipmentIds.contains(controller.selectedEquipmentId) ? 1 : 0) +
                      (controller.selectedAxisId != null && !controller.selectedAxisIds.contains(controller.selectedAxisId) ? 1 : 0) +
                      (controller.selectedDimensionId != null && !controller.selectedDimensionIds.contains(controller.selectedDimensionId) ? 1 : 0);

                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.shade700, width: 0.8),
                        ),
                        child: Text(
                          'Выбрано: $totalCount',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                        icon: const Icon(Icons.open_with, size: 14),
                        label: const Text('Переместить (M)', style: TextStyle(fontSize: 11)),
                        onPressed: () => controller.setTool(CanvasTool.move),
                      ),
                      const SizedBox(width: 6),
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                        icon: const Icon(Icons.content_copy, size: 14),
                        label: const Text('Копировать (CO)', style: TextStyle(fontSize: 11)),
                        onPressed: () => controller.setTool(CanvasTool.copy),
                      ),
                      const SizedBox(width: 6),
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                        icon: const Icon(Icons.rotate_right, size: 14),
                        label: const Text('Развернуть (RO)', style: TextStyle(fontSize: 11)),
                        onPressed: () => controller.setTool(CanvasTool.rotate),
                      ),
                      const SizedBox(width: 6),
                      Tooltip(
                        message: 'Повернуть против часовой стрелки на 90°',
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
                          onPressed: () => controller.rotateSelectionAroundZ(-90),
                          child: const Text('↶ -90°', style: TextStyle(fontSize: 11)),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Tooltip(
                        message: 'Повернуть по часовой стрелке на 90°',
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
                          onPressed: () => controller.rotateSelectionAroundZ(90),
                          child: const Text('↷ +90°', style: TextStyle(fontSize: 11)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                        tooltip: 'Удалить выбранное (Delete)',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: controller.deleteSelected,
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
                        onPressed: controller.cancelCurrentOperation,
                        child: const Text('Снять выбор (Esc)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ),
                    ],
                  );
                }

                return const Text('Выбор и навигация: кликните на узел или трубу, либо выделите рамкой', style: TextStyle(fontSize: 12, color: Colors.grey));
              }(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLeftToolPalette(BuildContext context) {
    return Container(
      width: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Colors.grey.shade300)),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 8),
            _toolButton(CanvasTool.select, Icons.near_me, 'Выбор (V)'),
            _toolButton(CanvasTool.pan, Icons.pan_tool, 'Панорамирование (H / СКМ)'),
            _toolButton(CanvasTool.orbit, Icons.threed_rotation, '3D Орбита (O / ПКМ)'),
            const Divider(height: 16, indent: 8, endIndent: 8),
            _toolButton(CanvasTool.move, Icons.open_with, 'Перемещение (M)'),
            _toolButton(CanvasTool.copy, Icons.content_copy, 'Копирование (CO)'),
            _toolButton(CanvasTool.rotate, Icons.rotate_right, 'Разворот (RO)'),
            const Divider(height: 16, indent: 8, endIndent: 8),
            _toolButton(CanvasTool.trace, Icons.edit, 'Трассировка трубы (T)'),
            _toolButton(CanvasTool.dimension, Icons.straighten, 'Размерная линия (D)'),
            _toolButton(CanvasTool.drawAxis, Icons.architecture, 'Строительная ось (G)'),
            _toolButton(CanvasTool.insertEquipment, Icons.precision_manufacturing, 'Технологическое оборудование (E)'),
            const Divider(height: 16, indent: 8, endIndent: 8),
            _toolButton(CanvasTool.insertValve, Icons.tune, 'Врезка арматуры'),
            _toolButton(CanvasTool.insertWeld, Icons.flare, 'Врезка сварного шва'),
            _toolButton(CanvasTool.insertReducer, Icons.call_split, 'Врезка перехода'),
            _toolButton(CanvasTool.insertFlange, Icons.radio_button_checked, 'Врезка фланцев'),
            _toolButton(CanvasTool.insertCap, Icons.block, 'Заглушка / днище'),
            _toolButton(CanvasTool.insertSupport, Icons.format_underlined, 'Опора / подвеска трубы'),
            const Divider(height: 16, indent: 8, endIndent: 8),
            IconButton(
              icon: Icon(controller.isSnapEnabled ? Icons.lens : Icons.lens_outlined, size: 16, color: controller.isSnapEnabled ? Colors.green : Colors.grey),
              tooltip: 'Привязка: ${controller.isSnapEnabled ? "ВКЛ" : "ВЫКЛ"} (F3)',
              onPressed: controller.toggleSnap,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _toolButton(CanvasTool tool, IconData icon, String tooltip) {
    final isSelected = controller.currentTool == tool;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: IconButton(
        icon: Icon(icon, size: 20),
        color: isSelected ? Colors.indigo : Colors.grey.shade700,
        style: IconButton.styleFrom(
          backgroundColor: isSelected ? Colors.indigo.shade50 : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        tooltip: tooltip,
        onPressed: () => controller.setTool(tool),
      ),
    );
  }

  Widget _buildPropertyInspector(BuildContext context) {
    final isDimension = controller.selectedDimensionId != null;
    final isAxis = !isDimension && controller.selectedAxisId != null;
    final isMultiSelect = controller.selectedNodeIds.length > 1 || controller.selectedSegmentIds.length > 1 || controller.selectedSpoolIds.length > 1;
    final isValve = !isDimension && !isAxis && !isMultiSelect && controller.selectedValveId != null;
    final isSupport = !isDimension && !isAxis && !isMultiSelect && !isValve && controller.selectedSupportId != null;
    final isWeld = !isDimension && !isAxis && !isMultiSelect && !isValve && !isSupport && controller.selectedWeldId != null;
    final isSpool = !isDimension && !isAxis && !isMultiSelect && !isValve && !isSupport && !isWeld && controller.selectedSpoolId != null;
    final isSegment = !isDimension && !isAxis && !isMultiSelect && !isValve && !isSupport && !isWeld && !isSpool && controller.selectedSegmentId != null;
    final isEquipment = !isDimension && !isAxis && !isMultiSelect && !isValve && !isSupport && !isWeld && !isSpool && controller.selectedEquipmentId != null;

    String title = 'Свойства узла';
    IconData icon = Icons.grain;
    if (isDimension) {
      title = 'Размерная линия';
      icon = Icons.straighten;
    } else if (isAxis) {
      final axis = controller.network.axes[controller.selectedAxisId!];
      final isGrid = axis?.isBuildingGrid ?? true;
      title = isGrid ? 'Ось здания' : 'Опорная линия';
      icon = isGrid ? Icons.architecture : Icons.linear_scale;
    } else if (isMultiSelect) {
      title = 'Выделено (${controller.selectedNodeIds.length} узл., ${controller.selectedSegmentIds.length} труб)';
      icon = Icons.select_all;
    } else if (isValve) {
      title = 'Арматура';
      icon = Icons.settings_input_component;
    } else if (isSupport) {
      title = 'Опора трубы';
      icon = Icons.vertical_align_bottom;
    } else if (isWeld) {
      title = 'Сварной стык';
      icon = Icons.join_inner;
    } else if (isSpool) {
      final spool = controller.network.spools[controller.selectedSpoolId!];
      title = 'Катушка ${spool?.number ?? ""}';
      icon = Icons.straighten;
    } else if (isSegment) {
      title = 'Свойства трубы';
      icon = Icons.linear_scale;
    } else if (isEquipment) {
      title = 'Оборудование';
      icon = Icons.precision_manufacturing;
    }

    return Card(
      elevation: 6,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 310,
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: Colors.indigo),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Снять выделение',
                  onPressed: () {
                    controller.selectedNodeId = null;
                    controller.selectedSegmentId = null;
                    controller.selectedSpoolId = null;
                    controller.selectedEquipmentId = null;
                    controller.selectedDimensionId = null;
                    controller.selectedAxisId = null;
                    controller.selectedValveId = null;
                    controller.selectedSupportId = null;
                    controller.selectedWeldId = null;
                    controller.selectedNodeIds.clear();
                    controller.selectedSegmentIds.clear();
                    controller.selectedSpoolIds.clear();
                    controller.refresh();
                  },
                ),
              ],
            ),
            const Divider(height: 14),
            if (isDimension) ...[
              () {
                final dim = controller.network.dimensions[controller.selectedDimensionId!];
                if (dim == null) return const Text('Размер не найден', style: TextStyle(fontSize: 11, color: Colors.grey));
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ID: ${dim.id}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Размер (L):', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Text('${dim.measuredLength.round()} мм', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Вынос:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Text('${dim.offsetDistance.round()} мм', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: BorderSide(color: Colors.red.shade300),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Удалить размер (Del)', style: TextStyle(fontSize: 11)),
                        onPressed: controller.deleteSelected,
                      ),
                    ),
                  ],
                );
              }(),
            ] else if (isAxis) ...[
              () {
                final axis = controller.network.axes[controller.selectedAxisId!];
                if (axis == null) return const Text('Ось не найдена', style: TextStyle(fontSize: 11, color: Colors.grey));
                final lengthMm = axis.startPoint.distanceTo(axis.endPoint);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ID: ${axis.id}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Тип:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Text(
                          axis.isBuildingGrid ? 'Ось здания' : 'Опорная линия',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo),
                        ),
                      ],
                    ),
                    if (axis.isBuildingGrid) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Марка:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          Text(axis.label.isEmpty ? '—' : axis.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Длина:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Text('${lengthMm.round()} мм', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'P1: (${axis.startPoint.x.round()}, ${axis.startPoint.y.round()})\nP2: (${axis.endPoint.x.round()}, ${axis.endPoint.y.round()})',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: BorderSide(color: Colors.red.shade300),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: Text(axis.isBuildingGrid ? 'Удалить ось (Del)' : 'Удалить опорную линию (Del)', style: const TextStyle(fontSize: 11)),
                        onPressed: controller.deleteSelected,
                      ),
                    ),
                  ],
                );
              }(),
            ] else if (isMultiSelect) ...[
              Text('Группа объектов', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(
                'Узлов: ${controller.selectedNodeIds.length}   Сегментов: ${controller.selectedSegmentIds.length}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.copy, size: 15),
                  label: const Text('Копировать со сдвигом (Ctrl+D)', style: TextStyle(fontSize: 11)),
                  onPressed: () => controller.duplicateSelection(dx: 500, dy: 500, dz: 0),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.rotate_90_degrees_cw, size: 15),
                  label: const Text('Повернуть на 90° (R)', style: TextStyle(fontSize: 11)),
                  onPressed: () => controller.rotateSelectionAroundZ(90),
                ),
              ),
              const SizedBox(height: 10),
              _MultiSelectPipeControls(controller: controller),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: BorderSide(color: Colors.red.shade300),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Удалить группу (Del)', style: TextStyle(fontSize: 11)),
                  onPressed: controller.deleteSelected,
                ),
              ),
            ] else if (isValve) ...[
              _DesktopValveInspector(
                controller: controller,
                valveId: controller.selectedValveId!,
              ),
            ] else if (isSupport) ...[
              () {
                final support = controller.network.supports[controller.selectedSupportId!];
                if (support == null) return const Text('Опора не найдена', style: TextStyle(fontSize: 11, color: Colors.grey));
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ID: ${support.id}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Text('Тип:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButton<PipeSupportType>(
                            value: support.type,
                            isDense: true,
                            isExpanded: true,
                            style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.bold),
                            items: PipeSupportType.values.map((st) {
                              return DropdownMenuItem(
                                value: st,
                                child: Text(st.displayName, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (newType) {
                              if (newType == null) return;
                              controller.history.recordState(controller.network);
                              controller.network.updateSupport(
                                support.id,
                                support.copyWith(type: newType),
                              );
                              controller.refresh();
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Маркировка:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Text(
                          support.name.isNotEmpty ? support.name : support.type.shortCode,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Позиция:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Text('${(support.distanceRatio * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: BorderSide(color: Colors.red.shade300),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Удалить опору (Del)', style: TextStyle(fontSize: 11)),
                        onPressed: controller.deleteSelected,
                      ),
                    ),
                  ],
                );
              }(),
            ] else if (isWeld) ...[
              () {
                final weld = controller.network.weldJoints[controller.selectedWeldId!];
                if (weld == null) return const Text('Сварной стык не найден', style: TextStyle(fontSize: 11, color: Colors.grey));
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ID: ${weld.id}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Номер шва:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Text('№ ${weld.number}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Клеймо:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Text(weld.stamp.isNotEmpty ? weld.stamp : '—', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Text('Тип:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButton<WeldType>(
                            value: weld.weldType,
                            isDense: true,
                            isExpanded: true,
                            style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.bold),
                            items: WeldType.values.map((wt) {
                              return DropdownMenuItem(
                                value: wt,
                                child: Text(wt.shortName, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (newType) {
                              if (newType == null) return;
                              controller.history.recordState(controller.network);
                              controller.network.updateWeldJoint(
                                weld.id,
                                (w) => w.copyWith(weldType: newType),
                              );
                              controller.refresh();
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Text('Контроль:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButton<InspectionMethod>(
                            value: weld.inspectionMethod,
                            isDense: true,
                            isExpanded: true,
                            style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.bold),
                            items: InspectionMethod.values.map((im) {
                              return DropdownMenuItem(
                                value: im,
                                child: Text(im.code, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (newMethod) {
                              if (newMethod == null) return;
                              controller.history.recordState(controller.network);
                              controller.network.updateWeldJoint(
                                weld.id,
                                (w) => w.copyWith(inspectionMethod: newMethod),
                              );
                              controller.refresh();
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Text('Стиль:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButton<WeldJointStyle?>(
                            value: weld.style,
                            isDense: true,
                            isExpanded: true,
                            style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.bold),
                            items: [
                              DropdownMenuItem<WeldJointStyle?>(
                                value: null,
                                child: Text('По умолчанию (${controller.network.defaultWeldStyle.label})',
                                    style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
                              ),
                              ...WeldJointStyle.values.map((st) {
                                return DropdownMenuItem<WeldJointStyle?>(
                                  value: st,
                                  child: Text(st.label, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
                                );
                              }),
                            ],
                            onChanged: (newStyle) {
                              controller.history.recordState(controller.network);
                              controller.network.updateWeldJoint(
                                weld.id,
                                (w) => w.copyWith(
                                  style: newStyle,
                                  clearStyle: newStyle == null,
                                ),
                              );
                              controller.refresh();
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Сталь:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Text(weld.steelGrade, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Позиция:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Text('${(weld.ratio * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: BorderSide(color: Colors.red.shade300),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Удалить стык (Del)', style: TextStyle(fontSize: 11)),
                        onPressed: controller.deleteSelected,
                      ),
                    ),
                  ],
                );
              }(),
            ] else if (isSpool)
              _DesktopSpoolInspector(
                controller: controller,
                spoolId: controller.selectedSpoolId!,
              )
            else if (isSegment)
              _DesktopSegmentInspector(
                controller: controller,
                segmentId: controller.selectedSegmentId!,
              )
            else if (isEquipment)
              _DesktopEquipmentInspector(
                controller: controller,
                equipmentId: controller.selectedEquipmentId!,
              )
            else if (controller.selectedNodeId != null) ...[
              () {
                final nodeId = controller.selectedNodeId!;
                final node = controller.network.nodes[nodeId];
                final connected = controller.network.getConnectedSegments(nodeId);
                final fit = controller.network.fittings[nodeId];
                final isEndNode = connected.length == 1 && node?.equipmentId == null;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Узел ID: $nodeId', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 6),
                    _DesktopNodeElevationEditor(
                      controller: controller,
                      nodeId: nodeId,
                    ),
                    const SizedBox(height: 6),
                    Text('Подключено труб: ${connected.length}', style: const TextStyle(fontSize: 11)),
                    const SizedBox(height: 10),

                    // Если на узле уже установлен фитинг (днище, фланец и т.д.)
                    if (fit != null) ...[
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.indigo.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  fit.fittingType == FittingType.cap
                                      ? Icons.block
                                      : (fit.fittingType == FittingType.flange
                                          ? Icons.radio_button_checked
                                          : (fit.fittingType == FittingType.directBranch
                                              ? Icons.merge_type
                                              : (fit.fittingType == FittingType.tee ? Icons.call_split : Icons.tune))),
                                  size: 16,
                                  color: Colors.indigo,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    fit.displayName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              'Ду: ${fit.dn}  |  ${fit.standard ?? "ГОСТ"}',
                              style: const TextStyle(fontSize: 11, color: Colors.black87),
                            ),
                            if (fit.fittingType == FittingType.reducerConcentric || fit.fittingType == FittingType.reducerEccentric) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Text('Длина L:', style: TextStyle(fontSize: 11, color: Colors.black87)),
                                  const SizedBox(width: 6),
                                  SizedBox(
                                    width: 70,
                                    height: 26,
                                    child: TextField(
                                      keyboardType: TextInputType.number,
                                      style: const TextStyle(fontSize: 11),
                                      decoration: const InputDecoration(
                                        suffixText: 'мм',
                                        suffixStyle: TextStyle(fontSize: 9),
                                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      controller: TextEditingController(text: fit.effectiveBuildingLengthMm.round().toString()),
                                      onSubmitted: (v) {
                                        final l = double.tryParse(v);
                                        if (l != null && l > 0) {
                                          controller.history.recordState(controller.network);
                                          controller.network.updateFittingLength(nodeId, l);
                                          controller.refresh();
                                        }
                                      },
                                    ),
                                  ),
                                  const Spacer(),
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () {
                                      controller.history.recordState(controller.network);
                                      final nextAngle = (fit.rotationAngleDeg + 90.0) % 360.0;
                                      controller.network.updateFittingRotation(nodeId, nextAngle);
                                      controller.refresh();
                                    },
                                    child: Text('Поворот ${fit.rotationAngleDeg.round()}°', style: const TextStyle(fontSize: 10)),
                                  ),
                                ],
                              ),
                            ],
                            if (fit.fittingType == FittingType.tee || fit.fittingType == FittingType.directBranch) ...[
                              const SizedBox(height: 8),
                              const Text('Исполнение ответвления:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87)),
                              const SizedBox(height: 4),
                              SizedBox(
                                width: double.infinity,
                                child: SegmentedButton<FittingType>(
                                  style: const ButtonStyle(
                                    visualDensity: VisualDensity.compact,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  segments: const [
                                    ButtonSegment(
                                      value: FittingType.tee,
                                      label: Text('Тройник (3 стыка)', style: TextStyle(fontSize: 10)),
                                      icon: Icon(Icons.call_split, size: 14),
                                    ),
                                    ButtonSegment(
                                      value: FittingType.directBranch,
                                      label: Text('Врезка У18 (1 шов)', style: TextStyle(fontSize: 10)),
                                      icon: Icon(Icons.merge_type, size: 14),
                                    ),
                                  ],
                                  selected: {fit.fittingType},
                                  onSelectionChanged: (set) {
                                    final newType = set.first;
                                    controller.history.recordState(controller.network);
                                    if (newType == FittingType.directBranch) {
                                      controller.network.updateFitting(
                                        nodeId,
                                        fit.copyWith(
                                          fittingType: FittingType.directBranch,
                                          name: 'Прямая врезка У18',
                                          standard: 'ГОСТ 16037-80 У18',
                                          weldType: WeldType.u18,
                                          radiusMm: 0.0,
                                          cutsMainPipe: false,
                                        ),
                                      );
                                    } else {
                                      controller.network.updateFitting(
                                        nodeId,
                                        fit.copyWith(
                                          fittingType: FittingType.tee,
                                          name: 'Тройник равнопроходный Ду${fit.dn}',
                                          standard: 'ГОСТ 17376-2001',
                                          weldType: WeldType.c17,
                                          radiusMm: fit.dn * 1.0,
                                          cutsMainPipe: true,
                                        ),
                                      );
                                    }
                                    controller.refresh();
                                  },
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                                    onPressed: () {
                                      showModalBottomSheet(
                                        context: context,
                                        isScrollControlled: true,
                                        builder: (_) => FittingPropertiesSheet(
                                          network: controller.network,
                                          nodeId: nodeId,
                                          onModified: controller.refresh,
                                        ),
                                      );
                                    },
                                    child: const Text('Свойства', style: TextStyle(fontSize: 11)),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    foregroundColor: Colors.red,
                                  ),
                                  onPressed: () {
                                    controller.history.recordState(controller.network);
                                    controller.network.removeFitting(nodeId);
                                    controller.refresh();
                                  },
                                  child: const Text('Снять', style: TextStyle(fontSize: 11)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ] else if (isEndNode) ...[
                      // Быстрые кнопки для концевого узла трубы
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.indigo.shade600,
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.block, size: 16),
                          label: const Text('Установить днище (заглушку)', style: TextStyle(fontSize: 12)),
                          onPressed: () {
                            controller.history.recordState(controller.network);
                            controller.network.attachCapToNode(nodeId);
                            controller.refresh();
                          },
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                          icon: const Icon(Icons.radio_button_checked, size: 16),
                          label: const Text('Установить концевой фланец', style: TextStyle(fontSize: 12)),
                          onPressed: () {
                            controller.history.recordState(controller.network);
                            controller.network.attachEndFlangeToNode(
                              nodeId,
                              flangeConnectionType: FlangeConnectionType.toEquipment,
                              pressurePn: controller.flangePressurePn,
                              material: controller.activeMaterial,
                            );
                            controller.refresh();
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                        icon: const Icon(Icons.tune, size: 16),
                        label: const Text('Настроить деталь / фитинг', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => FittingPropertiesSheet(
                              network: controller.network,
                              nodeId: nodeId,
                              onModified: controller.refresh,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: BorderSide(color: Colors.red.shade300),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Удалить узел (Del)', style: TextStyle(fontSize: 11)),
                        onPressed: controller.deleteSelected,
                      ),
                    ),
                  ],
                );
              }(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildViewportControls(BuildContext context) {
    return Card(
      elevation: 4,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color: Colors.white.withValues(alpha: 0.92),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.add, size: 18),
              tooltip: 'Приблизить (Ctrl + "+")',
              visualDensity: VisualDensity.compact,
              onPressed: () => controller.zoomIn(),
            ),
            InkWell(
              onTap: () => controller.zoom100(),
              borderRadius: BorderRadius.circular(4),
              child: Tooltip(
                message: 'Масштаб 1:1 (Ctrl + 0)',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    '${controller.zoomPercentage}%',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: Colors.indigo,
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.remove, size: 18),
              tooltip: 'Отдалить (Ctrl + "-")',
              visualDensity: VisualDensity.compact,
              onPressed: () => controller.zoomOut(),
            ),
            const Divider(height: 8, indent: 4, endIndent: 4),
            IconButton(
              icon: const Icon(Icons.center_focus_strong, size: 18, color: Colors.indigo),
              tooltip: 'Вписать всё в экран (Home / Двойной клик колесом)',
              visualDensity: VisualDensity.compact,
              onPressed: () => controller.zoomToFit(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context) {
    final curPos = controller.currentCursorScreenPos;
    final world = curPos != null
        ? controller.projector.unproject(curPos, controller.currentElevationZ)
        : null;

    final xStr = world != null ? '${world.x.round()}' : '—';
    final yStr = world != null ? '${world.y.round()}' : '—';
    final zStr = '${(controller.currentElevationZ / 1000.0).toStringAsFixed(3)} м';

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text('X: $xStr мм   Y: $yStr мм   Z: $zStr', style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.black87)),
            const SizedBox(width: 16),
            const VerticalDivider(width: 1, indent: 4, endIndent: 4),
            const SizedBox(width: 16),
            InkWell(
              onTap: controller.toggleSnap,
              child: Text(
                'SNAP: ${controller.isSnapEnabled ? "ВКЛ" : "ВЫКЛ"}',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: controller.isSnapEnabled ? Colors.green.shade800 : Colors.red.shade800),
              ),
            ),
            const SizedBox(width: 16),
            Text(
              '∠ ${_getAngleLabel(controller.angleSnapMode)}',
              style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 16),
            const VerticalDivider(width: 1, indent: 4, endIndent: 4),
            const SizedBox(width: 16),
            InkWell(
              onTap: () => controller.zoomToFit(),
              child: Tooltip(
                message: 'Вписать всё в экран (клавиша Home или двойной клик колесом)',
                child: Row(
                  children: [
                    const Icon(Icons.center_focus_strong, size: 13, color: Colors.indigo),
                    const SizedBox(width: 4),
                    Text(
                      '${controller.zoomPercentage}% [Вписать (Home)]',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 24),
            Text(
              _getHintText(
                controller.currentTool,
                controller.traceStartNode != null ||
                    controller.axisStartNode != null ||
                    controller.dimensionStartNode != null,
              ),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  String _getAngleLabel(AngleSnapMode mode) {
    switch (mode) {
      case AngleSnapMode.ortho90:
        return 'Орто 90°';
      case AngleSnapMode.isometric45:
        return '45°';
      case AngleSnapMode.iso30:
        return '30°';
      case AngleSnapMode.custom:
        return '15°';
      case AngleSnapMode.free:
        return 'Свободно';
    }
  }

  String _getHintText(CanvasTool tool, bool isTracing) {
    if (isTracing) return 'Кликните на узел или точку для завершения сегмента • Esc или ПКМ: отмена черчения';
    switch (tool) {
      case CanvasTool.trace:
        return 'Кликните на узел или свободное место для начала трассы • СКМ: панорама • Колесо: зум';
      case CanvasTool.select:
        return 'Клик или рамка для выбора • Drag: перемещение • Ctrl+D: копия • R: поворот • Del: удалить';
      case CanvasTool.dimension:
        return 'Кликните на два узла сети, затем укажите вынос размерной линии • Esc: отмена';
      case CanvasTool.drawAxis:
        return 'Кликните для задания начала и конца строительной оси здания';
      case CanvasTool.pan:
        return 'Зажмите ЛКМ и проведите для панорамирования чертежа';
      case CanvasTool.orbit:
        return 'Зажмите ЛКМ и проведите для 3D-вращения сцены';
      case CanvasTool.insertValve:
      case CanvasTool.insertWeld:
      case CanvasTool.insertReducer:
      case CanvasTool.insertFlange:
      case CanvasTool.insertCap:
      case CanvasTool.insertSupport:
        return 'Нажмите на участок трубы или концевой узел для установки элемента';
      case CanvasTool.move:
        return 'Укажите базовую точку и вторую точку смещения или введите расстояние • Esc: отмена';
      case CanvasTool.copy:
        return 'Укажите базовую точку и точки вставки для копий или введите расстояние • Esc: завершить';
      case CanvasTool.rotate:
        return 'Укажите центр вращения и угол разворота выбранных объектов • Esc: отмена';
      case CanvasTool.insertEquipment:
        return 'Кликните на холсте для размещения оборудования и штуцеров';
    }
  }

  void _showTouchDistanceEntryDialog(BuildContext context) {
    double? buttJointLen;
    if (controller.traceStartNode != null && controller.network.isElbowNode(controller.traceStartNode!.id)) {
      final t1 = controller.network.getElbowTangentMm(controller.traceStartNode!.id);
      buttJointLen = t1 * 2;
    }
    TouchDistanceEntryDialog.show(
      context,
      suggestedButtJointLength: buttJointLen,
      onCommit: (lengthMm, {dirX, dirY, dirZ}) {
        controller.commitTraceWithLength(
          lengthMm,
          dirX: dirX,
          dirY: dirY,
          dirZ: dirZ,
        );
      },
    );
  }
}

class _DesktopSegmentInspector extends StatefulWidget {
  final PipingInputController controller;
  final String segmentId;

  const _DesktopSegmentInspector({
    required this.controller,
    required this.segmentId,
  });

  @override
  State<_DesktopSegmentInspector> createState() => _DesktopSegmentInspectorState();
}

class _DesktopSegmentInspectorState extends State<_DesktopSegmentInspector> {
  late TextEditingController _lengthController;
  late TextEditingController _elevationController;
  late TextEditingController _nameController;
  late TextEditingController _serialController;
  final _materials = const ['Сталь 20', '09Г2С', '12Х18Н10Т', '10ХСНД', '15Х5М', '12Х1МФ'];

  @override
  void initState() {
    super.initState();
    final seg = widget.controller.network.segments[widget.segmentId];
    final len = widget.controller.selectedSegmentLength ?? 1000.0;
    final startNode = seg != null ? widget.controller.network.nodes[seg.startNodeId] : null;
    final elevM = (startNode?.z ?? 0.0) / 1000.0;
    _lengthController = TextEditingController(text: '${len.round()}');
    _elevationController = TextEditingController(text: elevM.toStringAsFixed(3));
    _nameController = TextEditingController(text: seg?.name ?? '');
    _serialController = TextEditingController(text: seg?.serialNumber ?? '');
  }

  @override
  void didUpdateWidget(covariant _DesktopSegmentInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.segmentId != widget.segmentId) {
      final seg = widget.controller.network.segments[widget.segmentId];
      final len = widget.controller.selectedSegmentLength ?? 1000.0;
      final startNode = seg != null ? widget.controller.network.nodes[seg.startNodeId] : null;
      final elevM = (startNode?.z ?? 0.0) / 1000.0;
      _lengthController.text = '${len.round()}';
      _elevationController.text = elevM.toStringAsFixed(3);
      _nameController.text = seg?.name ?? '';
      _serialController.text = seg?.serialNumber ?? '';
    }
  }

  @override
  void dispose() {
    _lengthController.dispose();
    _elevationController.dispose();
    _nameController.dispose();
    _serialController.dispose();
    super.dispose();
  }

  void _applyElevation() {
    final text = _elevationController.text.trim().replaceAll('+', '').replaceAll(',', '.');
    final val = double.tryParse(text);
    if (val != null) {
      widget.controller.changeSelectedSegmentElevation(val);
      _elevationController.text = val.toStringAsFixed(3);
    }
  }

  void _applyLength() {
    final val = double.tryParse(_lengthController.text.replaceAll(' ', ''));
    if (val != null && val > 0) {
      widget.controller.changeSelectedSegmentLength(val);
    }
  }

  void _applyName() {
    final text = _nameController.text.trim();
    widget.controller.changeSelectedSegmentName(text.isEmpty ? null : text);
  }

  void _applySerialNumber() {
    final text = _serialController.text.trim();
    widget.controller.changeSelectedSegmentSerialNumber(text.isEmpty ? null : text);
  }

  Future<void> _showAddWallThicknessDialog(BuildContext context, int dn) async {
    final textCtrl = TextEditingController();
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Толщина стенки S (мм)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: textCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Толщина стенки (мм)',
            hintText: 'например: 4.5, 5.6, 8.5...',
            suffixText: 'мм',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              final val = double.tryParse(textCtrl.text.trim().replaceAll(',', '.'));
              if (val != null && val > 0) {
                Navigator.of(ctx).pop(val);
              }
            },
            child: const Text('Применить'),
          ),
        ],
      ),
    );

    if (result != null) {
      widget.controller.addWallThicknessToDn(dn, result);
      widget.controller.changeSelectedSegmentWallThickness(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final seg = widget.controller.network.segments[widget.segmentId];
    if (seg == null) return const SizedBox.shrink();

    final sys = widget.controller.network.systems[seg.systemId];
    final curLength = widget.controller.selectedSegmentLength;

    final allDns = widget.controller.network.pipeCatalog.getAllDns();
    final segDim = widget.controller.network.pipeCatalog.getDimension(seg.dn);
    final wallOpts = List<double>.from(segDim?.wallThicknesses ?? [seg.wallThicknessMm]);
    if (!wallOpts.any((w) => (w - seg.wallThicknessMm).abs() < 0.05)) {
      wallOpts.add(seg.wallThicknessMm);
      wallOpts.sort();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: sys != null ? Color(sys.colorValue) : Colors.blue,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: widget.controller.network.systems.containsKey(seg.systemId) ? seg.systemId : null,
                  isDense: true,
                  isExpanded: true,
                  style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.bold),
                  items: widget.controller.network.systems.values.map((s) {
                    return DropdownMenuItem<String>(
                      value: s.id,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Color(s.colorValue),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text('${s.code} (${s.name})', style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (newSysId) {
                    if (newSysId != null) {
                      widget.controller.changeSelectedSegmentSystem(newSysId);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.amber.shade400),
              ),
              child: Text(
                seg.shortCallout,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.brown),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Маркировка / Название участка
        const Row(
          children: [
            Text('Маркировка / Название:', style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 32,
          child: TextField(
            controller: _nameController,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              hintText: 'напр. Т1-1, Линия 1...',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _applyName(),
            onTapOutside: (_) => _applyName(),
          ),
        ),
        const SizedBox(height: 8),

        // Заводской номер / Номер партии
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Зав. № / Партия:', style: TextStyle(fontSize: 11, color: Colors.grey)),
            if (seg.dn >= 500)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: Colors.blue.shade300),
                ),
                child: const Text('Ду≥500 (Обязательно)', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blue)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 32,
          child: TextField(
            controller: _serialController,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              hintText: seg.dn >= 500 ? 'Зав. № трубы или № плавки' : 'Номер партии / плавки...',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _applySerialNumber(),
            onTapOutside: (_) => _applySerialNumber(),
          ),
        ),
        const SizedBox(height: 10),

        // Диаметр трубы (DN)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Диаметр (Ду):', style: TextStyle(fontSize: 11, color: Colors.grey)),
            Text(
              'Dн = ${seg.outerDiameterMm.toStringAsFixed(seg.outerDiameterMm.truncateToDouble() == seg.outerDiameterMm ? 0 : 1)} мм',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: allDns.contains(seg.dn) ? seg.dn : null,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(),
                ),
                items: allDns.map((dn) {
                  final d = widget.controller.network.pipeCatalog.getDimension(dn);
                  final outerStr = d != null
                      ? '⌀${d.outerDiameterMm.toStringAsFixed(d.outerDiameterMm.truncateToDouble() == d.outerDiameterMm ? 0 : 1)}'
                      : '$dn мм';
                  return DropdownMenuItem(
                    value: dn,
                    child: Text('Ду$dn ($outerStr)', style: const TextStyle(fontSize: 12)),
                  );
                }).toList(),
                onChanged: (newDn) {
                  if (newDn != null) {
                    widget.controller.changeSelectedSegmentDn(newDn);
                  }
                },
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, size: 20, color: Colors.indigo),
              tooltip: 'Добавить свой типоразмер...',
              onPressed: () async {
                final newDim = await CustomPipeDimensionDialog.show(
                  context,
                  initialDn: seg.dn,
                  initialOuterD: seg.outerDiameterMm,
                  initialWallS: seg.wallThicknessMm,
                );
                if (newDim != null) {
                  widget.controller.addCustomPipeDimension(newDim);
                  widget.controller.changeSelectedSegmentSize(
                    dn: newDim.dn,
                    outerDiameterMm: newDim.outerDiameterMm,
                    wallThicknessMm: newDim.defaultWallThicknessMm,
                  );
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Толщина стенки S
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Толщина стенки (S):', style: TextStyle(fontSize: 11, color: Colors.grey)),
            Text(
              '${seg.wallThicknessMm.toStringAsFixed(seg.wallThicknessMm.truncateToDouble() == seg.wallThicknessMm ? 0 : 1)} мм',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<double>(
                initialValue: wallOpts.firstWhere(
                  (w) => (w - seg.wallThicknessMm).abs() < 0.05,
                  orElse: () => wallOpts.first,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(),
                ),
                items: wallOpts.map((w) => DropdownMenuItem(
                  value: w,
                  child: Text(
                    'S = ${w.toStringAsFixed(w.truncateToDouble() == w ? 0 : 1)} мм (⌀${seg.outerDiameterMm.toStringAsFixed(seg.outerDiameterMm.truncateToDouble() == seg.outerDiameterMm ? 0 : 1)}×${w.toStringAsFixed(w.truncateToDouble() == w ? 0 : 1)})',
                    style: const TextStyle(fontSize: 12),
                  ),
                )).toList(),
                onChanged: (newS) {
                  if (newS != null) {
                    widget.controller.changeSelectedSegmentWallThickness(newS);
                  }
                },
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.edit_note, size: 20, color: Colors.indigo),
              tooltip: 'Задать произвольную толщину стенки S...',
              onPressed: () => _showAddWallThicknessDialog(context, seg.dn),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Высотная отметка Z (м)
        Builder(
          builder: (context) {
            final startNode = widget.controller.network.nodes[seg.startNodeId];
            final endNode = widget.controller.network.nodes[seg.endNodeId];
            final isSloped = startNode != null && endNode != null && (startNode.z - endNode.z).abs() > 0.5;
            final curElevM = (startNode?.z ?? 0.0) / 1000.0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Отметка оси (Z):', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    Text(
                      isSloped
                          ? 'Z₁=${(startNode.z / 1000.0).toStringAsFixed(3)} / Z₂=${(endNode.z / 1000.0).toStringAsFixed(3)} м'
                          : '${curElevM >= 0 ? "+" : ""}${curElevM.toStringAsFixed(3)} м',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: TextField(
                          controller: _elevationController,
                          keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            suffixText: 'м',
                            hintText: '+2.800',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _applyElevation(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      height: 36,
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _applyElevation,
                        child: const Icon(Icons.check, size: 16),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),

        // Длина трубы (мм)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Длина (L):', style: TextStyle(fontSize: 11, color: Colors.grey)),
            if (curLength != null)
              Text('${curLength.round()} мм', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo)),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 36,
                child: TextField(
                  controller: _lengthController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    suffixText: 'мм',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _applyLength(),
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              height: 36,
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _applyLength,
                child: const Icon(Icons.check, size: 16),
              ),
            ),
          ],
        ),
        // Сопряжение отвод-отвод: статус или кнопка стягивания в 1 клик
        if (widget.controller.network.isElbowToElbowSegment(widget.segmentId)) ...[
          const SizedBox(height: 8),
          if (widget.controller.network.isButtJoint(widget.segmentId))
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Стык отвод-отвод (встык)',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            Builder(
              builder: (context) {
                final targetLen = widget.controller.network.getElbowToElbowTargetLength(widget.segmentId) ?? 0.0;
                return SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.indigo.shade50,
                      foregroundColor: Colors.indigo.shade800,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.link, size: 16),
                    label: Text(
                      '🔗 Стянуть встык (${targetLen.round()} мм)',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      widget.controller.collapseSelectedSegmentToButtJoint();
                      final updatedLen = widget.controller.selectedSegmentLength ?? targetLen;
                      _lengthController.text = '${updatedLen.round()}';
                    },
                  ),
                );
              },
            ),
          ],
        ],
        const SizedBox(height: 10),

        // Марка стали
        const Text('Марка стали:', style: TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: _materials.contains(seg.material) ? seg.material : _materials.first,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder(),
          ),
          items: _materials.map((m) => DropdownMenuItem(
            value: m,
            child: Text(m, style: const TextStyle(fontSize: 12)),
          )).toList(),
          onChanged: (newMat) {
            if (newMat != null) {
              widget.controller.changeSelectedSegmentMaterial(newMat);
            }
          },
        ),
        const SizedBox(height: 12),

        // Кнопка Удалить
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: BorderSide(color: Colors.red.shade300),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Удалить трубу (Del)', style: TextStyle(fontSize: 11)),
            onPressed: widget.controller.deleteSelected,
          ),
        ),
      ],
    );
  }
}

class _DesktopValveInspector extends StatefulWidget {
  final PipingInputController controller;
  final String valveId;

  const _DesktopValveInspector({
    required this.controller,
    required this.valveId,
  });

  @override
  State<_DesktopValveInspector> createState() => _DesktopValveInspectorState();
}

class _DesktopValveInspectorState extends State<_DesktopValveInspector> {
  late TextEditingController _nameController;
  late TextEditingController _serialController;
  late TextEditingController _lengthController;

  @override
  void initState() {
    super.initState();
    final valve = widget.controller.network.valves[widget.valveId];
    _nameController = TextEditingController(text: valve?.name ?? '');
    _serialController = TextEditingController(text: valve?.serialNumber ?? '');
    _lengthController = TextEditingController(text: valve != null ? valve.lengthMm.round().toString() : '140');
  }

  @override
  void didUpdateWidget(covariant _DesktopValveInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.valveId != widget.valveId) {
      final valve = widget.controller.network.valves[widget.valveId];
      _nameController.text = valve?.name ?? '';
      _serialController.text = valve?.serialNumber ?? '';
      _lengthController.text = valve != null ? valve.lengthMm.round().toString() : '140';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _serialController.dispose();
    _lengthController.dispose();
    super.dispose();
  }

  void _applyName() {
    final valve = widget.controller.network.valves[widget.valveId];
    if (valve == null) return;
    final text = _nameController.text.trim();
    if (text.isNotEmpty && text != valve.name) {
      widget.controller.history.recordState(widget.controller.network);
      widget.controller.network.updateValve(valve.id, valve.copyWith(name: text));
      widget.controller.refresh();
    }
  }

  void _applySerialNumber() {
    final valve = widget.controller.network.valves[widget.valveId];
    if (valve == null) return;
    final text = _serialController.text.trim();
    final newSerial = text.isEmpty ? null : text;
    if (newSerial != valve.serialNumber) {
      widget.controller.history.recordState(widget.controller.network);
      widget.controller.network.updateValve(
        valve.id,
        valve.copyWith(
          serialNumber: newSerial,
          clearSerialNumber: text.isEmpty,
        ),
      );
      widget.controller.refresh();
    }
  }

  void _applyLength() {
    final valve = widget.controller.network.valves[widget.valveId];
    if (valve == null) return;
    final l = double.tryParse(_lengthController.text.replaceAll(' ', ''));
    if (l != null && l > 0 && l != valve.lengthMm) {
      widget.controller.history.recordState(widget.controller.network);
      widget.controller.network.updateValveLength(valve.id, l);
      widget.controller.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final valve = widget.controller.network.valves[widget.valveId];
    if (valve == null) return const Text('Арматура не найдена', style: TextStyle(fontSize: 11, color: Colors.grey));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ID: ${valve.id}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(height: 6),

        // Наименование / Марка
        const Text('Наименование:', style: TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 3),
        SizedBox(
          height: 30,
          child: TextField(
            controller: _nameController,
            style: const TextStyle(fontSize: 11),
            decoration: const InputDecoration(
              hintText: 'напр. Задвижка 10с9бк, КОП-1',
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _applyName(),
            onTapOutside: (_) => _applyName(),
          ),
        ),
        const SizedBox(height: 6),

        // Заводской номер
        const Text('Заводской №:', style: TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 3),
        SizedBox(
          height: 30,
          child: TextField(
            controller: _serialController,
            style: const TextStyle(fontSize: 11),
            decoration: const InputDecoration(
              hintText: 'напр. № 48219',
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _applySerialNumber(),
            onTapOutside: (_) => _applySerialNumber(),
          ),
        ),
        const SizedBox(height: 6),

        // Тип арматуры
        Row(
          children: [
            const Text('Тип:', style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButton<ValveType>(
                value: valve.valveType,
                isDense: true,
                isExpanded: true,
                style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.bold),
                items: ValveType.values.map((vt) {
                  return DropdownMenuItem(
                    value: vt,
                    child: Text(vt.displayName, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (newType) {
                  if (newType == null) return;
                  widget.controller.history.recordState(widget.controller.network);
                  widget.controller.network.updateValve(
                    valve.id,
                    valve.copyWith(valveType: newType),
                  );
                  widget.controller.refresh();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Диаметр DN
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Диаметр DN:', style: TextStyle(fontSize: 11, color: Colors.grey)),
            Text('Ду ${valve.dn}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo)),
          ],
        ),
        const SizedBox(height: 4),

        // Строительная длина L
        Row(
          children: [
            const Text('Строит. длина L:', style: TextStyle(fontSize: 11, color: Colors.grey)),
            const Spacer(),
            SizedBox(
              width: 80,
              height: 26,
              child: TextField(
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 11),
                decoration: const InputDecoration(
                  suffixText: 'мм',
                  suffixStyle: TextStyle(fontSize: 9),
                  contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                controller: _lengthController,
                onSubmitted: (_) => _applyLength(),
                onTapOutside: (_) => _applyLength(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),

        // Позиция
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Позиция:', style: TextStyle(fontSize: 11, color: Colors.grey)),
            Text('${(valve.ratio * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 6),

        // Рукоятка
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Рукоятка: ${valve.handleAngleDeg.round()}°', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () {
                widget.controller.history.recordState(widget.controller.network);
                final nextAngle = (valve.handleAngleDeg + 90.0) % 360.0;
                widget.controller.network.updateValve(
                  valve.id,
                  valve.copyWith(handleAngleDeg: nextAngle),
                );
                widget.controller.refresh();
              },
              child: const Text('Поворот +90°', style: TextStyle(fontSize: 10)),
            ),
          ],
        ),
        const SizedBox(height: 4),

        // Фланцевая
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Фланцевая:', style: TextStyle(fontSize: 11)),
            Switch(
              value: valve.isFlanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (val) {
                widget.controller.history.recordState(widget.controller.network);
                widget.controller.network.updateValve(
                  valve.id,
                  valve.copyWith(isFlanged: val),
                );
                widget.controller.refresh();
              },
            ),
          ],
        ),

        // Инвертировать
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Инвертировать:', style: TextStyle(fontSize: 11)),
            Switch(
              value: valve.isReversed,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (val) {
                widget.controller.history.recordState(widget.controller.network);
                widget.controller.network.updateValve(
                  valve.id,
                  valve.copyWith(isReversed: val),
                );
                widget.controller.refresh();
              },
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Удалить арматуру
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: BorderSide(color: Colors.red.shade300),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Удалить арматуру (Del)', style: TextStyle(fontSize: 11)),
            onPressed: widget.controller.deleteSelected,
          ),
        ),
      ],
    );
  }
}

class _DesktopSpoolInspector extends StatefulWidget {
  final PipingInputController controller;
  final String spoolId;

  const _DesktopSpoolInspector({
    required this.controller,
    required this.spoolId,
  });

  @override
  State<_DesktopSpoolInspector> createState() => _DesktopSpoolInspectorState();
}

class _DesktopSpoolInspectorState extends State<_DesktopSpoolInspector> {
  late TextEditingController _nameController;
  late TextEditingController _serialController;
  late TextEditingController _lengthController;
  late TextEditingController _elevationController;

  @override
  void initState() {
    super.initState();
    final spool = widget.controller.network.spools[widget.spoolId];
    final seg = spool != null ? widget.controller.network.segments[spool.segmentId] : null;
    final startNode = seg != null ? widget.controller.network.nodes[seg.startNodeId] : null;
    final elevM = (startNode?.z ?? 0.0) / 1000.0;
    _nameController = TextEditingController(text: spool?.name ?? '');
    _serialController = TextEditingController(text: spool?.serialNumber ?? '');
    _lengthController = TextEditingController(
      text: spool != null ? spool.cutLengthMm.round().toString() : '',
    );
    _elevationController = TextEditingController(text: elevM.toStringAsFixed(3));
  }

  @override
  void didUpdateWidget(covariant _DesktopSpoolInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spoolId != widget.spoolId) {
      final spool = widget.controller.network.spools[widget.spoolId];
      final seg = spool != null ? widget.controller.network.segments[spool.segmentId] : null;
      final startNode = seg != null ? widget.controller.network.nodes[seg.startNodeId] : null;
      final elevM = (startNode?.z ?? 0.0) / 1000.0;
      _nameController.text = spool?.name ?? '';
      _serialController.text = spool?.serialNumber ?? '';
      _lengthController.text = spool != null ? spool.cutLengthMm.round().toString() : '';
      _elevationController.text = elevM.toStringAsFixed(3);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _serialController.dispose();
    _lengthController.dispose();
    _elevationController.dispose();
    super.dispose();
  }

  void _applyElevation() {
    final text = _elevationController.text.trim().replaceAll('+', '').replaceAll(',', '.');
    final val = double.tryParse(text);
    if (val != null) {
      widget.controller.changeSelectedSpoolElevation(val);
      _elevationController.text = val.toStringAsFixed(3);
    }
  }

  void _applyName() {
    final spool = widget.controller.network.spools[widget.spoolId];
    if (spool == null) return;
    final text = _nameController.text.trim();
    if (text != (spool.name ?? '')) {
      widget.controller.setSelectedSpoolMetadata(name: text.isEmpty ? null : text);
    }
  }

  void _applySerialNumber() {
    final spool = widget.controller.network.spools[widget.spoolId];
    if (spool == null) return;
    final text = _serialController.text.trim();
    if (text != (spool.serialNumber ?? '')) {
      widget.controller.setSelectedSpoolMetadata(serialNumber: text.isEmpty ? null : text);
    }
  }

  void _applyLength() {
    final spool = widget.controller.network.spools[widget.spoolId];
    if (spool == null) return;
    final val = double.tryParse(_lengthController.text.replaceAll(' ', ''));
    if (val != null && val > 0 && (val - spool.cutLengthMm).abs() > 0.5) {
      widget.controller.changeSelectedSpoolLength(val);
      final updatedSpool = widget.controller.network.spools[widget.spoolId];
      if (updatedSpool != null) {
        _lengthController.text = updatedSpool.cutLengthMm.round().toString();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final spool = widget.controller.network.spools[widget.spoolId];
    if (spool == null) {
      return const Text('Катушка не найдена', style: TextStyle(fontSize: 11, color: Colors.grey));
    }
    final seg = widget.controller.network.segments[spool.segmentId];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Марка: ${spool.number}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('Ду${spool.dn}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
            ),
          ],
        ),
        if (seg != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('Система:', style: TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: widget.controller.network.systems.containsKey(seg.systemId) ? seg.systemId : null,
                    isDense: true,
                    isExpanded: true,
                    style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.bold),
                    items: widget.controller.network.systems.values.map((s) {
                      return DropdownMenuItem<String>(
                        value: s.id,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Color(s.colorValue),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text('${s.code} (${s.name})', style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (newSysId) {
                      if (newSysId != null) {
                        widget.controller.changeSelectedSpoolSystem(newSysId);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),

        // Высотная отметка Z (м)
        Builder(
          builder: (context) {
            final startNode = seg != null ? widget.controller.network.nodes[seg.startNodeId] : null;
            final curElevM = (startNode?.z ?? 0.0) / 1000.0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Отметка оси (Z):', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    Text(
                      '${curElevM >= 0 ? "+" : ""}${curElevM.toStringAsFixed(3)} м',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 34,
                        child: TextField(
                          controller: _elevationController,
                          keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            suffixText: 'м',
                            hintText: '+2.800',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _applyElevation(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      height: 34,
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _applyElevation,
                        child: const Icon(Icons.check, size: 16),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),

        // Чистая длина реза (мм)
        const Text('Длина реза заготовки (мм):', style: TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _lengthController,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(),
                  suffixText: 'мм',
                ),
                onSubmitted: (_) => _applyLength(),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              icon: const Icon(Icons.check, size: 16),
              tooltip: 'Применить длину',
              onPressed: _applyLength,
              style: IconButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Наименование / Маркировка
        const Text('Наименование / Позиция:', style: TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 4),
        Focus(
          onFocusChange: (has) { if (!has) _applyName(); },
          child: TextField(
            controller: _nameController,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(),
              hintText: 'например: Участок В1-1',
            ),
            onSubmitted: (_) => _applyName(),
          ),
        ),
        const SizedBox(height: 8),

        // Заводской номер / Партия
        const Text('Заводской номер / Номер плавки:', style: TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 4),
        Focus(
          onFocusChange: (has) { if (!has) _applySerialNumber(); },
          child: TextField(
            controller: _serialController,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(),
              hintText: 'например: ПЛ-4509 / Зав. 12',
            ),
            onSubmitted: (_) => _applySerialNumber(),
          ),
        ),
        const SizedBox(height: 8),

        // Материал и толщина стенки
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Стенка S:', style: TextStyle(fontSize: 11, color: Colors.grey)),
            Text('${spool.wallThickness} мм', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Материал:', style: TextStyle(fontSize: 11, color: Colors.grey)),
            Text(seg?.material ?? spool.material, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 12),

        // Удалить катушку (сегмент)
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: BorderSide(color: Colors.red.shade300),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Удалить катушку (Del)', style: TextStyle(fontSize: 11)),
            onPressed: widget.controller.deleteSelected,
          ),
        ),
      ],
    );
  }
}

class _DesktopNodeElevationEditor extends StatefulWidget {
  final PipingInputController controller;
  final String nodeId;

  const _DesktopNodeElevationEditor({
    required this.controller,
    required this.nodeId,
  });

  @override
  State<_DesktopNodeElevationEditor> createState() => _DesktopNodeElevationEditorState();
}

class _DesktopNodeElevationEditorState extends State<_DesktopNodeElevationEditor> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    final node = widget.controller.network.nodes[widget.nodeId];
    final elevM = (node?.z ?? 0.0) / 1000.0;
    _ctrl = TextEditingController(text: elevM.toStringAsFixed(3));
  }

  @override
  void didUpdateWidget(covariant _DesktopNodeElevationEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeId != widget.nodeId) {
      final node = widget.controller.network.nodes[widget.nodeId];
      final elevM = (node?.z ?? 0.0) / 1000.0;
      _ctrl.text = elevM.toStringAsFixed(3);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _apply() {
    final text = _ctrl.text.trim().replaceAll('+', '').replaceAll(',', '.');
    final val = double.tryParse(text);
    if (val != null) {
      widget.controller.changeSelectedNodeElevation(val);
      _ctrl.text = val.toStringAsFixed(3);
    }
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.controller.network.nodes[widget.nodeId];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Отметка (Z):', style: TextStyle(fontSize: 11, color: Colors.grey)),
            Text(
              node?.elevationString ?? "0.000 м",
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 32,
                child: TextField(
                  controller: _ctrl,
                  keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    suffixText: 'м',
                    hintText: '+2.800',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _apply(),
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              height: 32,
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _apply,
                child: const Icon(Icons.check, size: 16),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DesktopEquipmentInspector extends StatefulWidget {
  final PipingInputController controller;
  final String equipmentId;

  const _DesktopEquipmentInspector({
    required this.controller,
    required this.equipmentId,
  });

  @override
  State<_DesktopEquipmentInspector> createState() => _DesktopEquipmentInspectorState();
}

class _DesktopEquipmentInspectorState extends State<_DesktopEquipmentInspector> {
  late TextEditingController _elevationCtrl;

  @override
  void initState() {
    super.initState();
    final eq = widget.controller.network.equipments[widget.equipmentId];
    final elevM = (eq?.z ?? 0.0) / 1000.0;
    _elevationCtrl = TextEditingController(text: elevM.toStringAsFixed(3));
  }

  @override
  void didUpdateWidget(covariant _DesktopEquipmentInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.equipmentId != widget.equipmentId) {
      final eq = widget.controller.network.equipments[widget.equipmentId];
      final elevM = (eq?.z ?? 0.0) / 1000.0;
      _elevationCtrl.text = elevM.toStringAsFixed(3);
    }
  }

  @override
  void dispose() {
    _elevationCtrl.dispose();
    super.dispose();
  }

  void _applyElevation() {
    final text = _elevationCtrl.text.trim().replaceAll('+', '').replaceAll(',', '.');
    final val = double.tryParse(text);
    if (val != null) {
      widget.controller.changeSelectedEquipmentElevation(val);
      _elevationCtrl.text = val.toStringAsFixed(3);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eq = widget.controller.network.equipments[widget.equipmentId];
    if (eq == null) {
      return const Text('Оборудование не найдено', style: TextStyle(fontSize: 11, color: Colors.grey));
    }
    final elevM = eq.z / 1000.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ID: ${eq.id}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          eq.name.isNotEmpty ? eq.name : eq.type.displayName,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),

        // Высотная отметка Z (м)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Отметка основания (Z):', style: TextStyle(fontSize: 11, color: Colors.grey)),
            Text(
              '${elevM >= 0 ? "+" : ""}${elevM.toStringAsFixed(3)} м',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 34,
                child: TextField(
                  controller: _elevationCtrl,
                  keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    suffixText: 'м',
                    hintText: '+0.000',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _applyElevation(),
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              height: 34,
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _applyElevation,
                child: const Icon(Icons.check, size: 16),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            icon: const Icon(Icons.tune, size: 16),
            label: const Text('Свойства оборудования', style: TextStyle(fontSize: 12)),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => EquipmentPropertiesSheet(
                  network: widget.controller.network,
                  equipmentId: eq.id,
                  onModified: () {
                    final updated = widget.controller.network.equipments[eq.id];
                    if (updated != null) {
                      _elevationCtrl.text = (updated.z / 1000.0).toStringAsFixed(3);
                    }
                    widget.controller.refresh();
                  },
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: BorderSide(color: Colors.red.shade300),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Удалить оборудование (Del)', style: TextStyle(fontSize: 11)),
            onPressed: widget.controller.deleteSelected,
          ),
        ),
      ],
    );
  }
}

class _MultiSelectPipeControls extends StatefulWidget {
  final PipingInputController controller;

  const _MultiSelectPipeControls({required this.controller});

  @override
  State<_MultiSelectPipeControls> createState() => _MultiSelectPipeControlsState();
}

class _MultiSelectPipeControlsState extends State<_MultiSelectPipeControls> {
  final TextEditingController _shiftCtrl = TextEditingController(text: '+0.500');

  @override
  void dispose() {
    _shiftCtrl.dispose();
    super.dispose();
  }

  void _applyShift() {
    final text = _shiftCtrl.text.trim().replaceAll('+', '').replaceAll(',', '.');
    final val = double.tryParse(text);
    if (val != null && val != 0.0) {
      widget.controller.shiftSelectedSegmentsElevation(val);
    }
  }

  @override
  Widget build(BuildContext context) {
    final segCount = widget.controller.selectedSegmentIds.length;
    if (segCount == 0) return const SizedBox.shrink();

    final systems = widget.controller.network.systems.values.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 14),
        const Text(
          'Массовые действия с трубами:',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo),
        ),
        const SizedBox(height: 6),
        // Смена системы для всех труб
        Row(
          children: [
            const Text('Система:', style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  hint: const Text('Сменить систему...', style: TextStyle(fontSize: 11)),
                  isDense: true,
                  isExpanded: true,
                  items: systems.map((s) {
                    return DropdownMenuItem<String>(
                      value: s.id,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Color(s.colorValue),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text('${s.code} (${s.name})', style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (newSysId) {
                    if (newSysId != null) {
                      widget.controller.changeSelectedSegmentSystem(newSysId);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Массовый сдвиг отметки Z (± м)
        Row(
          children: [
            const Text('Сдвиг Z:', style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 30,
                child: TextField(
                  controller: _shiftCtrl,
                  keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                  style: const TextStyle(fontSize: 11),
                  decoration: const InputDecoration(
                    hintText: '±0.500',
                    suffixText: 'м',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _applyShift(),
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              height: 30,
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _applyShift,
                child: const Text('Сдвинуть', style: TextStyle(fontSize: 11)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}


