import CoreGraphics
import Foundation

public enum GenderBadgeHint: String, Codable, Sendable {
    case female
    case male
    case unknown
}

public struct GenderBadgeEvidence: Sendable {
    public let hint: GenderBadgeHint
    public let confidence: Double
    public let magentaPixelRatio: Double
    public let bluePixelRatio: Double
    public let sampledPixelCount: Int

    public init(
        hint: GenderBadgeHint,
        confidence: Double,
        magentaPixelRatio: Double,
        bluePixelRatio: Double,
        sampledPixelCount: Int
    ) {
        self.hint = hint
        self.confidence = confidence
        self.magentaPixelRatio = magentaPixelRatio
        self.bluePixelRatio = bluePixelRatio
        self.sampledPixelCount = sampledPixelCount
    }
}

public struct GenderBadgeClassifier: Sendable {
    public init() {}

    public func classify(image: CGImage, ageMatch: ProfileAgeMatch) -> GenderBadgeEvidence {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ), let data = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return GenderBadgeEvidence(
                hint: .unknown,
                confidence: 0,
                magentaPixelRatio: 0,
                bluePixelRatio: 0,
                sampledPixelCount: 0
            )
        }

        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let source = ageMatch.source.bounds
        let expanded = NormalizedRect(
            x: max(0, source.x - max(0.012, source.width * 0.5)),
            y: max(0, source.y - max(0.008, source.height * 0.45)),
            width: min(1 - max(0, source.x - max(0.012, source.width * 0.5)), source.width * 2.0 + 0.024),
            height: min(1 - max(0, source.y - max(0.008, source.height * 0.45)), source.height * 1.9 + 0.016)
        )

        let minX = max(0, Int(expanded.minX * Double(width)))
        let maxX = min(width - 1, Int(expanded.maxX * Double(width)))
        // Bitmap-context memory rows use the Core Graphics bottom-left basis,
        // while all curator observations use a top-left normalized origin.
        let minY = max(0, Int((1 - expanded.maxY) * Double(height)))
        let maxY = min(height - 1, Int((1 - expanded.minY) * Double(height)))

        guard minX <= maxX, minY <= maxY else {
            return GenderBadgeEvidence(
                hint: .unknown,
                confidence: 0,
                magentaPixelRatio: 0,
                bluePixelRatio: 0,
                sampledPixelCount: 0
            )
        }

        var saturatedPixelCount = 0
        var magentaPixelCount = 0
        var bluePixelCount = 0

        for y in minY...maxY {
            for x in minX...maxX {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let red = Double(data[offset]) / 255
                let green = Double(data[offset + 1]) / 255
                let blue = Double(data[offset + 2]) / 255
                let maximum = max(red, green, blue)
                let minimum = min(red, green, blue)
                let saturation = maximum == 0 ? 0 : (maximum - minimum) / maximum

                guard maximum >= 0.32, saturation >= 0.32 else { continue }
                saturatedPixelCount += 1

                if red >= 0.5, red > green * 1.25, red >= blue * 0.9 {
                    magentaPixelCount += 1
                }
                if blue >= 0.45, blue > red * 1.15, blue > green * 1.05 {
                    bluePixelCount += 1
                }
            }
        }

        guard saturatedPixelCount >= 8 else {
            return GenderBadgeEvidence(
                hint: .unknown,
                confidence: 0,
                magentaPixelRatio: 0,
                bluePixelRatio: 0,
                sampledPixelCount: saturatedPixelCount
            )
        }

        let magentaRatio = Double(magentaPixelCount) / Double(saturatedPixelCount)
        let blueRatio = Double(bluePixelCount) / Double(saturatedPixelCount)

        if magentaPixelCount >= 8, magentaRatio > blueRatio * 1.5 {
            return GenderBadgeEvidence(
                hint: .female,
                confidence: min(1, 0.55 + magentaRatio * 0.45),
                magentaPixelRatio: magentaRatio,
                bluePixelRatio: blueRatio,
                sampledPixelCount: saturatedPixelCount
            )
        }
        if bluePixelCount >= 8, blueRatio > magentaRatio * 1.5 {
            return GenderBadgeEvidence(
                hint: .male,
                confidence: min(1, 0.55 + blueRatio * 0.45),
                magentaPixelRatio: magentaRatio,
                bluePixelRatio: blueRatio,
                sampledPixelCount: saturatedPixelCount
            )
        }

        return GenderBadgeEvidence(
            hint: .unknown,
            confidence: 0.25,
            magentaPixelRatio: magentaRatio,
            bluePixelRatio: blueRatio,
            sampledPixelCount: saturatedPixelCount
        )
    }
}
