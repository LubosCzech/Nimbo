import AppKit
import ImageIO
import UniformTypeIdentifiers

// Remove the neutral outer matte, preserving all original foreground pixels.
for variant in ["icon-dark", "icon-light", "logo-dark", "logo-light"] {
    let source = URL(fileURLWithPath: "Assets/nimbo-\(variant).png")
    let destination = URL(fileURLWithPath: "Assets/nimbo-\(variant)-transparent.png")
    let input = CGImageSourceCreateWithURL(source as CFURL, nil)!
    let image = CGImageSourceCreateImageAtIndex(input, 0, nil)!
    let w = image.width, h = image.height
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    let dark = variant.hasSuffix("dark")
    pixels.withUnsafeMutableBytes { buffer in
        let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    func background(_ p: Int) -> Bool {
        let i = p * 4
        let r = Int(pixels[i]), g = Int(pixels[i+1]), b = Int(pixels[i+2])
        if dark { return max(r,g,b) < 53 && g-r < 15 && b-r < 19 }
        return min(r,g,b) > 225 && max(r,g,b)-min(r,g,b) < 20
    }
    var seen = [Bool](repeating: false, count: w*h)
    var queue: [Int] = []
    func seed(_ p: Int) {
        if !seen[p] && background(p) { seen[p] = true; queue.append(p) }
    }
    for x in 0..<w { seed(x); seed((h-1)*w+x) }
    for y in 0..<h { seed(y*w); seed(y*w+w-1) }
    // Letter counters are disconnected from the outside matte; only seed to
    // the right of the icon, leaving the white ribbon inside the tile intact.
    if variant.hasPrefix("logo") {
        for y in 0..<h { for x in (w*32/100)..<w { seed(y*w+x) } }
    }
    var head = 0
    while head < queue.count {
        let p = queue[head]; head += 1
        let x = p % w, y = p / w
        if x > 0 { seed(p-1) }; if x+1 < w { seed(p+1) }
        if y > 0 { seed(p-w) }; if y+1 < h { seed(p+w) }
    }
    for p in queue { for channel in 0..<4 { pixels[p*4+channel] = 0 } }
    let data = Data(pixels)
    let output = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: w*4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    let writer = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(writer, output, nil)
    precondition(CGImageDestinationFinalize(writer))
    print("\(variant): transparent pixels \(queue.count) / \(w*h)")
}
