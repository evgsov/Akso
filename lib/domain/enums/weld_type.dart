/// Типы сварных соединений по ГОСТ 16037-80 / ГОСТ 5264-80
enum WeldType {
  /// С17 по ГОСТ 16037-80 (стыковое труб со скосом кромок)
  c17,

  /// С2 по ГОСТ 16037-80 (стыковое труб без скоса кромок, для малых толщин)
  c2,

  /// У18 по ГОСТ 16037-80 (угловое соединение трубы с фланцем)
  u18,

  /// Заводской шов (выполнен на трубном заводе / в заготовительном цехе)
  factoryWeld,

  /// Монтажный шов (выполнен непосредственно на объекте)
  fieldWeld,

  /// Раструбная диффузионная сварка / пайка (для полипропилена, меди)
  socketWeld,
}

extension WeldTypeExt on WeldType {
  String get gostCode {
    switch (this) {
      case WeldType.c17:
        return 'ГОСТ 16037-С17';
      case WeldType.c2:
        return 'ГОСТ 16037-С2';
      case WeldType.u18:
        return 'ГОСТ 16037-У18';
      case WeldType.factoryWeld:
        return 'Заводской';
      case WeldType.fieldWeld:
        return 'Монтажный';
      case WeldType.socketWeld:
        return 'Раструбный';
    }
  }

  String get shortName {
    switch (this) {
      case WeldType.c17:
        return 'С17';
      case WeldType.c2:
        return 'С2';
      case WeldType.u18:
        return 'У18';
      case WeldType.factoryWeld:
        return 'Зав.';
      case WeldType.fieldWeld:
        return 'Монт.';
      case WeldType.socketWeld:
        return 'Раструб';
    }
  }
}
