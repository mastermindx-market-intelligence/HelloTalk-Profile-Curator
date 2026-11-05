import CryptoKit
import Foundation
import ImageIO

public enum VisualAgentLocalImageError: Error {
    case missingImage, invalidImage, oversizedImage
}

/// Local file -> actual pixels -> Apple Vision -> trusted controls. Reads only;
/// never transmits bytes or attests that arbitrary input is synthetic/authorized.
/// Simulation runners supply exclusively locally generated fictional PNGs.
public enum VisualAgentLocalImageFrame {
    public static func load(at url: URL) throws -> VisualAgentFrame {
        guard FileManager.default.fileExists(atPath: url.path) else { throw VisualAgentLocalImageError.missingImage }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 3_000_000 else { throw VisualAgentLocalImageError.oversizedImage }
        let bytes = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 4096, height <= 4096 else {
            throw VisualAgentLocalImageError.invalidImage
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw VisualAgentLocalImageError.invalidImage }
        let analysis = try VisionFixtureAnalyzer().analyze(image)
        let observation = ObservationSnapshotBuilder().build(from: analysis, image: image)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return try VisualAgentFrameAdapter().build(screenshotDigest: digest, observation: observation, analysis: analysis)
    }
}
