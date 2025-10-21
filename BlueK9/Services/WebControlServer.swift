import Foundation
import Network
#if canImport(UIKit)
import UIKit
#endif

final class WebControlServer {
    enum WebCommand {
        case startScan(ScanMode)
        case stopScan
        case setTarget(UUID)
        case clearTarget
        case activeGeo(UUID)
        case getInfo(UUID)
        case setCoordinatePreference(CoordinateDisplayMode)
    }

    private let port: NWEndpoint.Port
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.bluek9.webserver")
    private let stateProvider: () -> MissionState
    private let commandHandler: (WebCommand) -> Void
    private let logURLProvider: () -> URL
    private let encoder: JSONEncoder
#if canImport(UIKit)
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
#endif

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
#if canImport(UIKit)
                self.beginBackgroundTaskIfNeeded()
#endif
            } catch {
                print("Failed to start WebControlServer: \(error)")
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
#if canImport(UIKit)
        endBackgroundTask()
#endif
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

#if canImport(UIKit)
    private func beginBackgroundTaskIfNeeded() {
        DispatchQueue.main.async {
            guard self.backgroundTaskIdentifier == .invalid else { return }
            self.backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "WebControlServer") {
                self.endBackgroundTask()
            }
        }
    }

    private func endBackgroundTask() {
        DispatchQueue.main.async {
            if self.backgroundTaskIdentifier != .invalid {
                UIApplication.shared.endBackgroundTask(self.backgroundTaskIdentifier)
                self.backgroundTaskIdentifier = .invalid
            }
        }
    }
#endif

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

        if path == "/api/device/clear-target" {
            commandHandler(.clearTarget)
            return httpResponse(status: "200 OK", body: Data("Target cleared".utf8))
        }

        if path.hasPrefix("/api/device/") {
            let components = path.split(separator: "/")
            guard components.count >= 4, let uuid = UUID(uuidString: String(components[2])) else {
                return httpResponse(status: "400 Bad Request", body: Data("Invalid device identifier".utf8))
            }
            let action = components[3]
            switch action {
            case "target":
                commandHandler(.setTarget(uuid))
                return httpResponse(status: "200 OK", body: Data("Target locked".utf8))
            case "active-geo":
                commandHandler(.activeGeo(uuid))
                return httpResponse(status: "200 OK", body: Data("Active geo engaged".utf8))
            case "info":
                commandHandler(.getInfo(uuid))
                return httpResponse(status: "200 OK", body: Data("Device interrogation started".utf8))
            default:
                return httpResponse(status: "404 Not Found", body: Data("Unknown device action".utf8))
            }
        }

        if path.hasPrefix("/api/coordinate-mode") {
            guard let urlComponents = URLComponents(string: path),
                  let modeQuery = urlComponents.queryItems?.first(where: { $0.name == "mode" })?.value,
                  let mode = CoordinateDisplayMode(rawValue: modeQuery) else {
                return httpResponse(status: "400 Bad Request", body: Data("Invalid coordinate mode".utf8))
            }
            commandHandler(.setCoordinatePreference(mode))
            return httpResponse(status: "200 OK", body: Data("Coordinate mode updated".utf8))
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
            <link rel=\"stylesheet\" href=\"https://unpkg.com/leaflet@1.9.4/dist/leaflet.css\" integrity=\"sha256-o9N1j7kP0tE2kNvztNFVQVHNEqbb0w7YLMwZsZ1pPPA=\" crossorigin=\"\" />
            <style>
                :root {
                    color-scheme: dark;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
                    background-color: #05070d;
                    color: #f8fafc;
                }
                body {
                    margin: 0;
                    padding: 2rem;
                    background: radial-gradient(circle at top, rgba(37, 99, 235, 0.15), transparent 45%), #05070d;
                }
                h1 { font-size: 1.9rem; margin-bottom: 0.5rem; }
                h2 { font-size: 1.2rem; margin-bottom: 0.75rem; }
                .subtle { color: #94a3b8; font-size: 0.9rem; }
                .card {
                    background: rgba(17, 24, 39, 0.82);
                    border: 1px solid rgba(96, 165, 250, 0.25);
                    border-radius: 18px;
                    padding: 1.5rem;
                    margin-bottom: 1.5rem;
                    box-shadow: 0 20px 45px rgba(15, 23, 42, 0.45);
                }
                button {
                    background: linear-gradient(135deg, #2563eb, #1d4ed8);
                    border: none;
                    border-radius: 999px;
                    padding: 0.65rem 1.4rem;
                    color: white;
                    font-weight: 600;
                    cursor: pointer;
                    transition: transform 0.2s ease, box-shadow 0.2s ease;
                    margin-right: 0.5rem;
                }
                button.secondary {
                    background: rgba(148, 163, 184, 0.18);
                    color: #e2e8f0;
                }
                button.danger {
                    background: rgba(248, 113, 113, 0.18);
                    color: #fecaca;
                }
                button:hover { transform: translateY(-2px); box-shadow: 0 10px 30px rgba(37, 99, 235, 0.35); }
                button:focus { outline: none; box-shadow: 0 0 0 2px rgba(37, 99, 235, 0.45); }
                select {
                    background: rgba(15, 23, 42, 0.65);
                    border: 1px solid rgba(148, 163, 184, 0.25);
                    border-radius: 999px;
                    padding: 0.45rem 1.1rem;
                    color: #e2e8f0;
                    font-weight: 600;
                }
                table {
                    width: 100%;
                    border-collapse: collapse;
                    margin-top: 1rem;
                    font-size: 0.9rem;
                }
                th, td {
                    text-align: left;
                    padding: 0.5rem 0.75rem;
                    border-bottom: 1px solid rgba(148, 163, 184, 0.12);
                    vertical-align: top;
                }
                th { color: #94a3b8; font-size: 0.8rem; letter-spacing: 0.05em; text-transform: uppercase; }
                tr.highlight { background: rgba(239, 68, 68, 0.25); color: #fee2e2; }
                tr.highlight td { border-bottom: 1px solid rgba(239, 68, 68, 0.35); }
                .status-pill {
                    display: inline-flex;
                    align-items: center;
                    padding: 0.25rem 0.75rem;
                    border-radius: 999px;
                    font-size: 0.75rem;
                    background: rgba(59, 130, 246, 0.18);
                    color: #bfdbfe;
                }
                .status-pill.idle { background: rgba(148, 163, 184, 0.2); color: #cbd5f5; }
                .status-pill.connected { background: rgba(134, 239, 172, 0.2); color: #86efac; }
                .status-pill.failed { background: rgba(248, 113, 113, 0.2); color: #fecaca; }
                .log {
                    max-height: 260px;
                    overflow-y: auto;
                    font-family: \"SFMono-Regular\", ui-monospace, Menlo, Consolas, monospace;
                    font-size: 0.82rem;
                    background: rgba(15, 23, 42, 0.78);
                    padding: 1rem;
                    border-radius: 14px;
                    border: 1px solid rgba(59, 130, 246, 0.22);
                }
                .log-entry { margin-bottom: 0.65rem; }
                .log-entry time { color: #64748b; margin-right: 0.5rem; }
                .map-header { display:flex; justify-content: space-between; align-items: center; gap: 0.75rem; flex-wrap: wrap; }
                .map-controls { display:flex; gap: 0.5rem; align-items: center; }
                #mission-map { height: 320px; border-radius: 14px; overflow: hidden; transition: height 0.25s ease; }
                #mission-map.expanded { height: 520px; }
                .coordinate-toggle button { margin-right: 0.25rem; }
                .coordinate-toggle button.active { background: rgba(37, 99, 235, 0.35); }
                .actions button { margin-bottom: 0.25rem; }
                .color-swatch { display:inline-block; width:0.75rem; height:0.75rem; border-radius:50%; margin-right:0.4rem; border:1px solid rgba(255,255,255,0.4); }
            </style>
        </head>
        <body>
            <header style=\"margin-bottom: 2rem;\">
                <h1>BlueK9 Mission Console</h1>
                <p class=\"subtle\">Monitor team position, radio contacts, and mission telemetry from any browser on the local network.</p>
            </header>

            <section class=\"card\">
                <h2>Mission Systems</h2>
                <div style=\"display:flex;flex-wrap:wrap;gap:0.75rem;align-items:center;\">
                    <button onclick=\"startScan('passive')\">Start Passive</button>
                    <button onclick=\"startScan('active')\">Start Active</button>
                    <button class=\"secondary\" onclick=\"stopScan()\">Stop Scan</button>
                    <button class=\"secondary\" onclick=\"window.location='/api/log'\">Download Log</button>
                    <span id=\"scanStatus\" class=\"subtle\" style=\"margin-left:auto;\"></span>
                </div>
                <div class=\"coordinate-toggle\" style=\"margin-top:1rem;\">
                    <span class=\"subtle\">Coordinate display:</span>
                    <button id=\"modeLatLon\" class=\"secondary\" onclick=\"setCoordinateMode('latitudeLongitude')\">Lat/Lon</button>
                    <button id=\"modeMgrs\" class=\"secondary\" onclick=\"setCoordinateMode('mgrs')\">MGRS</button>
                </div>
            </section>

            <section class=\"card\">
                <div class=\"map-header\">
                    <h2>Mission Map</h2>
                    <div class=\"map-controls\">
                        <button class=\"secondary\" onclick=\"toggleMapSize()\">Toggle Fullscreen</button>
                        <select id=\"mapFilterSelect\" onchange=\"setMapFilter(this.value)\"></select>
                    </div>
                </div>
                <div id=\"mission-map\"></div>
                <p class=\"subtle\" style=\"margin-top:0.75rem;\">Team and device fixes update automatically as new telemetry arrives. Tap any marker for full details.</p>
            </section>

            <section class=\"card\">
                <h2>Devices in Contact</h2>
                <table>
                    <thead>
                        <tr>
                            <th onclick=\"setSort('name')\">Name</th>
                            <th onclick=\"setSort('signal')\">Signal</th>
                            <th onclick=\"setSort('recent')\">Identifiers &amp; Last Seen</th>
                            <th onclick=\"setSort('range')\">Range</th>
                            <th>Coordinate</th>
                            <th>Actions</th>
                        </tr>
                    </thead>
                    <tbody id=\"deviceTable\"></tbody>
                </table>
            </section>

            <section class=\"card\">
                <h2>Mission Log</h2>
                <div id=\"logView\" class=\"log\"></div>
            </section>

            <script src=\"https://unpkg.com/leaflet@1.9.4/dist/leaflet.js\" integrity=\"sha256-o9N1j7kP0tE2kNvztNFVQVHNEqbb0w7YLMwZsZ1pPPA=\" crossorigin=\"\"></script>
            <script>
                const map = L.map('mission-map').setView([0, 0], 2);
                L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
                    attribution: '&copy; OpenStreetMap contributors',
                    maxZoom: 19
                }).addTo(map);
                const markerLayer = L.layerGroup().addTo(map);
                const pathLayer = L.layerGroup().addTo(map);
                const mapFilterState = { type: 'all', deviceId: null };
                let latestDevices = [];
                let latestTargetId = null;
                let latestTeamLocation = null;
                const sortState = { column: 'signal', ascending: false };
                let mapExpanded = false;

                async function fetchState() {
                    const response = await fetch('/api/state');
                    if (!response.ok) return;
                    const state = await response.json();
                    latestTeamLocation = state.location || null;
                    updateScanStatus(state);
                    updateCoordinateButtons(state.coordinatePreference);
                    updateDeviceTable(state.devices, state.targetDeviceID);
                    refreshFilterOptions(state.devices, state.targetDeviceID);
                    updateLog(state.logEntries);
                    updateMap(latestTeamLocation, state.devices, state.targetDeviceID);
                }

                function updateScanStatus(state) {
                    const status = state.isScanning ? `Scanning (${state.scanMode})` : 'Idle';
                    document.getElementById('scanStatus').textContent = status;
                }

                function updateCoordinateButtons(mode) {
                    document.getElementById('modeLatLon').classList.toggle('active', mode === 'latitudeLongitude');
                    document.getElementById('modeMgrs').classList.toggle('active', mode === 'mgrs');
                }

                function updateDeviceTable(devices, targetId) {
                    latestDevices = devices || [];
                    latestTargetId = targetId || null;
                    const tbody = document.getElementById('deviceTable');
                    const sorted = [...latestDevices];
                    sorted.sort((a, b) => {
                        switch (sortState.column) {
                            case 'name':
                                return a.name.localeCompare(b.name);
                            case 'range':
                                const ar = a.estimatedRange ?? Number.POSITIVE_INFINITY;
                                const br = b.estimatedRange ?? Number.POSITIVE_INFINITY;
                                return ar - br;
                            case 'recent':
                                return new Date(b.lastSeen) - new Date(a.lastSeen);
                            case 'signal':
                            default:
                                return (b.lastRSSI ?? -200) - (a.lastRSSI ?? -200);
                        }
                    });
                    if (sortState.ascending) {
                        sorted.reverse();
                    }

                    tbody.innerHTML = sorted.map(device => {
                        const isTarget = device.id === latestTargetId;
                        const services = device.services?.map(s => s.id).join(', ') || '—';
                        const advertised = device.advertisedServiceUUIDs?.join(', ') || '—';
                        const range = device.estimatedRange ? `${device.estimatedRange.toFixed(1)} m` : '—';
                        const latestFix = device.locations?.length ? device.locations[device.locations.length - 1] : null;
                        const coordinate = device.displayCoordinate || (latestFix ? `${latestFix.latitude.toFixed(5)}, ${latestFix.longitude.toFixed(5)}` : '—');
                        const stateLabel = `<span class=\"status-pill ${device.state.toLowerCase()}\">${device.state}</span>`;
                        const swatch = device.mapColorHex ? `<span class=\"color-swatch\" style=\"background:${device.mapColorHex}\"></span>` : '';
                        return `
                            <tr class='${isTarget ? 'highlight' : ''}'>
                                <td>
                                    <div style=\"display:flex;flex-direction:column;gap:0.25rem;\">
                                        <strong>${swatch}${device.name}</strong>
                                        <span class=\"subtle\">Manufacturer: ${device.manufacturerData || '—'}</span>
                                        <span class=\"subtle\">Advertised UUIDs: ${advertised}</span>
                                        <span class=\"subtle\">Services: ${services}</span>
                                    </div>
                                </td>
                                <td>
                                    <div>${device.signalDescription}</div>
                                    <div>${stateLabel}</div>
                                    <div class=\"subtle\">Last RSSI: ${device.lastRSSI} dBm</div>
                                    <div class=\"subtle\">Seen: ${new Date(device.lastSeen).toLocaleTimeString()}</div>
                                </td>
                                <td>
                                    <div class=\"subtle\">Address: ${device.hardwareAddress}</div>
                                    <div class=\"subtle\">UUID: ${device.id}</div>
                                </td>
                                <td>${range}</td>
                                <td>${coordinate}</td>
                                <td class=\"actions\">
                                    ${isTarget ? '<button class=\"danger\" onclick=\"clearTarget()\">Clear Target</button>' : `<button onclick=\"markTarget('${device.id}')\">Mark Target</button>`}
                                    <button class=\"secondary\" onclick=\"activeGeo('${device.id}')\">Active Geo</button>
                                    <button class=\"secondary\" onclick=\"getInfo('${device.id}')\">Get Info</button>
                                </td>
                            </tr>
                        `;
                    }).join('');
                }

                function updateLog(entries) {
                    const logView = document.getElementById('logView');
                    const recent = entries.slice(-40).reverse();
                    logView.innerHTML = recent.map(entry => {
                        const metadata = entry.metadata ? ' ' + Object.entries(entry.metadata).map(([k,v]) => `${k}: ${v}`).join(' | ') : '';
                        return `<div class=\"log-entry\"><time>${new Date(entry.timestamp).toLocaleTimeString()}</time><span>[${entry.type}] ${entry.message}${metadata}</span></div>`;
                    }).join('');
                }

                function updateMap(teamLocation, devices, targetId) {
                    markerLayer.clearLayers();
                    pathLayer.clearLayers();
                    const filteredDevices = applyMapFilter(devices || [], targetId);
                    const points = [];
                    if (teamLocation) {
                        L.circleMarker([teamLocation.latitude, teamLocation.longitude], {
                            radius: 8,
                            color: '#38bdf8',
                            fillColor: '#38bdf8',
                            fillOpacity: 0.6
                        }).bindPopup('Team Position').addTo(markerLayer);
                        points.push([teamLocation.latitude, teamLocation.longitude]);
                    }
                    filteredDevices.forEach(device => {
                        if (!device.locations || device.locations.length === 0) return;
                        const color = device.mapColorHex || '#22d3ee';
                        const historyColor = colorWithAlpha(color, 0.3);
                        const latest = device.locations[device.locations.length - 1];
                        const coordinate = device.displayCoordinate || `${latest.latitude.toFixed(5)}, ${latest.longitude.toFixed(5)}`;
                        const path = device.locations.map(loc => [loc.latitude, loc.longitude]);
                        if (path.length > 1) {
                            L.polyline(path, {
                                color,
                                weight: device.id === targetId ? 4 : 2,
                                opacity: 0.5
                            }).addTo(pathLayer);
                        }
                        device.locations.slice(0, -1).forEach(loc => {
                            L.circleMarker([loc.latitude, loc.longitude], {
                                radius: 5,
                                color: historyColor,
                                fillColor: historyColor,
                                fillOpacity: 0.35,
                                weight: 1
                            }).addTo(markerLayer);
                        });
                        const latestMarker = L.circleMarker([latest.latitude, latest.longitude], {
                            radius: device.id === targetId ? 11 : 8,
                            color,
                            fillColor: color,
                            fillOpacity: 0.7,
                            weight: 2
                        }).bindPopup(`<strong>${device.name}</strong><br/>${coordinate}<br/>RSSI ${device.lastRSSI} dBm`);
                        latestMarker.addTo(markerLayer);
                        points.push([latest.latitude, latest.longitude]);
                    });
                    if (points.length > 0) {
                        const bounds = L.latLngBounds(points);
                        map.fitBounds(bounds.pad(0.25));
                    }
                }

                function refreshFilterOptions(devices, targetId) {
                    const select = document.getElementById('mapFilterSelect');
                    if (!select) return;
                    const options = ['all', 'target'];
                    (devices || []).forEach(device => options.push(`device:${device.id}`));
                    const previous = select.value;
                    select.innerHTML = options.map(option => {
                        if (option === 'all') { return '<option value="all">Show All Geos</option>'; }
                        if (option === 'target') {
                            const label = targetId ? 'Target Only' : 'Target (none)';
                            return `<option value="target">${label}</option>`;
                        }
                        const id = option.split(':')[1];
                        const device = (devices || []).find(d => d.id === id);
                        const name = device ? device.name : id;
                        return `<option value="${option}">Device: ${name}</option>`;
                    }).join('');
                    const currentValue = mapFilterValue(targetId);
                    if (options.includes(previous)) {
                        select.value = previous;
                    } else {
                        select.value = currentValue;
                        setMapFilter(currentValue);
                    }
                }

                function setMapFilter(value) {
                    if (value === 'target') {
                        mapFilterState.type = 'target';
                        mapFilterState.deviceId = null;
                    } else if (value && value.startsWith('device:')) {
                        mapFilterState.type = 'device';
                        mapFilterState.deviceId = value.split(':')[1];
                    } else {
                        mapFilterState.type = 'all';
                        mapFilterState.deviceId = null;
                    }
                    updateMap(latestTeamLocation, latestDevices, latestTargetId);
                }

                function mapFilterValue(targetId) {
                    switch (mapFilterState.type) {
                    case 'target':
                        return 'target';
                    case 'device':
                        return mapFilterState.deviceId ? `device:${mapFilterState.deviceId}` : 'all';
                    default:
                        return 'all';
                    }
                }

                function applyMapFilter(devices, targetId) {
                    switch (mapFilterState.type) {
                        case 'target':
                            if (!targetId) return devices;
                            return devices.filter(device => device.id === targetId);
                        case 'device':
                            if (!mapFilterState.deviceId) return devices;
                            return devices.filter(device => device.id === mapFilterState.deviceId);
                        default:
                            return devices;
                    }
                }

                function toggleMapSize() {
                    mapExpanded = !mapExpanded;
                    const mapElement = document.getElementById('mission-map');
                    if (!mapElement) return;
                    mapElement.classList.toggle('expanded', mapExpanded);
                    setTimeout(() => map.invalidateSize(), 250);
                }

                function setSort(column) {
                    if (sortState.column === column) {
                        sortState.ascending = !sortState.ascending;
                    } else {
                        sortState.column = column;
                        sortState.ascending = false;
                    }
                    updateDeviceTable(latestDevices, latestTargetId);
                }

                function colorWithAlpha(hex, alpha) {
                    const fallback = '22d3ee';
                    const parsed = (hex || `#${fallback}`).replace('#', '');
                    const safe = (parsed.length === 6 && !Number.isNaN(parseInt(parsed, 16))) ? parsed : fallback;
                    const bigint = parseInt(safe, 16);
                    const r = (bigint >> 16) & 255;
                    const g = (bigint >> 8) & 255;
                    const b = bigint & 255;
                    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
                }

                async function startScan(mode) {
                    await fetch(`/api/scan/start?mode=${mode}`, { method: 'POST' });
                    setTimeout(fetchState, 500);
                }

                async function stopScan() {
                    await fetch('/api/scan/stop', { method: 'POST' });
                    setTimeout(fetchState, 500);
                }

                async function markTarget(id) {
                    await fetch(`/api/device/${id}/target`, { method: 'POST' });
                    setTimeout(fetchState, 500);
                }

                async function clearTarget() {
                    await fetch('/api/device/clear-target', { method: 'POST' });
                    setTimeout(fetchState, 500);
                }

                async function activeGeo(id) {
                    await fetch(`/api/device/${id}/active-geo`, { method: 'POST' });
                    setTimeout(fetchState, 500);
                }

                async function getInfo(id) {
                    await fetch(`/api/device/${id}/info`, { method: 'POST' });
                    setTimeout(fetchState, 500);
                }

                async function setCoordinateMode(mode) {
                    await fetch(`/api/coordinate-mode?mode=${mode}`, { method: 'POST' });
                    setTimeout(fetchState, 300);
                }

                setInterval(fetchState, 4000);
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
