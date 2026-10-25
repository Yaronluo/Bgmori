import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Package the approved artwork for Apple's classic app icon sizes.
// iOS uses an opaque square; macOS uses a flat rounded mask and clear margins.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("docs/branding/bgmori-white-original.png")
let catalog = root.appendingPathComponent("Bgmori/Resources/Assets.xcassets/AppIconFlat.appiconset")
guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
    fatalError("Cannot read approved icon artwork")
}

func render(size: Int, mac: Bool, to url: URL) throws {
    let alpha = mac ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast
    guard let context = CGContext(data: nil, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: alpha.rawValue) else {
        fatalError("Cannot create icon bitmap")
    }
    context.interpolationQuality = .high
    let canvas = CGRect(x: 0, y: 0, width: size, height: size)
    if mac {
        let tile = canvas.insetBy(dx: CGFloat(size) * 0.098, dy: CGFloat(size) * 0.098)
        let radius = tile.width * 0.22
        context.addPath(CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(tile)
        context.draw(artwork, in: tile)
    } else {
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(canvas)
        context.draw(artwork, in: canvas)
    }
    guard let output = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Cannot write icon: \(url.path)")
    }
    CGImageDestinationAddImage(destination, output, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("PNG export failed") }
}

let data = try Data(contentsOf: catalog.appendingPathComponent("Contents.json"))
let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
for item in json["images"] as! [[String: String]] {
    guard let filename = item["filename"], let sizeText = item["size"] else { continue }
    let points = Double(sizeText.components(separatedBy: "x")[0])!
    let scale = Double((item["scale"] ?? "1x").replacingOccurrences(of: "x", with: ""))!
    try render(size: Int((points * scale).rounded()), mac: item["idiom"] == "mac",
               to: catalog.appendingPathComponent(filename))
}
try render(size: 1024, mac: false, to: root.appendingPathComponent("docs/branding/bgmori-white.png"))
try render(size: 256, mac: true, to: root.appendingPathComponent("docs/branding/bgmori-white-mac.png"))
print("Generated flat iOS and macOS icon assets")
