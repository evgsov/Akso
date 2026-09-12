import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../canvas/input_controller.dart';
import '../../canvas/piping_canvas.dart';
import 'widgets/desktop_cad_layout.dart';
import 'widgets/tablet_touch_layout.dart';
import 'widgets/trace_length_input.dart';

class EditorScreen extends StatefulWidget {
  final PipingInputController controller;

  const EditorScreen({super.key, required this.controller});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final FocusNode _focusNode = FocusNode();
  Offset? _lastFocalPoint;
  double _baseScale = 1.0;
  bool _isMiddleClick = false;
  DateTime? _lastMiddleClickTime;
  bool _isRightClick = false;
  bool _isRightDrag = false;
  Offset? _rightDownPos;
  bool _showLengthInput = false;
  String? _initialTraceInput;
  Offset? _lengthInputSpawnPos;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  String? _getDigitFromKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) return '0';
    if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) return '1';
    if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) return '2';
    if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) return '3';
    if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) return '4';
    if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) return '5';
    if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) return '6';
    if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) return '7';
    if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) return '8';
    if (key == LogicalKeyboardKey.digit9 || key == LogicalKeyboardKey.numpad9) return '9';
    return null;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isCtrlOrCmd = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_showLengthInput) {
        setState(() {
          _showLengthInput = false;
          _initialTraceInput = null;
          _lengthInputSpawnPos = null;
        });
        return KeyEventResult.handled;
      }
      widget.controller.cancelCurrentOperation();
      return KeyEventResult.handled;
    }

    final isTracing = (widget.controller.currentTool == CanvasTool.trace && widget.controller.traceStartNode != null) ||
        (widget.controller.currentTool == CanvasTool.drawAxis && widget.controller.axisStartNode != null);

    if (isTracing && !isCtrlOrCmd && !HardwareKeyboard.instance.isAltPressed) {
      final digit = _getDigitFromKey(event.logicalKey);
      if (digit != null) {
        setState(() {
          _initialTraceInput = digit;
          _showLengthInput = true;
          _lengthInputSpawnPos = widget.controller.currentCursorScreenPos;
        });
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.home) {
      widget.controller.zoomToFit();
      return KeyEventResult.handled;
    }

    if (isCtrlOrCmd && (event.logicalKey == LogicalKeyboardKey.digit0 || event.logicalKey == LogicalKeyboardKey.numpad0)) {
      widget.controller.zoom100();
      return KeyEventResult.handled;
    }

    if (isCtrlOrCmd && (event.logicalKey == LogicalKeyboardKey.equal || event.logicalKey == LogicalKeyboardKey.numpadAdd)) {
      widget.controller.zoomIn();
      return KeyEventResult.handled;
    }

    if (isCtrlOrCmd && (event.logicalKey == LogicalKeyboardKey.minus || event.logicalKey == LogicalKeyboardKey.numpadSubtract)) {
      widget.controller.zoomOut();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.delete || event.logicalKey == LogicalKeyboardKey.backspace) {
      widget.controller.deleteSelected();
      return KeyEventResult.handled;
    }

    if (isCtrlOrCmd && event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (isShift) {
        if (widget.controller.canRedo) {
          widget.controller.redo();
        }
      } else {
        if (widget.controller.canUndo) {
          widget.controller.undo();
        }
      }
      return KeyEventResult.handled;
    }

    if (isCtrlOrCmd && event.logicalKey == LogicalKeyboardKey.keyY) {
      if (widget.controller.canRedo) {
        widget.controller.redo();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final mode = controller.layoutMode;
        final isDesktop = mode == UiLayoutMode.desktopCad ||
            (mode == UiLayoutMode.auto &&
                defaultTargetPlatform != TargetPlatform.android &&
                defaultTargetPlatform != TargetPlatform.iOS &&
                MediaQuery.of(context).size.width >= 900);

        final canvas = _buildCanvas(context, controller);

        Widget content;
        if (isDesktop) {
          content = Scaffold(
            backgroundColor: const Color(0xFFF1F5F9),
            body: SafeArea(
              child: DesktopCadLayout(
                controller: controller,
                canvasWidget: canvas,
              ),
            ),
          );
        } else {
          content = TabletTouchLayout(
            controller: controller,
            canvasWidget: canvas,
          );
        }

        return Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: content,
        );
      },
    );
  }

  Widget _buildCanvas(BuildContext context, PipingInputController controller) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Синхронизируем размер области рисования с контроллером для корректного Fit to Screen
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (controller.lastViewportSize != constraints.biggest) {
            controller.lastViewportSize = constraints.biggest;
          }
        });

        final isTracing = (controller.currentTool == CanvasTool.trace && controller.traceStartNode != null) ||
            (controller.currentTool == CanvasTool.drawAxis && controller.axisStartNode != null);

        final showInput = _showLengthInput && isTracing;

        return SizedBox.expand(
          child: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) {
                    if (_showLengthInput) {
                      setState(() {
                        _showLengthInput = false;
                        _initialTraceInput = null;
                        _lengthInputSpawnPos = null;
                      });
                    }
                    _focusNode.requestFocus();
                    if (event.buttons & kMiddleMouseButton != 0) {
                      _isMiddleClick = true;
                final now = DateTime.now();
                // Двойной клик колесом мыши (СКМ): классический жест Zoom to Fit
                if (_lastMiddleClickTime != null && now.difference(_lastMiddleClickTime!).inMilliseconds < 350) {
                  controller.zoomToFit();
                }
                _lastMiddleClickTime = now;
              } else if (event.buttons & kSecondaryMouseButton != 0) {
                _isRightClick = true;
                _isRightDrag = false;
                _rightDownPos = event.localPosition;
              }
            },
            onPointerMove: (event) {
              if (event.buttons & kMiddleMouseButton != 0) {
                controller.pan(event.delta);
                return;
              }
              if (event.buttons & kSecondaryMouseButton != 0) {
                if (_rightDownPos != null && (event.localPosition - _rightDownPos!).distance > 4.0) {
                  _isRightDrag = true;
                }
                controller.orbit(event.delta);
                return;
              }
            },
            onPointerUp: (event) {
              if (_isRightClick) {
                if (!_isRightDrag) {
                  // Короткий клик ПКМ: отмена текущей операции / сброс трассировки
                  controller.cancelCurrentOperation();
                }
                _isRightClick = false;
                _isRightDrag = false;
                _rightDownPos = null;
              }
              if (_isMiddleClick) {
                _isMiddleClick = false;
              }
            },
            onPointerHover: (event) {
              controller.handlePointerMove(event.localPosition);
            },
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                final dy = event.scrollDelta.dy;
                // Плавное адаптивное масштабирование:
                // Стандартный щелчок мыши (~100-120) дает ~1.15x / 0.87x.
                // Небольшие движения тачпада дают пропорционально мягкий отклик.
                final factor = math.pow(0.87, (dy / 100.0).clamp(-2.0, 2.0)).toDouble();
                controller.zoom(factor, event.localPosition);
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (details) {
                _lastFocalPoint = details.localFocalPoint;
                _baseScale = 1.0;
              },
              onScaleUpdate: (details) {
                if (_isMiddleClick || _isRightClick) return;

                if (details.pointerCount > 1) {
                  // Мультитач на планшете (зум и панорамирование двумя пальцами)
                  final scaleDelta = details.scale / _baseScale;
                  _baseScale = details.scale;

                  if ((scaleDelta - 1.0).abs() > 0.001) {
                    controller.zoom(scaleDelta, details.localFocalPoint);
                  }

                  if (_lastFocalPoint != null) {
                    final delta = details.localFocalPoint - _lastFocalPoint!;
                    controller.pan(delta);
                  }
                  _lastFocalPoint = details.localFocalPoint;
                } else if (details.pointerCount == 1) {
                  // Одиночный указатель (ЛКМ / стилус / палец)
                  final delta = _lastFocalPoint != null
                      ? details.localFocalPoint - _lastFocalPoint!
                      : Offset.zero;
                  _lastFocalPoint = details.localFocalPoint;
                  controller.handlePointerMove(details.localFocalPoint, delta: delta);
                }
              },
              onScaleEnd: (details) {
                _lastFocalPoint = null;
                _baseScale = 1.0;
                if (!_isMiddleClick && !_isRightClick) {
                  controller.handlePointerUp();
                }
              },
              onTapDown: (details) {
                if (!_isMiddleClick && !_isRightClick) {
                  controller.handlePointerDown(details.localPosition);
                }
              },
              onDoubleTap: () {
                // Двойное касание по холсту: вписать всё в экран
                controller.zoomToFit();
              },
              onSecondaryTap: () {
                controller.cancelCurrentOperation();
              },
              child: CustomPaint(
                size: Size.infinite,
                painter: PipingCanvasPainter(
                  network: controller.network,
                  projector: controller.projector,
                  selectedNodeId: controller.selectedNodeId,
                  selectedSegmentId: controller.selectedSegmentId,
                  activeSystemId: controller.activeSystemId,
                  activeTraceStart: controller.traceStartNode,
                  activeTraceEnd: controller.currentCursorScreenPos,
                  activeAxisStart: controller.axisStartNode,
                  snapResult: controller.currentSnapResult,
                  currentElevationZ: controller.currentElevationZ,
                  showGrid: controller.showGrid,
                ),
              ),
            ),
          ),
              ),
              if (showInput) _buildLengthInputOverlay(context, controller, constraints),
            ],
          ),
        );
      },
    );
  }


  Widget _buildLengthInputOverlay(
    BuildContext context,
    PipingInputController controller,
    BoxConstraints constraints,
  ) {
    const inputWidth = 210.0;
    const inputHeight = 44.0;

    final targetPos = _lengthInputSpawnPos ?? controller.currentCursorScreenPos;
    if (targetPos != null && constraints.maxWidth > 0 && constraints.maxHeight > 0) {
      double left = targetPos.dx + 20.0;
      double top = targetPos.dy + 20.0;

      if (left + inputWidth > constraints.maxWidth - 12.0) {
        left = math.max(12.0, targetPos.dx - inputWidth - 12.0);
      }
      if (top + inputHeight > constraints.maxHeight - 12.0) {
        top = math.max(12.0, targetPos.dy - inputHeight - 12.0);
      }
      left = left.clamp(12.0, math.max(12.0, constraints.maxWidth - inputWidth - 12.0));
      top = top.clamp(12.0, math.max(12.0, constraints.maxHeight - inputHeight - 12.0));

      return Positioned(
        left: left,
        top: top,
        child: TraceLengthInput(
          initialValue: _initialTraceInput ?? '',
          onSubmitted: (length) {
            controller.commitTraceWithLength(length);
            setState(() {
              _showLengthInput = false;
              _initialTraceInput = null;
              _lengthInputSpawnPos = null;
            });
            _focusNode.requestFocus();
          },
          onCancel: () {
            setState(() {
              _showLengthInput = false;
              _initialTraceInput = null;
              _lengthInputSpawnPos = null;
            });
            _focusNode.requestFocus();
          },
        ),
      );
    } else {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 24.0),
          child: TraceLengthInput(
            initialValue: _initialTraceInput ?? '',
            onSubmitted: (length) {
              controller.commitTraceWithLength(length);
              setState(() {
                _showLengthInput = false;
                _initialTraceInput = null;
                _lengthInputSpawnPos = null;
              });
              _focusNode.requestFocus();
            },
            onCancel: () {
              setState(() {
                _showLengthInput = false;
                _initialTraceInput = null;
                _lengthInputSpawnPos = null;
              });
              _focusNode.requestFocus();
            },
          ),
        ),
      );
    }
  }
}

