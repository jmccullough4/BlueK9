import Foundation
import Network

final class WebControlServer {
    enum WebCommand {
        case startScan(ScanMode)
        case stopScan
    }

    private let port: NWEndpoint.Port
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.bluek9.webserver")
    private let stateProvider: () -> MissionState
    private let commandHandler: (WebCommand) -> Void
    private let logURLProvider: () -> URL
    private let encoder: JSONEncoder

    init(port: UInt16 = 8080, stateProvider: @escaping () -> MissionState, commandHandler: @escaping (WebCommand) -> Void, logURLProvider: @escaping () -> URL) {
        self.port = NWEndpoint.Port(rawValue: port) ?? 8080
        self.stateProvider = stateProvider
        self.commandHandler = commandHandler
        self.logURLProvider = logURLProvider
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
    }

    func start() {
        queue.async { [weak self] in
            guard let self, listener == nil else { return }
            do {
                let listener = try NWListener(using: .tcp, on: port)
                listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection: connection)
                }
                listener.start(queue: queue)
                self.listener = listener
                print("WebControlServer started on port \(port)")
            } catch {
                print("Failed to start WebControlServer: \(error)")
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self, let data = data, !data.isEmpty else {
                if isComplete { connection.cancel() }
                return
            }

            let request = String(decoding: data, as: UTF8.self)
            let response = self.handle(request: request)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func handle(request: String) -> Data {
        guard let requestLine = request.components(separatedBy: "\r\n").first else {
            return httpResponse(status: "400 Bad Request", body: Data())
        }
        let components = requestLine.split(separator: " ")
        guard components.count >= 2 else {
            return httpResponse(status: "400 Bad Request", body: Data())
        }

        let method = String(components[0])
        let path = String(components[1])

        switch (method, path) {
        case ("GET", "/"):
            return htmlResponse()
        case ("GET", "/api/state"):
            return stateResponse()
        case ("POST", _):
            return handlePost(path: path)
        case ("GET", "/api/log"):
            return logResponse()
        default:
            return httpResponse(status: "404 Not Found", body: Data("Not found".utf8))
        }
    }

    private func handlePost(path: String) -> Data {
        if path.hasPrefix("/api/scan/start") {
            guard let urlComponents = URLComponents(string: path),
                  let modeQuery = urlComponents.queryItems?.first(where: { $0.name == "mode" })?.value,
                  let mode = ScanMode(rawValue: modeQuery) else {
                return httpResponse(status: "400 Bad Request", body: Data("Invalid mode".utf8))
            }
            commandHandler(.startScan(mode))
            return httpResponse(status: "200 OK", body: Data("Starting scan in \(mode.rawValue)".utf8))
        }

        if path == "/api/scan/stop" {
            commandHandler(.stopScan)
            return httpResponse(status: "200 OK", body: Data("Scan stopped".utf8))
        }

        return httpResponse(status: "404 Not Found", body: Data("Unknown command".utf8))
    }

    private func stateResponse() -> Data {
        let missionState = stateProvider()
        guard let data = try? encoder.encode(missionState) else {
            return httpResponse(status: "500 Internal Server Error", body: Data("Failed to encode state".utf8))
        }
        return httpResponse(status: "200 OK", body: data, contentType: "application/json")
    }

    private func logResponse() -> Data {
        let url = logURLProvider()
        guard let data = try? Data(contentsOf: url) else {
            return httpResponse(status: "404 Not Found", body: Data("Log file unavailable".utf8))
        }
        return httpResponse(status: "200 OK", body: data, contentType: "application/json", additionalHeaders: ["Content-Disposition": "attachment; filename=mission-log.json"])
    }

    private func htmlResponse() -> Data {
        let html = """
        <!DOCTYPE html>
        <html lang=\"en\">
        <head>
            <meta charset=\"utf-8\" />
            <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
            <title>BlueK9 Mission Console</title>
            <style>
                :root {
                    color-scheme: dark;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
                    background-color: #0b0d11;
                    color: #f0f5ff;
                }
                body {
                    margin: 0;
                    padding: 2rem;
                    background: linear-gradient(180deg, #0b0d11 0%, #121826 100%);
                }
                h1 { font-size: 1.8rem; margin-bottom: 0.5rem; }
                .card {
                    background: rgba(17, 24, 39, 0.75);
                    border: 1px solid rgba(59, 130, 246, 0.2);
                    border-radius: 16px;
                    padding: 1.5rem;
                    margin-bottom: 1.5rem;
                    box-shadow: 0 15px 35px rgba(0, 0, 0, 0.2);
                }
                button {
                    background: linear-gradient(135deg, #2563eb, #1d4ed8);
                    border: none;
                    border-radius: 999px;
                    padding: 0.75rem 1.5rem;
                    color: white;
                    font-weight: 600;
                    cursor: pointer;
                    transition: transform 0.2s ease, box-shadow 0.2s ease;
                    margin-right: 0.5rem;
                }
                button.secondary {
                    background: rgba(148, 163, 184, 0.2);
                    color: #e2e8f0;
                }
                button:hover { transform: translateY(-2px); box-shadow: 0 10px 25px rgba(37, 99, 235, 0.35); }
                table {
                    width: 100%;
                    border-collapse: collapse;
                    margin-top: 1rem;
                }
                th, td {
                    text-align: left;
                    padding: 0.5rem 0.75rem;
                    border-bottom: 1px solid rgba(148, 163, 184, 0.15);
                }
                th { color: #94a3b8; font-size: 0.85rem; }
                .status-pill {
                    display: inline-flex;
                    align-items: center;
                    padding: 0.25rem 0.75rem;
                    border-radius: 999px;
                    font-size: 0.75rem;
                    background: rgba(59, 130, 246, 0.2);
                    color: #bfdbfe;
                }
                .log {
                    max-height: 260px;
                    overflow-y: auto;
                    font-family: "SFMono-Regular", ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
                    font-size: 0.8rem;
                    background: rgba(15, 23, 42, 0.8);
                    padding: 1rem;
                    border-radius: 12px;
                    border: 1px solid rgba(59, 130, 246, 0.2);
                }
                .log-entry { margin-bottom: 0.75rem; }
                .log-entry time { color: #64748b; margin-right: 0.5rem; }
                .controls { margin-top: 1rem; }
            </style>
        </head>
        <body>
            <h1>BlueK9 Mission Console</h1>
            <div class=\"card\">
                <h2>Scan Control</h2>
                <div class=\"controls\">
                    <button onclick=\"startScan('passive')\">Start Passive</button>
                    <button onclick=\"startScan('active')\">Start Active</button>
                    <button class=\"secondary\" onclick=\"stopScan()\">Stop Scan</button>
                    <a href=\"/api/log\" class=\"secondary\" style=\"margin-left:1rem;color:#bfdbfe;text-decoration:none;\">Download Log</a>
                </div>
                <p id=\"scanStatus\" style=\"margin-top:1rem;color:#bfdbfe;\"></p>
            </div>
            <div class=\"card\">
                <h2>Devices</h2>
                <table>
                    <thead>
                        <tr><th>Name</th><th>Signal</th><th>Last Seen</th><th>State</th></tr>
                    </thead>
                    <tbody id=\"deviceTable\"></tbody>
                </table>
            </div>
            <div class=\"card\">
                <h2>Mission Log</h2>
                <div id=\"logView\" class=\"log\"></div>
            </div>
            <script>
                async function fetchState() {
                    const response = await fetch('/api/state');
                    if (!response.ok) return;
                    const state = await response.json();
                    document.getElementById('scanStatus').textContent = state.isScanning ? `Scanning (${state.scanMode})` : 'Idle';
                    const table = document.getElementById('deviceTable');
                    table.innerHTML = state.devices.map(device => `<tr><td>${device.name}</td><td>${device.signalDescription}</td><td>${new Date(device.lastSeen).toLocaleTimeString()}</td><td><span class=\"status-pill\">${device.state}</span></td></tr>`).join('');
                    const logView = document.getElementById('logView');
                    logView.innerHTML = state.logEntries.slice(-25).reverse().map(entry => `<div class=\"log-entry\"><time>${new Date(entry.timestamp).toLocaleTimeString()}</time><span>[${entry.type}] ${entry.message}</span></div>`).join('');
                }
                async function startScan(mode) {
                    await fetch(`/api/scan/start?mode=${mode}`, { method: 'POST' });
                    setTimeout(fetchState, 500);
                }
                async function stopScan() {
                    await fetch('/api/scan/stop', { method: 'POST' });
                    setTimeout(fetchState, 500);
                }
                setInterval(fetchState, 3000);
                fetchState();
            </script>
        </body>
        </html>
        """
        return httpResponse(status: "200 OK", body: Data(html.utf8), contentType: "text/html; charset=utf-8")
    }

    private func httpResponse(status: String, body: Data, contentType: String = "text/plain; charset=utf-8", additionalHeaders: [String: String] = [:]) -> Data {
        var headers = [
            "HTTP/1.1 \(status)",
            "Content-Length: \(body.count)",
            "Content-Type: \(contentType)",
            "Access-Control-Allow-Origin: *",
            "Connection: close"
        ]
        additionalHeaders.forEach { headers.append("\($0): \($1)") }
        let headerString = headers.joined(separator: "\r\n") + "\r\n\r\n"
        var response = Data(headerString.utf8)
        response.append(body)
        return response
    }
}
