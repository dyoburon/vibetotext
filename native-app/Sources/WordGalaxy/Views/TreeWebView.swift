import SwiftUI
import WebKit

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
    let onClearPendingDeaths: () -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.userContentController.add(context.coordinator, name: "treeReady")
        config.userContentController.add(context.coordinator, name: "requestVillageUpdate")
        config.userContentController.add(context.coordinator, name: "clearPendingDeaths")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadFileURL(treeSceneFileURL, allowingReadAccessTo: treeSceneFileURL.deletingLastPathComponent())
        context.coordinator.webView = webView
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
        coord.onClearPendingDeaths = onClearPendingDeaths

        // Send word data once the page is ready
        if !coord.introStarted && wordDataJSON != "[]" {
            coord.pendingWordDataJSON = wordDataJSON
            coord.pendingUniqueWords = uniqueWords
            coord.pendingTotalWords = totalWords
            coord.pendingStrataJSON = strataJSON
            coord.tryInit()
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
        """
        nsView.evaluateJavaScript(js, completionHandler: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKScriptMessageHandler {
        var webView: WKWebView?
        var pageReady = false
        var introStarted = false
        var pendingWordDataJSON: String = "[]"
        var pendingUniqueWords: Int = 0
        var pendingTotalWords: Int = 0
        var pendingStrataJSON: String = "[]"
        var currentMood: Float = 0.0
        var currentPopulation: Int = 0
        var currentTrend: Float = 0.0
        var currentTotalWords: Int = 0
        var currentVillageStateJSON: String = "{}"
        var onClearPendingDeaths: (() -> Void)?

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
            } else if message.name == "clearPendingDeaths" {
                onClearPendingDeaths?()
            }
        }

        func tryInit() {
            guard pageReady, !introStarted, pendingWordDataJSON != "[]", let webView else { return }
            introStarted = true
            webView.evaluateJavaScript(
                "if(window.initTreeWords) window.initTreeWords(\(pendingWordDataJSON), \(pendingUniqueWords), \(pendingTotalWords), \(pendingStrataJSON))",
                completionHandler: nil
            )
        }
    }
}
