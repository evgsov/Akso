/// Типы трубопроводной арматуры и приборов КИПиА
enum ValveType {
  /// Задвижка клиновая (фланцевая с выдвижным/невыдвижным шпинделем и маховиком)
  gateValve,

  /// Затвор дисковый поворотный межфланцевый («баттерфляй»)
  butterflyValve,

  /// Кран шаровой (муфтовый / фланцевый / приварной)
  ballValve,

  /// Клапан обратный (подъемный / поворотный / межфланцевый)
  checkValve,

  /// Фильтр осадочный сетчатый (грязевик Y-образный)
  strainer,

  /// Счетчик расхода воды (водомерный узел)
  waterMeter,

  /// Балансировочный / регулирующий клапан
  balancingValve,

  /// Манометр технический (с трехходовым краном)
  pressureGauge,

  /// Термометр технический (в защитной гильзе/бобышке)
  thermometer,

  /// Автоматический воздухоотводчик / кран Маевского
  airVent,

  /// Спускной / дренажный кран
  drainValve,
}

extension ValveTypeExt on ValveType {
  String get displayName {
    switch (this) {
      case ValveType.gateValve:
        return 'Задвижка клиновая';
      case ValveType.butterflyValve:
        return 'Затвор дисковый «баттерфляй»';
      case ValveType.ballValve:
        return 'Кран шаровой';
      case ValveType.checkValve:
        return 'Клапан обратный';
      case ValveType.strainer:
        return 'Фильтр сетчатый (грязевик)';
      case ValveType.waterMeter:
        return 'Счетчик воды';
      case ValveType.balancingValve:
        return 'Клапан балансировочный';
      case ValveType.pressureGauge:
        return 'Манометр';
      case ValveType.thermometer:
        return 'Термометр';
      case ValveType.airVent:
        return 'Воздухоотводчик';
      case ValveType.drainValve:
        return 'Спускник дренажный';
    }
  }

  /// Стандартная монтажная длина корпуса (мм) по умолчанию для расчета вычета катушки
  double defaultLengthMm(int dn) {
    switch (this) {
      case ValveType.gateValve:
        return dn <= 50 ? 150.0 : (dn * 1.5 + 50.0);
      case ValveType.butterflyValve:
        return dn <= 50 ? 43.0 : (dn * 0.4 + 25.0);
      case ValveType.ballValve:
        return dn <= 25 ? 75.0 : (dn * 1.2 + 40.0);
      case ValveType.checkValve:
        return dn <= 50 ? 60.0 : (dn * 1.0 + 30.0);
      case ValveType.strainer:
        return dn <= 50 ? 120.0 : (dn * 1.6 + 40.0);
      case ValveType.waterMeter:
        return 130.0;
      case ValveType.balancingValve:
        return dn <= 50 ? 140.0 : (dn * 1.5 + 50.0);
      case ValveType.pressureGauge:
      case ValveType.thermometer:
      case ValveType.airVent:
      case ValveType.drainValve:
        return 0.0; // Врезка через бобышку/штуцер, не разрывает трубу
    }
  }

  /// Является ли элемент проходным (разрывающим строительную длину катушки)
  bool get isInline {
    switch (this) {
      case ValveType.pressureGauge:
      case ValveType.thermometer:
      case ValveType.airVent:
        return false;
      default:
        return true;
    }
  }
}
