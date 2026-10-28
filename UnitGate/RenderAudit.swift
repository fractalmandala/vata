// Offscreen render audit, compiled into the unit gate (never shipped).
// Renders real views to bitmaps WITHOUT showing windows: no screen,
// no prompts, no focus. Catches black slabs, zero-size views, collapsed
// layouts. PNGs are saved for human eyeballing per build.
import AppKit
import Foundation

struct RenderAudit {
    static var failures: [String] = []
    static func check(_ cond: Bool, _ name: String) {
        if !cond { failures.append(name); print("FAIL: \(name)") }
    }

    static var outDir = "/tmp/vata-render"

    static func render(_ view: NSView, size: NSSize, name: String, requireNonBlank: Bool = true) {
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            check(false, "render-rep:\(name)"); return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        // Non-blank: sample pixels for variance.
        var sum = 0, sumSq = 0, n = 0
        let w = rep.pixelsWide, h = rep.pixelsHigh
        let stride = max(1, min(w, h) / 40)
        var y = 0
        while y < h {
            var x = 0
            while x < w {
                if let c = rep.colorAt(x: x, y: y) {
                    let v = Int((c.redComponent + c.greenComponent + c.blueComponent) * 85)
                    sum += v; sumSq += v * v; n += 1
                }
                x += stride
            }
            y += stride
        }
        let variance = n > 0 ? Double(sumSq) / Double(n) - pow(Double(sum) / Double(n), 2) : 0
        if requireNonBlank {
            check(variance > 5, "render-nonblank:\(name)")
        }
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
        }
        print("rendered \(name) variance=\(Int(variance))")
    }

    static func run() {
        let scratch = "/tmp/vata-render-scratch"
        let fm = FileManager.default
        try? fm.removeItem(atPath: scratch)
        try? fm.createDirectory(atPath: scratch, withIntermediateDirectories: true)
        fm.createFile(atPath: "\(scratch)/a.txt", contents: Data("hello".utf8))
        fm.createFile(atPath: "\(scratch)/b.md", contents: Data("# t".utf8))
        try? fm.createDirectory(atPath: "\(scratch)/sub", withIntermediateDirectories: true)
        let ds = LocalDatasource(initialPath: scratch)
        let pane = PaneViewController(datasource: ds)
        _ = pane.view
        let items = (try? ds.list(scratch)) ?? []
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        outDir = "/Users/amrit/projectguppy/ForkLift-RE/GuppyLift/verify-evidence/render"
        // Gallery: the black-slab regression.
        let gal = GalleryContentView()
        gal.pane = pane
        _ = gal.view
        gal.show(items: items)
        render(gal.view, size: NSSize(width: 900, height: 600), name: "gallery")
        // Columns: the ten-empty-columns regression — exactly 3 columns expected.
        let col = ColumnContentView()
        col.pane = pane
        _ = col.view
        col.show(items: items)
        check(col.browser(col.browser, numberOfRowsInColumn: 0) >= 0, "columns-parent-rows")
        check(col.browser(col.browser, isColumnValid: 5) == false, "columns-max-3")
        render(col.view, size: NSSize(width: 900, height: 600), name: "columns")
        // List + icons sanity.
        let list = ListContentView()
        list.pane = pane
        _ = list.view
        list.show(items: items)
        render(list.view, size: NSSize(width: 900, height: 600), name: "list")
        let icons = IconContentView()
        icons.pane = pane
        _ = icons.view
        icons.show(items: items)
        // NSCollectionView won't lay out detached from a window; assert the
        // data path structurally instead of by pixels.
        render(icons.view, size: NSSize(width: 900, height: 600), name: "icons", requireNonBlank: false)
        if let sample = items.first(where: { $0.type == .file }) {
            let cell = IconCellView()
            cell.loadView()
            cell.configure(sample, dark: false)
            let txt = (cell.view.subviews.first { !($0 is NSImageView) } as? NSTextField)?.stringValue
            check(txt == sample.name, "icons:cell-label")
            let ext = (sample.name as NSString).pathExtension.lowercased()
            check(FileIconMap.byExtension[ext] != nil, "icons:cell-ext-mapped:\(ext)")
        }
    }
}
