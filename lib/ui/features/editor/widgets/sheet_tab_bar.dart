import 'package:flutter/material.dart';
import '../../../../domain/enums/sheet_format_type.dart';
import '../../../../domain/models/drawing_sheet.dart';
import '../../../../domain/models/sheet_format.dart';
import '../../../canvas/input_controller.dart';

/// Нижняя панель вкладок чертежных листов в стиле AutoCAD / СПДС:
/// `[ Пространство модели ] | [ Лист 1 (А3) ] | [ Лист 2 (А4) ] | [ + Новый лист ]`
class SheetTabBar extends StatelessWidget {
  final PipingInputController controller;

  const SheetTabBar({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Container(
          height: 32,
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A), // Slate 900
            border: Border(
              top: BorderSide(color: Color(0xFF334155), width: 1.0),
              bottom: BorderSide(color: Color(0xFF1E293B), width: 1.0),
            ),
          ),
          child: Row(
            children: [
              // Вкладка "Пространство модели"
              _buildModelTab(context),

              // Разделитель
              Container(width: 1, height: 20, color: const Color(0xFF334155)),

              // Список чертежных листов
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: controller.sheets.length,
                  itemBuilder: (context, index) {
                    final sheet = controller.sheets[index];
                    return _buildSheetTab(context, sheet);
                  },
                ),
              ),

              // Кнопка добавления нового листа
              _buildAddSheetButton(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModelTab(BuildContext context) {
    final isActive = controller.isModelSpaceActive;
    return InkWell(
      key: const Key('tab_model_space'),
      onTap: () => controller.selectModelSpace(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF1E293B) : Colors.transparent,
          border: Border(
            top: BorderSide(
              color: isActive ? Colors.cyanAccent : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.grid_view_rounded,
              size: 15,
              color: isActive ? Colors.cyanAccent : Colors.white60,
            ),
            const SizedBox(width: 6),
            Text(
              'Модель',
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSheetTab(BuildContext context, DrawingSheet sheet) {
    final isActive = !controller.isModelSpaceActive && controller.activeSheetId == sheet.id;
    final formatText = '${sheet.format.type.name.toUpperCase()}${sheet.format.orientation == SheetOrientation.portrait ? ' верт.' : ''}';

    return InkWell(
      key: Key('tab_sheet_${sheet.id}'),
      onTap: () => controller.selectSheet(sheet.id),
      onSecondaryTapDown: (details) => _showSheetContextMenu(context, sheet, details.globalPosition),
      onLongPress: () => _showSheetContextMenu(context, sheet, Offset.zero),
      child: Container(
        padding: const EdgeInsets.only(left: 12, right: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF1E293B) : Colors.transparent,
          border: Border(
            top: BorderSide(
              color: isActive ? Colors.amberAccent : Colors.transparent,
              width: 2.5,
            ),
            right: const BorderSide(color: Color(0xFF334155), width: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.description_outlined,
              size: 14,
              color: isActive ? Colors.amberAccent : Colors.white60,
            ),
            const SizedBox(width: 6),
            Text(
              sheet.name,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF334155),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                formatText,
                style: const TextStyle(color: Colors.white60, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 4),
            // Меню листа
            InkWell(
              onTap: () => _showSheetContextMenu(context, sheet, Offset.zero),
              borderRadius: BorderRadius.circular(4),
              child: const Padding(
                padding: EdgeInsets.all(2.0),
                child: Icon(Icons.more_vert, size: 14, color: Colors.white38),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddSheetButton(BuildContext context) {
    return PopupMenuButton<SheetFormatType>(
      key: const Key('add_sheet_button'),
      tooltip: 'Добавить новый чертежный лист (СПДС)',
      icon: const Icon(Icons.add, size: 16, color: Colors.cyanAccent),
      padding: EdgeInsets.zero,
      color: const Color(0xFF1E293B),
      itemBuilder: (ctx) => [
        const PopupMenuItem(
          value: SheetFormatType.a3,
          child: Text('Лист А3 (420 × 297 мм, альбомная)', style: TextStyle(color: Colors.white, fontSize: 13)),
        ),
        const PopupMenuItem(
          value: SheetFormatType.a4,
          child: Text('Лист А4 (210 × 297 мм, книжная)', style: TextStyle(color: Colors.white, fontSize: 13)),
        ),
        const PopupMenuItem(
          value: SheetFormatType.a2,
          child: Text('Лист А2 (594 × 420 мм, альбомная)', style: TextStyle(color: Colors.white, fontSize: 13)),
        ),
        const PopupMenuItem(
          value: SheetFormatType.a1,
          child: Text('Лист А1 (841 × 594 мм, альбомная)', style: TextStyle(color: Colors.white, fontSize: 13)),
        ),
      ],
      onSelected: (format) {
        final orientation = format == SheetFormatType.a4 ? SheetOrientation.portrait : SheetOrientation.landscape;
        controller.addSheet(formatType: format, orientation: orientation);
      },
    );
  }

  void _showSheetContextMenu(BuildContext context, DrawingSheet sheet, Offset tapPos) {
    final RenderBox? overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final position = RelativeRect.fromRect(
      Rect.fromLTWH(tapPos.dx, tapPos.dy, 1, 1),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      color: const Color(0xFF1E293B),
      items: [
        const PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit, size: 16, color: Colors.cyanAccent),
              SizedBox(width: 8),
              Text('Переименовать лист...', style: TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'format',
          child: Row(
            children: [
              Icon(Icons.aspect_ratio, size: 16, color: Colors.cyanAccent),
              SizedBox(width: 8),
              Text('Сменить формат листа...', style: TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
              SizedBox(width: 8),
              Text('Удалить лист', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],
          ),
        ),
      ],
    ).then((choice) {
      if (choice == null || !context.mounted) return;
      if (choice == 'rename') {
        _promptRenameSheet(context, sheet);
      } else if (choice == 'format') {
        _promptChangeFormat(context, sheet);
      } else if (choice == 'delete') {
        controller.removeSheet(sheet.id);
      }
    });
  }

  void _promptRenameSheet(BuildContext context, DrawingSheet sheet) {
    final textController = TextEditingController(text: sheet.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Переименование листа', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: textController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Название листа',
            labelStyle: TextStyle(color: Colors.white70),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent)),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена', style: TextStyle(color: Colors.white70)),
          ),
          FilledButton(
            onPressed: () {
              final newName = textController.text.trim();
              if (newName.isNotEmpty) {
                controller.updateSheet(sheet.copyWith(name: newName));
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  void _promptChangeFormat(BuildContext context, DrawingSheet sheet) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Выбор формата листа', style: TextStyle(color: Colors.white)),
        children: [
          _formatDialogOption(ctx, sheet, SheetFormatType.a4, SheetOrientation.portrait, 'А4 книжная (210 × 297 мм)'),
          _formatDialogOption(ctx, sheet, SheetFormatType.a4, SheetOrientation.landscape, 'А4 альбомная (297 × 210 мм)'),
          _formatDialogOption(ctx, sheet, SheetFormatType.a3, SheetOrientation.landscape, 'А3 альбомная (420 × 297 мм)'),
          _formatDialogOption(ctx, sheet, SheetFormatType.a3, SheetOrientation.portrait, 'А3 книжная (297 × 420 мм)'),
          _formatDialogOption(ctx, sheet, SheetFormatType.a2, SheetOrientation.landscape, 'А2 альбомная (594 × 420 мм)'),
          _formatDialogOption(ctx, sheet, SheetFormatType.a1, SheetOrientation.landscape, 'А1 альбомная (841 × 594 мм)'),
        ],
      ),
    );
  }

  Widget _formatDialogOption(
    BuildContext context,
    DrawingSheet sheet,
    SheetFormatType formatType,
    SheetOrientation orientation,
    String title,
  ) {
    return SimpleDialogOption(
      onPressed: () {
        final newFormat = SheetFormat(type: formatType, orientation: orientation);
        controller.updateSheet(sheet.copyWith(format: newFormat));
        Navigator.of(context).pop();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(title, style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}
