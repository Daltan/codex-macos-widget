// Convert the upstream SVG to vector PDF for reliable CoreSVG rendering on macOS.
import AppKit
import WebKit
@MainActor
final class MarkRenderer: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
    let output: URL
    init(source: URL, output: URL) throws {
        self.output = output
        super.init()
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        let svg = try String(contentsOf: source, encoding: .utf8)
        web.loadHTMLString("<html><head><style>html,body{margin:0;background:transparent}svg{display:block}</style></head><body>\(svg)</body></html>", baseURL: source.deletingLastPathComponent())
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let config = WKPDFConfiguration()
        config.rect = NSRect(x: 0, y: 0, width: 24, height: 24)
        web.createPDF(configuration: config) { result in
            do { try result.get().write(to: self.output); print("Exported vector PDF"); exit(0) }
            catch { fputs("\(error)\n", stderr); exit(1) }
        }
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let args = CommandLine.arguments
guard args.count == 3 else { fatalError("Usage: swift Scripts/render-codex-mark.swift input.svg output.pdf") }
let renderer = try MainActor.assumeIsolated {
    try MarkRenderer(source: URL(fileURLWithPath: args[1]), output: URL(fileURLWithPath: args[2]))
}
app.run()
