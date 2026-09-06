import SwiftUI
import ProfileCuratorCore

/// Geometry uses top-left source pixels, independent of window size or display scale.
enum JimuPhotoCropGeometry {
    static func imageRect(width: Int, height: Int, in size: CGSize) -> CGRect? {
        guard width > 0, height > 0, width <= 8192, height <= 8192,
              size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        let scale = min(size.width / CGFloat(width), size.height / CGFloat(height))
        return CGRect(x: (size.width - CGFloat(width) * scale) / 2,
            y: (size.height - CGFloat(height) * scale) / 2,
            width: CGFloat(width) * scale, height: CGFloat(height) * scale)
    }
    static func selection(from start: CGPoint, to end: CGPoint,
        width: Int, height: Int, in size: CGSize) -> JimuPhotoRect? {
        guard start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite,
              let box = imageRect(width: width, height: height, in: size), box.contains(start) else { return nil }
        let scale = box.width / CGFloat(width)
        let a = CGPoint(x: (start.x - box.minX) / scale, y: (start.y - box.minY) / scale)
        let b = CGPoint(x: min(CGFloat(width), max(0, (end.x - box.minX) / scale)),
                        y: min(CGFloat(height), max(0, (end.y - box.minY) / scale)))
        guard abs(a.x - b.x) >= 1, abs(a.y - b.y) >= 1 else { return nil }
        let x = max(0, Int(floor(min(a.x, b.x))))
        let y = max(0, Int(floor(min(a.y, b.y))))
        let right = min(width, Int(ceil(max(a.x, b.x))))
        let bottom = min(height, Int(ceil(max(a.y, b.y))))
        return JimuPhotoRect(x: x, y: y, width: right - x, height: bottom - y)
    }
}

struct JimuPhotoCropEditor: View {
    let image: CGImage
    let save: (JimuPhotoRect, Bool) -> Void
    @State private var x: Int
    @State private var y: Int
    @State private var width: Int
    @State private var height: Int
    @State private var confirmed = false
    init(image: CGImage, initial: JimuPhotoRect?, save: @escaping (JimuPhotoRect, Bool) -> Void) {
        self.image = image; self.save = save
        _x = State(initialValue: initial?.x ?? 0)
        _y = State(initialValue: initial?.y ?? 0)
        _width = State(initialValue: initial?.width ?? image.width)
        _height = State(initialValue: initial?.height ?? image.height)
    }
    private var rect: JimuPhotoRect { JimuPhotoRect(x: x, y: y, width: width, height: height) }
    private var valid: Bool {
        x >= 0 && y >= 0 && width > 0 && height > 0 && width <= image.width && height <= image.height &&
        x <= image.width - width && y <= image.height - height
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prepare a photo-only region").font(.headline)
            Text("Drag on the image or enter pixel coordinates. Exclude profile text, captions and interface controls.")
                .font(.caption).foregroundStyle(.secondary)
            canvas.frame(height: 280)
            HStack(spacing: 16) {
                coordinate("X", value: $x); coordinate("Y", value: $y)
                coordinate("Width", value: $width); coordinate("Height", value: $height)
            }
            Toggle("I confirm this region contains only the intended photo, without profile text or controls.", isOn: $confirmed)
                .font(.caption)
            HStack {
                Button("Save photo region") { save(rect, confirmed) }
                    .disabled(!valid || !confirmed).buttonStyle(.borderedProminent).tint(.teal)
                Text(valid ? "Source pixels · top-left origin" : "Region must be inside the image.")
                    .font(.caption).foregroundStyle(valid ? Color.secondary : Color.orange)
            }
            Text("This records human confirmation, not automatic proof of text absence. Calibrate hides the surrounding profile.")
                .font(.caption2).foregroundStyle(.secondary)
        }.onChange(of: rect) { _, _ in confirmed = false }
    }
    private func coordinate(_ title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            TextField(title, value: value, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder).frame(maxWidth: 105)
        }
    }
    private var canvas: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.06)
                if let box = JimuPhotoCropGeometry.imageRect(width: image.width, height: image.height, in: proxy.size) {
                    Image(decorative: image, scale: 1).resizable()
                        .frame(width: box.width, height: box.height).offset(x: box.minX, y: box.minY)
                    if valid {
                        let scale = box.width / CGFloat(image.width)
                        Rectangle().fill(Color.teal.opacity(0.15))
                            .overlay(Rectangle().stroke(Color.teal, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                            .frame(width: CGFloat(width) * scale, height: CGFloat(height) * scale)
                            .offset(x: box.minX + CGFloat(x) * scale, y: box.minY + CGFloat(y) * scale)
                    }
                }
            }.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 3).onChanged { drag in
                    if let next = JimuPhotoCropGeometry.selection(from: drag.startLocation, to: drag.location,
                        width: image.width, height: image.height, in: proxy.size) {
                        x = next.x; y = next.y; width = next.width; height = next.height; confirmed = false
                    }
                })
                .accessibilityLabel("Photo region editor. Pixel coordinates are editable below.")
        }
    }
}
