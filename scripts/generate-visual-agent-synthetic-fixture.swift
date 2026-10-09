#!/usr/bin/env swift
// Generate a locally owned, fictional UI image. No HelloTalk account, media or API is accessed.
// Usage: swift scripts/generate-visual-agent-synthetic-fixture.swift /tmp/visual-agent-demo.png
import AppKit
import Foundation

let size = NSSize(width: 420, height: 932)
let image = NSImage(size: size)
image.lockFocus()

func panel(x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat,
           color: NSColor, radius: CGFloat = 0) {
    let rect = NSRect(x: x, y: size.height - top - height, width: width, height: height)
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func text(_ value: String, x: CGFloat, top: CGFloat, fontSize: CGFloat = 16,
          weight: NSFont.Weight = .regular, color: NSColor = .black) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
        .foregroundColor: color
    ]
    (value as NSString).draw(at: NSPoint(x: x, y: size.height - top - fontSize - 4),
                             withAttributes: attributes)
}

panel(x: 0, top: 0, width: 420, height: 932, color: .white)
panel(x: 0, top: 0, width: 420, height: 82, color: NSColor(calibratedRed: 0.12, green: 0.32, blue: 0.59, alpha: 1))
text("SYNTHETIC TEST SCREEN", x: 24, top: 24, fontSize: 19, weight: .bold, color: .white)
text("No real profile or user data", x: 24, top: 50, fontSize: 12, color: .white)

panel(x: 24, top: 125, width: 72, height: 72,
      color: NSColor(calibratedRed: 0.87, green: 0.91, blue: 0.96, alpha: 1), radius: 36)
text("S", x: 47, top: 138, fontSize: 44, weight: .bold)
text("Sample Person", x: 112, top: 128, fontSize: 23, weight: .bold)
text("@fictional_fixture", x: 112, top: 162, fontSize: 13, color: .darkGray)
text("Age 20  |  Languages", x: 26, top: 218, fontSize: 15)
text("Example City  |  Learning", x: 26, top: 250, fontSize: 15)

panel(x: 20, top: 310, width: 380, height: 146,
      color: NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.99, alpha: 1), radius: 10)
text("Introduction", x: 36, top: 326, fontSize: 17, weight: .semibold)
text("Fictional content for navigation testing", x: 36, top: 361, fontSize: 14)
text("Only the interface controls matter.", x: 36, top: 392, fontSize: 14)

panel(x: 18, top: 498, width: 186, height: 45,
      color: NSColor(calibratedRed: 0.84, green: 0.91, blue: 1.0, alpha: 1), radius: 7)
panel(x: 216, top: 498, width: 186, height: 45,
      color: NSColor(calibratedRed: 0.94, green: 0.94, blue: 0.96, alpha: 1), radius: 7)
text("About Me", x: 64, top: 508, fontSize: 19, weight: .semibold)
text("Moments", x: 258, top: 508, fontSize: 19, weight: .semibold)

text("Personal Info", x: 28, top: 576, fontSize: 20, weight: .bold)
text("Languages: English, Spanish", x: 30, top: 612, fontSize: 14)
text("Interests: Music, hiking, reading", x: 30, top: 646, fontSize: 14)
text("MBTI: INTJ (fictional)", x: 30, top: 680, fontSize: 14)

panel(x: 0, top: 850, width: 420, height: 82,
      color: NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.96, alpha: 1))
panel(x: 12, top: 867, width: 108, height: 45,
      color: NSColor(calibratedRed: 0.91, green: 0.92, blue: 0.94, alpha: 1), radius: 7)
panel(x: 129, top: 867, width: 161, height: 45,
      color: NSColor(calibratedRed: 0.8, green: 0.85, blue: 1.0, alpha: 1), radius: 7)
panel(x: 299, top: 867, width: 109, height: 45,
      color: NSColor(calibratedRed: 0.93, green: 0.9, blue: 0.92, alpha: 1), radius: 7)
text("Follow", x: 32, top: 877, fontSize: 16)
text("Say Hi", x: 180, top: 877, fontSize: 16)
text("Gift", x: 335, top: 877, fontSize: 16)

image.unlockFocus()
let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
    ?? (NSTemporaryDirectory() + "visual-agent-synthetic-profile.png"))
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to produce synthetic PNG")
}
try png.write(to: destination, options: .atomic)
print("Synthetic fixture written to \(destination.path) (\(png.count) bytes)")
