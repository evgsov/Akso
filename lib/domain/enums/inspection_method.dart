/// Методы неразрушающего контроля сварных соединений
enum InspectionMethod {
  /// ВИК — Визуальный и измерительный контроль (100%)
  vik,

  /// РК — Радиографический контроль (рентген)
  rk,

  /// УЗК — Ультразвуковой контроль
  uzk,

  /// ПВК / ПВТ — Капиллярный (цветной) контроль
  pvk,

  /// Гидравлические испытания на прочность и герметичность
  hydro,

  /// Без специального дефектоскопического контроля
  none,
}

extension InspectionMethodExt on InspectionMethod {
  String get code {
    switch (this) {
      case InspectionMethod.vik:
        return 'ВИК';
      case InspectionMethod.rk:
        return 'РК';
      case InspectionMethod.uzk:
        return 'УЗК';
      case InspectionMethod.pvk:
        return 'ПВК';
      case InspectionMethod.hydro:
        return 'ГИ';
      case InspectionMethod.none:
        return '—';
    }
  }

  String get shortName => code;

  String get displayName {
    switch (this) {
      case InspectionMethod.vik:
        return 'ВИК 100%';
      case InspectionMethod.rk:
        return 'РК';
      case InspectionMethod.uzk:
        return 'УЗК';
      case InspectionMethod.pvk:
        return 'ПВК';
      case InspectionMethod.hydro:
        return 'Гидроиспытания';
      case InspectionMethod.none:
        return '—';
    }
  }
}
