import 'package:flutter/material.dart';
import '../../../../domain/models/drawing_sheet.dart';
import '../../../../domain/services/viewport_transform_service.dart';
import '../../../canvas/input_controller.dart';
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
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Правая секция: ТТ, Штамп, Печать
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
}
