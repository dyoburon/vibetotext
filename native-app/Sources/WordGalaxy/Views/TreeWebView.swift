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

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.userContentController.add(context.coordinator, name: "treeReady")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadFileURL(treeSceneFileURL, allowingReadAccessTo: treeSceneFileURL.deletingLastPathComponent())
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        let coord = context.coordinator

        // Send word data once the page is ready
        if !coord.introStarted && wordDataJSON != "[]" {
            coord.pendingWordDataJSON = wordDataJSON
            coord.pendingUniqueWords = uniqueWords
            coord.pendingTotalWords = totalWords
            coord.tryInit()
        }

        // Ongoing tree data updates
        let js = "if(window.updateTreeData) window.updateTreeData(\(health), \(season), \(streakTier), \(growthProgress))"
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

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "treeReady" {
                pageReady = true
                tryInit()
            }
        }

        func tryInit() {
            guard pageReady, !introStarted, pendingWordDataJSON != "[]", let webView else { return }
            introStarted = true
            webView.evaluateJavaScript(
                "if(window.initTreeWords) window.initTreeWords(\(pendingWordDataJSON), \(pendingUniqueWords), \(pendingTotalWords))",
                completionHandler: nil
            )
        }
    }
}
