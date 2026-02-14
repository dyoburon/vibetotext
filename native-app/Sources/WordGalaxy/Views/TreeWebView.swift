import SwiftUI
import WebKit

private let debugLogPath = "/tmp/wg_scroll.log"
private func scrollLog(_ msg: String) {
    let line = "\(Date()): \(msg)\n"
    if let fh = FileHandle(forWritingAtPath: debugLogPath) {
        fh.seekToEndOfFile()
        fh.write(line.data(using: .utf8)!)
        fh.closeFile()
    } else {
        FileManager.default.createFile(atPath: debugLogPath, contents: line.data(using: .utf8))
    }
}

struct TreeWebView: NSViewRepresentable {
    let health: Float
    let season: Float
    let streakTier: Int
    let growthProgress: Float
    let wordDataJSON: String
    let uniqueWords: Int
    let totalWords: Int
    let strataJSON: String
    let mood: Float
    let population: Int
    let recentTrend: Float
    let villageStateJSON: String
    let nebulaEntriesJSON: String
    let onVillagerKilled: (Int, String, String) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.userContentController.add(context.coordinator, name: "treeReady")
        config.userContentController.add(context.coordinator, name: "requestVillageUpdate")
        config.userContentController.add(context.coordinator, name: "villagerKilled")
        config.userContentController.add(context.coordinator, name: "jsLog")

        // Capture JS console.log and console.error → forward to Swift
        let consoleScript = WKUserScript(source: """
            (function(){
                var origLog = console.log, origErr = console.error;
                console.log = function() {
                    origLog.apply(console, arguments);
                    window.webkit.messageHandlers.jsLog.postMessage('[LOG] ' + Array.from(arguments).join(' '));
                };
                console.error = function() {
                    origErr.apply(console, arguments);
                    window.webkit.messageHandlers.jsLog.postMessage('[ERR] ' + Array.from(arguments).join(' '));
                };
                window.onerror = function(msg, url, line) {
                    window.webkit.messageHandlers.jsLog.postMessage('[ERR] ' + msg + ' at ' + url + ':' + line);
                };
            })();
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(consoleScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        webView.loadFileURL(treeSceneFileURL, allowingReadAccessTo: treeSceneFileURL.deletingLastPathComponent())
        context.coordinator.webView = webView
        context.coordinator.installScrollMonitor(for: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        let coord = context.coordinator

        // Store current village data so coordinator can re-send on request
        coord.currentMood = mood
        coord.currentPopulation = population
        coord.currentTrend = recentTrend
        coord.currentTotalWords = totalWords
        coord.currentVillageStateJSON = villageStateJSON
        coord.onVillagerKilled = onVillagerKilled

        // Send word data once the page is ready
        if !coord.introStarted && wordDataJSON != "[]" {
            AppState.debugLog("updateNSView: data ready, uniqueWords=\(uniqueWords), totalWords=\(totalWords), jsonLen=\(wordDataJSON.count)")
            coord.pendingWordDataJSON = wordDataJSON
            coord.pendingUniqueWords = uniqueWords
            coord.pendingTotalWords = totalWords
            coord.pendingStrataJSON = strataJSON
            coord.pendingNebulaEntriesJSON = nebulaEntriesJSON
            coord.tryInit()
        } else if !coord.introStarted {
            AppState.debugLog("updateNSView: waiting (wordDataJSON empty, pageReady=\(coord.pageReady))")
        }

        // Ongoing tree data updates
        let escapedVillageJSON = villageStateJSON
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        let js = """
        if(window.updateTreeData) window.updateTreeData(\(health), \(season), \(streakTier), \(growthProgress));
        if(window.updateVillageMood) window.updateVillageMood(\(mood), \(population), \(recentTrend), \(totalWords));
        if(window.updateVillageState) window.updateVillageState('\(escapedVillageJSON)');
        if(window.updateNebula) window.updateNebula(\(nebulaEntriesJSON));
        """
        nsView.evaluateJavaScript(js, completionHandler: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKScriptMessageHandler {
        var webView: WKWebView?
        var scrollMonitor: Any?
        var magnifyMonitor: Any?
        var scrollLogCount = 0
        var pageReady = false

        func installScrollMonitor(for webView: WKWebView) {
            scrollLog("installScrollMonitor called — consume + synthetic dispatch mode")

            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self, weak webView] event in
                guard let self, let webView else { return event }
                guard let window = webView.window, event.window === window else { return event }
                let point = webView.convert(event.locationInWindow, from: nil)
                guard webView.bounds.contains(point) else { return event }

                let deltaY = event.scrollingDeltaY
                self.scrollLogCount += 1
                if self.scrollLogCount <= 10 || self.scrollLogCount % 100 == 0 {
                    scrollLog("SCROLL #\(self.scrollLogCount) deltaY=\(deltaY) — consumed, dispatching synthetic")
                }
                // Dispatch synthetic wheel event on the canvas for OrbitControls
                webView.evaluateJavaScript("""
                    (function(){
                        var c = document.querySelector('canvas');
                        if(c) c.dispatchEvent(new WheelEvent('wheel', {
                            deltaY: \(-deltaY), deltaMode: 0,
                            bubbles: true, cancelable: true
                        }));
                    })();
                """, completionHandler: nil)
                return nil // consume — WKWebView never sees it
            }

            magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak webView] event in
                guard let webView else { return event }
                guard let window = webView.window, event.window === window else { return event }
                let point = webView.convert(event.locationInWindow, from: nil)
                guard webView.bounds.contains(point) else { return event }

                let delta = event.magnification * 200
                scrollLog("PINCH delta=\(delta)")
                webView.evaluateJavaScript("""
                    (function(){
                        var c = document.querySelector('canvas');
                        if(c) c.dispatchEvent(new WheelEvent('wheel', {
                            deltaY: \(-delta), deltaMode: 0,
                            bubbles: true, cancelable: true
                        }));
                    })();
                """, completionHandler: nil)
                return nil
            }
        }

        deinit {
            if let m = scrollMonitor { NSEvent.removeMonitor(m) }
            if let m = magnifyMonitor { NSEvent.removeMonitor(m) }
        }
        var introStarted = false
        var pendingWordDataJSON: String = "[]"
        var pendingUniqueWords: Int = 0
        var pendingTotalWords: Int = 0
        var pendingStrataJSON: String = "[]"
        var pendingNebulaEntriesJSON: String = "[]"
        var currentMood: Float = 0.0
        var currentPopulation: Int = 0
        var currentTrend: Float = 0.0
        var currentTotalWords: Int = 0
        var currentVillageStateJSON: String = "{}"
        var onVillagerKilled: ((Int, String, String) -> Void)?

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "treeReady" {
                pageReady = true
                tryInit()
            } else if message.name == "requestVillageUpdate" {
                // Re-send current village data after intro completes
                let escaped = currentVillageStateJSON
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "'", with: "\\'")
                    .replacingOccurrences(of: "\n", with: "\\n")
                webView?.evaluateJavaScript("""
                    if(window.updateVillageMood) window.updateVillageMood(\(currentMood), \(currentPopulation), \(currentTrend), \(currentTotalWords));
                    if(window.updateVillageState) window.updateVillageState('\(escaped)');
                    """,
                    completionHandler: nil
                )
            } else if message.name == "jsLog" {
                if let msg = message.body as? String {
                    scrollLog("JS: \(msg)")
                }
            } else if message.name == "villagerKilled" {
                if let jsonStr = message.body as? String,
                   let data = jsonStr.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let villagerId = json["villagerId"] as? Int,
                   let name = json["name"] as? String,
                   let role = json["role"] as? String {
                    onVillagerKilled?(villagerId, name, role)
                }
            }
        }

        func tryInit() {
            guard pageReady, !introStarted, pendingWordDataJSON != "[]", let webView else {
                AppState.debugLog("tryInit SKIP: pageReady=\(pageReady), introStarted=\(introStarted), hasData=\(pendingWordDataJSON != "[]"), hasWebView=\(self.webView != nil)")
                return
            }
            introStarted = true
            AppState.debugLog("tryInit FIRING: uniqueWords=\(pendingUniqueWords), totalWords=\(pendingTotalWords)")
            let js = """
            if(window.initTreeWords) window.initTreeWords(\(pendingWordDataJSON), \(pendingUniqueWords), \(pendingTotalWords), \(pendingStrataJSON));
            if(window.initNebula) window.initNebula(\(pendingNebulaEntriesJSON));
            """
            webView.evaluateJavaScript(js) { result, error in
                if let error = error {
                    AppState.debugLog("initTreeWords JS ERROR: \(error)")
                } else {
                    AppState.debugLog("initTreeWords JS OK")
                }
            }
        }
    }
}
