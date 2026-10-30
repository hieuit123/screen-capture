import AppKit
import ScreenCaptureKit

enum FullPageError: LocalizedError {
    case noBrowser
    case automationDenied(String)
    case scriptFailed(String, String)
    case windowNotFound(String)
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .noBrowser:
            "Full-page screenshots need Google Chrome (or Chromium, Brave, Edge) to be open with a web page."
        case .automationDenied(let app):
            "ScreenCapture isn't allowed to control \(app). Enable it in System Settings › Privacy & Security › Automation, then try again."
        case .scriptFailed(let app, let message):
            "\(app) couldn't run the page script: \(message)\n\nMake sure “View › Developer › Allow JavaScript from Apple Events” is turned on in \(app), and that the tab shows a normal web page."
        case .windowNotFound(let app):
            "The front \(app) window isn't visible on this screen. Bring it forward and try again."
        case .captureFailed:
            "Couldn't build the full-page image."
        }
    }
}

/// Scrolls the active tab of a Chromium-based browser via AppleScript, captures each viewport and stitches them.
@MainActor
enum FullPageCapture {
    private static let browserIDs = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "org.chromium.Chromium", "com.brave.Browser", "com.microsoft.edgemac",
    ]
    /// Keeps memory and image-encoder limits in check on endless pages.
    private static let maxPixelHeight = 32_000
    private static let settleDelay = Duration.milliseconds(250)
    /// Size in CSS pixels of the marker pinned to the viewport's top-left corner.
    nonisolated private static let markerSize = 12.0

    /// Window geometry in screen points; scroll region (`rx`…`rh`) in CSS pixels relative to the viewport.
    private struct Metrics: Decodable {
        let sx, sy, ow, oh, iw, ih, dpr, rx, ry, rw, rh: Double
    }

    private struct PageState: Decodable {
        let y, h: Double
    }

    /// `scale` shrinks the output (1 = native resolution).
    static func capture(scale outputScale: CGFloat = 1) async throws -> CGImage {
        let browser = try findBrowser()
        let name = browser.localizedName ?? "Chrome"
        let bundleID = browser.bundleIdentifier!

        func js(_ code: String) throws -> String { try runJavaScript(code, bundleID: bundleID, appName: name) }
        func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
            guard let value = try? JSONDecoder().decode(type, from: Data(json.utf8)) else {
                throw FullPageError.scriptFailed(name, "Unexpected response from the page.")
            }
            return value
        }

        let metrics = try decode(Metrics.self, try js(Scripts.prepare))
        defer { _ = try? js(Scripts.restore) }

        let window = try await findWindow(pid: browser.processIdentifier, metrics: metrics, appName: name)
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let target = CaptureTarget(
            filter: filter, sourceRect: nil,
            nativePixelSize: CGSize(width: filter.contentRect.width * scale, height: filter.contentRect.height * scale),
            areaSelection: nil)

        // Side panels, vertical tabs and docked DevTools move the page inside the window, so find it on screen.
        try await Task.sleep(for: settleDelay)
        let probe = try await ScreenshotService.capture(target: target, showsCursor: false)
        let dpr = CGFloat(metrics.dpr)
        let pixelScale = CGFloat(probe.width) / window.frame.width
        let viewportOrigin = locateMarker(in: probe, size: Int(markerSize * dpr))
            ?? CGPoint(x: 0, y: ((metrics.oh - metrics.ih) * pixelScale).rounded())
        let region = CGRect(x: viewportOrigin.x + metrics.rx * dpr, y: viewportOrigin.y + metrics.ry * dpr,
                            width: metrics.rw * dpr, height: metrics.rh * dpr).integral

        var state = try decode(PageState.self, try js(Scripts.scroll(to: 0)))
        try await Task.sleep(for: settleDelay)

        var frames: [(image: CGImage, offset: Int)] = []
        while true {
            let shot = try await ScreenshotService.capture(target: target, showsCursor: false)
            let crop = region.intersection(CGRect(x: 0, y: 0, width: shot.width, height: shot.height))
            guard let frame = shot.cropping(to: crop) else { throw FullPageError.captureFailed }
            let offset = Int((state.y * dpr).rounded())
            frames.append((frame, offset))

            // Fixed/sticky headers and banners would repeat on every slice; keep them only in the first one.
            if frames.count == 1 { _ = try js(Scripts.hideFixed) }

            let bottom = state.y + metrics.rh
            if bottom >= state.h - 1 || CGFloat(offset + frame.height) * outputScale >= CGFloat(maxPixelHeight) { break }
            let next = try decode(PageState.self, try js(Scripts.scroll(to: bottom)))
            guard next.y > state.y else { break }
            state = next
            try await Task.sleep(for: settleDelay)
        }

        guard let last = frames.last, let first = frames.first else { throw FullPageError.captureFailed }
        return try stitch(frames, width: first.image.width, height: last.offset + last.image.height, scale: outputScale)
    }

    /// Top-left of the magenta marker in image pixels.
    private static func locateMarker(in image: CGImage, size: Int) -> CGPoint? {
        let w = image.width, h = image.height
        guard size >= 4,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)

        // Bitmap context memory starts with the top row.
        func isMarker(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, y >= 0, x < w, y < h else { return false }
            let i = (y * w + x) * 4
            return px[i] > 220 && px[i + 1] < 50 && px[i + 2] > 220
        }
        let step = max(1, size / 2)
        for y in stride(from: 0, to: h, by: step) {
            for x in stride(from: 0, to: w, by: step) where isMarker(x, y) {
                var left = x, top = y
                while isMarker(left - 1, top) { left -= 1 }
                while isMarker(left, top - 1) { top -= 1 }
                let far = size - 3
                if isMarker(left + far, top) && isMarker(left, top + far) && isMarker(left + far, top + far) {
                    return CGPoint(x: left, y: top)
                }
            }
        }
        return nil
    }

    private static func findBrowser() throws -> NSRunningApplication {
        let isBrowser = { (app: NSRunningApplication) in browserIDs.contains(app.bundleIdentifier ?? "") }
        if let front = NSWorkspace.shared.frontmostApplication, isBrowser(front) { return front }
        guard let running = NSWorkspace.shared.runningApplications.first(where: isBrowser) else {
            throw FullPageError.noBrowser
        }
        return running
    }

    /// Matches the browser's front window (as reported by the page) to a ScreenCaptureKit window.
    private static func findWindow(pid: pid_t, metrics: Metrics, appName: String) async throws -> SCWindow {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw CaptureError.permissionDenied
        }
        let expected = CGRect(x: metrics.sx, y: metrics.sy, width: metrics.ow, height: metrics.oh)
        let candidates = content.windows.filter {
            $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.isOnScreen
                && $0.frame.width >= 100 && $0.frame.height >= 100
        }
        func distance(_ frame: CGRect) -> CGFloat {
            abs(frame.minX - expected.minX) + abs(frame.minY - expected.minY)
                + abs(frame.width - expected.width) + abs(frame.height - expected.height)
        }
        guard let best = candidates.min(by: { distance($0.frame) < distance($1.frame) }),
              distance(best.frame) < 40 else {
            throw FullPageError.windowNotFound(appName)
        }
        return best
    }

    private static func stitch(_ frames: [(image: CGImage, offset: Int)], width: Int, height: Int,
                               scale: CGFloat) throws -> CGImage {
        let outWidth = max(1, Int((CGFloat(width) * scale).rounded()))
        let outHeight = max(1, min(Int((CGFloat(height) * scale).rounded()), maxPixelHeight))
        guard let context = CGContext(
            data: nil, width: outWidth, height: outHeight, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { throw FullPageError.captureFailed }
        context.interpolationQuality = .high
        for frame in frames {
            // CoreGraphics has a bottom-left origin; offsets are measured from the top of the page.
            let rect = CGRect(x: 0, y: CGFloat(outHeight) - CGFloat(frame.offset + frame.image.height) * scale,
                              width: CGFloat(frame.image.width) * scale, height: CGFloat(frame.image.height) * scale)
            context.draw(frame.image, in: rect)
        }
        guard let image = context.makeImage() else { throw FullPageError.captureFailed }
        return image
    }

    private static func runJavaScript(_ code: String, bundleID: String, appName: String) throws -> String {
        let escaped = code.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "tell application id \"\(bundleID)\" to execute active tab of front window javascript \"\(escaped)\""
        guard let script = NSAppleScript(source: source) else { throw FullPageError.scriptFailed(appName, "Invalid script.") }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            if (error[NSAppleScript.errorNumber] as? Int) == -1743 { throw FullPageError.automationDenied(appName) }
            throw FullPageError.scriptFailed(appName, error[NSAppleScript.errorMessage] as? String ?? "Unknown error.")
        }
        return result.stringValue ?? ""
    }

    private enum Scripts {
        /// Picks what to scroll: the document, or (for apps like Jira or Gmail) the largest scrollable element.
        /// Adds a magenta marker at the viewport's top-left so the page can be located in the window capture.
        static let prepare = """
        (function(){var d=document.documentElement,se=document.scrollingElement||d;\
        if(!document.getElementById('__scFullPage')){var s=document.createElement('style');s.id='__scFullPage';\
        s.textContent='html,body,[data-sc-scroll]{scrollbar-width:none!important;scroll-behavior:auto!important}\
        html::-webkit-scrollbar,body::-webkit-scrollbar,[data-sc-scroll]::-webkit-scrollbar{display:none!important}';\
        (document.head||d).appendChild(s);}\
        window.__scScroll=[window.scrollX,window.scrollY];\
        var y0=window.scrollY;window.scrollTo(0,y0+1);var docScrolls=se.scrollHeight>window.innerHeight*1.25&&(window.scrollY!==y0||y0>0);\
        window.scrollTo(0,y0);var el=null;\
        if(!docScrolls&&document.body){var area=0,all=document.body.getElementsByTagName('*');\
        for(var i=0;i<all.length;i++){var e=all[i];if(e.scrollHeight<=e.clientHeight+1||e.clientHeight<100)continue;\
        var o=getComputedStyle(e).overflowY;if(o!=='auto'&&o!=='scroll'&&o!=='overlay')continue;\
        var b=e.getBoundingClientRect();var w=Math.max(0,Math.min(b.right,innerWidth)-Math.max(b.left,0));\
        var hh=Math.max(0,Math.min(b.bottom,innerHeight)-Math.max(b.top,0));if(w*hh>area){area=w*hh;el=e;}}}\
        window.__scEl=el;var rx=0,ry=0,rw=Math.min(d.clientWidth,innerWidth),rh=Math.min(d.clientHeight,innerHeight);\
        if(el){window.__scElScroll=el.scrollTop;el.setAttribute('data-sc-scroll','');var r=el.getBoundingClientRect();\
        rx=Math.max(0,r.left+el.clientLeft);ry=Math.max(0,r.top+el.clientTop);\
        rw=Math.min(el.clientWidth,innerWidth-rx);rh=Math.min(el.clientHeight,innerHeight-ry);}\
        var m=document.getElementById('__scMarker');if(!m){m=document.createElement('div');m.id='__scMarker';d.appendChild(m);}\
        m.style.cssText='position:fixed!important;left:0!important;top:0!important;width:\(markerSize)px!important;\
        height:\(markerSize)px!important;background:#ff00ff!important;z-index:2147483647!important;pointer-events:none!important;\
        margin:0!important;border:0!important;opacity:1!important;transform:none!important';\
        return JSON.stringify({sx:window.screenX,sy:window.screenY,ow:window.outerWidth,oh:window.outerHeight,\
        iw:innerWidth,ih:innerHeight,dpr:window.devicePixelRatio,rx:rx,ry:ry,rw:rw,rh:rh});})()
        """

        static func scroll(to y: Double) -> String {
            """
            (function(){var m=document.getElementById('__scMarker');if(m){m.remove();}var e=window.__scEl;\
            if(e){e.scrollTo({top:\(y),behavior:'instant'});return JSON.stringify({y:e.scrollTop,h:e.scrollHeight});}\
            window.scrollTo({top:\(y),left:0,behavior:'instant'});\
            return JSON.stringify({y:window.scrollY,h:Math.max(document.documentElement.scrollHeight,\
            document.body?document.body.scrollHeight:0)});})()
            """
        }

        /// Skips fixed elements that contain the scrolled element (e.g. a modal dialog).
        static let hideFixed = """
        (function(){var h=[],t=window.__scEl;var all=document.body?document.body.getElementsByTagName('*'):[];\
        for(var i=0;i<all.length;i++){var e=all[i];if(t&&e.contains(t))continue;var p=getComputedStyle(e).position;\
        if(p==='fixed'||p==='sticky'){h.push([e,e.style.getPropertyValue('visibility'),e.style.getPropertyPriority('visibility')]);\
        e.style.setProperty('visibility','hidden','important');}}window.__scHidden=h;return String(h.length);})()
        """

        static let restore = """
        (function(){(window.__scHidden||[]).forEach(function(x){x[0].style.setProperty('visibility',x[1],x[2]);});\
        window.__scHidden=null;var e=window.__scEl;if(e){e.scrollTo({top:window.__scElScroll||0,behavior:'instant'});\
        e.removeAttribute('data-sc-scroll');}window.__scEl=null;\
        var p=window.__scScroll;if(p){window.scrollTo({top:p[1],left:p[0],behavior:'instant'});}\
        var m=document.getElementById('__scMarker');if(m){m.remove();}\
        var s=document.getElementById('__scFullPage');if(s){s.remove();}return 'ok';})()
        """
    }
}
