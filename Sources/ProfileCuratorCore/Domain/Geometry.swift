import Foundation

public struct NormalizedPoint: Codable, Hashable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public var isInsideUnitSquare: Bool {
        (0...1).contains(x) && (0...1).contains(y)
    }
}

public struct NormalizedRect: Codable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    public var isValidNormalizedRect: Bool {
        width >= 0 && height >= 0 && minX >= 0 && minY >= 0 && maxX <= 1 && maxY <= 1
    }

    public var center: NormalizedPoint {
        NormalizedPoint(x: x + width / 2, y: y + height / 2)
    }

    public func contains(_ point: NormalizedPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }
}
