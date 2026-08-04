import CoreGraphics
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

public struct MomentVisitKeyBuilder: Sendable {
    public init() {}

    public func keys(
        targetIndex: Int,
        feedPage: Int,
        thumbnailHash: String?,
        timelineDate: String? = nil
    ) -> Set<String> {
        var keys: Set<String> = ["slot|\(feedPage)|\(targetIndex)"]
        if let thumbnailHash, !thumbnailHash.isEmpty {
            keys.insert("thumbnail|\(thumbnailHash)")
        }
        if let timelineDate, !timelineDate.isEmpty {
            keys.insert("timeline|\(timelineDate.lowercased())")
        }
        return keys
    }
}

public struct MomentThumbnailTargetDetector: Sendable {
    public init() {}

    public func targets(
        in image: CGImage,
        from marks: [CalibrationMark],
        observations: [OCRObservation] = [],
        faces: [DetectedFace] = []
    ) -> [MomentThumbnailTarget] {
        guard let searchMark = marks.last(where: {
            $0.context == .momentsFeed && $0.kind == .safeMomentThumbnailGrid
        }), searchMark.confirmed, searchMark.bounds.isValidNormalizedRect,
              let pixels = MomentPixelBuffer(image: image) else {
            return []
        }
        let declaredPostCount = declaredMomentPostCount(in: observations)
        // Some profiles expose Moments as a timeline rather than a square
        // gallery. The post header and caption occupy the upper part of the
        // calibrated region; treating that chrome as row one opens Details.
        // For a visible dated post, derive points below its header. If a long
        // caption still intercepts one, the Details recovery skips that point
        // and continues instead of ending the entire media pass.
        let timelineTargets: [MomentThumbnailTarget]
        if observations.isEmpty {
            timelineTargets = []
        } else {
            timelineTargets = timelinePhotoTargets(
               searchMark: searchMark,
               observations: observations
            )
            let hasRelativePostTime = observations.contains {
                $0.text.range(
                    of: #"\b\d+\s+(?:minutes?|hours?|days?)\s+ago\b"#,
                    options: [.regularExpression, .caseInsensitive]
                ) != nil && $0.bounds.center.y > 0.50
            }
            if hasRelativePostTime, !timelineTargets.isEmpty {
                return limited(timelineTargets, toDeclaredPostCount: declaredPostCount)
            }
        }
        // Production captures must prove that the visible three-column geometry
        // belongs to the profile's top Moments gallery. Embedded photo mosaics in
        // timeline posts can have nearly identical pixel structure but open the
        // post container instead of a full-photo viewer.
        guard observations.isEmpty || hasTopGalleryAnchors(observations) else {
            return limited(timelineTargets, toDeclaredPostCount: declaredPostCount)
        }

        let columns = 3
        let left = max(0, Int((searchMark.bounds.minX * Double(pixels.width)).rounded()))
        let searchWidth = min(
            pixels.width - left,
            Int((searchMark.bounds.width * Double(pixels.width)).rounded())
        )
        let gutter = max(3, Int((Double(searchWidth) * 0.015).rounded()))
        let cellSize = max(1, (searchWidth - gutter * (columns - 1)) / columns)
        let searchMinY = max(0, Int((searchMark.bounds.minY * Double(pixels.height)).rounded()))
        let searchMaxY = min(
            pixels.height,
            Int((searchMark.bounds.maxY * Double(pixels.height)).rounded())
        )
        guard searchWidth > 0, searchMaxY - searchMinY >= cellSize else { return timelineTargets }

        let runs = activeRuns(
            pixels: pixels,
            left: left,
            cellSize: cellSize,
            gutter: gutter,
            searchMinY: searchMinY,
            searchMaxY: searchMaxY
        )
        guard let firstRow = bestGridStart(
            in: runs,
            cellSize: cellSize,
            gutter: gutter,
            left: left,
            imageWidth: pixels.width,
            imageHeight: pixels.height,
            observations: observations
        ) else {
            return limited(timelineTargets, toDeclaredPostCount: declaredPostCount)
        }

        let pitch = cellSize + gutter
        let inset = max(4, Int(Double(cellSize) * 0.045))
        var targets: [MomentThumbnailTarget] = []
        for row in 0..<3 {
            let top = firstRow.lowerBound + row * pitch
            guard top + cellSize <= searchMaxY else { break }
            let activities = (0..<columns).map { column in
                patchActivity(
                    pixels: pixels,
                    x: left + column * pitch,
                    y: top,
                    size: cellSize
                )
            }
            let sampleTopInset = max(inset, cellSize / 5)
            let textures = (0..<columns).map { column in
                pixels.textureFraction(
                    x: left + column * pitch + inset,
                    y: top + sampleTopInset,
                    width: max(1, cellSize - inset * 2),
                    height: max(1, cellSize - sampleTopInset - inset),
                    stride: 3
                )
            }
            let presences = (0..<columns).map { column in
                pixels.contentLinePresence(
                    x: left + column * pitch + inset,
                    y: top + sampleTopInset,
                    width: max(1, cellSize - inset * 2),
                    height: max(1, cellSize - sampleTopInset - inset)
                )
            }
            let activeColumns = (0..<columns).filter {
                activities[$0] >= 0.50
                    || (activities[$0] >= 0.08 && textures[$0] >= 0.01 && presences[$0] >= 0.19)
            }
            guard !activeColumns.isEmpty else { break }
            for column in activeColumns {
                let pixelX = left + column * pitch + inset
                let pixelY = top + inset
                let safe = NormalizedRect(
                    x: Double(pixelX) / Double(pixels.width),
                    y: Double(pixelY) / Double(pixels.height),
                    width: Double(cellSize - inset * 2) / Double(pixels.width),
                    height: Double(cellSize - inset * 2) / Double(pixels.height)
                )
                guard !isAdvertisingPoint(
                    safe.center,
                    observations: observations,
                    verticalTolerance: max(0.075, safe.height * 0.95)
                ) else { continue }
                targets.append(MomentThumbnailTarget(
                    index: row * columns + column,
                    point: safe.center,
                    safePhotoRegion: safe
                ))
            }
        }
        return limited(
            targets.isEmpty ? timelineTargets : targets,
            toDeclaredPostCount: declaredPostCount
        )
    }

    private func declaredMomentPostCount(in observations: [OCRObservation]) -> Int? {
        let pattern = #"\bMoments\s*(\d{1,3})\b"#
        for observation in observations {
            let text = observation.text
            guard let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
                continue
            }
            let token = text[match].filter(\.isNumber)
            if let count = Int(token), count > 0 { return count }
        }
        return nil
    }

    private func limited(
        _ targets: [MomentThumbnailTarget],
        toDeclaredPostCount declaredPostCount: Int?
    ) -> [MomentThumbnailTarget] {
        guard let declaredPostCount else { return targets }
        // The tab count is posts, not photos. A post can expose multiple photos
        // after one tile opens, and the viewer traversal collects those frames.
        // Never reinterpret one full-width video/post cover as three grid cells.
        return Array(targets.prefix(declaredPostCount))
    }

    private func timelinePhotoTargets(
        searchMark: CalibrationMark,
        observations: [OCRObservation]
    ) -> [MomentThumbnailTarget] {
        let joined = observations.map(\.text).joined(separator: " · ")
        let matcher = OCRAnchorMatcher()
        let hasTabs = matcher.contains(anchor: "About Me", in: joined)
            && matcher.contains(anchor: "Achievements", in: joined)
        let hasEngagement = joined.range(
            of: #"\b\d+\s*Like\b.*\b\d+\s*Comment\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        guard hasTabs || hasEngagement else { return [] }

        let tabBottom = observations.filter {
            matcher.contains(anchor: "About Me", in: $0.text)
                || matcher.contains(anchor: "Achievements", in: $0.text)
        }.map(\.bounds.maxY).max()
        let postTimePattern = #"\b(?:\d+\s+(?:minutes?|hours?|days?)\s+ago|today|yesterday|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b|\b\d{1,4}[/.-]\d{1,2}(?:[/.-]\d{1,4})?\b"#
        let postTimes = observations.filter { observation in
            guard observation.text.range(
                of: postTimePattern,
                options: [.regularExpression, .caseInsensitive]
            ) != nil else { return false }
            if let tabBottom { return observation.bounds.center.y > tabBottom + 0.04 }
            return true
        }.sorted { $0.bounds.center.y < $1.bounds.center.y }
        guard !postTimes.isEmpty else { return [] }

        var targets: [MomentThumbnailTarget] = []
        for (index, postTime) in postTimes.enumerated() {
            let point = NormalizedPoint(
                x: searchMark.bounds.minX + min(0.18, searchMark.bounds.width * 0.30),
                y: min(searchMark.bounds.maxY - 0.07, max(0.72, postTime.bounds.maxY + 0.12))
            )
            guard searchMark.bounds.contains(point),
                  !isAdvertisingPoint(point, observations: observations, verticalTolerance: 0.14) else {
                continue
            }

            let safe = NormalizedRect(
                x: max(searchMark.bounds.minX, point.x - 0.045),
                y: max(searchMark.bounds.minY, point.y - 0.04),
                width: 0.09,
                height: 0.08
            )
            targets.append(MomentThumbnailTarget(
                index: 100 + index,
                point: point,
                safePhotoRegion: safe
            ))
        }
        return targets
    }

    private func hasTopGalleryAnchors(_ observations: [OCRObservation]) -> Bool {
        let text = observations.map(\.text).joined(separator: " · ")
        let matcher = OCRAnchorMatcher()
        let hasTabs = matcher.contains(anchor: "About Me", in: text)
            && matcher.contains(anchor: "Moments", in: text)
            && matcher.contains(anchor: "Achievements", in: text)
        let hasEngagement = text.range(
            of: #"\b\d+\s*Like\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil && text.range(
            of: #"\b\d+\s*Comment\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let hasPostDate = text.range(
            of: #"\b(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\b|\b\d{1,2}[/.-]\d{1,2}(?:[/.-]\d{2,4})?\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let hasProfileUsername = text.range(
            of: #"@[A-Z0-9_.-]{2,40}"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let isDetails = matcher.contains(anchor: "Details", in: text)
            && (matcher.contains(anchor: "Type a message", in: text)
                || matcher.contains(anchor: "Comments", in: text))
        // A profile can hide its @handle once the Moment feed is scrolled. The
        // three profile tabs prove the top surface; engagement plus a post date
        // prove a lower post. Pixel targeting still has to pass the ad filters.
        return !isDetails && ((hasTabs && (hasProfileUsername || hasEngagement))
            || (hasEngagement && hasPostDate))
    }

    private func bestGridStart(
        in runs: [ClosedRange<Int>],
        cellSize: Int,
        gutter: Int,
        left: Int,
        imageWidth: Int,
        imageHeight: Int,
        observations: [OCRObservation]
    ) -> ClosedRange<Int>? {
        let minimumRunHeight = Int(Double(cellSize) * 0.65)
        let advertisingCenters = advertisingObservations(in: observations).map(\.bounds.center.y)
        let normalizedCellHeight = Double(cellSize) / Double(imageHeight)
        let candidates = runs.filter { candidate in
            let centerY = Double(candidate.lowerBound + cellSize / 2) / Double(imageHeight)
            return candidate.upperBound - candidate.lowerBound + 1 >= minimumRunHeight
                && !advertisingCenters.contains {
                    abs($0 - centerY) <= normalizedCellHeight * 1.15
                }
        }
        let pitch = cellSize + gutter
        let tolerance = max(gutter * 2, Int(Double(cellSize) * 0.08))
        let filteredCandidates: [ClosedRange<Int>]
        if observations.isEmpty {
            filteredCandidates = candidates
        } else {
            let contamination = candidates.map {
                ocrContamination(
                    for: $0,
                    left: left,
                    gridWidth: cellSize * 3 + gutter * 2,
                    cellSize: cellSize,
                    imageWidth: imageWidth,
                    imageHeight: imageHeight,
                    observations: observations
                )
            }
            let minimum = contamination.min() ?? 0
            filteredCandidates = zip(candidates, contamination).compactMap { candidate, count in
                count <= minimum + 1 ? candidate : nil
            }
        }

        return filteredCandidates.max { lhs, rhs in
            let lhsScore = alignedRowCount(
                from: lhs,
                candidates: candidates,
                pitch: pitch,
                tolerance: tolerance
            )
            let rhsScore = alignedRowCount(
                from: rhs,
                candidates: candidates,
                pitch: pitch,
                tolerance: tolerance
            )
            if lhsScore == rhsScore {
                return lhs.lowerBound < rhs.lowerBound
            }
            return lhsScore < rhsScore
        }
    }

    private func advertisingObservations(in observations: [OCRObservation]) -> [OCRObservation] {
        let markers = [
            "download now", "ad-free", "ad free", "sponsored", "advertisement",
            "install", "promoted", "ad x", "download mobile", "deposit match",
            "bonus spins", "betway"
        ]
        return observations.filter { observation in
            guard observation.confidence >= 0.35 else { return false }
            let text = observation.text.lowercased()
            return markers.contains(where: text.contains)
        }
    }

    private func isAdvertisingPoint(
        _ point: NormalizedPoint,
        observations: [OCRObservation],
        verticalTolerance: Double
    ) -> Bool {
        advertisingObservations(in: observations).contains {
            abs($0.bounds.center.y - point.y) <= verticalTolerance
        }
    }

    private func ocrContamination(
        for candidate: ClosedRange<Int>,
        left: Int,
        gridWidth: Int,
        cellSize: Int,
        imageWidth: Int,
        imageHeight: Int,
        observations: [OCRObservation]
    ) -> Int {
        let bounds = NormalizedRect(
            x: Double(left) / Double(imageWidth),
            y: Double(candidate.lowerBound) / Double(imageHeight),
            width: Double(gridWidth) / Double(imageWidth),
            height: Double(cellSize) / Double(imageHeight)
        )
        return observations.filter { observation in
            observation.confidence >= 0.45 && bounds.contains(observation.bounds.center)
        }.count
    }

    private func alignedRowCount(
        from candidate: ClosedRange<Int>,
        candidates: [ClosedRange<Int>],
        pitch: Int,
        tolerance: Int
    ) -> Int {
        1 + (1..<3).filter { row in
            let expected = candidate.lowerBound + row * pitch
            return candidates.contains { abs($0.lowerBound - expected) <= tolerance }
        }.count
    }

    private func activeRuns(
        pixels: MomentPixelBuffer,
        left: Int,
        cellSize: Int,
        gutter: Int,
        searchMinY: Int,
        searchMaxY: Int
    ) -> [ClosedRange<Int>] {
        var runs: [ClosedRange<Int>] = []
        var runStart: Int?
        for y in searchMinY..<searchMaxY {
            let active = lineLooksLikeGrid(
                pixels: pixels,
                left: left,
                y: y,
                cellSize: cellSize,
                gutter: gutter
            )
            if active, runStart == nil { runStart = y }
            if !active, let start = runStart {
                runs.append(start...(y - 1))
                runStart = nil
            }
        }
        if let start = runStart { runs.append(start...(searchMaxY - 1)) }
        return runs
    }

    private func lineLooksLikeGrid(
        pixels: MomentPixelBuffer,
        left: Int,
        y: Int,
        cellSize: Int,
        gutter: Int
    ) -> Bool {
        let pitch = cellSize + gutter
        let columnFractions = (0..<3).map { column in
            pixels.contentFraction(
                x: left + column * pitch + 5,
                y: y,
                width: max(1, cellSize - 10),
                height: 1,
                stride: 2
            )
        }
        let activeColumns = columnFractions.filter { $0 > 0.05 }.count
        guard activeColumns >= 2 else { return false }
        let gutterScores = (1..<3).map { boundary in
            let expectedX = left + boundary * cellSize + (boundary - 1) * gutter
            let probeWidth = max(2, gutter / 2)
            return (-gutter...gutter).map { offset in
                max(
                    pixels.whiteFraction(
                        x: expectedX + offset,
                        y: y,
                        width: probeWidth,
                        height: 1
                    ),
                    pixels.darkFraction(
                        x: expectedX + offset,
                        y: y,
                        width: probeWidth,
                        height: 1
                    )
                )
            }.max() ?? 0
        }
        return gutterScores.allSatisfy { $0 > 0.75 }
    }

    private func patchActivity(
        pixels: MomentPixelBuffer,
        x: Int,
        y: Int,
        size: Int
    ) -> Double {
        let inset = max(4, size / 24)
        let topInset = max(inset, size / 5)
        return pixels.contentFraction(
            x: x + inset,
            y: y + topInset,
            width: max(1, size - inset * 2),
            height: max(1, size - topInset - inset),
            stride: 4
        )
    }
}

private struct MomentPixelBuffer {
    let width: Int
    let height: Int
    private let bytesPerRow: Int
    private let bytes: [UInt8]

    init?(image: CGImage) {
        let imageWidth = image.width
        let imageHeight = image.height
        let imageBytesPerRow = imageWidth * 4
        var storage = [UInt8](repeating: 0, count: imageBytesPerRow * imageHeight)
        let didDraw = storage.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let context = CGContext(
                data: rawBuffer.baseAddress,
                width: imageWidth,
                height: imageHeight,
                bitsPerComponent: 8,
                bytesPerRow: imageBytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
            return true
        }
        guard didDraw else {
            return nil
        }
        width = imageWidth
        height = imageHeight
        bytesPerRow = imageBytesPerRow
        bytes = storage
    }

    func contentFraction(x: Int, y: Int, width: Int, height: Int, stride: Int) -> Double {
        fraction(x: x, y: y, width: width, height: height, stride: stride) { red, green, blue in
            Swift.min(red, Swift.min(green, blue)) < 235
                || Swift.max(red, Swift.max(green, blue))
                    - Swift.min(red, Swift.min(green, blue)) > 18
        }
    }

    func whiteFraction(x: Int, y: Int, width: Int, height: Int) -> Double {
        fraction(x: x, y: y, width: width, height: height, stride: 1) { red, green, blue in
            Swift.min(red, Swift.min(green, blue)) > 238
                && Swift.max(red, Swift.max(green, blue))
                    - Swift.min(red, Swift.min(green, blue)) < 18
        }
    }

    func darkFraction(x: Int, y: Int, width: Int, height: Int) -> Double {
        fraction(x: x, y: y, width: width, height: height, stride: 1) { red, green, blue in
            Swift.max(red, Swift.max(green, blue)) < 42
        }
    }

    func textureFraction(x: Int, y: Int, width: Int, height: Int, stride: Int) -> Double {
        let minX = max(0, x)
        let minY = max(0, y)
        let maxX = min(self.width - 1, x + width)
        let maxY = min(self.height - 1, y + height)
        guard minX < maxX, minY < maxY else { return 0 }
        var textured = 0
        var samples = 0
        for row in Swift.stride(from: minY, to: maxY, by: max(1, stride)) {
            for column in Swift.stride(from: minX, to: maxX, by: max(1, stride)) {
                let pixel = rgb(x: column, y: row)
                let right = rgb(x: column + 1, y: row)
                let down = rgb(x: column, y: row + 1)
                let horizontal = abs(pixel.0 - right.0) + abs(pixel.1 - right.1) + abs(pixel.2 - right.2)
                let vertical = abs(pixel.0 - down.0) + abs(pixel.1 - down.1) + abs(pixel.2 - down.2)
                if max(horizontal, vertical) > 30 { textured += 1 }
                samples += 1
            }
        }
        return samples == 0 ? 0 : Double(textured) / Double(samples)
    }

    func contentLinePresence(x: Int, y: Int, width: Int, height: Int) -> Double {
        let minY = max(0, y)
        let maxY = min(self.height, y + height)
        guard minY < maxY else { return 0 }
        var activeLines = 0
        var lines = 0
        for row in minY..<maxY {
            if contentFraction(x: x, y: row, width: width, height: 1, stride: 2) >= 0.05 {
                activeLines += 1
            }
            lines += 1
        }
        return lines == 0 ? 0 : Double(activeLines) / Double(lines)
    }

    private func rgb(x: Int, y: Int) -> (Int, Int, Int) {
        let offset = y * bytesPerRow + x * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }

    private func fraction(
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        stride: Int,
        predicate: (Int, Int, Int) -> Bool
    ) -> Double {
        let minX = max(0, x)
        let minY = max(0, y)
        let maxX = min(self.width, x + width)
        let maxY = min(self.height, y + height)
        guard minX < maxX, minY < maxY else { return 0 }
        var matches = 0
        var samples = 0
        for row in Swift.stride(from: minY, to: maxY, by: max(1, stride)) {
            for column in Swift.stride(from: minX, to: maxX, by: max(1, stride)) {
                let offset = row * bytesPerRow + column * 4
                if predicate(Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2])) {
                    matches += 1
                }
                samples += 1
            }
        }
        return samples == 0 ? 0 : Double(matches) / Double(samples)
    }
}
