import AppKit
import ProfileCuratorCore
import SwiftUI

struct FixtureCanvas: View {
    let image: NSImage?
    let analysis: FixtureAnalysis?
    let showOCRBoxes: Bool
    let showFaceBoxes: Bool
    let showSafetyPreview: Bool
    let action: PlannedAction
    let exclusions: [ExclusionZone]
    let calibrationMode: Bool
    let calibrationMarks: [CalibrationMark]
    let onCalibrationRect: (NormalizedRect) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.92)

                if let image {
                    let fitted = aspectFitRect(imageSize: image.size, container: geometry.size)

                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: fitted.width, height: fitted.height)
                        .position(x: fitted.midX, y: fitted.midY)

                    if let analysis, showOCRBoxes {
                        ForEach(analysis.text) { observation in
                            overlayRect(observation.bounds, fitted: fitted, color: .yellow, lineWidth: 1)
                                .help("\(observation.text) — \(Int(observation.confidence * 100))%")
                        }
                    }

                    if let analysis, showFaceBoxes {
                        ForEach(analysis.faces) { face in
                            overlayRect(face.bounds, fitted: fitted, color: .green, lineWidth: 2)
                                .help(face.captureQuality.map { "Face quality \(String(format: "%.2f", $0))" } ?? "Face quality unavailable")
                        }
                    }

                    if showSafetyPreview {
                        if let safeRegion = action.requiredSafeRegion {
                            overlayRect(safeRegion, fitted: fitted, color: .blue, lineWidth: 2, dashed: true)
                                .help("Required safe region preview")
                        }

                        ForEach(exclusions) { zone in
                            overlayRect(zone.bounds, fitted: fitted, color: .red, lineWidth: 2)
                                .help(zone.label)
                        }

                        Circle()
                            .fill(.cyan)
                            .overlay(Circle().stroke(.black, lineWidth: 1))
                            .frame(width: 12, height: 12)
                            .position(
                                x: fitted.minX + action.point.x * fitted.width,
                                y: fitted.minY + action.point.y * fitted.height
                            )
                            .help(action.rationale)
                    }

                    ForEach(calibrationMarks) { mark in
                        overlayRect(
                            mark.bounds,
                            fitted: fitted,
                            color: mark.kind.isExclusion ? .red : .purple,
                            lineWidth: 3,
                            dashed: !mark.confirmed
                        )
                        .help(mark.kind.displayName)
                    }

                    if calibrationMode {
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .frame(width: fitted.width, height: fitted.height)
                            .position(x: fitted.midX, y: fitted.midY)
                            .gesture(
                                DragGesture(minimumDistance: 4)
                                    .onEnded { value in
                                        let start = value.startLocation
                                        let end = value.location
                                        let minX = max(0, min(start.x, end.x) / fitted.width)
                                        let minY = max(0, min(start.y, end.y) / fitted.height)
                                        let maxX = min(1, max(start.x, end.x) / fitted.width)
                                        let maxY = min(1, max(start.y, end.y) / fitted.height)
                                        onCalibrationRect(
                                            NormalizedRect(
                                                x: minX,
                                                y: minY,
                                                width: maxX - minX,
                                                height: maxY - minY
                                            )
                                        )
                                    }
                            )
                    }
                } else {
                    ContentUnavailableView(
                        "No fixture loaded",
                        systemImage: "photo.badge.plus",
                        description: Text("Load a private screenshot to replay OCR and face detection. No input events are generated.")
                    )
                    .foregroundStyle(.white)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func aspectFitRect(imageSize: CGSize, container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func overlayRect(
        _ normalized: NormalizedRect,
        fitted: CGRect,
        color: Color,
        lineWidth: CGFloat,
        dashed: Bool = false
    ) -> some View {
        let rect = CGRect(
            x: fitted.minX + normalized.x * fitted.width,
            y: fitted.minY + normalized.y * fitted.height,
            width: normalized.width * fitted.width,
            height: normalized.height * fitted.height
        )

        return Rectangle()
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, dash: dashed ? [6, 4] : []))
            .background(color.opacity(0.06))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }
}
