// Draws the app icon: a barbell inside an open ring, on a dark background.
// Usage: swift tools/make-app-icon.swift <output.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

// Background: a slight vertical gradient.
let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
    colors: [color(0x2A2E37), color(0x121418)] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: []
)

let sand = color(0xE9D8B8)
let center = CGPoint(x: size / 2, y: size / 2)

// Open ring, like a brush-drawn circle with a gap at the top right.
context.setStrokeColor(sand)
context.setLineWidth(34)
context.setLineCap(.round)
context.addArc(
    center: center, radius: 340,
    startAngle: .pi * 0.42, endAngle: .pi * 0.42 + .pi * 1.8, clockwise: false
)
context.strokePath()

// Barbell: the bar, then two plates on each side.
context.setFillColor(sand)
func fill(width: CGFloat, height: CGFloat, centerX: CGFloat, radius: CGFloat) {
    let rect = CGRect(x: centerX - width / 2, y: center.y - height / 2, width: width, height: height)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.fillPath()
}
fill(width: 560, height: 26, centerX: center.x, radius: 13)
for side: CGFloat in [-1, 1] {
    fill(width: 50, height: 250, centerX: center.x + side * 172, radius: 14)
    fill(width: 40, height: 180, centerX: center.x + side * 228, radius: 12)
}

let image = context.makeImage()!
let url = URL(fileURLWithPath: output)
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Couldn't write \(output)") }
print("Wrote \(output)")
