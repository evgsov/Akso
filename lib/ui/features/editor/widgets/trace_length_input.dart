import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Плавающий виджет для прямого ввода точной длины отрезка трассировки (Direct Distance Entry).
class TraceLengthInput extends StatefulWidget {
  final String initialValue;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<double> onSubmitted;
  final VoidCallback onCancel;

  const TraceLengthInput({
    super.key,
    required this.initialValue,
    this.controller,
    this.focusNode,
    required this.onSubmitted,
    required this.onCancel,
  });

  @override
  State<TraceLengthInput> createState() => _TraceLengthInputState();
}

class _TraceLengthInputState extends State<TraceLengthInput> {
  TextEditingController? _internalController;
  FocusNode? _internalFocusNode;

  TextEditingController get _effectiveController => widget.controller ?? _internalController!;
  FocusNode get _effectiveFocusNode => widget.focusNode ?? _internalFocusNode!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _internalController = TextEditingController(text: widget.initialValue);
      _internalController!.selection = TextSelection.fromPosition(
        TextPosition(offset: widget.initialValue.length),
      );
    } else if (widget.controller!.text.isEmpty && widget.initialValue.isNotEmpty) {
      widget.controller!.text = widget.initialValue;
      widget.controller!.selection = TextSelection.fromPosition(
        TextPosition(offset: widget.initialValue.length),
      );
    }

    if (widget.focusNode == null) {
      _internalFocusNode = FocusNode();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _effectiveFocusNode.requestFocus();
      }
    });
  }

  @override
  void didUpdateWidget(covariant TraceLengthInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue && _effectiveController.text.isEmpty) {
      _effectiveController.text = widget.initialValue;
      _effectiveController.selection = TextSelection.fromPosition(
        TextPosition(offset: widget.initialValue.length),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_effectiveFocusNode.hasFocus) {
        _effectiveFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _internalController?.dispose();
    _internalFocusNode?.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _effectiveController.text.trim().replaceAll(',', '.');
    final val = double.tryParse(text);
    if (val != null && val > 0 && !val.isNaN && !val.isInfinite) {
      widget.onSubmitted(val);
    } else {
      widget.onCancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            widget.onCancel();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            _submit();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade500, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.straighten,
                size: 18,
                color: Colors.amber.shade400,
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 90,
                child: TextField(
                  key: const Key('trace_length_text_field'),
                  controller: _effectiveController,
                  focusNode: _effectiveFocusNode,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*[\.,]?\d*')),
                  ],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    border: InputBorder.none,
                    hintText: 'Длина',
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const Text(
                'мм',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                key: const Key('trace_length_submit_button'),
                onTap: _submit,
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.check, size: 16, color: Colors.greenAccent),
                ),
              ),
              InkWell(
                key: const Key('trace_length_cancel_button'),
                onTap: widget.onCancel,
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 16, color: Colors.white54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
