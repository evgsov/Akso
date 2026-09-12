import 'package:flutter/material.dart';
import '../../../../domain/enums/projection_type.dart';
import '../../../canvas/input_controller.dart';
import 'custom_pipe_dimension_dialog.dart';
import 'dxf_export_dialog.dart';
import 'elevation_panel.dart';
import 'fitting_catalog_dialog.dart';
import 'fitting_properties_sheet.dart';
import 'materials_specification_dialog.dart';
import 'pipe_assortment_dialog.dart';
import 'piping_systems_dialog.dart';
import 'tools_panel.dart';
import 'touch_distance_entry_dialog.dart';
import 'weld_journal_dialog.dart';

class TabletTouchLayout extends StatelessWidget {
  final PipingInputController controller;
  final Widget canvasWidget;

  const TabletTouchLayout({
    super.key,
    required this.controller,
    required this.canvasWidget,
  });

  @override
  Widget build(BuildContext context) {
    final activeSys = controller.network.systems[controller.activeSystemId];

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          children: [
            // Компактная верхняя полоса для планшета
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.hub, color: Colors.indigo, size: 22),
                  const SizedBox(width: 8),
                  const Text('AKSO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo)),
                  const SizedBox(width: 16),

                  // Активная система (крупный чип)
                  ActionChip(
                    avatar: CircleAvatar(
                      backgroundColor: activeSys != null ? Color(activeSys.colorValue) : Colors.blue,
                      radius: 8,
                    ),
                    label: Text(
                      activeSys?.code ?? 'В1',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => PipingSystemsDialog(
                          network: controller.network,
                          activeSystemId: controller.activeSystemId,
                          onSystemSelected: (id) => controller.setActiveSystem(id),
                          onSystemsChanged: controller.refresh,
                        ),
                      );
                    },
                  ),

                  const Spacer(),

                  // Меню проекций
                  DropdownButtonHideUnderline(
                    child: DropdownButton<ProjectionType>(
                      value: controller.projector.projectionType,
                      items: const [
                        DropdownMenuItem(value: ProjectionType.gostFrontal45, child: Text('ГОСТ 45°')),
                        DropdownMenuItem(value: ProjectionType.gostMirrored45, child: Text('Зеркало 45°')),
                        DropdownMenuItem(value: ProjectionType.iso30, child: Text('ISO 30°')),
                        DropdownMenuItem(value: ProjectionType.orbit3d, child: Text('3D Орбита')),
                        DropdownMenuItem(value: ProjectionType.topPlan2d, child: Text('План 2D')),
                      ],
                      onChanged: (p) {
                        if (p != null) controller.setProjectionType(p);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Меню действий
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'pipe_assortment', child: Text('Сортамент труб (ГОСТ)')),
                      const PopupMenuItem(value: 'catalog', child: Text('Каталог деталей')),
                      const PopupMenuItem(value: 'mto', child: Text('Спецификация (СО)')),
                      const PopupMenuItem(value: 'weld', child: Text('Журнал сварки')),
                      const PopupMenuItem(value: 'export', child: Text('Экспорт DXF')),
                      const PopupMenuItem(value: 'desktop', child: Text('Режим: Десктоп CAD')),
                    ],
                    onSelected: (val) {
                      if (val == 'pipe_assortment') {
                        PipeAssortmentDialog.show(
                          context,
                          network: controller.network,
                          controller: controller,
                          onCatalogChanged: controller.refresh,
                        );
                      } else if (val == 'catalog') {
                        showDialog(context: context, builder: (_) => FittingCatalogDialog(network: controller.network, onCatalogChanged: controller.refresh));
                      } else if (val == 'mto') {
                        showDialog(context: context, builder: (_) => MaterialsSpecificationDialog(network: controller.network));
                      } else if (val == 'weld') {
                        showDialog(context: context, builder: (_) => WeldJournalDialog(network: controller.network));
                      } else if (val == 'export') {
                        showDialog(context: context, builder: (_) => DxfExportDialog(network: controller.network, currentProjection: controller.projector.projectionType, calloutTemplates: controller.currentProject.calloutTemplates));
                      } else if (val == 'desktop') {
                        controller.setLayoutMode(UiLayoutMode.desktopCad);
                      }
                    },
                  ),
                ],
              ),
            ),

            // Основная рабочая область
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      color: const Color(0xFFF8F9FA),
                      child: canvasWidget,
                    ),
                  ),

                  // Плавающий остров инструментов слева (укрупненные кнопки для пальца и стилуса >= 48x48)
                  Positioned(
                    left: 16,
                    top: 16,
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _touchToolBtn(CanvasTool.trace, Icons.edit, 'Трассировка'),
                            _touchToolBtn(CanvasTool.select, Icons.open_with, 'Выбор / Сдвиг'),
                            _touchToolBtn(CanvasTool.pan, Icons.pan_tool, 'Панорама'),
                            _touchToolBtn(CanvasTool.orbit, Icons.threed_rotation, '3D Орбита'),
                            const Divider(height: 12),
                            _touchToolBtn(CanvasTool.insertValve, Icons.tune, 'Арматура'),
                            _touchToolBtn(CanvasTool.insertWeld, Icons.flare, 'Сварка'),
                            _touchToolBtn(CanvasTool.insertReducer, Icons.call_split, 'Переход'),
                            _touchToolBtn(CanvasTool.insertFlange, Icons.radio_button_checked, 'Фланец'),
                            _touchToolBtn(CanvasTool.insertSupport, Icons.format_underlined, 'Опора'),
                            _touchToolBtn(CanvasTool.insertEquipment, Icons.precision_manufacturing, 'Оборудование'),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Плавающие кнопки управления справа (Undo, Redo, Отмена, Настройки)
                  Positioned(
                    right: 16,
                    top: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        ElevationPanel(controller: controller),
                        const SizedBox(height: 12),
                        Card(
                          elevation: 3,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.undo),
                                onPressed: controller.canUndo ? controller.undo : null,
                              ),
                              IconButton(
                                icon: const Icon(Icons.redo),
                                onPressed: controller.canRedo ? controller.redo : null,
                              ),
                            ],
                          ),
                        ),
                        if (controller.traceStartNode != null || controller.axisStartNode != null) ...[
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            key: const Key('tablet_exact_length_button'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.amber.shade700,
                              foregroundColor: Colors.white,
                              elevation: 2,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                            icon: const Icon(Icons.straighten, size: 18),
                            label: const Text(
                              '📐 Точная длина',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            onPressed: () => _showTouchDistanceEntryDialog(context),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
                            icon: const Icon(Icons.close, size: 18),
                            label: const Text('Отменить черчение'),
                            onPressed: controller.cancelCurrentOperation,
                          ),
                        ],
                        if (controller.selectedSegmentId != null) ...[
                          const SizedBox(height: 12),
                          Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.linear_scale, color: Colors.indigo, size: 18),
                                      const SizedBox(width: 6),
                                      const Text('Выбрана труба', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(Icons.close, size: 16),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        tooltip: 'Снять выбор',
                                        onPressed: () {
                                          controller.selectedSegmentId = null;
                                          controller.refresh();
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      ActionChip(
                                        avatar: const Icon(Icons.straighten, size: 16, color: Colors.indigo),
                                        label: Text('L = ${(controller.selectedSegmentLength ?? 0).round()} мм'),
                                        onPressed: () => _showChangeLengthDialog(context),
                                      ),
                                      ActionChip(
                                        avatar: const Icon(Icons.radio_button_checked, size: 16, color: Colors.indigo),
                                        label: Text(controller.network.segments[controller.selectedSegmentId]?.shortCallout ?? "Ду"),
                                        onPressed: () => _showChangeDnSheet(context),
                                      ),
                                      ActionChip(
                                        avatar: const Icon(Icons.shield_outlined, size: 16, color: Colors.blueGrey),
                                        label: Text(controller.network.segments[controller.selectedSegmentId]?.material ?? "Сталь 20"),
                                        onPressed: () => _showChangeMaterialSheet(context),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.red.shade600,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    icon: const Icon(Icons.delete_outline, size: 16),
                                    label: const Text('Удалить трубу'),
                                    onPressed: controller.deleteSelected,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        if (controller.selectedNodeId != null) ...[
                          const SizedBox(height: 12),
                          Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.grain, color: Colors.indigo, size: 18),
                                      const SizedBox(width: 6),
                                      const Text('Выбран узел', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(Icons.close, size: 16),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        tooltip: 'Снять выбор',
                                        onPressed: () {
                                          controller.selectedNodeId = null;
                                          controller.refresh();
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Отметка: ${controller.network.nodes[controller.selectedNodeId]?.elevationString ?? "0.000 м"}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      FilledButton.tonalIcon(
                                        style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                                        icon: const Icon(Icons.tune, size: 16),
                                        label: const Text('Деталь'),
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
                                      const SizedBox(width: 8),
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.red,
                                          side: BorderSide(color: Colors.red.shade300),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        icon: const Icon(Icons.delete_outline, size: 16),
                                        label: const Text('Удалить'),
                                        onPressed: controller.deleteSelected,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Кнопки масштаба в правом нижнем углу
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.add),
                            tooltip: 'Приблизить',
                            onPressed: () => controller.zoomIn(),
                          ),
                          InkWell(
                            onTap: () => controller.zoom100(),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              child: Text(
                                '${controller.zoomPercentage}%',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                  color: Colors.blueGrey,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove),
                            tooltip: 'Отдалить',
                            onPressed: () => controller.zoomOut(),
                          ),
                          IconButton(
                            icon: const Icon(Icons.center_focus_strong),
                            tooltip: 'Вписать всё в экран',
                            onPressed: () => controller.zoomToFit(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Нижняя панель параметров инструментов
            EditorToolsPanel(controller: controller),
          ],
        ),
      ),
    );
  }

  Widget _touchToolBtn(CanvasTool tool, IconData icon, String tooltip) {
    final isSel = controller.currentTool == tool;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: SizedBox(
        width: 48,
        height: 48,
        child: IconButton(
          icon: Icon(icon, size: 24),
          color: isSel ? Colors.indigo : Colors.black87,
          style: IconButton.styleFrom(
            backgroundColor: isSel ? Colors.indigo.shade50 : Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          tooltip: tooltip,
          onPressed: () => controller.setTool(tool),
        ),
      ),
    );
  }

  void _showChangeLengthDialog(BuildContext context) {
    final curLen = controller.selectedSegmentLength ?? 1000.0;
    final textController = TextEditingController(text: '${curLen.round()}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.straighten, color: Colors.indigo),
            SizedBox(width: 8),
            Text('Изменить длину трубы'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Введите новую длину в миллиметрах (мм):', style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                suffixText: 'мм',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (val) {
                final d = double.tryParse(val.replaceAll(' ', ''));
                if (d != null && d > 0) {
                  controller.changeSelectedSegmentLength(d);
                  Navigator.of(ctx).pop();
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final d = double.tryParse(textController.text.replaceAll(' ', ''));
              if (d != null && d > 0) {
                controller.changeSelectedSegmentLength(d);
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('Применить'),
          ),
        ],
      ),
    );
  }

  void _showChangeDnSheet(BuildContext context) {
    final seg = controller.network.segments[controller.selectedSegmentId];
    if (seg == null) return;

    final catalog = controller.network.pipeCatalog;
    int selectedDn = seg.dn;
    double selectedWall = seg.wallThicknessMm;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final dim = catalog.getDimension(selectedDn);
          final wallOpts = List<double>.from(dim?.wallThicknesses ?? [selectedWall]);
          if (!wallOpts.any((w) => (w - selectedWall).abs() < 0.05)) {
            wallOpts.add(selectedWall);
            wallOpts.sort();
          }

          final allDns = catalog.getAllDns();
          final standardDns = allDns.where((d) => d <= 200).toList();
          final industrialDns = allDns.where((d) => d > 200).toList();

          return Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.tune, color: Colors.indigo),
                          SizedBox(width: 8),
                          Text('Типоразмер трубы', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Свой размер'),
                        onPressed: () async {
                          final newDim = await CustomPipeDimensionDialog.show(
                            context,
                            initialDn: selectedDn,
                            initialOuterD: dim?.outerDiameterMm,
                            initialWallS: selectedWall,
                          );
                          if (newDim != null) {
                            controller.addCustomPipeDimension(newDim);
                            controller.changeSelectedSegmentSize(
                              dn: newDim.dn,
                              outerDiameterMm: newDim.outerDiameterMm,
                              wallThicknessMm: newDim.defaultWallThicknessMm,
                            );
                            if (ctx.mounted) {
                              Navigator.of(ctx).pop();
                            }
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Карточка выбранного типоразмера
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.indigo.shade200),
                    ),
                    child: Text(
                      'Размер: ⌀${(dim?.outerDiameterMm ?? selectedDn).toStringAsFixed((dim?.outerDiameterMm ?? selectedDn).truncateToDouble() == (dim?.outerDiameterMm ?? selectedDn) ? 0 : 1)}×${selectedWall.toStringAsFixed(selectedWall.truncateToDouble() == selectedWall ? 0 : 1)} (Ду$selectedDn)',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Толщина стенки S
                  const Text('Толщина стенки (S, мм):', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: wallOpts.map((s) {
                      final isSelected = (s - selectedWall).abs() < 0.05;
                      return ChoiceChip(
                        label: Text('S = ${s.toStringAsFixed(s.truncateToDouble() == s ? 0 : 1)} мм'),
                        selected: isSelected,
                        selectedColor: Colors.amber.shade200,
                        onSelected: (selected) {
                          if (selected) {
                            setSheetState(() => selectedWall = s);
                            controller.changeSelectedSegmentWallThickness(s);
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Ду (ЖКХ и здания)
                  const Text('Диаметр DN (ЖКХ и здания, 15–200 мм):', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: standardDns.map((dn) {
                      final isSelected = selectedDn == dn;
                      return ChoiceChip(
                        label: Text('Ду$dn'),
                        selected: isSelected,
                        selectedColor: Colors.indigo.shade100,
                        onSelected: (selected) {
                          if (selected) {
                            setSheetState(() {
                              selectedDn = dn;
                              final newDim = catalog.getDimension(dn);
                              if (newDim != null) {
                                selectedWall = newDim.defaultWallThicknessMm;
                              }
                            });
                            controller.changeSelectedSegmentDn(dn);
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Ду (Промышленность)
                  if (industrialDns.isNotEmpty) ...[
                    const Text('Диаметр DN (Промышленность, 250–1400 мм):', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: industrialDns.map((dn) {
                        final isSelected = selectedDn == dn;
                        return ChoiceChip(
                          label: Text('Ду$dn'),
                          selected: isSelected,
                          selectedColor: Colors.indigo.shade100,
                          onSelected: (selected) {
                            if (selected) {
                              setSheetState(() {
                                selectedDn = dn;
                                final newDim = catalog.getDimension(dn);
                                if (newDim != null) {
                                  selectedWall = newDim.defaultWallThicknessMm;
                                }
                              });
                              controller.changeSelectedSegmentDn(dn);
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showChangeMaterialSheet(BuildContext context) {
    final seg = controller.network.segments[controller.selectedSegmentId];
    if (seg == null) return;
    const materials = ['Сталь 20', '09Г2С', '12Х18Н10Т', '10ХСНД', '15Х5М', '12Х1МФ'];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.shield_outlined, color: Colors.indigo),
                SizedBox(width: 8),
                Text('Марка стали трубы', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: materials.map((m) {
                final isSelected = seg.material == m;
                return ChoiceChip(
                  label: Text(m, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                  selected: isSelected,
                  selectedColor: Colors.indigo.shade100,
                  onSelected: (selected) {
                    if (selected) {
                      controller.changeSelectedSegmentMaterial(m);
                      Navigator.of(ctx).pop();
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showTouchDistanceEntryDialog(BuildContext context) {
    TouchDistanceEntryDialog.show(
      context,
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
