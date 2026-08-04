import Foundation

public struct MomentThumbnailTarget: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let index: Int
    public let point: NormalizedPoint
    public let safePhotoRegion: NormalizedRect

    public init(
        id: UUID = UUID(),
        index: Int,
        point: NormalizedPoint,
        safePhotoRegion: NormalizedRect
    ) {
        self.id = id
        self.index = index
        self.point = point
        self.safePhotoRegion = safePhotoRegion
    }

    public var plannedAction: PlannedAction {
        PlannedAction(
            kind: .openMomentThumbnail,
            point: point,
            requiredSafeRegion: safePhotoRegion,
            rationale: "Dry-run Moment thumbnail \(index + 1) proposal"
        )
    }
}

public struct MomentThumbnailTargetDetector: Sendable {
    public init() {}

    public func targets(from marks: [CalibrationMark]) -> [MomentThumbnailTarget] {
        guard let grid = marks.last(where: {
            $0.context == .momentsFeed && $0.kind == .safeMomentThumbnailGrid
        }), grid.confirmed, grid.bounds.isValidNormalizedRect else {
            return []
        }

        let columns = 3
        let rows = 3
        let horizontalInset = min(0.012, grid.bounds.width / 20)
        let verticalInset = min(0.012, grid.bounds.height / 20)
        let cellWidth = grid.bounds.width / Double(columns)
        let cellHeight = grid.bounds.height / Double(rows)

        return (0..<(columns * rows)).map { index in
            let row = index / columns
            let column = index % columns
            let cell = NormalizedRect(
                x: grid.bounds.minX + Double(column) * cellWidth + horizontalInset,
                y: grid.bounds.minY + Double(row) * cellHeight + verticalInset,
                width: max(0, cellWidth - horizontalInset * 2),
                height: max(0, cellHeight - verticalInset * 2)
            )
            return MomentThumbnailTarget(
                index: index,
                point: cell.center,
                safePhotoRegion: cell
            )
        }
    }
}
