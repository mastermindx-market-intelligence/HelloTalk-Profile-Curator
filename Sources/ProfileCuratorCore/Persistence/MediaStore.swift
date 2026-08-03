import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ImagePerceptualHasher: Sendable {
    public init() {}

    public func differenceHash(_ image: CGImage) -> String? {
        let width = 9
        let height = 8
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var value: UInt64 = 0
        var bit: UInt64 = 1
        for y in 0..<height {
            for x in 0..<(width - 1) {
                if pixels[y * width + x] > pixels[y * width + x + 1] { value |= bit }
                bit <<= 1
            }
        }
        return String(format: "%016llx", value)
    }

    public func hammingDistance(_ lhs: String, _ rhs: String) -> Int? {
        guard let left = UInt64(lhs, radix: 16), let right = UInt64(rhs, radix: 16) else { return nil }
        return (left ^ right).nonzeroBitCount
    }
}

public final class MediaStore: @unchecked Sendable {
    public let rootURL: URL
    private let repository: ProfileRepository
    private let fileManager: FileManager
    private let hasher = ImagePerceptualHasher()

    public init(rootURL: URL, repository: ProfileRepository, fileManager: FileManager = .default) throws {
        self.rootURL = rootURL
        self.repository = repository
        self.fileManager = fileManager
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    @discardableResult
    public func persist(
        image: CGImage,
        profileID: String,
        kind: MediaKind,
        sourceSequence: Int,
        faceCount: Int,
        largestFaceRatio: Double,
        faceCaptureQuality: Double?,
        usableFace: Bool,
        retained: Bool,
        now: Date = Date()
    ) throws -> MediaRecord? {
        guard let hash = hasher.differenceHash(image) else { throw MediaStoreError.hashFailed }
        let profileDirectory = rootURL.appendingPathComponent(profileID, isDirectory: true)
        try fileManager.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let fileURL = profileDirectory.appendingPathComponent("\(sourceSequence)-\(kind.rawValue)-\(id).png")
        guard let destination = CGImageDestinationCreateWithURL(
            fileURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { throw MediaStoreError.destinationFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw MediaStoreError.writeFailed(fileURL) }

        let record = MediaRecord(
            id: id,
            profileID: profileID,
            kind: kind.rawValue,
            filePath: fileURL.path,
            perceptualHash: hash,
            sourceSequence: sourceSequence,
            faceCount: faceCount,
            largestFaceRatio: largestFaceRatio,
            faceCaptureQuality: faceCaptureQuality,
            usableFace: usableFace,
            retained: retained,
            createdAt: now
        )
        guard try repository.insertMedia(record) else {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
        return record
    }
}

public enum MediaStoreError: Error, LocalizedError, Sendable {
    case hashFailed
    case destinationFailed
    case writeFailed(URL)

    public var errorDescription: String? {
        switch self {
        case .hashFailed: "Could not calculate the local perceptual hash."
        case .destinationFailed: "Could not create the local PNG destination."
        case .writeFailed(let url): "Could not write collected media to \(url.path)."
        }
    }
}
