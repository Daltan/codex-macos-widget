// Render the editable SVG master with WebKit, then produce native macOS icon sizes.
import AppKit
import WebKit

@MainActor
final class IconRenderer: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 1024))
    let destination: URL
    init(source: URL, destination: URL) throws {
        self.destination = destination
        super.init()
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        let svg = try String(contentsOf: source, encoding: .utf8)
        web.loadHTMLString("<html><head><style>html,body{margin:0;background:transparent}svg{display:block}</style></head><body>\(svg)</body></html>", baseURL: source.deletingLastPathComponent())
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = 1024
        web.takeSnapshot(with: config) { image, error in
            guard let image else { fputs("SVG rendering failed: \(String(describing: error))\n", stderr); exit(1) }
            do {
                var entries: [[String: String]] = []
                for size in [16, 32, 128, 256, 512] {
                    for scale in [1, 2] {
                        let pixels = size * scale
                        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                        NSGraphicsContext.saveGraphicsState()
                        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                        NSGraphicsContext.current?.imageInterpolation = .high
                        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
                        NSGraphicsContext.restoreGraphicsState()
                        let name = "icon_\(size)x\(size)@\(scale)x.png"
                        try bitmap.representation(using: .png, properties: [:])!.write(to: self.destination.appendingPathComponent(name))
                        entries.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name])
                    }
                }
                let data = try JSONSerialization.data(withJSONObject: ["images": entries, "info": ["author": "xcode", "version": 1]], options: [.prettyPrinted, .sortedKeys])
                try data.write(to: self.destination.appendingPathComponent("Contents.json"))
                print("Rendered 10 app icon representations from SVG")
                exit(0)
            } catch { fputs("\(error)\n", stderr); exit(1) }
        }
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let args = CommandLine.arguments
guard args.count == 3 else { fatalError("Usage: swift Scripts/render-icon.swift Assets/AppIcon.svg Sources/App/Assets.xcassets/AppIcon.appiconset") }
let renderer = try MainActor.assumeIsolated {
    try IconRenderer(source: URL(fileURLWithPath: args[1]), destination: URL(fileURLWithPath: args[2]))
}
app.run()
