 = Get-Content lib/domain/models/piping_network.dart
 = [array]::IndexOf(, "  void moveEquipment(String eqId, double dx, double dy, double dz) {")
 = @(
"  void updateEquipment(Equipment updatedEq) {",
"    if (!equipments.containsKey(updatedEq.id)) return;",
"    equipments[updatedEq.id] = updatedEq;",
"  }",
""
)
 = [0..(-1)] +  + [..(.Count-1)]
 | Set-Content lib/domain/models/piping_network.dart
