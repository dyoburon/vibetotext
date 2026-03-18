import Foundation
import Network

/// Minimal HTTP API server using NWListener — exposes TTS and status
/// endpoints for external tools (e.g. DevGlide MCP voice server).
final class ApiServer {
    private var listener: NWListener?
    let port: UInt16

    init(port: UInt16 = 7865) {
        self.port = port
    }

    // MARK: - Lifecycle

    func start() {
        do {
            let params = NWParameters.tcp
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("[API] Server running on http://127.0.0.1:\(self.port)")
                case .failed(let error):
                    print("[API] Listener failed: \(error)")
                default:
                    break
                }
            }
            listener?.start(queue: .global())
        } catch {
            print("[API] Failed to start: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global())
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            if let error {
                print("[API] Receive error: \(error)")
                connection.cancel()
                return
            }
            guard let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            self?.handleHTTP(request: request, connection: connection)
        }
    }

    // MARK: - HTTP routing

    private func handleHTTP(request: String, connection: NWConnection) {
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection, status: 400, body: #"{"error":"malformed request"}"#)
            return
        }

        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else {
            sendResponse(connection, status: 400, body: #"{"error":"malformed request line"}"#)
            return
        }

        let method = String(parts[0])
        let path = String(parts[1])

        // Handle CORS preflight
        if method == "OPTIONS" {
            sendCORSPreflight(connection)
            return
        }

        switch (method, path) {
        case ("POST", "/api/speak"):
            handleSpeak(request: request, connection: connection)

        case ("POST", "/api/stop"):
            TtsService.shared.stop()
            sendResponse(connection, status: 200, body: #"{"status":"stopped"}"#)

        case ("GET", "/api/status"):
            sendResponse(connection, status: 200, body: #"{"status":"ok","tts_enabled":\#(ConfigStore.shared.ttsEnabled)}"#)

        default:
            sendResponse(connection, status: 404, body: #"{"error":"not found"}"#)
        }
    }

    // MARK: - Endpoint handlers

    private func handleSpeak(request: String, connection: NWConnection) {
        // Extract JSON body after the blank line separating headers from body
        guard let bodyRange = request.range(of: "\r\n\r\n") else {
            sendResponse(connection, status: 400, body: #"{"error":"no body"}"#)
            return
        }
        let bodyStr = String(request[bodyRange.upperBound...])

        guard let bodyData = bodyStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let text = json["text"] as? String, !text.isEmpty else {
            sendResponse(connection, status: 400, body: #"{"error":"missing or empty \"text\" field"}"#)
            return
        }

        TtsService.shared.speak(text)
        sendResponse(connection, status: 200, body: #"{"status":"speaking"}"#)
    }

    // MARK: - Response helpers

    private func sendResponse(_ connection: NWConnection, status: Int, body: String) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 405: statusText = "Method Not Allowed"
        default:  statusText = "Error"
        }

        let response = [
            "HTTP/1.1 \(status) \(statusText)",
            "Content-Type: application/json",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type",
            "Content-Length: \(body.utf8.count)",
            "",
            body,
        ].joined(separator: "\r\n")

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendCORSPreflight(_ connection: NWConnection) {
        let response = [
            "HTTP/1.1 204 No Content",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type",
            "Content-Length: 0",
            "",
            "",
        ].joined(separator: "\r\n")

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
