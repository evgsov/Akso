import 'dart:convert';
import 'piping_network.dart';

/// Менеджер состояний топологической сети (Undo / Redo)
class NetworkHistoryManager {
  final int maxSnapshots;
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];

  NetworkHistoryManager({this.maxSnapshots = 50});

  bool get canUndo => _undoStack.length > 1;
  bool get canRedo => _redoStack.isNotEmpty;

  /// Зафиксировать текущее состояние сети
  void recordState(PipingNetwork network) {
    final snapshot = jsonEncode(network.toJson());
    if (_undoStack.isNotEmpty && _undoStack.last == snapshot) {
      return;
    }
    _undoStack.add(snapshot);
    if (_undoStack.length > maxSnapshots) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  /// Отменить последнее действие (Undo)
  bool undo(PipingNetwork network) {
    if (!canUndo) return false;
    final currentState = _undoStack.removeLast();
    _redoStack.add(currentState);
    final previousState = _undoStack.last;
    final Map<String, dynamic> json = jsonDecode(previousState) as Map<String, dynamic>;
    network.loadFromJson(json);
    network.recalculateSpools();
    return true;
  }

  /// Повторить отмененное действие (Redo)
  bool redo(PipingNetwork network) {
    if (!canRedo) return false;
    final stateToRestore = _redoStack.removeLast();
    _undoStack.add(stateToRestore);
    final Map<String, dynamic> json = jsonDecode(stateToRestore) as Map<String, dynamic>;
    network.loadFromJson(json);
    network.recalculateSpools();
    return true;
  }

  /// Очистить стек истории
  void clear() {
    _undoStack.clear();
    _redoStack.clear();
  }
}
