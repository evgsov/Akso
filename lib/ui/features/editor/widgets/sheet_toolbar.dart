import 'package:flutter/material.dart';
import '../../../../domain/enums/viewport_layout_preset.dart';
import '../../../../domain/models/callout.dart';
import '../../../../domain/models/drawing_legend.dart';
import '../../../../domain/models/drawing_sheet.dart';
import '../../../../domain/services/viewport_transform_service.dart';
import '../../../canvas/input_controller.dart';
import 'drawing_legend_dialog.dart';
import 'drawing_style_dialog.dart';
import 'technical_requirements_dialog.dart';
import 'title_block_editor_dialog.dart';

/// Контекстная панель управления чертежным листом по СПДС / ГОСТ 21.101-2020:
/// фильтрация инженерных систем, масштаб видового экрана, фокус, ТТ, штамп и печать.
class SheetToolbar extends StatelessWidget {
  final PipingInputController controller;
  final VoidCallback? onExportPdf;
  final VoidCallback? onExportDxf;

  const SheetToolbar({
    super.key,
    required this.controller,
    this.onExportPdf,
    this.onExportDxf,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final sheet = controller.activeSheet;
        if (sheet == null) return const SizedBox.shrink();

        final isFocused = controller.isViewportFocused;
        final vp = sheet.viewport;
        final scaleText = ViewportTransformService.formatScaleText(vp.viewScale);

        return Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(
            color: Color(0xFF1E293B), // Dark slate
            border: Border(bottom: BorderSide(color: Color(0xFF334155))),
          ),
          child: Row(
            children: [
              // Левая прокручиваемая секция элементов управления
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // Индикатор активного режима (Лист / Фокус ВЭ)
                      InkWell(
                        key: const Key('sheet_viewport_focus_toggle'),
                        onTap: () => controller.toggleViewportFocus(),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isFocused ? const Color(0xFF1976D2) : const Color(0xFF334155),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isFocused ? Colors.lightBlueAccent : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isFocused ? Icons.crop_free : Icons.layers_outlined,
                                size: 15,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isFocused ? 'Фокус ВЭ (Модель)' : 'Пространство листа',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Выбор масштаба видового экрана
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF334155),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: DropdownButton<double>(
                          key: const Key('viewport_scale_dropdown'),
                          isDense: true,
                          value: ViewportTransformService.standardScales.contains(vp.viewScale) ? vp.viewScale : null,
                          hint: Text(scaleText, style: const TextStyle(color: Colors.cyanAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                          dropdownColor: const Color(0xFF1E293B),
                          underline: const SizedBox.shrink(),
                          items: [
                            for (final scale in ViewportTransformService.standardScales)
                              DropdownMenuItem<double>(
                                value: scale,
                                child: Text(
                                  ViewportTransformService.formatScaleText(scale),
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                ),
                              ),
                          ],
                          onChanged: (newScale) {
                            if (newScale != null) {
                              controller.updateSheet(sheet.copyWith(
                                viewport: vp.copyWith(viewScale: newScale),
                              ));
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 6),

                      // Кнопка автоподбора масштаба (Auto-Fit)
                      IconButton(
                        key: const Key('viewport_autofit_button'),
                        tooltip: 'Вписать трассу в видовой экран (Auto-Fit)',
                        icon: const Icon(Icons.fit_screen_outlined, size: 18, color: Colors.cyanAccent),
                        onPressed: () => controller.autoFitActiveSheetViewport(),
                      ),
                      const SizedBox(width: 4),

                      // Переключатель 3D объемные тела / 2D линии
                      IconButton(
                        key: const Key('sheet_volume_mode_toggle'),
                        tooltip: controller.isVolumeMode ? '3D Модель (Тела)' : '2D Линейная схема',
                        icon: Icon(
                          Icons.view_in_ar,
                          size: 18,
                          color: controller.isVolumeMode ? Colors.amberAccent : Colors.white70,
                        ),
                        onPressed: () => controller.toggleVolumeMode(),
                      ),
                      const SizedBox(width: 4),

                      // Переключатель осевых линий
                      IconButton(
                        key: const Key('sheet_centerline_mode_toggle'),
                        tooltip: 'Осевые линии',
                        icon: Icon(
                          Icons.linear_scale,
                          size: 18,
                          color: controller.isCenterlineMode ? Colors.cyanAccent : Colors.white70,
                        ),
                        onPressed: () => controller.toggleCenterlineMode(),
                      ),
                      const SizedBox(width: 6),

                      Container(width: 1, height: 20, color: const Color(0xFF334155)),
                      const SizedBox(width: 10),

                      // Фильтр систем для данного листа
                      ActionChip(
                        key: const Key('sheet_systems_filter_chip'),
                        avatar: const Icon(Icons.filter_alt_outlined, size: 15, color: Colors.amberAccent),
                        label: Text(
                          vp.visibleSystemIds == null
                              ? 'Все системы'
                              : 'Системы (${vp.visibleSystemIds!.length})',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                        backgroundColor: const Color(0xFF334155),
                        onPressed: () => _showSystemFilterDialog(context, sheet),
                      ),
                      const SizedBox(width: 8),

                      // Фильтр выносок для данного листа
                      ActionChip(
                        key: const Key('sheet_callout_filter_chip'),
                        avatar: const Icon(Icons.label_outlined, size: 15, color: Colors.tealAccent),
                        label: Text(
                          sheet.enabledCalloutTypes == null
                              ? 'Все выноски'
                              : 'Выноски (${sheet.enabledCalloutTypes!.length})',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                        backgroundColor: const Color(0xFF334155),
                        onPressed: () => _showCalloutFilterDialog(context, sheet),
                      ),
                      const SizedBox(width: 8),

                      Container(width: 1, height: 20, color: const Color(0xFF334155)),
                      const SizedBox(width: 8),

                      // Быстрые пресеты компоновки ВЭ (AutoCAD-стиль)
                      PopupMenuButton<ViewportLayoutPreset>(
                        key: const Key('viewport_preset_menu'),
                        tooltip: 'Пресеты формы видового экрана',
                        color: const Color(0xFF1E293B),
                        icon: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.dashboard_customize_outlined, size: 16, color: Colors.cyanAccent),
                            SizedBox(width: 4),
                            Text(
                              'Форма ВЭ',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                        onSelected: (preset) => controller.applyViewportPreset(preset),
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: ViewportLayoutPreset.wideAboveStamp,
                            child: Row(
                              children: [
                                Icon(Icons.table_rows_outlined, size: 18, color: Colors.cyanAccent),
                                SizedBox(width: 8),
                                Text('Над штампом (391×224 мм) - стандарт', style: TextStyle(color: Colors.white, fontSize: 12)),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: ViewportLayoutPreset.fullSheet,
                            child: Row(
                              children: [
                                Icon(Icons.crop_landscape, size: 18, color: Colors.lightBlueAccent),
                                SizedBox(width: 8),
                                Text('Во весь лист (391×283 мм)', style: TextStyle(color: Colors.white, fontSize: 12)),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: ViewportLayoutPreset.leftColumn,
                            child: Row(
                              children: [
                                Icon(Icons.view_sidebar_outlined, size: 18, color: Colors.amberAccent),
                                SizedBox(width: 8),
                                Text('Слева от штампа (202×283 мм)', style: TextStyle(color: Colors.white, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 6),

                      // Индикатор физических размеров ВЭ
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Text(
                          'ВЭ: ${vp.widthMm.round()}×${vp.heightMm.round()} мм',
                          style: const TextStyle(color: Colors.white60, fontSize: 11, fontFamily: 'monospace'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Правая секция: ТТ, Штамп, Печать
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Кнопка Условные обозначения
                  TextButton.icon(
                    key: const Key('sheet_legend_button'),
                    icon: const Icon(Icons.list_alt, size: 16, color: Colors.amberAccent),
                    label: const Text('Обозначения', style: TextStyle(color: Colors.white, fontSize: 12)),
                    onPressed: () {
                      final currentLeg = sheet.legend ??
                          DrawingLegend.createDefault(
                            xMm: sheet.format.widthMm - sheet.format.frameRightMm - 185.0,
                            yMm: sheet.format.heightMm - sheet.format.frameBottomMm - 55.0 - 55.0 - 50.0,
                          );
                      showDialog(
                        context: context,
                        builder: (ctx) => DrawingLegendDialog(
                          legend: currentLeg,
                          onSave: (updated) {
                            controller.updateSheet(sheet.copyWith(legend: updated));
                          },
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 6),

                  // Кнопка Толщины линий ГОСТ
                  IconButton(
                    key: const Key('sheet_style_button'),
                    icon: const Icon(Icons.line_weight, size: 16, color: Colors.cyanAccent),
                    tooltip: 'Толщины линий и шрифты ГОСТ (ГОСТ 2.303 / 2.304)',
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => DrawingStyleDialog(
                          initialConfig: controller.styleConfig,
                          onSave: (newCfg) {
                            controller.updateDrawingStyleConfig(newCfg);
                          },
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 6),

                  // Кнопка Сетка препятствий (Debug)
                  IconButton(
                    key: const Key('sheet_debug_obstacles_button'),
                    icon: Icon(
                      sheet.debugShowObstacles ? Icons.grid_on : Icons.grid_off_outlined,
                      size: 16,
                      color: sheet.debugShowObstacles ? Colors.redAccent : Colors.white60,
                    ),
                    tooltip: sheet.debugShowObstacles
                        ? 'Скрыть сетку препятствий выносок (Debug)'
                        : 'Показать сетку препятствий выносок (Debug)',
                    onPressed: () => controller.toggleDebugObstacles(sheet.id),
                  ),
                  const SizedBox(width: 6),

                  // Кнопка Авто-расстановка выносок листа (ГОСТ) и сброс
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const Key('sheet_auto_layout_callouts_button'),
                        tooltip: 'Авторасстановка выносок листа (ГОСТ)',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.auto_fix_high, size: 16, color: Colors.tealAccent),
                        onPressed: () {
                          final updated = controller.runSheetCalloutAutoLayout(sheet.id, groupMultiLevel: true);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                updated > 0
                                    ? 'Авторасстановка (с этажерками): оптимизировано: $updated'
                                    : 'Все выноски листа уже расположены оптимально',
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                      PopupMenuButton<String>(
                        key: const Key('sheet_auto_layout_callouts_options_button'),
                        tooltip: 'Опции авторасстановки',
                        color: const Color(0xFF1E293B),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 260, maxWidth: 320),
                        icon: const Icon(Icons.arrow_drop_down, size: 18, color: Colors.tealAccent),
                        onSelected: (action) {
                          if (action == 'auto_smart_animated') {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Оптимизация Simulated Annealing запущена...'),
                                duration: Duration(milliseconds: 1200),
                              ),
                            );
                            controller.runAnimatedSheetCalloutOptimization(sheet.id).then((updated) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      updated > 0
                                          ? 'Умная оптимизация завершена! Оптимизировано: $updated'
                                          : 'Все выноски листа уже расположены оптимально',
                                    ),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            });
                          } else if (action == 'auto_grouped') {
                            final updated = controller.runSheetCalloutAutoLayout(sheet.id, groupMultiLevel: true);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  updated > 0
                                      ? 'Авторасстановка (с этажерками): оптимизировано: $updated'
                                      : 'Все выноски листа уже расположены оптимально',
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          } else if (action == 'auto_single') {
                            final updated = controller.runSheetCalloutAutoLayout(sheet.id, groupMultiLevel: false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  updated > 0
                                      ? 'Авторасстановка (построчно): оптимизировано: $updated'
                                      : 'Все выноски листа уже расположены оптимально',
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          } else if (action == 'auto_unpin_all') {
                            final updated = controller.runSheetCalloutAutoLayout(sheet.id, groupMultiLevel: true, onlyUnpinned: false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Снята фиксация и перераспределено: $updated выносок'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          } else if (action == 'auto_merge_now') {
                            final count = controller.autoMergeIdenticalCallouts(sheetId: sheet.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  count > 0
                                      ? 'Объединено групп одинаковых выносок: $count'
                                      : 'Одинаковых элементов рядом для объединения не найдено',
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          } else if (action == 'toggle_merge_identical') {
                            controller.toggleSheetMergeIdenticalCallouts(sheet.id);
                            final isMerged = controller.activeSheet?.mergeIdenticalCallouts ?? true;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  isMerged
                                      ? 'Автообъединение одинаковых выносок включено'
                                      : 'Автообъединение одинаковых выносок выключено',
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          } else if (action == 'unmerge_all') {
                            final count = controller.unmergeAllCallouts(sheetId: sheet.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  count > 0
                                      ? 'Разъединено вилочных выносок: $count'
                                      : 'Объединенных выносок на листе нет',
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          } else if (action == 'reset_sheet') {
                            controller.resetAllSheetCalloutOffsets(sheet.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Позиции выносок на листе сброшены к 3D-модели'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(
                            value: 'auto_smart_animated',
                            child: Row(
                              children: [
                                Icon(Icons.psychology, size: 16, color: Colors.purpleAccent),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text('Умная оптимизация (с анимацией)', style: TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'auto_grouped',
                            child: Row(
                              children: [
                                Icon(Icons.auto_fix_high, size: 16, color: Colors.tealAccent),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text('Авторасстановка (с этажерками)', style: TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'auto_single',
                            child: Row(
                              children: [
                                Icon(Icons.view_headline, size: 16, color: Colors.cyanAccent),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text('Авторасстановка (построчно)', style: TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'auto_unpin_all',
                            child: Row(
                              children: [
                                Icon(Icons.refresh, size: 16, color: Colors.amberAccent),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text('Все выноски (снять фиксацию)', style: TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          ),
                          const PopupMenuDivider(),
                          CheckedPopupMenuItem(
                            value: 'toggle_merge_identical',
                            checked: sheet.mergeIdenticalCallouts,
                            child: const Text(
                              'Объединять одинаковые (ГОСТ)',
                              style: TextStyle(color: Colors.white, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'auto_merge_now',
                            child: Row(
                              children: [
                                Icon(Icons.merge_type, size: 16, color: Colors.tealAccent),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text('Объединить одинаковые сейчас', style: TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'unmerge_all',
                            child: Row(
                              children: [
                                Icon(Icons.call_split, size: 16, color: Colors.blueGrey),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text('Разъединить все вилочные выноски', style: TextStyle(color: Colors.white70, fontSize: 12), overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'reset_sheet',
                            child: Row(
                              children: [
                                Icon(Icons.restore, size: 16, color: Colors.orangeAccent),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text('Сбросить выноски к 3D-модели', style: TextStyle(color: Colors.white70, fontSize: 12), overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),

                  // Кнопка ТТ (Технические требования)
                  TextButton.icon(
                    key: const Key('sheet_tt_button'),
                    icon: const Icon(Icons.notes, size: 16, color: Colors.cyanAccent),
                    label: const Text('ТТ', style: TextStyle(color: Colors.white, fontSize: 12)),
                    onPressed: () => TechnicalRequirementsDialog.show(context, controller: controller, sheet: sheet),
                  ),
                  const SizedBox(width: 6),

                  // Кнопка Основная надпись (Штамп ГОСТ)
                  FilledButton.icon(
                    key: const Key('sheet_title_block_button'),
                    icon: const Icon(Icons.edit_note, size: 16),
                    label: const Text('Штамп ГОСТ', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => TitleBlockEditorDialog.show(context, controller: controller, sheet: sheet),
                  ),
                  const SizedBox(width: 8),

                  // Печать / Экспорт PDF
                  if (onExportPdf != null)
                    FilledButton.icon(
                      key: const Key('sheet_export_pdf_button'),
                      icon: const Icon(Icons.picture_as_pdf, size: 16),
                      label: const Text('Печать PDF', style: TextStyle(fontSize: 12)),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE11D48), // Rose
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: onExportPdf,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSystemFilterDialog(BuildContext context, DrawingSheet sheet) {
    final systems = controller.network.systems.values.toList();
    Set<String> selected = sheet.viewport.visibleSystemIds != null
        ? Set<String>.from(sheet.viewport.visibleSystemIds!)
        : systems.map((s) => s.id).toSet();
    bool ghost = sheet.viewport.ghostInactiveSystems;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Фильтр систем на листе', style: TextStyle(color: Colors.white, fontSize: 16)),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  title: const Text('Показывать все системы', style: TextStyle(color: Colors.white)),
                  value: selected.length == systems.length,
                  activeColor: Colors.cyanAccent,
                  checkColor: Colors.black,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        selected = systems.map((s) => s.id).toSet();
                      } else {
                        selected.clear();
                      }
                    });
                  },
                ),
                const Divider(color: Color(0xFF334155)),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final sys in systems)
                        CheckboxListTile(
                          title: Row(
                            children: [
                              CircleAvatar(backgroundColor: Color(sys.colorValue), radius: 6),
                              const SizedBox(width: 8),
                              Text('${sys.code} (${sys.name})', style: const TextStyle(color: Colors.white, fontSize: 13)),
                            ],
                          ),
                          value: selected.contains(sys.id),
                          activeColor: Colors.cyanAccent,
                          checkColor: Colors.black,
                          onChanged: (checked) {
                            setState(() {
                              if (checked == true) {
                                selected.add(sys.id);
                              } else {
                                selected.remove(sys.id);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ),
                const Divider(color: Color(0xFF334155)),
                SwitchListTile(
                  title: const Text('Отображать соседние системы тонкими серыми линиями', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  value: ghost,
                  activeThumbColor: Colors.cyanAccent,
                  onChanged: (val) => setState(() => ghost = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Отмена', style: TextStyle(color: Colors.white70)),
            ),
            FilledButton(
              onPressed: () {
                final updatedVp = sheet.viewport.copyWith(
                  visibleSystemIds: selected.length == systems.length ? null : selected,
                  ghostInactiveSystems: ghost,
                );
                controller.updateSheet(sheet.copyWith(viewport: updatedVp));
                Navigator.of(ctx).pop();
              },
              child: const Text('Применить'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCalloutFilterDialog(BuildContext context, DrawingSheet sheet) {
    final categories = controller.network.getExistingCalloutCategories();
    final totalElevations = controller.network.totalElevationCalloutsCount;

    // Инициализация выбранных категорий
    // Если sheet.enabledCalloutTypes == null, значит включены все существующие
    Set<CalloutTargetType> selected = sheet.enabledCalloutTypes != null
        ? Set<CalloutTargetType>.from(sheet.enabledCalloutTypes!)
        : categories.map((c) => c.type).toSet();
    bool showElevations = sheet.showElevationCallouts;
    bool groupMultiLevel = sheet.groupMultiLevelCallouts;
    bool mergeIdentical = sheet.mergeIdenticalCallouts;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Row(
            children: [
              const Icon(Icons.label_outlined, color: Colors.tealAccent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Фильтр выносок: ${sheet.name}',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Быстрые пресеты схемы:',
                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ActionChip(
                      label: const Text('Монтажная схема', style: TextStyle(fontSize: 11)),
                      backgroundColor: const Color(0xFF334155),
                      avatar: const Icon(Icons.architecture, size: 14, color: Colors.cyanAccent),
                      onPressed: () {
                        setState(() {
                          selected = {
                            CalloutTargetType.segment,
                            CalloutTargetType.fitting,
                            CalloutTargetType.valve,
                            CalloutTargetType.equipment,
                          };
                          showElevations = true;
                        });
                      },
                    ),
                    ActionChip(
                      label: const Text('Схема сварки', style: TextStyle(fontSize: 11)),
                      backgroundColor: const Color(0xFF334155),
                      avatar: const Icon(Icons.join_inner, size: 14, color: Colors.orangeAccent),
                      onPressed: () {
                        setState(() {
                          selected = {CalloutTargetType.weld};
                          showElevations = false;
                        });
                      },
                    ),
                    ActionChip(
                      label: const Text('Все выноски', style: TextStyle(fontSize: 11)),
                      backgroundColor: const Color(0xFF334155),
                      avatar: const Icon(Icons.select_all, size: 14, color: Colors.greenAccent),
                      onPressed: () {
                        setState(() {
                          selected = categories.map((c) => c.type).toSet();
                          showElevations = true;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(color: Color(0xFF334155)),
                if (categories.isEmpty && totalElevations == 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'В проекте пока нет созданных выносок.\nСоздайте выноски в 3D-модели.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final cat in categories)
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(cat.nameRu, style: const TextStyle(color: Colors.white, fontSize: 13)),
                            secondary: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${cat.count}',
                                style: const TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                            value: selected.contains(cat.type),
                            activeColor: Colors.tealAccent,
                            checkColor: Colors.black,
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  selected.add(cat.type);
                                } else {
                                  selected.remove(cat.type);
                                }
                              });
                            },
                          ),
                        CheckboxListTile(
                           dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Высотные отметки (Z)', style: TextStyle(color: Colors.white, fontSize: 13)),
                          secondary: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '$totalElevations',
                              style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                          value: showElevations,
                          activeColor: Colors.cyanAccent,
                          checkColor: Colors.black,
                          onChanged: (checked) {
                            setState(() {
                              showElevations = checked ?? true;
                            });
                          },
                        ),
                        const Divider(color: Color(0xFF334155)),
                        SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Группировать узлы в этажерки', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: const Text('Объединять кран, фланцы и стыки в одну выноску', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          value: groupMultiLevel,
                          activeThumbColor: Colors.tealAccent,
                          onChanged: (val) {
                            setState(() {
                              groupMultiLevel = val;
                            });
                          },
                        ),
                        SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Объединять одинаковые выноски (Ласточкин хвост)', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: const Text('Группировать одинаковые элементы рядом под одну полочку по ГОСТ 2.316', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          value: mergeIdentical,
                          activeThumbColor: Colors.tealAccent,
                          onChanged: (val) {
                            setState(() {
                              mergeIdentical = val;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Отмена', style: TextStyle(color: Colors.white70)),
            ),
            FilledButton(
              onPressed: () {
                final isAllSelected = selected.length == categories.length;
                controller.setSheetCalloutFilter(
                  sheet.id,
                  types: isAllSelected ? null : selected,
                  showElevations: showElevations,
                  groupMultiLevel: groupMultiLevel,
                  mergeIdentical: mergeIdentical,
                );
                Navigator.of(ctx).pop();
              },
              child: const Text('Применить'),
            ),
          ],
        ),
      ),
    );
  }
}
