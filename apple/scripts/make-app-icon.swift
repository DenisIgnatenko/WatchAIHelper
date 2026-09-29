#!/usr/bin/env swift
// Draws the app icon (1024 x 1024 PNG) for iOS and watchOS and writes it into both asset catalogs.
//  swift apple/scripts/make-app-icon.swift
//
// Why code instead of a drawn file: the icon is reproducible and reviewable, and changing a colour is a one-line diff.
// Design: the app's deep-blue accent (CompactStyle.accent) as a gradient, a white speech bubble (answers)
// with an AI sparkle inside. Everything important sits in the central circle, because watchOS masks
// the icon to a circle and iOS to a rounded square.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let appleDir = scriptDir.deletingLastPathComponent()
let targets = [
 appleDir.appending(path: "iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png"),
 appleDir.appending(path: "Watch/Assets.xcassets/AppIcon.appiconset/AppIcon.png"),
]

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
 CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

/// Four-pointed star (the usual "AI sparkle"): concave sides between four tips.
func sparkle(center: CGPoint, radius: CGFloat, waist: CGFloat) -> CGPath {
 let path = CGMutablePath()
 let tips = (0..<4).map { i -> CGPoint in
  let angle = CGFloat(i) * .pi / 2 - .pi / 2
  return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
 }
 path.move(to: tips[0])
 for i in 0..<4 {
  let next = tips[(i + 1) % 4]
  // Control point pulled towards the centre makes the sides concave.
  let mid = CGPoint(x: (tips[i].x + next.x) / 2, y: (tips[i].y + next.y) / 2)
  let control = CGPoint(x: center.x + (mid.x - center.x) * waist, y: center.y + (mid.y - center.y) * waist)
  path.addQuadCurve(to: next, control: control)
 }
 path.closeSubpath()
 return path
}

let context = CGContext(
 data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
 space: CGColorSpace(name: CGColorSpace.sRGB)!,
 bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue // icons must be opaque
)!
// Core Graphics has the origin at the bottom left; flip so the coordinates below read top-down.
context.translateBy(x: 0, y: CGFloat(size))
context.scaleBy(x: 1, y: -1)

// Background: deep blue (the app accent) to a darker indigo, top-left to bottom-right.
let background = CGGradient(
 colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
 colors: [rgb(0.20, 0.42, 0.78), rgb(0.10, 0.16, 0.42)] as CFArray,
 locations: [0, 1]
)!
context.drawLinearGradient(background, start: .zero, end: CGPoint(x: size, y: size), options: [])

// Speech bubble with a tail at the bottom left.
// The tail starts inside the body; both parts are filled in one transparency layer, so they merge into one shape
// with one shadow (separate fills avoid winding-rule holes where they overlap).
let body = CGPath(roundedRect: CGRect(x: 232, y: 262, width: 560, height: 440), cornerWidth: 150, cornerHeight: 150,
 transform: nil)
let tail = CGMutablePath()
tail.move(to: CGPoint(x: 310, y: 600))
tail.addLine(to: CGPoint(x: 268, y: 800))
tail.addLine(to: CGPoint(x: 470, y: 660))
tail.closeSubpath()
context.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: rgb(0, 0, 0, 0.30))
context.beginTransparencyLayer(auxiliaryInfo: nil)
context.setFillColor(rgb(0.97, 0.98, 1.0))
context.addPath(body)
context.fillPath()
context.addPath(tail)
context.fillPath()
context.endTransparencyLayer()
context.setShadow(offset: .zero, blur: 0, color: nil)

// Sparkle inside the bubble, in the accent colour; a small one beside it.
context.addPath(sparkle(center: CGPoint(x: 490, y: 482), radius: 150, waist: 0.18))
context.setFillColor(rgb(0.16, 0.33, 0.62))
context.fillPath()
context.addPath(sparkle(center: CGPoint(x: 648, y: 372), radius: 62, waist: 0.2))
context.setFillColor(rgb(0.30, 0.52, 0.88))
context.fillPath()

let image = context.makeImage()!
for url in targets {
 try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
 let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
 CGImageDestinationAddImage(destination, image, nil)
 guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(url.path)") }
 print("Wrote \(url.path)")
}
