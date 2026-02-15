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

// ── Persistent holder for the WKWebView ──
// Stored as @StateObject in TreeContainerView so it survives SwiftUI re-renders.
final class TreeWebViewStore: NSObject, ObservableObject, WKScriptMessageHandler {
    static let shared = TreeWebViewStore()

    var webView: WKWebView?
    private var scrollMonitor: Any?
    private var magnifyMonitor: Any?
    private var scrollLogCount = 0

    var pageReady = false
    var introStarted = false
    var pendingWordDataJSON: String = "[]"
    var pendingUniqueWords: Int = 0
    var pendingTotalWords: Int = 0
    var pendingStrataJSON: String = "[]"
    var pendingNebulaEntriesJSON: String = "[]"
    var pendingDailySentimentJSON: String = "[]"
    var pendingVillageStateJSON: String = "{}"
    var currentMood: Float = 0.0
    var currentPopulation: Int = 0
    var currentTrend: Float = 0.0
    var currentTotalWords: Int = 0
    var currentVillageStateJSON: String = "{}"
    var onVillagerKilled: ((Int, String, String) -> Void)?
    var onNebulaQueueUpdate: ((Int) -> Void)?

    override init() {
        super.init()
    }

    func getOrCreateWebView() -> WKWebView {
        if let existing = webView { return existing }

        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.userContentController.add(self, name: "treeReady")
        config.userContentController.add(self, name: "requestVillageUpdate")
        config.userContentController.add(self, name: "villagerKilled")
        config.userContentController.add(self, name: "jsLog")
        config.userContentController.add(self, name: "nebulaQueue")

        let consoleScript = WKUserScript(source: """
            (function(){
                var origLog = console.log, origErr = console.error, origWarn = console.warn;
                console.log = function() {
                    origLog.apply(console, arguments);
                    window.webkit.messageHandlers.jsLog.postMessage('[LOG] ' + Array.from(arguments).join(' '));
                };
                console.error = function() {
                    origErr.apply(console, arguments);
                    window.webkit.messageHandlers.jsLog.postMessage('[ERR] ' + Array.from(arguments).join(' '));
                };
                console.warn = function() {
                    origWarn.apply(console, arguments);
                    window.webkit.messageHandlers.jsLog.postMessage('[WARN] ' + Array.from(arguments).join(' '));
                };
                window.onerror = function(msg, url, line) {
                    window.webkit.messageHandlers.jsLog.postMessage('[ERR] ' + msg + ' at ' + url + ':' + line);
                };
            })();
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(consoleScript)

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.setValue(false, forKey: "drawsBackground")
        wv.allowsMagnification = false
        wv.loadFileURL(treeSceneFileURL, allowingReadAccessTo: treeSceneFileURL.deletingLastPathComponent())
        webView = wv
        installScrollMonitor(for: wv)
        AppState.debugLog("TreeWebViewStore: created new WKWebView")
        return wv
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        if message.name == "treeReady" {
            pageReady = true
            tryInit()
        } else if message.name == "requestVillageUpdate" {
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
        } else if message.name == "nebulaQueue" {
            if let count = message.body as? Int {
                onNebulaQueueUpdate?(count)
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
        let escapedVillageState = pendingVillageStateJSON
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        let js = """
        if(window.initTreeWords) window.initTreeWords(\(pendingWordDataJSON), \(pendingUniqueWords), \(pendingTotalWords), \(pendingStrataJSON), '\(escapedVillageState)');
        if(window.initNebula) window.initNebula(\(pendingNebulaEntriesJSON));
        if(window.initIntroStats) window.initIntroStats(\(pendingDailySentimentJSON));
        """
        webView.evaluateJavaScript(js) { result, error in
            if let error = error {
                AppState.debugLog("initTreeWords JS ERROR: \(error)")
            } else {
                AppState.debugLog("initTreeWords JS OK")
            }
        }
    }

    // MARK: - Scroll handling

    private func installScrollMonitor(for webView: WKWebView) {
        scrollLog("installScrollMonitor called — consume + synthetic dispatch mode")

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self, weak webView] event in
            guard let self, let webView else { return event }
            guard let window = webView.window, event.window === window else { return event }
            let point = webView.convert(event.locationInWindow, from: nil)
            guard webView.bounds.contains(point) else { return event }

            let deltaY = event.scrollingDeltaY
            self.scrollLogCount += 1
            if self.scrollLogCount <= 20 || self.scrollLogCount % 50 == 0 {
                scrollLog("SCROLL #\(self.scrollLogCount) deltaY=\(String(format: "%.2f", deltaY)) phase=\(event.phase.rawValue) momentum=\(event.momentumPhase.rawValue)")
            }
            webView.evaluateJavaScript("window.applyZoom(\(deltaY))", completionHandler: nil)
            return nil
        }

        magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak webView] event in
            guard let webView else { return event }
            guard let window = webView.window, event.window === window else { return event }
            let point = webView.convert(event.locationInWindow, from: nil)
            guard webView.bounds.contains(point) else { return event }

            let delta = event.magnification * 200
            scrollLog("PINCH delta=\(delta)")
            webView.evaluateJavaScript("window.applyZoom(\(delta))", completionHandler: nil)
            return nil
        }
    }

    deinit {
        if let m = scrollMonitor { NSEvent.removeMonitor(m) }
        if let m = magnifyMonitor { NSEvent.removeMonitor(m) }
    }
}

// ── NSViewRepresentable wrapper ──
// Now lightweight — the WKWebView and all state live in TreeWebViewStore.
struct TreeWebView: NSViewRepresentable {
    let store: TreeWebViewStore
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
    let dailySentimentJSON: String
    let onVillagerKilled: (Int, String, String) -> Void

    func makeNSView(context: Context) -> WKWebView {
        AppState.debugLog("TreeWebView.makeNSView called (store has webView: \(store.webView != nil))")
        return store.getOrCreateWebView()
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Store current village data so store can re-send on request
        store.currentMood = mood
        store.currentPopulation = population
        store.currentTrend = recentTrend
        store.currentTotalWords = totalWords
        store.currentVillageStateJSON = villageStateJSON
        store.onVillagerKilled = onVillagerKilled

        // Send word data once the page is ready
        if !store.introStarted && wordDataJSON != "[]" {
            AppState.debugLog("updateNSView: data ready, uniqueWords=\(uniqueWords), totalWords=\(totalWords), jsonLen=\(wordDataJSON.count)")
            store.pendingWordDataJSON = wordDataJSON
            store.pendingUniqueWords = uniqueWords
            store.pendingTotalWords = totalWords
            store.pendingStrataJSON = strataJSON
            store.pendingNebulaEntriesJSON = nebulaEntriesJSON
            store.pendingDailySentimentJSON = dailySentimentJSON
            store.pendingVillageStateJSON = villageStateJSON
            store.tryInit()
        } else if !store.introStarted {
            AppState.debugLog("updateNSView: waiting (wordDataJSON empty, pageReady=\(store.pageReady))")
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

    // No coordinator needed — store handles WKScriptMessageHandler
    class Coordinator {}
    func makeCoordinator() -> Coordinator { Coordinator() }
}
