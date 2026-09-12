import 'package:flutter/material.dart';
import '../../../../domain/enums/projection_type.dart';
import '../../../../domain/enums/valve_type.dart';
import '../../../../domain/enums/weld_type.dart';
import '../../../../domain/models/pipe_support.dart';
import '../../../../core/math/snap_engine.dart';
import '../../../canvas/input_controller.dart';
import 'custom_pipe_dimension_dialog.dart';
import 'dxf_export_dialog.dart';
import 'elevation_panel.dart';
import 'fitting_catalog_dialog.dart';
import 'fitting_properties_sheet.dart';
import 'materials_specification_dialog.dart';
import 'pipe_assortment_dialog.dart';
import 'piping_systems_dialog.dart';
import 'weld_journal_dialog.dart';

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

                    // Плавающий инспектор свойств выбранного элемента
                    if (controller.selectedNodeId != null || controller.selectedSegmentId != null)
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

          // Ведомости (Спецификация, Сварка)
          PopupMenuButton<String>(
            tooltip: 'Ведомости и спецификации',
            icon: const Icon(Icons.table_chart, size: 18, color: Colors.white70),
            color: const Color(0xFF1E293B),
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'mto', child: Text('Спецификация (СО ГОСТ 21.110)', style: TextStyle(color: Colors.white, fontSize: 13))),
              const PopupMenuItem(value: 'weld', child: Text('Журнал сварки и катушек', style: TextStyle(color: Colors.white, fontSize: 13))),
            ],
            onSelected: (val) {
              if (val == 'mto') {
                showDialog(context: context, builder: (_) => MaterialsSpecificationDialog(network: controller.network));
              } else if (val == 'weld') {
                showDialog(context: context, builder: (_) => WeldJournalDialog(network: controller.network));
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
                ),
              );
            },
          ),

          const SizedBox(width: 8),
          // Переключатель на планшетный вид
          IconButton(
            icon: const Icon(Icons.tablet_mac, size: 18, color: Colors.white70),
            tooltip: 'Переключить в сенсорный стиль (Планшет)',
            onPressed: () => controller.setLayoutMode(UiLayoutMode.tabletTouch),
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
              const Text('Строительная ось:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo)),
              const SizedBox(width: 12),
              const Text('Марка оси:', style: TextStyle(fontSize: 12, color: Colors.grey)),
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
              const Text('Укажите начальную и конечную точку оси на плане', style: TextStyle(fontSize: 12, color: Colors.grey)),
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
            ] else ...[
              const Text('Выбор и навигация: кликните на узел или трубу для редактирования', style: TextStyle(fontSize: 12, color: Colors.grey)),
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
            _toolButton(CanvasTool.select, Icons.near_me, 'Выбор и перемещение (V)'),
            _toolButton(CanvasTool.pan, Icons.pan_tool, 'Панорамирование (H / СКМ)'),
            _toolButton(CanvasTool.orbit, Icons.threed_rotation, '3D Орбита (O / ПКМ)'),
            const Divider(height: 16, indent: 8, endIndent: 8),
            _toolButton(CanvasTool.trace, Icons.edit, 'Трассировка трубы (T)'),
            _toolButton(CanvasTool.drawAxis, Icons.architecture, 'Строительная ось (G)'),
            _toolButton(CanvasTool.insertEquipment, Icons.precision_manufacturing, 'Технологическое оборудование (E)'),
            const Divider(height: 16, indent: 8, endIndent: 8),
            _toolButton(CanvasTool.insertValve, Icons.tune, 'Врезка арматуры'),
            _toolButton(CanvasTool.insertWeld, Icons.flare, 'Врезка сварного шва'),
            _toolButton(CanvasTool.insertReducer, Icons.call_split, 'Врезка перехода'),
            _toolButton(CanvasTool.insertFlange, Icons.radio_button_checked, 'Врезка фланцев'),
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
    final isSegment = controller.selectedSegmentId != null;
    return Card(
      elevation: 6,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSegment ? Icons.linear_scale : Icons.grain,
                  size: 18,
                  color: Colors.indigo,
                ),
                Expanded(
                  child: Text(
                    isSegment ? 'Свойства трубы' : 'Свойства узла',
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
                    controller.refresh();
                  },
                ),
              ],
            ),
            const Divider(height: 14),
            if (isSegment)
              _DesktopSegmentInspector(
                controller: controller,
                segmentId: controller.selectedSegmentId!,
              )
            else if (controller.selectedNodeId != null) ...[
              Text('Узел ID: ${controller.selectedNodeId}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(
                'Отметка: ${controller.network.nodes[controller.selectedNodeId]?.elevationString ?? "0.000 м"}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.tune, size: 16),
                  label: const Text('Настроить деталь / фитинг', style: TextStyle(fontSize: 12)),
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => FittingPropertiesSheet(
                        network: controller.network,
                        nodeId: controller.selectedNodeId!,
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
              _getHintText(controller.currentTool, controller.traceStartNode != null),
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
        return 'Потяните узел или стояк для параметрического сдвига • Del: удалить';
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
      case CanvasTool.insertSupport:
        return 'Нажмите на участок трубы на чертеже для установки элемента';
      case CanvasTool.insertEquipment:
        return 'Кликните на холсте для размещения оборудования и штуцеров';
    }
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
  final _materials = const ['Сталь 20', '09Г2С', '12Х18Н10Т', '10ХСНД', '15Х5М', '12Х1МФ'];

  @override
  void initState() {
    super.initState();
    final len = widget.controller.selectedSegmentLength ?? 1000.0;
    _lengthController = TextEditingController(text: '${len.round()}');
  }

  @override
  void didUpdateWidget(covariant _DesktopSegmentInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.segmentId != widget.segmentId) {
      final len = widget.controller.selectedSegmentLength ?? 1000.0;
      _lengthController.text = '${len.round()}';
    }
  }

  @override
  void dispose() {
    _lengthController.dispose();
    super.dispose();
  }

  void _applyLength() {
    final val = double.tryParse(_lengthController.text.replaceAll(' ', ''));
    if (val != null && val > 0) {
      widget.controller.changeSelectedSegmentLength(val);
    }
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
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: sys != null ? Color(sys.colorValue) : Colors.blue,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                sys != null ? '${sys.code} (${sys.name})' : 'Трубопровод',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
