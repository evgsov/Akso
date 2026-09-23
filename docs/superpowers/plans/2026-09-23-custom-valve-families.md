# План выполнения: Конструктор и каталог пользовательской арматуры (Custom Valve Families)

> **Цель:** Реализация расширяемой системы пользовательских семейств арматуры в Akso с настройкой 2D УГО (штриховка под 45°, сплошная заливка, разделитель-зигзаг для антивибрационных вставок, маркеры «Э», «АВ»), честной 3D-геометрией (электроприводы, сильфоны), каталогом и диалогом-конструктором с живым предпросмотром.

---

### Task 1: Доменная модель `CustomValveDefinition` и расширение `Valve`
- [ ] Написать тест `test/custom_valve_definition_test.dart` (стили крыльев, разделители, приводы, сериализация round-trip, интеграция с `Valve`).
- [ ] Создать `lib/domain/models/custom_valve_definition.dart`.
- [ ] Добавить в `lib/domain/models/valve.dart` поле `customDefinitionId` и методы вычисления длины/имени.
- [ ] Добавить в `lib/domain/models/project_model.dart` словарь `customValves`.
- [ ] Убедиться в прохождении тестов, `flutter analyze`, закоммитить Task 1.

---

### Task 2: Сервис каталога семейств `CustomValveCatalog`
- [ ] Написать тест `test/custom_valve_catalog_test.dart` (встроенные пресеты: антивибрационный клапан, электропривод, обратный с заливкой, регулятор давления; CRUD операции; экспорт/импорт JSON).
- [ ] Создать `lib/domain/services/custom_valve_catalog.dart`.
- [ ] Убедиться в прохождении тестов, `flutter analyze`, закоммитить Task 2.

---

### Task 3: Графический движок 2D УГО (`ValveSymbolPainter` и `ValvePainter`)
- [ ] Написать тест `test/custom_valve_rendering_test.dart` (штриховка под 45°, сплошная заливка `solid`, разделитель `zigzag`, шток `boxWithText` с текстом «Э»/«АВ»).
- [ ] Обновить `lib/ui/canvas/valve_symbol_painter.dart` для поддержки `ValveSymbolConfig`.
- [ ] Обновить `lib/ui/canvas/painters/valve_painter.dart` для разрешения кастомных определений.
- [ ] Убедиться в прохождении тестов, `flutter analyze`, закоммитить Task 3.

---

### Task 4: 3D Wireframe и твердотельные полигоны (`Element3dGeometry` и `Solid3dEngine`)
- [ ] Написать тест `test/custom_valve_3d_geometry_test.dart` (генерация каркаса и полигонов для `bellows`, `actuatorBox`, `diaphragm`).
- [ ] Обновить `lib/domain/services/element_3d_geometry.dart`.
- [ ] Обновить `lib/ui/canvas/painters/solid_3d_engine.dart`.
- [ ] Убедиться в прохождении тестов, `flutter analyze`, закоммитить Task 4.

---

### Task 5: UI Конструктора и Каталога (`CustomValveEditorDialog` и интеграция)
- [ ] Написать тест `test/custom_valve_editor_dialog_test.dart` (виджет конструктора, живой предпросмотр 2D и 3D, сохранение).
- [ ] Создать `lib/ui/features/editor/widgets/custom_valve_editor_dialog.dart`.
- [ ] Создать `lib/ui/features/editor/widgets/custom_valve_catalog_dialog.dart`.
- [ ] Интегрировать в `lib/ui/features/editor/widgets/fitting_properties_sheet.dart` и `desktop_cad_layout.dart`.
- [ ] Убедиться в прохождении тестов, `flutter analyze`, закоммитить Task 5.

---

### Task 6: Полная верификация, документация и обновление графа
- [ ] Полный прогон `flutter test` (100% pass rate).
- [ ] Полный `flutter analyze` (0 замечаний).
- [ ] Выполнить `graphify update .`.
- [ ] Обновить `PROJECT_MEMORY.md`.
- [ ] Закоммитить и представить walkthrough пользователю.
