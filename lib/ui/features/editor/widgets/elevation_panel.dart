import 'package:flutter/material.dart';
import '../../../canvas/input_controller.dart';

class ElevationPanel extends StatelessWidget {
  final PipingInputController controller;

  const ElevationPanel({super.key, required this.controller});

  void _showElevationInputDialog(BuildContext context) {
    final textController = TextEditingController(
      text: (controller.currentElevationZ / 1000.0).toStringAsFixed(3),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Задать высотную отметку Z'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Введите уровень в метрах (например, 2.800 или 0.600). '
              'Если выбран узел, будет построен вертикальный стояк.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(
                labelText: 'Отметка (м)',
                border: OutlineInputBorder(),
                prefixText: '∇ ',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('Отмена'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          ElevatedButton(
            child: const Text('Применить'),
            onPressed: () {
              final val = double.tryParse(textController.text.replaceAll(',', '.'));
              if (val != null) {
                controller.addVerticalRiser(val * 1000.0);
              }
              Navigator.of(ctx).pop();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final meters = controller.currentElevationZ / 1000.0;
    final sign = meters >= 0 ? '+' : '';
    final elevText = '∇ $sign${meters.toStringAsFixed(3)} м';

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 170,
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.height, size: 18, color: Colors.indigo),
                const SizedBox(width: 6),
                const Text(
                  'Уровень Z',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: () => _showElevationInputDialog(context),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.indigo.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          elevText,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.indigo),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.edit, size: 14, color: Colors.indigo),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Кнопки быстрых подъемов
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                    child: const Text('+0.5м', style: TextStyle(fontSize: 11)),
                    onPressed: () => controller.addVerticalRiser(controller.currentElevationZ + 500.0),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                    child: const Text('+1.0м', style: TextStyle(fontSize: 11)),
                    onPressed: () => controller.addVerticalRiser(controller.currentElevationZ + 1000.0),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Кнопки быстрых опусков
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                    child: const Text('-0.5м', style: TextStyle(fontSize: 11)),
                    onPressed: () => controller.addVerticalRiser(controller.currentElevationZ - 500.0),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                    child: const Text('-1.0м', style: TextStyle(fontSize: 11)),
                    onPressed: () => controller.addVerticalRiser(controller.currentElevationZ - 1000.0),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
