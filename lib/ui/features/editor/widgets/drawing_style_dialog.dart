import 'package:flutter/material.dart';
import '../../../../domain/models/drawing_style_config.dart';

/// Диалог выбора и настройки толщин линий и шрифтов по ГОСТ 2.303 / 2.304
class DrawingStyleDialog extends StatefulWidget {
  final DrawingStyleConfig initialConfig;
  final ValueChanged<DrawingStyleConfig> onSave;

  const DrawingStyleDialog({
    super.key,
    required this.initialConfig,
    required this.onSave,
  });

  @override
  State<DrawingStyleDialog> createState() => _DrawingStyleDialogState();
}

class _DrawingStyleDialogState extends State<DrawingStyleDialog> {
  late double _pipeLineWidthMm;
  late double _thinLineWidthMm;
  late double _fittingLineWidthMm;
  late double _frameLineWidthMm;
  late double _stampBorderWidthMm;
  late double _stampGridWidthMm;
  late double _axisLineWidthMm;
  late double _textHeightSmallMm;
  late double _textHeightRegularMm;
  late double _textHeightMediumMm;
  late double _textHeightLargeMm;
  late String _fontFamily;

  /// Стандартный ряд толщин линий по ГОСТ 2.303-68 (в мм)
  static const List<double> gostLineWidths = [0.18, 0.25, 0.35, 0.5, 0.7, 0.8, 1.0, 1.4, 2.0];

  @override
  void initState() {
    super.initState();
    _pipeLineWidthMm = widget.initialConfig.pipeLineWidthMm;
    _thinLineWidthMm = widget.initialConfig.thinLineWidthMm;
    _fittingLineWidthMm = widget.initialConfig.fittingLineWidthMm;
    _frameLineWidthMm = widget.initialConfig.frameLineWidthMm;
    _stampBorderWidthMm = widget.initialConfig.stampBorderWidthMm;
    _stampGridWidthMm = widget.initialConfig.stampGridWidthMm;
    _axisLineWidthMm = widget.initialConfig.axisLineWidthMm;
    _textHeightSmallMm = widget.initialConfig.textHeightSmallMm;
    _textHeightRegularMm = widget.initialConfig.textHeightRegularMm;
    _textHeightMediumMm = widget.initialConfig.textHeightMediumMm;
    _textHeightLargeMm = widget.initialConfig.textHeightLargeMm;
    _fontFamily = widget.initialConfig.fontFamily;
  }

  void _applyPreset(String preset) {
    setState(() {
      switch (preset) {
        case 'standard':
          _pipeLineWidthMm = 0.8;
          _thinLineWidthMm = 0.25;
          _fittingLineWidthMm = 0.5;
          _frameLineWidthMm = 0.8;
          _stampBorderWidthMm = 0.8;
          _stampGridWidthMm = 0.35;
          _axisLineWidthMm = 0.25;
          break;
        case 'thin':
          _pipeLineWidthMm = 0.5;
          _thinLineWidthMm = 0.18;
          _fittingLineWidthMm = 0.35;
          _frameLineWidthMm = 0.7;
          _stampBorderWidthMm = 0.7;
          _stampGridWidthMm = 0.25;
          _axisLineWidthMm = 0.18;
          break;
        case 'bold':
          _pipeLineWidthMm = 1.0;
          _thinLineWidthMm = 0.35;
          _fittingLineWidthMm = 0.7;
          _frameLineWidthMm = 1.0;
          _stampBorderWidthMm = 1.0;
          _stampGridWidthMm = 0.35;
          _axisLineWidthMm = 0.35;
          break;
      }
    });
  }

  DrawingStyleConfig _buildConfig() {
    return DrawingStyleConfig(
      pipeLineWidthMm: _pipeLineWidthMm,
      thinLineWidthMm: _thinLineWidthMm,
      fittingLineWidthMm: _fittingLineWidthMm,
      frameLineWidthMm: _frameLineWidthMm,
      stampBorderWidthMm: _stampBorderWidthMm,
      stampGridWidthMm: _stampGridWidthMm,
      axisLineWidthMm: _axisLineWidthMm,
      textHeightSmallMm: _textHeightSmallMm,
      textHeightRegularMm: _textHeightRegularMm,
      textHeightMediumMm: _textHeightMediumMm,
      textHeightLargeMm: _textHeightLargeMm,
      fontFamily: _fontFamily,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.line_weight, color: Color(0xFF1976D2)),
          SizedBox(width: 8),
          Text('Толщины линий и шрифты ГОСТ (ГОСТ 2.303 / 2.304)', style: TextStyle(fontSize: 18)),
        ],
      ),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Быстрые пресеты стандартов оформления:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('ГОСТ Стандарт (0.8 / 0.25 мм)'),
                    onPressed: () => _applyPreset('standard'),
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.border_style, size: 16),
                    label: const Text('Тонкий (0.5 / 0.18 мм)'),
                    onPressed: () => _applyPreset('thin'),
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.line_weight, size: 16),
                    label: const Text('Презентация (1.0 / 0.35 мм)'),
                    onPressed: () => _applyPreset('bold'),
                  ),
                ],
              ),
              const Divider(height: 24),
              const Text('Толщины линий на бумаге (мм):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              _buildWidthDropdown(
                label: 'Основные линии (трубы, магистрали s):',
                value: _pipeLineWidthMm,
                onChanged: (v) => setState(() => _pipeLineWidthMm = v),
              ),
              _buildWidthDropdown(
                label: 'Тонкие линии (выноски, размеры, s/3):',
                value: _thinLineWidthMm,
                onChanged: (v) => setState(() => _thinLineWidthMm = v),
              ),
              _buildWidthDropdown(
                label: 'Контуры арматуры и фитингов (s/2):',
                value: _fittingLineWidthMm,
                onChanged: (v) => setState(() => _fittingLineWidthMm = v),
              ),
              _buildWidthDropdown(
                label: 'Внешняя рамка листа (ГОСТ 20-5-5-5):',
                value: _frameLineWidthMm,
                onChanged: (v) => setState(() => _frameLineWidthMm = v),
              ),
              _buildWidthDropdown(
                label: 'Внешняя рамка штампа (185х55 мм):',
                value: _stampBorderWidthMm,
                onChanged: (v) => setState(() => _stampBorderWidthMm = v),
              ),
              _buildWidthDropdown(
                label: 'Внутренняя сетка штампа и граф:',
                value: _stampGridWidthMm,
                onChanged: (v) => setState(() => _stampGridWidthMm = v),
              ),
              _buildWidthDropdown(
                label: 'Осевые линии трубопроводов и осей:',
                value: _axisLineWidthMm,
                onChanged: (v) => setState(() => _axisLineWidthMm = v),
              ),
              const Divider(height: 24),
              const Text('Высоты аннотативных шрифтов (мм бумаги):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              _buildHeightRow('Мелкий шрифт (штамп, таблицы, 2.5 мм):', _textHeightSmallMm, [1.8, 2.0, 2.2, 2.5, 3.0], (v) {
                setState(() => _textHeightSmallMm = v);
              }),
              _buildHeightRow('Основной шрифт (выноски, размеры, ТТ, 3.5 мм):', _textHeightRegularMm, [2.5, 3.0, 3.5, 4.0], (v) {
                setState(() => _textHeightRegularMm = v);
              }),
              _buildHeightRow('Средний шрифт (шифр, марки осей, 5.0 мм):', _textHeightMediumMm, [4.0, 5.0, 6.0], (v) {
                setState(() => _textHeightMediumMm = v);
              }),
              _buildHeightRow('Крупный шрифт (заголовок схемы, 7.0 мм):', _textHeightLargeMm, [5.0, 7.0, 10.0], (v) {
                setState(() => _textHeightLargeMm = v);
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            widget.onSave(_buildConfig());
            Navigator.of(context).pop();
          },
          child: const Text('Применить'),
        ),
      ],
    );
  }

  Widget _buildWidthDropdown({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    // Подбираем ближайшее значение из gostLineWidths, если не совпадает
    final safeValue = gostLineWidths.contains(value)
        ? value
        : gostLineWidths.reduce((a, b) => (a - value).abs() < (b - value).abs() ? a : b);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          DropdownButton<double>(
            value: safeValue,
            isDense: true,
            items: gostLineWidths.map((w) {
              return DropdownMenuItem<double>(
                value: w,
                child: Text('$w мм'),
              );
            }).toList(),
            onChanged: (newVal) {
              if (newVal != null) onChanged(newVal);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeightRow(
    String label,
    double value,
    List<double> options,
    ValueChanged<double> onChanged,
  ) {
    final safeValue = options.contains(value)
        ? value
        : options.reduce((a, b) => (a - value).abs() < (b - value).abs() ? a : b);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          DropdownButton<double>(
            value: safeValue,
            isDense: true,
            items: options.map((h) {
              return DropdownMenuItem<double>(
                value: h,
                child: Text('$h мм'),
              );
            }).toList(),
            onChanged: (newVal) {
              if (newVal != null) onChanged(newVal);
            },
          ),
        ],
      ),
    );
  }
}
