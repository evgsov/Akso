class DraftingSettings {
  final bool snapNodes;
  final bool snapIntersections;
  final bool snapMidpoints;
  final bool snapPerpendicular;
  final bool snapNearest;
  final bool enableOtrack;
  final bool isZLocked;
  final bool showZPlaneGrid;
  final double nodeSnapRadius;
  final double nearestSnapRadius;

  const DraftingSettings({
    this.snapNodes = true,
    this.snapIntersections = true,
    this.snapMidpoints = true,
    this.snapPerpendicular = true,
    this.snapNearest = false,
    this.enableOtrack = true,
    this.isZLocked = true,
    this.showZPlaneGrid = false,
    this.nodeSnapRadius = 20.0,
    this.nearestSnapRadius = 8.0,
  });

  DraftingSettings copyWith({
    bool? snapNodes,
    bool? snapIntersections,
    bool? snapMidpoints,
    bool? snapPerpendicular,
    bool? snapNearest,
    bool? enableOtrack,
    bool? isZLocked,
    bool? showZPlaneGrid,
    double? nodeSnapRadius,
    double? nearestSnapRadius,
  }) {
    return DraftingSettings(
      snapNodes: snapNodes ?? this.snapNodes,
      snapIntersections: snapIntersections ?? this.snapIntersections,
      snapMidpoints: snapMidpoints ?? this.snapMidpoints,
      snapPerpendicular: snapPerpendicular ?? this.snapPerpendicular,
      snapNearest: snapNearest ?? this.snapNearest,
      enableOtrack: enableOtrack ?? this.enableOtrack,
      isZLocked: isZLocked ?? this.isZLocked,
      showZPlaneGrid: showZPlaneGrid ?? this.showZPlaneGrid,
      nodeSnapRadius: nodeSnapRadius ?? this.nodeSnapRadius,
      nearestSnapRadius: nearestSnapRadius ?? this.nearestSnapRadius,
    );
  }
}
