import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../domain/enums/fitting_type.dart';
import '../../../../domain/enums/inspection_method.dart';
import '../../../../domain/enums/projection_type.dart';
import '../../../../domain/enums/valve_type.dart';
import '../../../../domain/enums/weld_joint_style.dart';
import '../../../../domain/enums/weld_type.dart';
import '../../../../domain/models/fitting.dart';
import '../../../../domain/models/pipe_support.dart';
import '../../../../core/math/snap_engine.dart';
import '../../../../domain/models/callout.dart';
import '../../../canvas/input_controller.dart';
import '../../../../domain/services/segment_positioning_service.dart';
import 'callout_manager_panel.dart';
import 'custom_pipe_dimension_dialog.dart';
import 'custom_valve_catalog_dialog.dart';
import '../../../../domain/services/custom_valve_catalog.dart';
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
import 'project_properties_dialog.dart';
import 'quick_bridge_dialog.dart';
import 'riser_sectioning_dialog.dart';
import 'sheet_tab_bar.dart';
import 'sheet_toolbar.dart';
import '../../../../data/services/pdf_export_service.dart';
import '../../../../domain/models/construction_axis.dart';
import '../../../../domain/services/grid_system_engine.dart';

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

        // 2. Контекстная строка параметров (Options Bar в модели ИЛИ SheetToolbar на листе)
        controller.isModelSpaceActive
            ? _buildOptionsBar(context)
            : SheetToolbar(
                controller: controller,
                onExportPdf: () => _exportSheetPdf(context),
              ),

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

        // 4. Панель вкладок чертежных листов (AutoCAD / СПДС)
        SheetTabBar(controller: controller),

        // 5. Нижняя строка состояния (Status Bar)
        _buildStatusBar(context),
      ],
    );
  }

  Future<void> _exportSheetPdf(BuildContext context) async {
    final sheet = controller.activeSheet;
    if (sheet == null) return;
    try {
      final bytes = await PdfExportService.generateSheetPdf(
        sheet: sheet,
        network: controller.network,
        styleConfig: controller.styleConfig,
        projectionType: controller.projector.projectionType,
        orbitAzimuth: controller.projector.orbitAzimuth,
        orbitElevation: controller.projector.orbitElevation,
        targetCenter: controller.projector.targetCenter,
        customValves: controller.customValves,
        calloutTemplates: controller.currentProject.calloutTemplates,
      );
      final fileName = '${sheet.name.replaceAll(':', '_').replaceAll(' ', '_')}.pdf';
      final ok = await PdfExportService.savePdfFile(
        bytes: bytes,
        suggestedFileName: fileName,
      );
      if (ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Чертеж сохранен в PDF: $fileName'),
            backgroundColor: Colors.teal.shade800,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка экспорта PDF: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  Future<void> _confirmAndNewProject(BuildContext context) async {
    if (controller.hasUnsavedChanges) {
      final shouldProceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Несохраненные изменения', style: TextStyle(color: Colors.white)),
          content: const Text(
            'В текущем проекте есть несохраненные изменения. Создать новый проект без сохранения?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(backgroundColor: Colors.amber.shade700),
              child: const Text('Создать новый'),
            ),
          ],
        ),
      );
      if (shouldProceed != true) return;
    }
    controller.newProject(force: true);
  }

  void _showOffsetAxisDialog(BuildContext context, PipingInputController controller, ConstructionAxis axis) {
    final distController = TextEditingController(text: '3000');
    final labelController = TextEditingController(text: GridSystemEngine.generateNextLabel(axis.label));
    bool isPositive = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Создать параллельную ось (Offset)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: distController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Расстояние смещения (мм)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: labelController,
                decoration: const InputDecoration(
                  labelText: 'Марка новой оси',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('+ Смещение')),
                  ButtonSegment(value: false, label: Text('- Смещение')),
                ],
                selected: {isPositive},
                onSelectionChanged: (set) {
                  setState(() => isPositive = set.first);
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
                final dist = double.tryParse(distController.text.trim()) ?? 3000.0;
                final newLabel = labelController.text.trim();
                final newAxis = controller.createOffsetAxis(axis.id, dist, positiveSide: isPositive);
                if (newLabel.isNotEmpty) {
                  controller.updateConstructionAxis(newAxis.copyWith(label: newLabel));
                }
                Navigator.of(ctx).pop();
              },
              child: const Text('Создать'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRecentProjectsDialog(BuildContext context) async {
    final recents = await controller.recentProjectsManager.getRecentProjects();
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Row(
          children: [
            Icon(Icons.history, color: Colors.cyanAccent),
            SizedBox(width: 8),
            Text('Недавние проекты', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: recents.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('Список недавних проектов пуст', style: TextStyle(color: Colors.white54)),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: recents.length,
                  separatorBuilder: (_, _) => const Divider(color: Colors.white12),
                  itemBuilder: (ctx, i) {
                    final item = recents[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.description, color: Colors.cyanAccent),
                      title: Text(item.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        item.filePath,
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        '${item.lastOpened.day.toString().padLeft(2, '0')}.${item.lastOpened.month.toString().padLeft(2, '0')}',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        try {
                          await controller.openProject(filePath: item.filePath);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Проект "${item.title}" загружен')),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Ошибка открытия проекта: $e')),
                            );
                          }
                        }
                      },
                    );
                  },
                ),
        ),
        actions: [
          if (recents.isNotEmpty)
            TextButton(
              onPressed: () async {
                await controller.recentProjectsManager.clearRecentProjects();
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('Очистить список', style: TextStyle(color: Colors.redAccent)),
            ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Widget _buildFileMenu(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Меню проекта',
      icon: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.asset(
          'assets/images/akso_logo.png',
          width: 22,
          height: 22,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const Icon(Icons.hub, color: Colors.cyanAccent, size: 20),
        ),
      ),
      color: const Color(0xFF1E293B),
      onSelected: (value) async {
        switch (value) {
          case 'new':
            await _confirmAndNewProject(context);
            break;
          case 'open':
            try {
              final ok = await controller.openProject();
              if (ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Проект открыт')),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Ошибка открытия: $e')),
                );
              }
            }
            break;
          case 'recent':
            _showRecentProjectsDialog(context);
            break;
          case 'save':
            try {
              final ok = await controller.saveProject();
              if (ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Проект сохранён')),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Ошибка сохранения: $e')),
                );
              }
            }
            break;
          case 'save_as':
            try {
              final ok = await controller.saveProjectAs();
              if (ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Проект сохранён как новый файл')),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Ошибка сохранения: $e')),
                );
              }
            }
            break;
          case 'properties':
            showDialog(
              context: context,
              builder: (_) => ProjectPropertiesDialog(controller: controller),
            );
            break;
          case 'quick_bridge':
            showDialog(
              context: context,
              builder: (_) => QuickBridgeDialog(controller: controller),
            );
            break;
          case 'share':
            try {
              await controller.shareCurrentProject();
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Ошибка экспорта: $e')),
                );
              }
            }
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'new',
          child: Row(
            children: [
              Icon(Icons.add, color: Colors.cyanAccent, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text('Новый проект', style: TextStyle(color: Colors.white, fontSize: 13))),
              Text('Ctrl+N', style: TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'open',
          child: Row(
            children: [
              Icon(Icons.folder_open, color: Colors.cyanAccent, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text('Открыть...', style: TextStyle(color: Colors.white, fontSize: 13))),
              Text('Ctrl+O', style: TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'recent',
          child: Row(
            children: [
              Icon(Icons.history, color: Colors.cyanAccent, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text('Недавние проекты', style: TextStyle(color: Colors.white, fontSize: 13))),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        const PopupMenuItem(
          value: 'save',
          child: Row(
            children: [
              Icon(Icons.save, color: Colors.cyanAccent, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text('Сохранить', style: TextStyle(color: Colors.white, fontSize: 13))),
              Text('Ctrl+S', style: TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'save_as',
          child: Row(
            children: [
              Icon(Icons.save_as, color: Colors.cyanAccent, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text('Сохранить как...', style: TextStyle(color: Colors.white, fontSize: 13))),
              Text('Ctrl+Shift+S', style: TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        const PopupMenuItem(
          value: 'properties',
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.cyanAccent, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text('Свойства проекта...', style: TextStyle(color: Colors.white, fontSize: 13))),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'quick_bridge',
          child: Row(
            children: [
              Icon(Icons.wifi_tethering, color: Colors.cyanAccent, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text('Wi-Fi QuickBridge...', style: TextStyle(color: Colors.white, fontSize: 13))),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'share',
          child: Row(
            children: [
              Icon(Icons.share, color: Colors.cyanAccent, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text('Поделиться файлом...', style: TextStyle(color: Colors.white, fontSize: 13))),
            ],
          ),
        ),
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
            // Меню «Файл» (Бренд)
            _buildFileMenu(context),
            const SizedBox(width: 4),
            const Text(
              'AKSO 3D',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.0, fontSize: 14),
            ),
            const SizedBox(width: 4),

            // Кликабельный заголовок проекта (открывает свойства)
            Tooltip(
              message: 'Свойства проекта (нажмите для редактирования)',
              child: InkWell(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => ProjectPropertiesDialog(controller: controller),
                  );
                },
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: controller.hasUnsavedChanges ? Colors.amber.shade700 : const Color(0xFF334155)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        controller.currentProject.title,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      if (controller.currentProject.projectCode.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Text(
                          '[${controller.currentProject.projectCode}]',
                          style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                      if (controller.hasUnsavedChanges)
                        const Text(
                          ' *',
                          style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),

            // Быстрые кнопки Сохранить / Wi-Fi QuickBridge
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: controller.isSaving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent)) : const Icon(Icons.save, size: 18),
              color: controller.hasUnsavedChanges ? Colors.amberAccent : Colors.white,
              tooltip: controller.hasUnsavedChanges ? 'Сохранить изменения * (Ctrl+S)' : 'Сохранить проект (Ctrl+S)',
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
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.wifi_tethering, size: 18),
              color: Colors.cyanAccent,
              tooltip: 'Быстрый обмен Wi-Fi (ПК ↔ Планшет)',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => QuickBridgeDialog(controller: controller),
                );
              },
            ),

            const VerticalDivider(color: Colors.white24, indent: 8, endIndent: 8),

            // Кнопки Undo / Redo
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.undo, size: 18),
              color: controller.canUndo ? Colors.white : Colors.white38,
              tooltip: 'Отменить (Ctrl+Z)',
              onPressed: controller.canUndo ? controller.undo : null,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.redo, size: 18),
              color: controller.canRedo ? Colors.white : Colors.white38,
              tooltip: 'Повторить (Ctrl+Y)',
              onPressed: controller.canRedo ? controller.redo : null,
            ),

            const VerticalDivider(color: Colors.white24, indent: 8, endIndent: 8),
            const SizedBox(width: 4),

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

            const SizedBox(width: 8),

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
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.line_weight, size: 16, color: Colors.cyanAccent),
              label: const Text('Сортамент', style: TextStyle(color: Colors.white, fontSize: 12)),
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
          const SizedBox(width: 4),

          // Каталог фитингов
          Tooltip(
            message: 'Каталог фитингов и правила трассировки',
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                visualDensity: VisualDensity.compact,
              ),
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
          const SizedBox(width: 4),

          // Выноски
          Tooltip(
            message: 'Умные выноски и аннотации (Менеджер)',
            child: IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.label_outline, size: 18, color: Colors.amberAccent),
              onPressed: () => CalloutManagerPanel.show(context, controller: controller),
            ),
          ),

          // Авто-расстановка выносок
          Tooltip(
            message: 'Авто-расстановка выносок (ГОСТ)',
            child: IconButton(
              key: const Key('cad_auto_layout_callouts_button'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.auto_fix_high, size: 18, color: Colors.tealAccent),
              onPressed: () {
                final updated = controller.autoLayoutCallouts();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      updated > 0
                          ? 'Авто-расстановка выполнена для $updated выносок'
                          : 'Все выноски уже расположены оптимально',
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 4),

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
                showDialog(context: context, builder: (_) => MaterialsSpecificationDialog(network: controller.network, controller: controller));
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
                  tooltip: 'Привязка (Snap / F3)',
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
                  icon: Icon(controller.draftingSettings.isZLocked ? Icons.lock : Icons.lock_open, size: 16),
                  tooltip: controller.draftingSettings.isZLocked ? 'Замок отметки Z (ВКЛ)' : 'Замок отметки Z (ВЫКЛ)',
                  color: controller.draftingSettings.isZLocked ? Colors.amberAccent : Colors.white60,
                  style: IconButton.styleFrom(
                    backgroundColor: controller.draftingSettings.isZLocked ? Colors.amber.shade900.withValues(alpha: 0.4) : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  onPressed: controller.toggleZLock,
                ),
                IconButton(
                  icon: const Icon(Icons.grid_on, size: 16),
                  tooltip: controller.draftingSettings.showZPlaneGrid ? 'Сетка Z-плоскости (ВКЛ)' : 'Сетка Z-плоскости (ВЫКЛ)',
                  color: controller.draftingSettings.showZPlaneGrid ? Colors.cyanAccent : Colors.white60,
                  style: IconButton.styleFrom(
                    backgroundColor: controller.draftingSettings.showZPlaneGrid ? Colors.cyan.shade900.withValues(alpha: 0.4) : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  onPressed: controller.toggleZGrid,
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
                  sheets: controller.sheets,
                  customValves: controller.customValves,
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
              const SizedBox(width: 12),
              FilterChip(
                selected: controller.isValveFlanged,
                label: const Text('Фланцы', style: TextStyle(fontSize: 11)),
                selectedColor: Colors.amber.shade200,
                onSelected: (val) => controller.setIsValveFlanged(val),
              ),
              if (controller.isValveFlanged) ...[
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: controller.valveFlangePressurePn,
                  isDense: true,
                  items: const [
                    DropdownMenuItem(value: 10, child: Text('Ру 10', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 16, child: Text('Ру 16', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 25, child: Text('Ру 25', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 40, child: Text('Ру 40', style: TextStyle(fontSize: 11))),
                  ],
                  onChanged: (pn) {
                    if (pn != null) controller.setValveFlangePressurePn(pn);
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  selected: controller.valveIncludeCounterFlanges,
                  label: const Text('Ответные фланцы', style: TextStyle(fontSize: 11)),
                  onSelected: (val) => controller.setValveIncludeCounterFlanges(val),
                ),
              ],
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
    final totalSelected = controller.selectedNodeIds.length +
        controller.selectedSegmentIds.length +
        controller.selectedEquipmentIds.length +
        controller.selectedAxisIds.length +
        controller.selectedDimensionIds.length;
    final isMultiSelect = totalSelected > 1;
    final isValve = !isDimension && !isAxis && !isMultiSelect && controller.selectedValveId != null;
    final isSupport = !isDimension && !isAxis && !isMultiSelect && !isValve && controller.selectedSupportId != null;
    final isWeld = !isDimension && !isAxis && !isMultiSelect && !isValve && !isSupport && controller.selectedWeldId != null;
    final isSpool = !isDimension && !isAxis && !isMultiSelect && !isValve && !isSupport && !isWeld && controller.selectedSpoolId != null;
    final isSegment = !isDimension && !isAxis && !isMultiSelect && !isValve && !isSupport && !isWeld && !isSpool && controller.selectedSegmentId != null;
    final isEquipment = !isDimension && !isAxis && !isMultiSelect && !isValve && !isSupport && !isWeld && !isSpool && controller.selectedEquipmentId != null;
    final selectedFit = (!isDimension && !isAxis && !isMultiSelect && !isValve && !isSupport && !isWeld && !isSpool && !isSegment && !isEquipment && controller.selectedNodeId != null)
        ? controller.network.fittings[controller.selectedNodeId]
        : null;

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
    } else if (selectedFit != null) {
      title = selectedFit.displayName;
      switch (selectedFit.fittingType) {
        case FittingType.elbow90:
        case FittingType.elbow45:
          icon = Icons.turn_right;
          break;
        case FittingType.tee:
          icon = Icons.call_split;
          break;
        case FittingType.cross:
          icon = Icons.add;
          break;
        case FittingType.reducerConcentric:
        case FittingType.reducerEccentric:
          icon = Icons.tune;
          break;
        case FittingType.flange:
          icon = Icons.radio_button_checked;
          break;
        case FittingType.cap:
          icon = Icons.block;
          break;
        case FittingType.directBranch:
          icon = Icons.merge_type;
          break;
      }
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('ID: ${axis.id}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        IconButton(
                          icon: Icon(
                            axis.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                            size: 16,
                            color: axis.isPinned ? Colors.red : Colors.grey,
                          ),
                          tooltip: axis.isPinned ? 'Разблокировать (Unpin)' : 'Заблокировать (Pin)',
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            controller.updateConstructionAxis(axis.copyWith(isPinned: !axis.isPinned));
                          },
                        ),
                      ],
                    ),
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
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Text('Марка:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SizedBox(
                              height: 28,
                              child: TextFormField(
                                key: ValueKey('axis_label_${axis.id}_${axis.label}'),
                                initialValue: axis.label,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                  border: OutlineInputBorder(),
                                ),
                                onFieldSubmitted: (val) {
                                  controller.updateConstructionAxis(axis.copyWith(label: val.trim()));
                                },
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward, size: 16),
                            tooltip: 'Следующая марка по ГОСТ',
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              final next = GridSystemEngine.generateNextLabel(axis.label);
                              controller.updateConstructionAxis(axis.copyWith(label: next));
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text('Кружки марок:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      Row(
                        children: [
                          Expanded(
                            child: CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              title: const Text('В начале', style: TextStyle(fontSize: 11)),
                              value: axis.showStartBubble,
                              onChanged: (val) {
                                controller.toggleAxisBubbleVisibility(axis.id, isStart: true);
                              },
                            ),
                          ),
                          Expanded(
                            child: CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              title: const Text('В конце', style: TextStyle(fontSize: 11)),
                              value: axis.showEndBubble,
                              onChanged: (val) {
                                controller.toggleAxisBubbleVisibility(axis.id, isStart: false);
                              },
                            ),
                          ),
                        ],
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        title: const Text('3D в плоскости', style: TextStyle(fontSize: 11)),
                        subtitle: const Text('Ориентация в плоскости XY', style: TextStyle(fontSize: 9, color: Colors.grey)),
                        value: axis.is3dPlaneOriented,
                        onChanged: (val) {
                          controller.updateConstructionAxis(axis.copyWith(is3dPlaneOriented: val));
                        },
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
                    if (axis.elevationZ != 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Отметка Z:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          Text('${axis.elevationZ.round()} мм', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'P1: (${axis.startPoint.x.round()}, ${axis.startPoint.y.round()})\nP2: (${axis.endPoint.x.round()}, ${axis.endPoint.y.round()})',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                    if (axis.startElbowOffset != null || axis.endElbowOffset != null) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.straighten, size: 14),
                          label: const Text('Сбросить изломы марки', style: TextStyle(fontSize: 11)),
                          onPressed: () {
                            controller.clearAxisElbowOffset(axis.id, isStart: true);
                            controller.clearAxisElbowOffset(axis.id, isStart: false);
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.copy, size: 14),
                        label: const Text('Создать смещение (Offset)', style: TextStyle(fontSize: 11)),
                        onPressed: () => _showOffsetAxisDialog(context, controller, axis),
                      ),
                    ),
                    const SizedBox(height: 8),
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
                              controller.network.updateSupport(
                                support.id,
                                support.copyWith(type: newType),
                              );
                              controller.history.recordState(controller.network);
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
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            ),
                            icon: const Icon(Icons.copy, size: 14),
                            label: const Text('Копировать (Ctrl+C)', style: TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis),
                            onPressed: () {
                              if (controller.copySelection()) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Опора скопирована в буфер обмена'),
                                    duration: Duration(seconds: 1),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            ),
                            icon: const Icon(Icons.control_point_duplicate, size: 14),
                            label: const Text('Дублировать (Ctrl+D)', style: TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis),
                            onPressed: () => controller.duplicateSelection(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
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
              _DesktopWeldInspector(
                controller: controller,
                weldId: controller.selectedWeldId!,
              ),
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

                if (fit != null) {
                  return _DesktopFittingInspector(
                    controller: controller,
                    nodeId: nodeId,
                    fitting: fit,
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Узел сети',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                              ),
                              const SizedBox(height: 1),
                              Tooltip(
                                message: 'Нажмите, чтобы скопировать ID:\n$nodeId',
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(4),
                                  onTap: () {
                                    Clipboard.setData(ClipboardData(text: nodeId));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('ID узла скопирован: $nodeId'),
                                        duration: const Duration(seconds: 1),
                                        behavior: SnackBarBehavior.floating,
                                        width: 320,
                                      ),
                                    );
                                  },
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '#${nodeId.length > 8 ? nodeId.substring(nodeId.length - 8) : nodeId}',
                                        style: TextStyle(fontSize: 9, fontFamily: 'monospace', color: Colors.grey.shade600),
                                      ),
                                      const SizedBox(width: 3),
                                      Icon(Icons.copy_rounded, size: 9, color: Colors.grey.shade500),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _DesktopNodeElevationEditor(
                      controller: controller,
                      nodeId: nodeId,
                    ),
                    const SizedBox(height: 6),
                    Text('Подключено труб: ${connected.length}', style: const TextStyle(fontSize: 11)),
                    const SizedBox(height: 10),
                    if (isEndNode) ...[
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
                            controller.network.attachCapToNode(nodeId);
                            controller.history.recordState(controller.network);
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
                            controller.network.attachEndFlangeToNode(
                              nodeId,
                              flangeConnectionType: FlangeConnectionType.toEquipment,
                              pressurePn: controller.flangePressurePn,
                              material: controller.activeMaterial,
                            );
                            controller.history.recordState(controller.network);
                            controller.refresh();
                          },
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                          icon: const Icon(Icons.settings_input_component, size: 16),
                          label: const Text('Установить арматуру на торец', style: TextStyle(fontSize: 12)),
                          onPressed: () {
                            controller.network.attachEndValveToNode(
                              nodeId,
                              valveType: controller.selectedValveType,
                            );
                            controller.network.generateElementWeldJoints();
                            controller.history.recordState(controller.network);
                            controller.refresh();
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    () {
                      final hasElevCallout = controller.nodeHasElevationCallout(nodeId);
                      final callout = hasElevCallout ? controller.getNodeElevationCallout(nodeId) : null;
                      final effectiveStyle = callout?.elevationStyle ??
                          ElevationMarkStyleExt.fromString(
                            controller.currentProject.calloutTemplates['elevation_style'],
                            fallback: ElevationMarkStyle.gostOutline,
                          );
                      final effectiveDir = callout?.shelfDirection ?? ShelfDirection.auto;
                      final effectiveArrowOnNode = callout?.arrowOnNode ??
                          (controller.currentProject.calloutTemplates['elevation_arrow_on_node'] != 'false');

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                backgroundColor: hasElevCallout ? Colors.green.shade50 : null,
                                foregroundColor: hasElevCallout ? Colors.green.shade800 : null,
                              ),
                              icon: Icon(hasElevCallout ? Icons.check_circle_outline : Icons.height, size: 16),
                              label: Text(
                                hasElevCallout ? 'Отметка ГОСТ (установлена)' : 'Поставить отметку уровня (ГОСТ)',
                                style: const TextStyle(fontSize: 11),
                              ),
                              onPressed: () {
                                final added = controller.toggleNodeElevationCallout(nodeId);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      added ? 'Высотная отметка ГОСТ создана' : 'Высотная отметка удалена',
                                    ),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              },
                            ),
                          ),
                          if (hasElevCallout) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      const Expanded(
                                        flex: 2,
                                        child: Text('Стиль:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: DropdownButton<ElevationMarkStyle>(
                                          isDense: true,
                                          isExpanded: true,
                                          value: effectiveStyle,
                                          items: ElevationMarkStyle.values.map((s) {
                                            return DropdownMenuItem(
                                              value: s,
                                              child: Text(s.shortName, style: const TextStyle(fontSize: 11)),
                                            );
                                          }).toList(),
                                          onChanged: (newStyle) {
                                            if (newStyle != null) {
                                              controller.updateNodeElevationCallout(nodeId, style: newStyle);
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Expanded(
                                        flex: 2,
                                        child: Text('Полка:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: DropdownButton<ShelfDirection>(
                                          isDense: true,
                                          isExpanded: true,
                                          value: effectiveDir,
                                          items: ShelfDirection.values.map((d) {
                                            return DropdownMenuItem(
                                              value: d,
                                              child: Text(d.displayName, style: const TextStyle(fontSize: 11)),
                                            );
                                          }).toList(),
                                          onChanged: (newDir) {
                                            if (newDir != null) {
                                              controller.updateNodeElevationCallout(nodeId, direction: newDir);
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Expanded(
                                        flex: 2,
                                        child: Text('Стрелка:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: DropdownButton<bool>(
                                          isDense: true,
                                          isExpanded: true,
                                          value: effectiveArrowOnNode,
                                          items: const [
                                            DropdownMenuItem(
                                              value: true,
                                              child: Text('На узле', style: TextStyle(fontSize: 11)),
                                            ),
                                            DropdownMenuItem(
                                              value: false,
                                              child: Text('На выноске', style: TextStyle(fontSize: 11)),
                                            ),
                                          ],
                                          onChanged: (newArrow) {
                                            if (newArrow != null) {
                                              controller.updateNodeElevationCallout(nodeId, arrowOnNode: newArrow);
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      );
                    }(),
                    const SizedBox(height: 6),
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: controller.toggleSnap,
                  child: Tooltip(
                    message: 'Объектная привязка OSNAP (клавиша F3)',
                    child: Text(
                      'SNAP (F3): ${controller.isSnapEnabled ? "ВКЛ" : "ВЫКЛ"}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: controller.isSnapEnabled ? Colors.green.shade800 : Colors.red.shade800,
                      ),
                    ),
                  ),
                ),
                Theme(
                  data: Theme.of(context).copyWith(
                    splashColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                  ),
                  child: PopupMenuButton<String>(
                    tooltip: 'Режимы объектной привязки (Osnap)',
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.arrow_drop_down, size: 16, color: Colors.blueGrey),
                    color: const Color(0xFF1E293B),
                    itemBuilder: (ctx) => [
                      _buildOsnapCheckItem('snapNodes', 'Узлы и концы труб (Endpoint)', controller.draftingSettings.snapNodes),
                      _buildOsnapCheckItem('snapIntersections', 'Пересечения (Intersection)', controller.draftingSettings.snapIntersections),
                      _buildOsnapCheckItem('snapMidpoints', 'Середины труб (Midpoint)', controller.draftingSettings.snapMidpoints),
                      _buildOsnapCheckItem('snapPerpendicular', 'Перпендикуляры (Perpendicular)', controller.draftingSettings.snapPerpendicular),
                      _buildOsnapCheckItem('snapNearest', 'Ближайшая к оси (Nearest / Trajectory)', controller.draftingSettings.snapNearest),
                      const PopupMenuDivider(),
                      _buildOsnapCheckItem('enableOtrack', 'Отслеживание створов (OTRACK F11)', controller.draftingSettings.enableOtrack),
                      _buildOsnapCheckItem('isZLocked', 'Замок отметки Z (Z-Lock)', controller.draftingSettings.isZLocked),
                      _buildOsnapCheckItem('showZPlaneGrid', 'Сетка рабочей плоскости Z', controller.draftingSettings.showZPlaneGrid),
                    ],
                    onSelected: (key) => _toggleOsnapSetting(key),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: controller.toggleObjectTracking,
              child: Tooltip(
                message: 'Отслеживание осей и створов OTRACK (клавиша F11)',
                child: Text(
                  'ОТСЛ (F11): ${controller.isObjectTrackingEnabled ? "ВКЛ" : "ВЫКЛ"}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: controller.isObjectTrackingEnabled ? Colors.teal.shade800 : Colors.grey.shade600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            InkWell(
              onTap: controller.toggleZLock,
              child: Tooltip(
                message: controller.draftingSettings.isZLocked
                    ? 'Замок отметки Z активен (привязка только на отметке ∇$zStr). Нажмите, чтобы отключить'
                    : 'Зафиксировать отметку Z на ∇$zStr (Z-Lock). Игнорирует узлы на других высотах',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: controller.draftingSettings.isZLocked ? Colors.amber.shade100 : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: controller.draftingSettings.isZLocked ? Colors.amber.shade800 : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        controller.draftingSettings.isZLocked ? Icons.lock : Icons.lock_open,
                        size: 13,
                        color: controller.draftingSettings.isZLocked ? Colors.amber.shade900 : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Z-Lock: ${controller.draftingSettings.isZLocked ? "ВКЛ" : "ВЫКЛ"}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: controller.draftingSettings.isZLocked ? Colors.amber.shade900 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            InkWell(
              onTap: controller.toggleZGrid,
              child: Tooltip(
                message: 'Сетка плоскости Z: аксонометрический контур активной высоты ∇$zStr',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: controller.draftingSettings.showZPlaneGrid ? Colors.cyan.shade50 : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: controller.draftingSettings.showZPlaneGrid ? Colors.cyan.shade700 : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.grid_on,
                        size: 13,
                        color: controller.draftingSettings.showZPlaneGrid ? Colors.cyan.shade800 : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Сетка Z: ${controller.draftingSettings.showZPlaneGrid ? "ВКЛ" : "ВЫКЛ"}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: controller.draftingSettings.showZPlaneGrid ? Colors.cyan.shade800 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
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

  void _toggleOsnapSetting(String key) {
    final s = controller.draftingSettings;
    switch (key) {
      case 'snapNodes':
        controller.updateDraftingSettings(s.copyWith(snapNodes: !s.snapNodes));
        break;
      case 'snapIntersections':
        controller.updateDraftingSettings(s.copyWith(snapIntersections: !s.snapIntersections));
        break;
      case 'snapMidpoints':
        controller.updateDraftingSettings(s.copyWith(snapMidpoints: !s.snapMidpoints));
        break;
      case 'snapPerpendicular':
        controller.updateDraftingSettings(s.copyWith(snapPerpendicular: !s.snapPerpendicular));
        break;
      case 'snapNearest':
        controller.updateDraftingSettings(s.copyWith(snapNearest: !s.snapNearest));
        break;
      case 'enableOtrack':
        controller.updateDraftingSettings(s.copyWith(enableOtrack: !s.enableOtrack));
        break;
      case 'isZLocked':
        controller.toggleZLock();
        break;
      case 'showZPlaneGrid':
        controller.toggleZGrid();
        break;
    }
  }

  PopupMenuItem<String> _buildOsnapCheckItem(String key, String title, bool isChecked) {
    return PopupMenuItem<String>(
      value: key,
      height: 34,
      child: Row(
        children: [
          Icon(
            isChecked ? Icons.check_box : Icons.check_box_outline_blank,
            size: 16,
            color: isChecked ? Colors.tealAccent.shade400 : Colors.white54,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
          ),
        ],
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

class _DesktopFittingInspector extends StatefulWidget {
  final PipingInputController controller;
  final String nodeId;
  final Fitting fitting;

  const _DesktopFittingInspector({
    required this.controller,
    required this.nodeId,
    required this.fitting,
  });

  @override
  State<_DesktopFittingInspector> createState() => _DesktopFittingInspectorState();
}

class _DesktopFittingInspectorState extends State<_DesktopFittingInspector> {
  late TextEditingController _lengthController;
  late TextEditingController _branchHController;

  @override
  void initState() {
    super.initState();
    _lengthController = TextEditingController(
      text: widget.fitting.effectiveBuildingLengthMm.round().toString(),
    );
    _branchHController = TextEditingController(
      text: widget.fitting.effectiveBranchLengthMm.round().toString(),
    );
  }

  @override
  void didUpdateWidget(covariant _DesktopFittingInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fitting.id != widget.fitting.id ||
        oldWidget.fitting.effectiveBuildingLengthMm != widget.fitting.effectiveBuildingLengthMm) {
      _lengthController.text = widget.fitting.effectiveBuildingLengthMm.round().toString();
    }
    if (oldWidget.fitting.id != widget.fitting.id ||
        oldWidget.fitting.effectiveBranchLengthMm != widget.fitting.effectiveBranchLengthMm) {
      _branchHController.text = widget.fitting.effectiveBranchLengthMm.round().toString();
    }
  }

  @override
  void dispose() {
    _lengthController.dispose();
    _branchHController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final nodeId = widget.nodeId;
    final fitting = widget.fitting;
    final connected = controller.network.getConnectedSegments(nodeId);
    const materials = ['Сталь 20', '09Г2С', '12Х18Н10Т', '10Г2', '15Х5М', '17Г1С'];
    final currentMat = materials.contains(fitting.material) ? fitting.material : 'Сталь 20';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Узел фитинга',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Tooltip(
                    message: 'Нажмите, чтобы скопировать ID:\n$nodeId',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: nodeId));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('ID узла скопирован: $nodeId'),
                            duration: const Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                            width: 320,
                          ),
                        );
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '#${nodeId.length > 8 ? nodeId.substring(nodeId.length - 8) : nodeId}',
                            style: TextStyle(fontSize: 9, fontFamily: 'monospace', color: Colors.grey.shade600),
                          ),
                          const SizedBox(width: 3),
                          Icon(Icons.copy_rounded, size: 9, color: Colors.grey.shade500),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: Colors.indigo.shade200),
              ),
              child: Text(
                'Ду${fitting.dn}${fitting.dnSecondary != null && fitting.dnSecondary != fitting.dn ? "х${fitting.dnSecondary}" : ""}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _DesktopNodeElevationEditor(
          controller: controller,
          nodeId: nodeId,
        ),
        const SizedBox(height: 6),
        if (fitting.standard != null && fitting.standard!.isNotEmpty) ...[
          Text('Стандарт: ${fitting.standard}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
          const SizedBox(height: 6),
        ],

        // Выбор марки стали
        Row(
          children: [
            const Text('Сталь:', style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButton<String>(
                value: currentMat,
                isDense: true,
                isExpanded: true,
                style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w600),
                items: materials.map((m) {
                  return DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 11)));
                }).toList(),
                onChanged: (newMat) {
                  if (newMat != null) {
                    controller.network.updateFitting(nodeId, fitting.copyWith(material: newMat));
                    controller.history.recordState(controller.network);
                    controller.refresh();
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Специфические контролы в зависимости от типа детали
        if (fitting.fittingType == FittingType.reducerConcentric ||
            fitting.fittingType == FittingType.reducerEccentric) ...[
          const Text('Исполнение перехода:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
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
                  value: FittingType.reducerConcentric,
                  label: Text('Концентр.', style: TextStyle(fontSize: 10)),
                ),
                ButtonSegment(
                  value: FittingType.reducerEccentric,
                  label: Text('Эксцентр.', style: TextStyle(fontSize: 10)),
                ),
              ],
              selected: {
                fitting.fittingType == FittingType.reducerEccentric
                    ? FittingType.reducerEccentric
                    : FittingType.reducerConcentric
              },
              onSelectionChanged: (set) {
                final newType = set.first;
                controller.network.updateFitting(
                  nodeId,
                  fitting.copyWith(
                    fittingType: newType,
                    name: newType == FittingType.reducerEccentric
                        ? 'Переход эксцентрический'
                        : 'Переход концентрический',
                  ),
                );
                controller.history.recordState(controller.network);
                controller.refresh();
              },
            ),
          ),
          if (connected.length == 2) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('D1: Ду${connected[0].dn}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                const Icon(Icons.arrow_forward, size: 14, color: Colors.grey),
                Text('D2: Ду${connected[1].dn}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('Длина L:', style: TextStyle(fontSize: 11)),
              const SizedBox(width: 6),
              Expanded(
                child: SizedBox(
                  height: 26,
                  child: TextField(
                    controller: _lengthController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 11),
                    decoration: const InputDecoration(
                      suffixText: 'мм',
                      suffixStyle: TextStyle(fontSize: 9),
                      contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (v) {
                      final l = double.tryParse(v);
                      if (l != null && l > 0) {
                        controller.network.updateFittingLength(nodeId, l);
                        controller.history.recordState(controller.network);
                        controller.refresh();
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.rotate_right, size: 14),
                label: Text('${fitting.rotationAngleDeg.round()}°', style: const TextStyle(fontSize: 10)),
                onPressed: () {
                  final next = (fitting.rotationAngleDeg + 90.0) % 360.0;
                  controller.network.updateFittingRotation(nodeId, next);
                  controller.history.recordState(controller.network);
                  controller.refresh();
                },
              ),
            ],
          ),
        ] else if (fitting.fittingType == FittingType.flange) ...[
          Row(
            children: [
              const Text('Режим:', style: TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<FlangeConnectionType>(
                  value: fitting.flangeConnectionType,
                  isDense: true,
                  isExpanded: true,
                  style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.bold),
                  items: FlangeConnectionType.values.map((mode) {
                    return DropdownMenuItem(
                      value: mode,
                      child: Text(mode.displayName, style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: (newMode) {
                    if (newMode != null) {
                      controller.network.updateFitting(
                        nodeId,
                        fitting.copyWith(
                          flangeConnectionType: newMode,
                          isFlangePair: newMode == FlangeConnectionType.pipeToPipe,
                        ),
                      );
                      controller.network.generateElementWeldJoints();
                      controller.history.recordState(controller.network);
                      controller.refresh();
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('Давл. Ру:', style: TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(width: 6),
              Expanded(
                child: Wrap(
                  spacing: 4,
                  children: [10, 16, 25, 40].map((pn) {
                    final isSel = fitting.pressurePn == pn;
                    return ChoiceChip(
                      label: Text('PN $pn', style: TextStyle(fontSize: 9, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                      selected: isSel,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      onSelected: (_) {
                        controller.network.updateFitting(nodeId, fitting.copyWith(pressurePn: pn));
                        controller.history.recordState(controller.network);
                        controller.refresh();
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  icon: const Icon(Icons.flip, size: 14),
                  label: Text(fitting.isFlipped ? 'Зеркало 180°' : 'Зеркало 0°', style: const TextStyle(fontSize: 10)),
                  onPressed: () {
                    controller.network.updateFitting(nodeId, fitting.copyWith(isFlipped: !fitting.isFlipped));
                    controller.history.recordState(controller.network);
                    controller.refresh();
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  icon: Icon(fitting.isFlangePair ? Icons.check_box : Icons.check_box_outline_blank, size: 14),
                  label: Text(fitting.isFlangePair ? 'Пара' : 'Одиночный', style: const TextStyle(fontSize: 10)),
                  onPressed: () {
                    controller.network.updateFitting(nodeId, fitting.copyWith(isFlangePair: !fitting.isFlangePair));
                    controller.network.generateElementWeldJoints();
                    controller.history.recordState(controller.network);
                    controller.refresh();
                  },
                ),
              ),
            ],
          ),
        ] else if (fitting.fittingType == FittingType.cap) ...[
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.block, size: 16, color: Colors.amber),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    fitting.standard ?? 'ГОСТ 17379-2001 (Эллиптическая)',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ] else if (fitting.fittingType == FittingType.tee || fitting.fittingType == FittingType.directBranch) ...[
          const Text('Исполнение ответвления:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
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
              selected: {fitting.fittingType},
              onSelectionChanged: (set) {
                final newType = set.first;
                if (newType == FittingType.directBranch) {
                  controller.network.updateFitting(
                    nodeId,
                    fitting.copyWith(
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
                    fitting.copyWith(
                      fittingType: FittingType.tee,
                      name: 'Тройник равнопроходный Ду${fitting.dn}',
                      standard: 'ГОСТ 17376-2001',
                      weldType: WeldType.c17,
                      radiusMm: fitting.dn * 1.0,
                      cutsMainPipe: true,
                    ),
                  );
                }
                controller.network.generateElementWeldJoints();
                controller.history.recordState(controller.network);
                controller.refresh();
              },
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Text('H:', style: TextStyle(fontSize: 11)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: SizedBox(
                        height: 26,
                        child: TextField(
                          controller: _branchHController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 11),
                          decoration: const InputDecoration(
                            suffixText: 'мм',
                            suffixStyle: TextStyle(fontSize: 9),
                            contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (v) {
                            final h = double.tryParse(v);
                            if (h != null && h > 0) {
                              controller.network.updateFitting(nodeId, fitting.copyWith(branchLengthMm: h));
                              controller.history.recordState(controller.network);
                              controller.refresh();
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    const Text('L:', style: TextStyle(fontSize: 11)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: SizedBox(
                        height: 26,
                        child: TextField(
                          controller: _lengthController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 11),
                          decoration: const InputDecoration(
                            suffixText: 'мм',
                            suffixStyle: TextStyle(fontSize: 9),
                            contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (v) {
                            final l = double.tryParse(v);
                            if (l != null && l > 0) {
                              controller.network.updateFittingLength(nodeId, l);
                              controller.history.recordState(controller.network);
                              controller.refresh();
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ] else if (fitting.fittingType == FittingType.elbow90 || fitting.fittingType == FittingType.elbow45) ...[
          Row(
            children: [
              const Text('Радиус R:', style: TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(width: 6),
              Expanded(
                child: SegmentedButton<double>(
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: const [
                    ButtonSegment(value: 1.5, label: Text('1.5 DN', style: TextStyle(fontSize: 10))),
                    ButtonSegment(value: 1.0, label: Text('1.0 DN', style: TextStyle(fontSize: 10))),
                  ],
                  selected: {
                    (fitting.customRadiusMm != null && (fitting.customRadiusMm! - fitting.dn * 1.0).abs() < 1.0)
                        ? 1.0
                        : 1.5
                  },
                  onSelectionChanged: (set) {
                    final mult = set.first;
                    controller.network.updateFitting(
                      nodeId,
                      fitting.copyWith(
                        customRadiusMm: fitting.dn * mult,
                        radiusMm: fitting.dn * mult,
                        standard: mult == 1.5 ? 'ГОСТ 17375-2001' : 'ГОСТ 30753-2001',
                      ),
                    );
                    controller.history.recordState(controller.network);
                    controller.refresh();
                  },
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: 10),
        // Кнопки действий: Все свойства и Снять
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
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: Colors.red,
                side: BorderSide(color: Colors.red.shade300),
              ),
              icon: const Icon(Icons.delete_outline, size: 14),
              label: const Text('Снять', style: TextStyle(fontSize: 11)),
              onPressed: () {
                controller.network.removeFitting(nodeId);
                controller.history.recordState(controller.network);
                controller.refresh();
              },
            ),
          ],
        ),
      ],
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
        // Сопряжение элементов: статус или кнопка стягивания в 1 клик
        if (widget.controller.network.isConnectingFittingsSegment(widget.segmentId)) ...[
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
                      'Стык ${widget.controller.network.getButtJointLabel(widget.segmentId)} (встык)',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            Builder(
              builder: (context) {
                final targetLen = widget.controller.network.getButtJointTargetLength(widget.segmentId) ?? 0.0;
                final label = widget.controller.network.getButtJointLabel(widget.segmentId);
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
                      '🔗 Стянуть встык [$label] (${targetLen.round()} мм)',
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
        // Нарезка стояка / трубы на катушки
        Builder(
          builder: (context) {
            final sNode = widget.controller.network.nodes[seg.startNodeId];
            final eNode = widget.controller.network.nodes[seg.endNodeId];
            final isVertical = (sNode != null && eNode != null) && (eNode.z - sNode.z).abs() > 10.0;
            return SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.teal.shade50,
                  foregroundColor: Colors.teal.shade900,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.content_cut, size: 16, color: Colors.teal),
                label: Text(
                  isVertical ? '📐 Нарезать стояк на катушки...' : '📐 Нарезать трубу на катушки...',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                onPressed: () => RiserSectioningDialog.show(
                  context,
                  controller: widget.controller,
                  segmentId: widget.segmentId,
                ),
              ),
            );
          },
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
  late TextEditingController _flangeLengthController;
  late TextEditingController _elevationController;
  late TextEditingController _l1Controller;
  late TextEditingController _l2Controller;

  @override
  void initState() {
    super.initState();
    final valve = widget.controller.network.valves[widget.valveId];
    _nameController = TextEditingController(text: valve?.name ?? '');
    _serialController = TextEditingController(text: valve?.serialNumber ?? '');
    _lengthController = TextEditingController(text: valve != null ? valve.lengthMm.round().toString() : '140');
    _flangeLengthController = TextEditingController(
      text: valve != null ? valve.effectiveCounterFlangeLengthMm.round().toString() : '45',
    );
    _elevationController = TextEditingController();
    _l1Controller = TextEditingController();
    _l2Controller = TextEditingController();
    _syncPositionControllers();
  }

  @override
  void didUpdateWidget(covariant _DesktopValveInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    final valve = widget.controller.network.valves[widget.valveId];
    if (oldWidget.valveId != widget.valveId) {
      _nameController.text = valve?.name ?? '';
      _serialController.text = valve?.serialNumber ?? '';
      _lengthController.text = valve != null ? valve.lengthMm.round().toString() : '140';
      _flangeLengthController.text = valve != null ? valve.effectiveCounterFlangeLengthMm.round().toString() : '45';
    }
    _syncPositionControllers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _serialController.dispose();
    _lengthController.dispose();
    _flangeLengthController.dispose();
    _elevationController.dispose();
    _l1Controller.dispose();
    _l2Controller.dispose();
    super.dispose();
  }

  void _syncPositionControllers() {
    final valve = widget.controller.network.valves[widget.valveId];
    if (valve == null) return;
    final posInfo = SegmentPositioningService.getPositionInfo(
      widget.controller.network,
      valve.segmentId,
      valve.ratio,
      elementLengthMm: valve.effectiveTotalLengthMm,
      currentElementId: valve.id,
    );
    _elevationController.text = posInfo.elevationM.toStringAsFixed(3);
    _l1Controller.text = posInfo.lengthToPrevMm.toStringAsFixed(0);
    _l2Controller.text = posInfo.lengthToNextMm.toStringAsFixed(0);
  }

  void _applyName() {
    final valve = widget.controller.network.valves[widget.valveId];
    if (valve == null) return;
    final text = _nameController.text.trim();
    if (text.isNotEmpty && text != valve.name) {
      widget.controller.network.updateValve(valve.id, valve.copyWith(name: text));
      widget.controller.history.recordState(widget.controller.network);
      widget.controller.refresh();
    }
  }

  void _applySerialNumber() {
    final valve = widget.controller.network.valves[widget.valveId];
    if (valve == null) return;
    final text = _serialController.text.trim();
    final newSerial = text.isEmpty ? null : text;
    if (newSerial != valve.serialNumber) {
      widget.controller.network.updateValve(
        valve.id,
        valve.copyWith(
          serialNumber: newSerial,
          clearSerialNumber: text.isEmpty,
        ),
      );
      widget.controller.history.recordState(widget.controller.network);
      widget.controller.refresh();
    }
  }

  void _applyLength() {
    final valve = widget.controller.network.valves[widget.valveId];
    if (valve == null) return;
    final l = double.tryParse(_lengthController.text.replaceAll(' ', ''));
    if (l != null && l > 0 && l != valve.lengthMm) {
      widget.controller.network.updateValveLength(valve.id, l);
      widget.controller.history.recordState(widget.controller.network);
      widget.controller.refresh();
      _syncPositionControllers();
    }
  }

  void _applyFlangeLength() {
    final valve = widget.controller.network.valves[widget.valveId];
    if (valve == null) return;
    final fl = double.tryParse(_flangeLengthController.text.replaceAll(' ', ''));
    if (fl != null && fl >= 0 && fl != (valve.counterFlangeLengthMm ?? valve.effectiveCounterFlangeLengthMm)) {
      widget.controller.network.updateValve(
        valve.id,
        valve.copyWith(counterFlangeLengthMm: fl),
      );
      widget.controller.network.generateElementWeldJoints();
      widget.controller.network.recalculateSpools();
      widget.controller.history.recordState(widget.controller.network);
      widget.controller.refresh();
      _syncPositionControllers();
    }
  }

  void _applyElevation() {
    final val = double.tryParse(_elevationController.text.replaceAll(',', '.').replaceAll(' ', ''));
    if (val != null) {
      widget.controller.updateValvePositionByElevation(widget.valveId, val);
      _syncPositionControllers();
    }
  }

  void _applyL1() {
    final val = double.tryParse(_l1Controller.text.replaceAll(',', '.').replaceAll(' ', ''));
    if (val != null) {
      widget.controller.updateValvePositionByPrevSection(widget.valveId, val);
      _syncPositionControllers();
    }
  }

  void _applyL2() {
    final val = double.tryParse(_l2Controller.text.replaceAll(',', '.').replaceAll(' ', ''));
    if (val != null) {
      widget.controller.updateValvePositionByNextSection(widget.valveId, val);
      _syncPositionControllers();
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
                  widget.controller.network.updateValve(
                    valve.id,
                    valve.copyWith(valveType: newType),
                  );
                  widget.controller.history.recordState(widget.controller.network);
                  widget.controller.refresh();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Семейство / УГО (Кастомное семейство арматуры)
        const Text('Семейство / УГО:', style: TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 3),
        Builder(
          builder: (context) {
            final customValves = widget.controller.customValves;
            final customId = valve.customDefinitionId;
            final customDef = customId != null
                ? (customValves[customId] ?? CustomValveCatalog.instance.getById(customId))
                : null;
            final isCustom = customDef != null;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isCustom ? Colors.indigo.shade50 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isCustom ? Colors.indigo.shade200 : Colors.grey.shade300,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isCustom ? Icons.auto_awesome : Icons.tune,
                    size: 16,
                    color: isCustom ? Colors.indigo : Colors.grey.shade700,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isCustom ? customDef.name : 'Стандартное ГОСТ',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isCustom ? FontWeight.bold : FontWeight.normal,
                        color: isCustom ? Colors.indigo.shade900 : Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isCustom)
                    InkWell(
                      onTap: () {
                        widget.controller.network.updateValve(
                          valve.id,
                          valve.copyWith(clearCustomDefinition: true),
                        );
                        widget.controller.network.generateElementWeldJoints();
                        widget.controller.network.recalculateSpools();
                        widget.controller.history.recordState(widget.controller.network);
                        widget.controller.refresh();
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(Icons.close, size: 14, color: Colors.grey),
                      ),
                    ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () async {
                      final selected = await CustomValveCatalogDialog.show(
                        context,
                        projectValves: widget.controller.customValves,
                      );
                      if (selected != null) {
                        widget.controller.addOrUpdateCustomValve(selected);
                        final willBeFlanged = selected.symbol2d.hasBodyFlanges;
                        widget.controller.network.updateValve(
                          valve.id,
                          valve.copyWith(
                            customDefinitionId: selected.id,
                            isFlanged: willBeFlanged,
                          ),
                        );
                        widget.controller.network.generateElementWeldJoints();
                        widget.controller.network.recalculateSpools();
                        widget.controller.history.recordState(widget.controller.network);
                        widget.controller.refresh();
                      }
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.indigo,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('Каталог', style: TextStyle(fontSize: 10, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            );
          },
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

        // Строительная длина корпуса L
        Row(
          children: [
            const Text('Длина корпуса L:', style: TextStyle(fontSize: 11, color: Colors.grey)),
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

        // Позиционирование и высотная отметка (Z / L1 / L2)
        Builder(
          builder: (context) {
            final posInfo = SegmentPositioningService.getPositionInfo(
              widget.controller.network,
              valve.segmentId,
              valve.ratio,
              elementLengthMm: valve.effectiveTotalLengthMm,
              currentElementId: valve.id,
            );
            return Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'Позиция / Отметка Z:',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${(valve.ratio * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Отметка оси Z
                  Row(
                    children: [
                      const Text('Отметка Z:', style: TextStyle(fontSize: 11, color: Colors.black87)),
                      const SizedBox(width: 4),
                      if (!posInfo.isElevationEditable)
                        Expanded(
                          child: Text(
                            '${posInfo.elevationM.toStringAsFixed(3)} м (горизонт)',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey),
                            textAlign: TextAlign.right,
                          ),
                        )
                      else
                        Expanded(
                          child: SizedBox(
                            height: 26,
                            child: TextField(
                              controller: _elevationController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.right,
                              decoration: const InputDecoration(
                                suffixText: 'м',
                                suffixStyle: TextStyle(fontSize: 9),
                                contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onSubmitted: (_) => _applyElevation(),
                              onTapOutside: (_) => _applyElevation(),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // L1 - отступ до предыдущего элемента
                  Row(
                    children: [
                      Expanded(
                        flex: 6,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '← ${posInfo.prevItemLabel} (L1):',
                                style: const TextStyle(fontSize: 10, color: Colors.black87),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                _l1Controller.text = '0';
                                _applyL1();
                              },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 2),
                                child: Text(
                                  'встык (0)',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.indigo,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        flex: 4,
                        child: SizedBox(
                          height: 26,
                          child: TextField(
                            controller: _l1Controller,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.right,
                            decoration: const InputDecoration(
                              suffixText: 'мм',
                              suffixStyle: TextStyle(fontSize: 9),
                              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onSubmitted: (_) => _applyL1(),
                            onTapOutside: (_) => _applyL1(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // L2 - отступ до следующего элемента
                  Row(
                    children: [
                      Expanded(
                        flex: 6,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '→ ${posInfo.nextItemLabel} (L2):',
                                style: const TextStyle(fontSize: 10, color: Colors.black87),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                _l2Controller.text = '0';
                                _applyL2();
                              },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 2),
                                child: Text(
                                  'встык (0)',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.indigo,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        flex: 4,
                        child: SizedBox(
                          height: 26,
                          child: TextField(
                            controller: _l2Controller,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.right,
                            decoration: const InputDecoration(
                              suffixText: 'мм',
                              suffixStyle: TextStyle(fontSize: 9),
                              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onSubmitted: (_) => _applyL2(),
                            onTapOutside: (_) => _applyL2(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'От начала: ${posInfo.distanceFromStartMm.toStringAsFixed(0)} мм | Катушки: L1=${posInfo.lengthToPrevMm.toStringAsFixed(0)}, L2=${posInfo.lengthToNextMm.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 9, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  // Выноска высотной отметки по ГОСТ 21.101
                  Builder(
                    builder: (context) {
                      final hasElevCallout = widget.controller.valveHasElevationCallout(valve.id);
                      return SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: hasElevCallout ? Colors.indigo : Colors.grey.shade700,
                            side: BorderSide(color: hasElevCallout ? Colors.indigo : Colors.grey.shade300),
                            backgroundColor: hasElevCallout ? Colors.indigo.shade50 : null,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          ),
                          icon: Icon(hasElevCallout ? Icons.check_circle : Icons.add_circle_outline, size: 14),
                          label: Text(
                            hasElevCallout ? '∇ Отметка оси: ВКЛ' : '∇ Добавить отметку оси',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () {
                            widget.controller.toggleValveElevationCallout(valve.id);
                            setState(() {});
                          },
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 6),

        // Рукоятка / маховик (только для арматуры с ручным приводом)
        if (valve.valveType != ValveType.checkValve &&
            valve.valveType != ValveType.strainer &&
            valve.valveType != ValveType.drainValve) ...[
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
                  final nextAngle = (valve.handleAngleDeg + 90.0) % 360.0;
                  widget.controller.network.updateValve(
                    valve.id,
                    valve.copyWith(handleAngleDeg: nextAngle),
                  );
                  widget.controller.history.recordState(widget.controller.network);
                  widget.controller.refresh();
                },
                child: const Text('Поворот +90°', style: TextStyle(fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],

        // Исполнение: Под приварку vs Фланцы
        Builder(
          builder: (context) {
            final isFlanged = valve.effectiveIsFlanged;
            return Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isFlanged ? Colors.indigo.withValues(alpha: 0.05) : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: isFlanged ? Colors.indigo.shade300 : Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              isFlanged ? Icons.all_inclusive : Icons.linear_scale,
                              size: 14,
                              color: isFlanged ? Colors.indigo : Colors.grey.shade700,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                isFlanged ? 'Фланцевая (ГОСТ 33259)' : 'Под приварку / муфтовая',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isFlanged ? Colors.indigo : Colors.black87,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: isFlanged,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: (val) {
                          widget.controller.network.updateValve(
                            valve.id,
                            valve.copyWith(isFlanged: val),
                          );
                          widget.controller.network.generateElementWeldJoints();
                          widget.controller.network.recalculateSpools();
                          widget.controller.history.recordState(widget.controller.network);
                          widget.controller.refresh();
                        },
                      ),
                    ],
                  ),
                  if (isFlanged) ...[
                const SizedBox(height: 6),
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: valve.flangePressurePn,
                  decoration: const InputDecoration(
                    labelText: 'Давление Ру (Pn)',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 10, child: Text('Ру10 (1.0 МПа)', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 16, child: Text('Ру16 (1.6 МПа)', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 25, child: Text('Ру25 (2.5 МПа)', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 40, child: Text('Ру40 (4.0 МПа)', style: TextStyle(fontSize: 11))),
                  ],
                  onChanged: (pn) {
                    if (pn == null) return;
                    widget.controller.network.updateValve(
                      valve.id,
                      valve.copyWith(flangePressurePn: pn),
                    );
                    widget.controller.history.recordState(widget.controller.network);
                    widget.controller.refresh();
                  },
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Ответные фланцы:', style: TextStyle(fontSize: 11)),
                    Switch(
                      value: valve.includeCounterFlanges,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (val) {
                        final updated = valve.copyWith(includeCounterFlanges: val);
                        widget.controller.network.updateValve(
                          valve.id,
                          updated,
                        );
                        _flangeLengthController.text = updated.effectiveCounterFlangeLengthMm.round().toString();
                        widget.controller.network.generateElementWeldJoints();
                        widget.controller.network.recalculateSpools();
                        widget.controller.history.recordState(widget.controller.network);
                        widget.controller.refresh();
                        _syncPositionControllers();
                      },
                    ),
                  ],
                ),
                if (valve.includeCounterFlanges) ...[
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: valve.counterFlangeType,
                    decoration: const InputDecoration(
                      labelText: 'Тип ответных фланцев',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'ГОСТ 33259-2015 тип 11',
                        child: Text('Воротниковые (тип 11)', style: TextStyle(fontSize: 11)),
                      ),
                      DropdownMenuItem(
                        value: 'ГОСТ 33259-2015 тип 01',
                        child: Text('Плоские приварные (тип 01)', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                    onChanged: (type) {
                      if (type == null) return;
                      final updated = valve.copyWith(counterFlangeType: type);
                      widget.controller.network.updateValve(
                        valve.id,
                        updated,
                      );
                      _flangeLengthController.text = updated.effectiveCounterFlangeLengthMm.round().toString();
                      widget.controller.network.generateElementWeldJoints();
                      widget.controller.network.recalculateSpools();
                      widget.controller.history.recordState(widget.controller.network);
                      widget.controller.refresh();
                      _syncPositionControllers();
                    },
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: const ['Сталь 20', '09Г2С', '12Х18Н10Т', '10ХСНД', '15Х5М', '12Х1МФ']
                            .contains(valve.effectiveCounterFlangeMaterial)
                        ? valve.effectiveCounterFlangeMaterial
                        : 'Сталь 20',
                    decoration: const InputDecoration(
                      labelText: 'Сталь фланцев',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Сталь 20', child: Text('Сталь 20', style: TextStyle(fontSize: 11))),
                      DropdownMenuItem(value: '09Г2С', child: Text('09Г2С', style: TextStyle(fontSize: 11))),
                      DropdownMenuItem(value: '12Х18Н10Т', child: Text('12Х18Н10Т (нерж)', style: TextStyle(fontSize: 11))),
                      DropdownMenuItem(value: '10ХСНД', child: Text('10ХСНД', style: TextStyle(fontSize: 11))),
                      DropdownMenuItem(value: '15Х5М', child: Text('15Х5М (жаропроч)', style: TextStyle(fontSize: 11))),
                      DropdownMenuItem(value: '12Х1МФ', child: Text('12Х1МФ', style: TextStyle(fontSize: 11))),
                    ],
                    onChanged: (mat) {
                      if (mat == null) return;
                      widget.controller.network.updateValve(
                        valve.id,
                        valve.copyWith(counterFlangeMaterial: mat),
                      );
                      widget.controller.history.recordState(widget.controller.network);
                      widget.controller.refresh();
                    },
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Длина воротника Lфл:',
                          style: TextStyle(fontSize: 11, color: Colors.black87),
                        ),
                      ),
                      SizedBox(
                        width: 75,
                        height: 26,
                        child: TextField(
                          controller: _flangeLengthController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.right,
                          decoration: const InputDecoration(
                            suffixText: 'мм',
                            suffixStyle: TextStyle(fontSize: 9),
                            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _applyFlangeLength(),
                          onTapOutside: (_) => _applyFlangeLength(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.indigo.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Монтажная длина:',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo),
                            ),
                            Text(
                              '${valve.effectiveTotalLengthMm.round()} мм',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Корпус: ${valve.lengthMm.round()} мм + Фланцы: 2×${valve.effectiveCounterFlangeLengthMm.round()} мм',
                          style: TextStyle(fontSize: 9, color: Colors.indigo.shade700),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    ),
    const SizedBox(height: 6),

        // Направление потока / Реверс (особенно важно для обратного клапана, фильтра, счетчика)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(
                    valve.isReversed ? Icons.west : Icons.east,
                    size: 14,
                    color: valve.valveType == ValveType.checkValve ? Colors.deepOrange : Colors.grey.shade700,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      valve.valveType == ValveType.checkValve
                          ? (valve.isReversed ? 'Обратный: реверс' : 'Обратный: прямой')
                          : 'Инвертировать:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: valve.valveType == ValveType.checkValve ? FontWeight.bold : FontWeight.normal,
                        color: valve.valveType == ValveType.checkValve ? Colors.deepOrange : Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: valve.isReversed,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (val) {
                widget.controller.network.updateValve(
                  valve.id,
                  valve.copyWith(isReversed: val),
                );
                widget.controller.history.recordState(widget.controller.network);
                widget.controller.refresh();
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                ),
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('Копировать (Ctrl+C)', style: TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis),
                onPressed: () {
                  if (widget.controller.copySelection()) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Арматура скопирована в буфер обмена'),
                        duration: Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                ),
                icon: const Icon(Icons.control_point_duplicate, size: 14),
                label: const Text('Дублировать (Ctrl+D)', style: TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis),
                onPressed: () => widget.controller.duplicateSelection(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

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

class _DesktopWeldInspector extends StatefulWidget {
  final PipingInputController controller;
  final String weldId;

  const _DesktopWeldInspector({
    required this.controller,
    required this.weldId,
  });

  @override
  State<_DesktopWeldInspector> createState() => _DesktopWeldInspectorState();
}

class _DesktopWeldInspectorState extends State<_DesktopWeldInspector> {
  late TextEditingController _elevationController;
  late TextEditingController _l1Controller;
  late TextEditingController _l2Controller;

  @override
  void initState() {
    super.initState();
    _elevationController = TextEditingController();
    _l1Controller = TextEditingController();
    _l2Controller = TextEditingController();
    _syncPositionControllers();
  }

  @override
  void didUpdateWidget(covariant _DesktopWeldInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPositionControllers();
  }

  @override
  void dispose() {
    _elevationController.dispose();
    _l1Controller.dispose();
    _l2Controller.dispose();
    super.dispose();
  }

  void _syncPositionControllers() {
    final weld = widget.controller.network.weldJoints[widget.weldId];
    if (weld == null) return;
    final posInfo = SegmentPositioningService.getPositionInfo(
      widget.controller.network,
      weld.segmentId,
      weld.ratio,
      elementLengthMm: 0.0,
      currentElementId: weld.id,
    );
    _elevationController.text = posInfo.elevationM.toStringAsFixed(3);
    _l1Controller.text = posInfo.lengthToPrevMm.toStringAsFixed(0);
    _l2Controller.text = posInfo.lengthToNextMm.toStringAsFixed(0);
  }

  void _applyElevation() {
    final val = double.tryParse(_elevationController.text.replaceAll(',', '.').replaceAll(' ', ''));
    if (val != null) {
      widget.controller.updateWeldPositionByElevation(widget.weldId, val);
      _syncPositionControllers();
    }
  }

  void _applyL1() {
    final val = double.tryParse(_l1Controller.text.replaceAll(',', '.').replaceAll(' ', ''));
    if (val != null) {
      widget.controller.updateWeldPositionByPrevSection(widget.weldId, val);
      _syncPositionControllers();
    }
  }

  void _applyL2() {
    final val = double.tryParse(_l2Controller.text.replaceAll(',', '.').replaceAll(' ', ''));
    if (val != null) {
      widget.controller.updateWeldPositionByNextSection(widget.weldId, val);
      _syncPositionControllers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final weld = widget.controller.network.weldJoints[widget.weldId];
    if (weld == null) {
      return const Text('Сварной стык не найден', style: TextStyle(fontSize: 11, color: Colors.grey));
    }
    final seg = widget.controller.network.segments[weld.segmentId];
    final pipeOuter = seg?.outerDiameterMm ?? (seg != null ? seg.dn.toDouble() : 50.0);
    final posInfo = SegmentPositioningService.getPositionInfo(
      widget.controller.network,
      weld.segmentId,
      weld.ratio,
      elementLengthMm: 0.0,
      currentElementId: weld.id,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Монтажный шов', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
            Tooltip(
              message: 'Нажмите, чтобы скопировать ID:\n${weld.id}',
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: weld.id));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('ID стыка скопирован: ${weld.id}'),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                      width: 320,
                    ),
                  );
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '#${weld.id.length > 8 ? weld.id.substring(weld.id.length - 8) : weld.id}',
                      style: TextStyle(fontSize: 9, fontFamily: 'monospace', color: Colors.grey.shade600),
                    ),
                    const SizedBox(width: 3),
                    Icon(Icons.copy_rounded, size: 9, color: Colors.grey.shade500),
                  ],
                ),
              ),
            ),
          ],
        ),
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
                  widget.controller.network.updateWeldJoint(
                    weld.id,
                    (w) => w.copyWith(weldType: newType),
                  );
                  widget.controller.history.recordState(widget.controller.network);
                  widget.controller.refresh();
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
                  widget.controller.network.updateWeldJoint(
                    weld.id,
                    (w) => w.copyWith(inspectionMethod: newMethod),
                  );
                  widget.controller.history.recordState(widget.controller.network);
                  widget.controller.refresh();
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
                    child: Text('По умолчанию (${widget.controller.network.defaultWeldStyle.label})',
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
                  widget.controller.network.updateWeldJoint(
                    weld.id,
                    (w) => w.copyWith(
                      style: newStyle,
                      clearStyle: newStyle == null,
                    ),
                  );
                  widget.controller.history.recordState(widget.controller.network);
                  widget.controller.refresh();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text('Размер:', style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: () async {
                  final ctrl = TextEditingController(
                    text: weld.tickSizeMm != null && weld.tickSizeMm! > 0
                        ? weld.tickSizeMm!.toStringAsFixed(0)
                        : '',
                  );
                  final res = await showDialog<double?>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Размер засечки стыка'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'По умолчанию (диаметр трубы): ${pipeOuter.toStringAsFixed(0)} мм\n'
                            'Размер по умолчанию для сети: ${widget.controller.network.defaultWeldTickSizeMm != null ? "${widget.controller.network.defaultWeldTickSizeMm!.toStringAsFixed(0)} мм" : "По диаметру"}\n\n'
                            'Оставьте пустым или 0 для автоматического размера по диаметру трубы.',
                            style: const TextStyle(fontSize: 12, color: Colors.black87),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: ctrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Размер (мм)',
                              hintText: 'Авто (по диаметру)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(-1.0),
                          child: const Text('Сброс (Авто)'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Отмена'),
                        ),
                        FilledButton(
                          onPressed: () {
                            final val = double.tryParse(ctrl.text.trim());
                            Navigator.of(ctx).pop(val ?? -1.0);
                          },
                          child: const Text('Применить'),
                        ),
                      ],
                    ),
                  );
                  if (res != null) {
                    widget.controller.network.updateWeldJoint(
                      weld.id,
                      (w) => w.copyWith(
                        tickSizeMm: res > 0 ? res : null,
                        clearTickSize: res <= 0,
                      ),
                    );
                    widget.controller.history.recordState(widget.controller.network);
                    widget.controller.refresh();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        weld.tickSizeMm != null && weld.tickSizeMm! > 0
                            ? '${weld.tickSizeMm!.toStringAsFixed(0)} мм'
                            : widget.controller.network.defaultWeldTickSizeMm != null
                                ? 'Сеть (${widget.controller.network.defaultWeldTickSizeMm!.toStringAsFixed(0)} мм)'
                                : 'Авто (${pipeOuter.toStringAsFixed(0)} мм)',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                      const Icon(Icons.edit, size: 13, color: Colors.grey),
                    ],
                  ),
                ),
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
        const SizedBox(height: 8),

        // Позиционирование и высотная отметка (Z / L1 / L2)
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Позиция / Отметка Z:',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${(weld.ratio * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Отметка оси Z
              Row(
                children: [
                  const Text('Отметка Z:', style: TextStyle(fontSize: 11, color: Colors.black87)),
                  const SizedBox(width: 4),
                  if (!posInfo.isElevationEditable)
                    Expanded(
                      child: Text(
                        '${posInfo.elevationM.toStringAsFixed(3)} м (горизонт)',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey),
                        textAlign: TextAlign.right,
                      ),
                    )
                  else
                    Expanded(
                      child: SizedBox(
                        height: 26,
                        child: TextField(
                          controller: _elevationController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.right,
                          decoration: const InputDecoration(
                            suffixText: 'м',
                            suffixStyle: TextStyle(fontSize: 9),
                            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _applyElevation(),
                          onTapOutside: (_) => _applyElevation(),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              // L1 - катушка до предыдущего стыка/фитинга
              Row(
                children: [
                  Expanded(
                    flex: 6,
                    child: Text(
                      '← ${posInfo.prevItemLabel} (L1):',
                      style: const TextStyle(fontSize: 10, color: Colors.black87),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    flex: 4,
                    child: SizedBox(
                      height: 26,
                      child: TextField(
                        controller: _l1Controller,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.right,
                        decoration: const InputDecoration(
                          suffixText: 'мм',
                          suffixStyle: TextStyle(fontSize: 9),
                          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _applyL1(),
                        onTapOutside: (_) => _applyL1(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // L2 - катушка до следующего стыка/фитинга
              Row(
                children: [
                  Expanded(
                    flex: 6,
                    child: Text(
                      '→ ${posInfo.nextItemLabel} (L2):',
                      style: const TextStyle(fontSize: 10, color: Colors.black87),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    flex: 4,
                    child: SizedBox(
                      height: 26,
                      child: TextField(
                        controller: _l2Controller,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.right,
                        decoration: const InputDecoration(
                          suffixText: 'мм',
                          suffixStyle: TextStyle(fontSize: 9),
                          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _applyL2(),
                        onTapOutside: (_) => _applyL2(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'От начала: ${posInfo.distanceFromStartMm.toStringAsFixed(0)} мм | Секции: L1=${posInfo.lengthToPrevMm.toStringAsFixed(0)}, L2=${posInfo.lengthToNextMm.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 9, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              // Выноска высотной отметки по ГОСТ 21.101
              Builder(
                builder: (context) {
                  final hasElevCallout = widget.controller.weldHasElevationCallout(weld.id);
                  return SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: hasElevCallout ? Colors.indigo : Colors.grey.shade700,
                        side: BorderSide(color: hasElevCallout ? Colors.indigo : Colors.grey.shade300),
                        backgroundColor: hasElevCallout ? Colors.indigo.shade50 : null,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      ),
                      icon: Icon(hasElevCallout ? Icons.check_circle : Icons.add_circle_outline, size: 14),
                      label: Text(
                        hasElevCallout ? '∇ Отметка оси: ВКЛ' : '∇ Добавить отметку оси',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        widget.controller.toggleWeldElevationCallout(weld.id);
                        setState(() {});
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ),

        if (widget.controller.network.isButtJoint(weld.segmentId)) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.link, size: 14, color: Colors.blue.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Стык встык: ${widget.controller.network.getButtJointLabel(weld.segmentId)}',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                  ),
                ),
              ],
            ),
          ),
        ],
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
        // Сопряжение элементов: статус или кнопка стягивания в 1 клик
        if (seg != null && widget.controller.network.isConnectingFittingsSegment(seg.id)) ...[
          const SizedBox(height: 8),
          if (widget.controller.network.isButtJoint(seg.id))
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
                      'Стык ${widget.controller.network.getButtJointLabel(seg.id)} (встык)',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            Builder(
              builder: (context) {
                final targetLen = widget.controller.network.getButtJointTargetLength(seg.id) ?? 0.0;
                final label = widget.controller.network.getButtJointLabel(seg.id);
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
                      '🔗 Стянуть встык [$label] (${targetLen.round()} мм)',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      widget.controller.collapseSpoolToButtJoint(widget.spoolId);
                      final updatedSpool = widget.controller.network.spools[widget.spoolId];
                      if (updatedSpool != null) {
                        _lengthController.text = updatedSpool.cutLengthMm.round().toString();
                      }
                    },
                  ),
                );
              },
            ),
          ],
        ],
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

        // Поворот оборудования вокруг вертикальной оси Z
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Поворот:', style: TextStyle(fontSize: 11, color: Colors.grey)),
            Text(
              '${eq.rotationAngleDeg.round()}°',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
            icon: const Icon(Icons.rotate_right, size: 16),
            label: const Text('Повернуть на 90°', style: TextStyle(fontSize: 12)),
            onPressed: () {
              widget.controller.network.rotateEquipment(eq.id, 90.0);
              widget.controller.refresh();
              setState(() {});
            },
          ),
        ),
        const SizedBox(height: 10),

        if (eq.nozzles.isNotEmpty) ...[
          Text('Штуцеры (${eq.nozzles.length}):', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          ...eq.nozzles.map((noz) {
            final faceStr = noz.face != null ? ' (${noz.face!.name})' : '';
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${noz.name}$faceStr Ду${noz.dn}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Удалить штуцер',
                        onPressed: () {
                          widget.controller.network.removeEquipmentNozzle(eq.id, noz.id);
                          widget.controller.refresh();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      SizedBox(
                        height: 20,
                        width: 20,
                        child: Checkbox(
                          value: noz.includeInMto,
                          onChanged: (val) {
                            if (val != null) {
                              widget.controller.network.setNozzleIncludeInMto(eq.id, noz.id, val);
                              widget.controller.refresh();
                              setState(() {});
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Expanded(
                        child: Text(
                          'Ответный фланец в МТО',
                          style: TextStyle(fontSize: 10, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 6),
        ],

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
    final segIds = widget.controller.selectedSegmentIds;
    final segCount = segIds.length;
    if (segCount == 0) return const SizedBox.shrink();

    final network = widget.controller.network;
    final systems = network.systems.values.toList();

    // Расчет суммарной длины выбранных труб
    double totalLengthMm = 0.0;
    for (final segId in segIds) {
      final seg = network.segments[segId];
      if (seg != null) {
        final start = network.nodes[seg.startNodeId];
        final end = network.nodes[seg.endNodeId];
        if (start != null && end != null) {
          totalLengthMm += start.distanceTo(end);
        }
      }
    }

    final firstSeg = network.segments[segIds.first];
    final commonDn = segIds.every((id) => network.segments[id]?.dn == firstSeg?.dn)
        ? firstSeg?.dn
        : null;
    final commonMat = segIds.every((id) => network.segments[id]?.material == firstSeg?.material)
        ? firstSeg?.material
        : null;
    final commonSysId = segIds.every((id) => network.segments[id]?.systemId == firstSeg?.systemId)
        ? firstSeg?.systemId
        : null;
    final commonSlope = segIds.every((id) => (network.segments[id]?.slope ?? 0.0) == (firstSeg?.slope ?? 0.0))
        ? firstSeg?.slope
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.indigo.shade50,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.indigo.shade100),
          ),
          child: Row(
            children: [
              const Icon(Icons.straighten, size: 14, color: Colors.indigo),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Выбрано: $segCount труб (${(totalLengthMm / 1000).toStringAsFixed(2)} м)',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Массовые параметры труб:',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo),
        ),
        const SizedBox(height: 6),
        // 1. Диаметр Ду
        Row(
          children: [
            const SizedBox(
              width: 60,
              child: Text('Ду:', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: const [15, 20, 25, 32, 40, 50, 65, 80, 100, 125, 150, 200, 250, 300, 350, 400, 500].contains(commonDn)
                      ? commonDn
                      : null,
                  hint: const Text('Сменить Ду...', style: TextStyle(fontSize: 11)),
                  isDense: true,
                  isExpanded: true,
                  items: const [15, 20, 25, 32, 40, 50, 65, 80, 100, 125, 150, 200, 250, 300, 350, 400, 500].map((dn) {
                    return DropdownMenuItem<int>(
                      value: dn,
                      child: Text('Ду $dn', style: const TextStyle(fontSize: 11)),
                    );
                  }).toList(),
                  onChanged: (newDn) {
                    if (newDn != null) {
                      widget.controller.changeSelectedSegmentDn(newDn);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // 2. Марка стали
        Row(
          children: [
            const SizedBox(
              width: 60,
              child: Text('Сталь:', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: const ['Сталь 20', '09Г2С', '12Х18Н10Т', '10ХСНД', '15Х5М', '12Х1МФ'].contains(commonMat)
                      ? commonMat
                      : null,
                  hint: const Text('Сменить сталь...', style: TextStyle(fontSize: 11)),
                  isDense: true,
                  isExpanded: true,
                  items: const ['Сталь 20', '09Г2С', '12Х18Н10Т', '10ХСНД', '15Х5М', '12Х1МФ'].map((m) {
                    return DropdownMenuItem<String>(
                      value: m,
                      child: Text(m, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: (newMat) {
                    if (newMat != null) {
                      widget.controller.changeSelectedSegmentMaterial(newMat);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // 3. Инженерная система
        Row(
          children: [
            const SizedBox(
              width: 60,
              child: Text('Система:', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: systems.any((s) => s.id == commonSysId) ? commonSysId : null,
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
        // 4. Уклон i
        Row(
          children: [
            const SizedBox(
              width: 60,
              child: Text('Уклон i:', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<double>(
                  value: const [0.0, 0.001, 0.002, 0.003, 0.005, 0.008, 0.010, 0.020].contains(commonSlope)
                      ? commonSlope
                      : null,
                  hint: const Text('Задать уклон...', style: TextStyle(fontSize: 11)),
                  isDense: true,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 0.0, child: Text('0.0 (Без уклона)', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 0.001, child: Text('i = 0.001 (1 мм/м)', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 0.002, child: Text('i = 0.002 (2 мм/м)', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 0.003, child: Text('i = 0.003 (3 мм/м)', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 0.005, child: Text('i = 0.005 (5 мм/м)', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 0.008, child: Text('i = 0.008 (8 мм/м)', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 0.010, child: Text('i = 0.010 (10 мм/м)', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 0.020, child: Text('i = 0.020 (20 мм/м)', style: TextStyle(fontSize: 11))),
                  ],
                  onChanged: (newSlope) {
                    if (newSlope != null) {
                      widget.controller.changeSelectedSegmentsSlope(newSlope);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // 5. Массовый сдвиг отметки Z (± м)
        Row(
          children: [
            const SizedBox(
              width: 60,
              child: Text('Сдвиг Z:', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ),
            Expanded(
              child: SizedBox(
                height: 28,
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
              height: 28,
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


