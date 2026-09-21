import 'package:flutter/material.dart';
import '../../../../domain/models/drawing_sheet.dart';
import '../../../canvas/input_controller.dart';

/// Диалог настройки и редактирования блока Технических требований (ТТ) чертежа
class TechnicalRequirementsDialog extends StatefulWidget {
  final PipingInputController controller;
  final DrawingSheet sheet;

  const TechnicalRequirementsDialog({
    super.key,
    required this.controller,
    required this.sheet,
  });

  static Future<void> show(BuildContext context, {
    required PipingInputController controller,
    required DrawingSheet sheet,
  }) async {
    await showDialog(
      context: context,
      builder: (ctx) => TechnicalRequirementsDialog(controller: controller, sheet: sheet),
    );
  }

  @override
  State<TechnicalRequirementsDialog> createState() => _TechnicalRequirementsDialogState();
}

class _TechnicalRequirementsDialogState extends State<TechnicalRequirementsDialog> {
  late TextEditingController _textController;
  late TextEditingController _titleController;
  late TextEditingController _widthController;
  late TextEditingController _heightController;
  late bool _hasBorder;
  double? _xMm;
  double? _yMm;

  static const List<String> _standardTemplates = [
    '1. Сварные соединения трубопроводов выполнить по ГОСТ 16037-80.',
    '2. Контроль качества сварных соединений выполнить методами ВИК 100%, РК (УЗК) в объеме согласно проектной документации и СП 75.13330.',
    '3. Трубопровод испытать на прочность и плотность гидравлическим давлением Рисп = 1.5 Рраб, но не менее 0.2 МПа.',
    '4. Опоры и подвески трубопроводов выполнить по ГОСТ 14911-82 (ОСТ 36-146-88).',
    '5. Антикоррозийную защиту выполнить грунтовкой ГФ-021 по ГОСТ 25129-82 в 2 слоя.',
    '6. Уклоны трубопроводов выдержать не менее 0.002 в сторону спускных устройств.',
  ];

  @override
  void initState() {
    super.initState();
    final tr = widget.sheet.technicalRequirements;
    _textController = TextEditingController(text: tr?.text ?? '');
    _titleController = TextEditingController(text: tr?.title ?? 'Технические требования');
    _widthController = TextEditingController(text: (tr?.widthMm ?? 185.0).toStringAsFixed(0));
    _heightController = TextEditingController(text: (tr?.heightMm ?? 40.0).toStringAsFixed(0));
    _hasBorder = tr?.hasBorder ?? false;
    _xMm = tr?.xMm;
    _yMm = tr?.yMm;
  }

  @override
  void dispose() {
    _textController.dispose();
    _titleController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _appendTemplate(String template) {
    if (_textController.text.trim().isEmpty) {
      _textController.text = template;
    } else {
      _textController.text = '${_textController.text.trimRight()}\n$template';
    }
  }

  void _save() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      widget.controller.updateActiveSheetTechnicalRequirements(null);
    } else {
      final width = double.tryParse(_widthController.text.trim()) ?? 185.0;
      final height = double.tryParse(_heightController.text.trim()) ?? 40.0;
      final title = _titleController.text.trim();
      final tr = (widget.sheet.technicalRequirements ?? const TechnicalRequirements(text: '')).copyWith(
        text: text,
        title: title.isEmpty ? null : title,
        widthMm: width,
        heightMm: height,
        hasBorder: _hasBorder,
        xMm: _xMm,
        yMm: _yMm,
      );
      widget.controller.updateActiveSheetTechnicalRequirements(tr);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: SizedBox(
        width: 700,
        height: 620,
        child: Column(
          children: [
            // Заголовок
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF334155))),
              ),
              child: Row(
                children: [
                  const Icon(Icons.notes, color: Colors.cyanAccent, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Технические требования (ТТ)',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Тело диалога
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Настройки заголовка и границ
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _titleController,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              labelText: 'Заголовок блока',
                              labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: _widthController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              labelText: 'Шир. (мм)',
                              labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: _heightController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              labelText: 'Выс. (мм)',
                              labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilterChip(
                          label: const Text('Рамка', style: TextStyle(fontSize: 12)),
                          selected: _hasBorder,
                          selectedColor: Colors.cyan.shade800,
                          onSelected: (val) => setState(() => _hasBorder = val),
                        ),
                        if (_xMm != null || _yMm != null) ...[
                          const SizedBox(width: 6),
                          IconButton(
                            icon: const Icon(Icons.restore, size: 18, color: Colors.amberAccent),
                            tooltip: 'Сбросить положение (над штампом)',
                            onPressed: () => setState(() {
                              _xMm = null;
                              _yMm = null;
                            }),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Текст примечаний:',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        maxLines: null,
                        expands: true,
                        style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                        decoration: InputDecoration(
                          hintText: 'Введите пункты технических требований...',
                          hintStyle: const TextStyle(color: Colors.white30),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Быстрые пункты из библиотеки:', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (int i = 0; i < _standardTemplates.length; i++)
                          ActionChip(
                            label: Text('Пункт ${i + 1}'),
                            tooltip: _standardTemplates[i],
                            backgroundColor: const Color(0xFF334155),
                            labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
                            onPressed: () => _appendTemplate(_standardTemplates[i]),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Действия
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFF334155))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => _textController.clear(),
                    child: const Text('Очистить', style: TextStyle(color: Colors.redAccent)),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Отмена', style: TextStyle(color: Colors.white70)),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Применить'),
                        style: FilledButton.styleFrom(backgroundColor: Colors.cyan.shade700),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
