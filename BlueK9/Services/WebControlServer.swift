import Foundation
import Network
#if canImport(UIKit)
import UIKit
#endif

private let webConsoleHTML: String = #"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>BlueK9 Mission Console</title>
    <link href="https://api.mapbox.com/mapbox-gl-js/v2.15.0/mapbox-gl.css" rel="stylesheet" />
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
        button:disabled {
            opacity: 0.45;
            cursor: not-allowed;
            box-shadow: none;
        }
        select, input[type="text"] {
            background: rgba(15, 23, 42, 0.65);
            border: 1px solid rgba(148, 163, 184, 0.25);
            border-radius: 999px;
            padding: 0.45rem 1.1rem;
            color: #e2e8f0;
            font-weight: 600;
        }
        input[type="text"] {
            border-radius: 12px;
            padding: 0.55rem 1rem;
            min-width: 160px;
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
        th { color: #94a3b8; font-size: 0.8rem; letter-spacing: 0.05em; text-transform: uppercase; cursor: pointer; }
        tr.highlight { background: rgba(239, 68, 68, 0.65); color: #fff5f5; }
        tr.highlight td { border-bottom: 1px solid rgba(239, 68, 68, 0.75); }
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
        .status-pill.active {
            background: rgba(37, 99, 235, 0.35);
            color: #dbeafe;
        }
        .mission-scan-controls {
            display:flex;
            flex-wrap:wrap;
            gap:0.75rem;
            align-items:stretch;
        }
        .mission-scan-actions {
            display:flex;
            flex-wrap:wrap;
            gap:0.5rem;
            align-items:center;
        }
        .mission-scan-actions button { margin-right: 0; }
        .scan-indicator {
            display:flex;
            align-items:center;
            gap:0.75rem;
            padding:0.75rem 1rem;
            border-radius:16px;
            background: rgba(148, 163, 184, 0.12);
            border:1px solid rgba(148, 163, 184, 0.25);
            min-width: 240px;
            flex:1 1 260px;
            transition: background 0.25s ease, border-color 0.25s ease, box-shadow 0.25s ease;
        }
        .scan-indicator .scan-dot {
            width:0.85rem;
            height:0.85rem;
            border-radius:50%;
            background:#94a3b8;
            box-shadow:none;
        }
        .scan-headline { font-weight: 600; }
        .scan-subtitle { font-size: 0.8rem; color: #94a3b8; }
        .scan-indicator[data-state="active"] {
            background: rgba(37, 99, 235, 0.18);
            border-color: rgba(37, 99, 235, 0.35);
            box-shadow: 0 12px 35px rgba(37, 99, 235, 0.22);
        }
        .scan-indicator[data-state="active"] .scan-dot {
            background: #2563eb;
            box-shadow: 0 0 14px rgba(37, 99, 235, 0.75);
        }
        .scan-indicator[data-state="passive"] {
            background: rgba(45, 212, 191, 0.18);
            border-color: rgba(45, 212, 191, 0.35);
            box-shadow: 0 12px 35px rgba(13, 148, 136, 0.22);
        }
        .scan-indicator[data-state="passive"] .scan-dot {
            background: #2dd4bf;
            box-shadow: 0 0 14px rgba(45, 212, 191, 0.75);
        }
        .target-pill {
            display: inline-flex;
            align-items: center;
            padding: 0.25rem 0.65rem;
            border-radius: 999px;
            font-size: 0.75rem;
            background: rgba(239, 68, 68, 0.35);
            color: #fee2e2;
        }
        .log {
            max-height: 260px;
            overflow-y: auto;
            font-family: "SFMono-Regular", ui-monospace, Menlo, Consolas, monospace;
            font-size: 0.82rem;
            background: rgba(15, 23, 42, 0.78);
            padding: 1rem;
            border-radius: 14px;
            border: 1px solid rgba(59, 130, 246, 0.22);
        }
        .log-entry { margin-bottom: 0.65rem; }
        .log-entry time { color: #64748b; margin-right: 0.5rem; }
        .map-header {
            display:flex;
            justify-content: space-between;
            align-items: center;
            gap: 0.75rem;
            flex-wrap: wrap;
        }
        .map-controls {
            display:flex;
            gap: 0.5rem;
            flex-wrap: wrap;
            align-items: center;
        }
        .map-controls select {
            min-width: 120px;
        }
        .map-button-group {
            display:flex;
            gap:0.4rem;
            flex-wrap:wrap;
            align-items:center;
        }
        .map-tool {
            width:42px;
            height:42px;
            border-radius:14px;
            display:flex;
            align-items:center;
            justify-content:center;
            font-size:1rem;
            padding:0;
        }
        .map-tool.active {
            background: rgba(37, 99, 235, 0.35);
            color: #dbeafe;
        }
        .device-header, .log-header {
            display:flex;
            justify-content: space-between;
            align-items: center;
            gap: 0.75rem;
            flex-wrap: wrap;
        }
        .device-controls, .log-controls {
            display:flex;
            gap: 0.5rem;
            flex-wrap: wrap;
            align-items: center;
        }
        #mission-map {
            height: 320px;
            border-radius: 14px;
            overflow: hidden;
            transition: height 0.25s ease;
        }
        #mission-map.expanded { height: 520px; }
        .coordinate-toggle button { margin-right: 0.25rem; }
        .coordinate-toggle button.active { background: rgba(37, 99, 235, 0.35); }
        .actions button { margin-bottom: 0.25rem; }
        .color-swatch {
            display:inline-block;
            width:0.75rem;
            height:0.75rem;
            border-radius:50%;
            margin-right:0.4rem;
            border:1px solid rgba(255,255,255,0.4);
        }
        .mapboxgl-popup-content {
            background: rgba(15, 23, 42, 0.92);
            color: #f8fafc;
            border-radius: 12px;
            padding: 1rem;
            box-shadow: 0 18px 45px rgba(15, 23, 42, 0.45);
        }
        .mapboxgl-popup-close-button { color: #e2e8f0; }
        .mapboxgl-popup-tip { border-top-color: rgba(15, 23, 42, 0.92); }
    </style>
</head>
<body>
    <header style="margin-bottom: 2rem;">
        <h1>BlueK9 Mission Console</h1>
        <p class="subtle">Monitor team position, radio contacts, and mission telemetry from any browser on the local network.</p>
    </header>

    <section class="card">
        <h2>Mission Systems</h2>
        <div class="mission-scan-controls">
            <div class="mission-scan-actions">
                <button onclick="startScan('passive')">Start Passive</button>
                <button onclick="startScan('active')">Start Active</button>
                <button class="secondary" onclick="stopScan()">Stop Scan</button>
            </div>
            <div id="scanStatus" class="scan-indicator" data-state="idle">
                <span class="scan-dot"></span>
                <div>
                    <div class="scan-headline">Scanner idle</div>
                    <div class="scan-subtitle">Select a mode to begin scanning.</div>
                </div>
            </div>
        </div>
        <div class="coordinate-toggle" style="margin-top:1rem;">
            <span class="subtle">Coordinate display:</span>
            <button id="modeLatLon" class="secondary" onclick="setCoordinateMode('latitudeLongitude')">Lat/Lon</button>
            <button id="modeMgrs" class="secondary" onclick="setCoordinateMode('mgrs')">MGRS</button>
        </div>
    </section>

    <section class="card">
        <div class="map-header">
            <h2>Mission Map</h2>
            <div class="map-controls">
                <div class="map-button-group">
                    <button class="secondary map-tool" onclick="zoomOut()" title="Zoom out">−</button>
                    <button class="secondary map-tool" onclick="zoomIn()" title="Zoom in">+</button>
                    <button id="toggle3DButton" class="secondary map-tool" onclick="toggle3D()" title="Toggle 3D">3D</button>
                    <button id="recenterButton" class="secondary map-tool" onclick="recenterMap()" title="Recenter view">⌖</button>
                </div>
                <select id="mapStyleSelect" onchange="setMapStyle(this.value)">
                    <option value="dark">Dark</option>
                    <option value="streets">Streets</option>
                    <option value="outdoors">Outdoors</option>
                    <option value="light">Light</option>
                    <option value="navigationNight">Night Nav</option>
                    <option value="satellite">Hybrid Satellite</option>
                    <option value="aerial">Aerial</option>
                </select>
                <button class="secondary" onclick="toggleMapSize()">Toggle Fullscreen</button>
                <select id="mapFilterSelect" onchange="setMapFilter(this.value)"></select>
            </div>
        </div>
        <div id="mission-map"></div>
        <p class="subtle" style="margin-top:0.75rem;">Team and device fixes update automatically as new telemetry arrives. Tap any marker for full details.</p>
    </section>

    <section class="card">
        <div class="device-header">
            <h2>Devices in Contact</h2>
            <div class="device-controls">
                <button id="freezeTableButton" class="secondary" onclick="toggleTableFreeze()">Freeze Table</button>
                <button class="secondary" onclick="clearDeviceList()">Clear Devices</button>
            </div>
        </div>
        <table>
            <thead>
                <tr>
                    <th onclick="setSort('target')">Target</th>
                    <th onclick="setSort('name')">Name</th>
                    <th onclick="setSort('signal')">Signal</th>
                    <th onclick="setSort('recent')">Identifiers &amp; Last Seen</th>
                    <th onclick="setSort('range')">Range</th>
                    <th onclick="setSort('cep')">CEP</th>
                    <th>Coordinate</th>
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody id="deviceTable"></tbody>
        </table>
    </section>

    <section class="card">
        <div class="log-header">
            <h2>Mission Log</h2>
            <div class="log-controls">
                <select id="logSelect" onchange="selectLogFromDropdown(this.value)"></select>
                <input id="logNameInput" type="text" placeholder="Active log name" />
                <button class="secondary" onclick="renameActiveLog()">Rename</button>
                <button class="secondary" onclick="createLogFromUI()">New Log</button>
                <button id="deleteLogButton" class="danger" onclick="deleteActiveLog()">Delete Log</button>
                <button class="danger" onclick="deleteAllLogs()">Delete All</button>
                <span id="activeLogBadge" class="status-pill active">—</span>
                <button class="secondary" onclick="window.location='/api/log'">Download CSV</button>
            </div>
        </div>
        <div id="logView" class="log"></div>
    </section>

    <script src="https://api.mapbox.com/mapbox-gl-js/v2.15.0/mapbox-gl.js"></script>
    <script>
        const MAPBOX_TOKEN = 'pk.eyJ1Ijoiam1jY3VsbG91Z2g0IiwiYSI6ImNtMGJvOXh3cDBjNncya3B4cDg0MXFuYnUifQ.uDJKnqE9WgkvGXYGLge-NQ';
        mapboxgl.accessToken = MAPBOX_TOKEN;
        const styleCatalog = {
            dark: 'mapbox://styles/mapbox/dark-v11',
            streets: 'mapbox://styles/mapbox/streets-v12',
            outdoors: 'mapbox://styles/mapbox/outdoors-v12',
            light: 'mapbox://styles/mapbox/light-v11',
            navigationNight: 'mapbox://styles/mapbox/navigation-night-v1',
            satellite: 'mapbox://styles/mapbox/satellite-streets-v12',
            aerial: 'mapbox://styles/mapbox/satellite-v9'
        };
        const terrainSourceId = 'mapbox-dem';
        let currentStyleKey = 'dark';
        const map = new mapboxgl.Map({
            container: 'mission-map',
            style: styleCatalog[currentStyleKey],
            center: [0, 0],
            zoom: 2
        });
        const popup = new mapboxgl.Popup({ closeButton: true, closeOnMove: true });

        const deviceSourceId = 'device-positions';
        const teamSourceId = 'team-position';
        const historyLimit = 40;
        const mapFilterState = { type: 'all', deviceId: null };
        const sortState = { column: 'signal', ascending: false };
        const tableState = { frozen: false };
        const logState = { logs: [], activeId: null };

        let mapReady = false;
        let mapExpanded = false;
        let mapFollow = true;
        let mapIs3D = false;
        let latestDevices = [];
        let latestTargetId = null;
        let latestTeamLocation = null;
        let lastFocusKey = null;

        map.on('load', () => {
            mapReady = true;
            ensureSources();
            fetchState();
        });
        map.on('styledata', () => {
            if (!mapReady) { return; }
            ensureSources();
            applyTerrainIfNeeded();
            updateMap(latestTeamLocation, latestDevices, latestTargetId);
        });
        const detachFollow = () => { mapFollow = false; updateMapControlsUI(); };
        map.on('dragstart', detachFollow);
        map.on('zoomstart', detachFollow);
        map.on('rotatestart', detachFollow);
        map.on('pitchstart', detachFollow);

        async function fetchState() {
            try {
                const response = await fetch('/api/state');
                if (!response.ok) { throw new Error('Request failed'); }
                const state = await response.json();
                const devices = Array.isArray(state.devices) ? state.devices : [];
                const logs = Array.isArray(state.logEntries) ? state.logEntries : [];
                latestTeamLocation = state.location ? { ...state.location, accuracy: state.locationAccuracy ?? null } : null;
                updateScanStatus(state);
                updateCoordinateButtons(state.coordinatePreference);
                updateDeviceTable(devices, state.targetDeviceID);
                refreshFilterOptions(devices, state.targetDeviceID);
                updateLogControls(state.logs || [], state.activeLogID);
                updateLog(logs);
                updateMap(latestTeamLocation, devices, state.targetDeviceID);
                updateMapControlsUI();
            } catch (error) {
                console.error('Failed to fetch mission state', error);
            }
        }

        function updateScanStatus(state) {
            const container = document.getElementById('scanStatus');
            if (!container) { return; }
            const isScanning = !!state.isScanning;
            const mode = (state.scanMode || 'passive').toLowerCase();
            const modeLabel = mode === 'active' ? 'Active Scan' : 'Passive Scan';
            const headline = isScanning ? `${modeLabel} running` : 'Scanner idle';
            const subtitle = isScanning
                ? (mode === 'active' ? 'Actively querying nearby emitters.' : 'Listening for advertisements and telemetry.')
                : 'Select a mode to begin scanning.';
            container.dataset.state = isScanning ? mode : 'idle';
            const headlineEl = container.querySelector('.scan-headline');
            const subtitleEl = container.querySelector('.scan-subtitle');
            if (headlineEl) { headlineEl.textContent = headline; }
            if (subtitleEl) { subtitleEl.textContent = subtitle; }
        }

        function updateCoordinateButtons(mode) {
            document.getElementById('modeLatLon').classList.toggle('active', mode === 'latitudeLongitude');
            document.getElementById('modeMgrs').classList.toggle('active', mode === 'mgrs');
        }

        function updateDeviceTable(devices, targetId) {
            latestDevices = devices || [];
            latestTargetId = targetId || null;
            if (tableState.frozen) { return; }
            const tbody = document.getElementById('deviceTable');
            if (!tbody) { return; }
            const sorted = [...latestDevices];
            sorted.sort((a, b) => {
                switch (sortState.column) {
                    case 'name':
                        return (a.name || '').localeCompare(b.name || '');
                    case 'range': {
                        const ar = toNumber(a.estimatedRange);
                        const br = toNumber(b.estimatedRange);
                        const av = Number.isFinite(ar) ? ar : Number.POSITIVE_INFINITY;
                        const bv = Number.isFinite(br) ? br : Number.POSITIVE_INFINITY;
                        return av - bv;
                    }
                    case 'cep':
                        return cepForDevice(a).value - cepForDevice(b).value;
                    case 'recent':
                        return new Date(b.lastSeen) - new Date(a.lastSeen);
                    case 'target':
                        if (a.id === latestTargetId && b.id !== latestTargetId) { return -1; }
                        if (b.id === latestTargetId && a.id !== latestTargetId) { return 1; }
                        return (a.name || '').localeCompare(b.name || '');
                    case 'signal':
                    default: {
                        const aRssi = toNumber(a.lastRSSI);
                        const bRssi = toNumber(b.lastRSSI);
                        const av = Number.isFinite(aRssi) ? aRssi : -200;
                        const bv = Number.isFinite(bRssi) ? bRssi : -200;
                        return bv - av;
                    }
                }
            });
            if (sortState.ascending) { sorted.reverse(); }

            tbody.innerHTML = sorted.map(device => {
                const isTarget = device.id === latestTargetId;
                const services = formatServiceList(device);
                const advertised = formatAdvertisedList(device);
                const rangeValue = toNumber(device.estimatedRange);
                const range = Number.isFinite(rangeValue) ? `${rangeValue.toFixed(1)} m` : '—';
                const latestFix = getLatestFix(device);
                const address = device.hardwareAddress || '—';
                const deviceId = device.id || '—';
                const coordinate = (() => {
                    if (device.displayCoordinate) { return device.displayCoordinate; }
                    if (!latestFix) { return '—'; }
                    const lat = toNumber(latestFix.latitude ?? latestFix.coordinate?.latitude);
                    const lon = toNumber(latestFix.longitude ?? latestFix.coordinate?.longitude);
                    if (!Number.isFinite(lat) || !Number.isFinite(lon)) { return '—'; }
                    return `${lat.toFixed(5)}, ${lon.toFixed(5)}`;
                })();
                const stateLabel = `<span class=\"status-pill ${device.state?.toLowerCase() || 'idle'}\">${device.state || 'Idle'}</span>`;
                const swatch = device.mapColorHex ? `<span class=\"color-swatch\" style=\"background:${device.mapColorHex}\"></span>` : '';
                const cep = cepForDevice(device);
                const lastSeen = device.lastSeen ? new Date(device.lastSeen).toLocaleTimeString() : '—';
                const signalDescription = device.signalDescription || `RSSI: ${device.lastRSSI ?? '—'} dBm`;
                const encodedName = JSON.stringify(device.name || '');
                return `
                    <tr class='${isTarget ? 'highlight' : ''}'>
                        <td>${isTarget ? '<span class="target-pill">Target</span>' : ''}</td>
                        <td>
                            <div style="display:flex;flex-direction:column;gap:0.25rem;">
                                <strong>${swatch}${device.name}</strong>
                                <span class="subtle">Manufacturer: ${device.manufacturerData || '—'}</span>
                                <span class="subtle">Advertised: ${advertised}</span>
                                <span class="subtle">Services: ${services}</span>
                            </div>
                        </td>
                        <td>
                            <div>${signalDescription}</div>
                            <div>${stateLabel}</div>
                            <div class="subtle">Last RSSI: ${device.lastRSSI ?? '—'} dBm</div>
                            <div class="subtle">Seen: ${lastSeen}</div>
                        </td>
                        <td>
                            <div class="subtle">Address: ${address}</div>
                            <div class="subtle">UUID: ${deviceId}</div>
                        </td>
                        <td>${range}</td>
                        <td>${cep.text}</td>
                        <td>${coordinate}</td>
                        <td class="actions">
                            ${isTarget ? '<button class="danger" onclick="clearTarget()">Clear Target</button>' : `<button onclick="markTarget('${device.id}')">Mark Target</button>`}
                            <button class="secondary" onclick="activeGeo('${device.id}')">Active Geo</button>
                            <button class="secondary" onclick="getInfo('${device.id}')">Get Info</button>
                            <button class="secondary" onclick="promptForName('${device.id}', ${encodedName})">Name Device</button>
                            <button class="secondary" onclick="clearDeviceName('${device.id}')">Clear Name</button>
                        </td>
                    </tr>
                `;
            }).join('');
        }

        function updateLog(entries) {
            const logView = document.getElementById('logView');
            if (!logView) { return; }
            const recent = (entries || []).slice(-40).reverse();
            logView.innerHTML = recent.map(entry => {
                const metadata = entry.metadata ? ' ' + Object.entries(entry.metadata).map(([k,v]) => `${k}: ${v}`).join(' | ') : '';
                return `<div class="log-entry"><time>${new Date(entry.timestamp).toLocaleTimeString()}</time><span>[${entry.type}] ${entry.message}${metadata}</span></div>`;
            }).join('');
        }

        function updateLogControls(logs, activeId) {
            logState.logs = Array.isArray(logs) ? logs : [];
            logState.activeId = activeId || (logState.logs[0]?.id ?? null);
            const select = document.getElementById('logSelect');
            if (select) {
                select.innerHTML = logState.logs.map(log => `<option value="${log.id}">${log.name}</option>`).join('');
                if (logState.activeId) {
                    select.value = logState.activeId;
                }
            }
            const input = document.getElementById('logNameInput');
            const active = logState.logs.find(log => log.id === logState.activeId);
            if (input) {
                input.value = active ? active.name : '';
            }
            const badge = document.getElementById('activeLogBadge');
            if (badge) {
                badge.textContent = active ? active.name : 'No log';
            }
            const deleteButton = document.getElementById('deleteLogButton');
            if (deleteButton) {
                deleteButton.disabled = logState.logs.length <= 1;
            }
        }

        function updateMap(teamLocation, devices, targetId) {
            if (!mapReady) { return; }
            const filteredDevices = applyMapFilter(devices || [], targetId);
            const mapData = buildMapFeatures(teamLocation, filteredDevices, targetId);
            const deviceSource = map.getSource(deviceSourceId);
            if (deviceSource) {
                deviceSource.setData(mapData.deviceCollection);
            }
            const teamSource = map.getSource(teamSourceId);
            if (teamSource) {
                teamSource.setData(mapData.teamCollection);
            }

            if (mapFollow) {
                focusMap(mapData);
            }
        }

        function refreshFilterOptions(devices, targetId) {
            const select = document.getElementById('mapFilterSelect');
            if (!select) { return; }
            const previous = select.value;
            const baseOptions = ['all', 'target'];
            const deviceOptions = (devices || []).map(device => `device:${device.id}`);
            const options = [...baseOptions, ...deviceOptions];
            select.innerHTML = options.map(option => {
                if (option === 'all') { return '<option value="all">All Devices</option>'; }
                if (option === 'target') { return '<option value="target">Target Only</option>'; }
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
            mapFollow = true;
            lastFocusKey = null;
            updateMap(latestTeamLocation, latestDevices, latestTargetId);
            updateMapControlsUI();
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
            setTimeout(() => map.resize(), 250);
        }

        function zoomIn() {
            mapFollow = false;
            updateMapControlsUI();
            map.zoomIn({ duration: 250 });
        }

        function zoomOut() {
            mapFollow = false;
            updateMapControlsUI();
            map.zoomOut({ duration: 250 });
        }

        function toggle3D() {
            mapIs3D = !mapIs3D;
            if (mapIs3D) {
                applyTerrainIfNeeded();
                map.easeTo({ pitch: 55, duration: 600 });
            } else {
                map.setTerrain(null);
                if (map.getLayer('sky')) { map.removeLayer('sky'); }
                map.easeTo({ pitch: 0, bearing: 0, duration: 500 });
            }
            updateMapControlsUI();
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

        function toggleTableFreeze() {
            tableState.frozen = !tableState.frozen;
            updateMapControlsUI();
            if (!tableState.frozen) {
                updateDeviceTable(latestDevices, latestTargetId);
            }
        }

        function recenterMap() {
            mapFollow = true;
            lastFocusKey = null;
            updateMap(latestTeamLocation, latestDevices, latestTargetId);
            updateMapControlsUI();
        }

        function setMapStyle(styleKey) {
            const style = styleCatalog[styleKey] || styleCatalog.dark;
            currentStyleKey = styleKey;
            lastFocusKey = null;
            map.setStyle(style);
            const select = document.getElementById('mapStyleSelect');
            if (select) { select.value = styleKey; }
        }

        function updateMapControlsUI() {
            const freezeButton = document.getElementById('freezeTableButton');
            if (freezeButton) {
                freezeButton.textContent = tableState.frozen ? 'Unfreeze Table' : 'Freeze Table';
            }
            const recenterButton = document.getElementById('recenterButton');
            if (recenterButton) {
                recenterButton.classList.toggle('active', mapFollow);
            }
            const button3D = document.getElementById('toggle3DButton');
            if (button3D) {
                button3D.classList.toggle('active', mapIs3D);
                button3D.textContent = mapIs3D ? '2D' : '3D';
                button3D.title = mapIs3D ? 'Switch to 2D' : 'Toggle 3D';
            }
        }
        function ensureSources() {
            if (!map.getSource(teamSourceId)) {
                map.addSource(teamSourceId, { type: 'geojson', data: emptyCollection() });
                map.addLayer({
                    id: 'team-shadow',
                    type: 'circle',
                    source: teamSourceId,
                    paint: {
                        'circle-radius': ['case', ['has', 'pixelRadius'], ['max', ['get', 'pixelRadius'], 12], ['interpolate', ['linear'], ['zoom'], 0, 8, 14, 18]],
                        'circle-color': 'rgba(56, 189, 248, 0.2)'
                    }
                });
                map.addLayer({
                    id: 'team-marker',
                    type: 'circle',
                    source: teamSourceId,
                    paint: {
                        'circle-radius': ['interpolate', ['linear'], ['zoom'], 0, 4, 14, 9],
                        'circle-color': '#38bdf8',
                        'circle-stroke-color': '#0f172a',
                        'circle-stroke-width': 2
                    }
                });
            }

            if (!map.getSource(deviceSourceId)) {
                map.addSource(deviceSourceId, { type: 'geojson', data: emptyCollection() });
                map.addLayer({
                    id: 'device-trails',
                    type: 'line',
                    source: deviceSourceId,
                    filter: ['==', ['get', 'featureType'], 'trail'],
                    paint: {
                        'line-color': ['get', 'color'],
                        'line-width': ['case', ['==', ['get', 'isTarget'], true], 4, 2],
                        'line-opacity': ['case', ['==', ['get', 'isTarget'], true], 0.85, 0.55]
                    }
                });
                map.addLayer({
                    id: 'device-history',
                    type: 'circle',
                    source: deviceSourceId,
                    filter: ['==', ['get', 'featureType'], 'history'],
                    paint: {
                        'circle-radius': ['interpolate', ['linear'], ['zoom'], 0, 2.5, 14, 6],
                        'circle-color': ['get', 'color'],
                        'circle-opacity': 0.72,
                        'circle-stroke-color': '#0f172a',
                        'circle-stroke-width': 1
                    }
                });
                map.addLayer({
                    id: 'device-target-glow',
                    type: 'circle',
                    source: deviceSourceId,
                    filter: ['all', ['==', ['get', 'featureType'], 'device'], ['==', ['get', 'isTarget'], true]],
                    paint: {
                        'circle-radius': ['case', ['has', 'pixelRadius'], ['max', ['*', ['get', 'pixelRadius'], 1.25], 18], ['interpolate', ['linear'], ['zoom'], 0, 10, 14, 22]],
                        'circle-color': ['get', 'color'],
                        'circle-opacity': 0.25
                    }
                });
                map.addLayer({
                    id: 'device-points',
                    type: 'circle',
                    source: deviceSourceId,
                    filter: ['==', ['get', 'featureType'], 'device'],
                    paint: {
                        'circle-radius': ['case', ['has', 'pixelRadius'], ['max', ['get', 'pixelRadius'], 8], ['interpolate', ['linear'], ['zoom'], 0, 6, 14, 12]],
                        'circle-color': ['get', 'color'],
                        'circle-stroke-color': '#0f172a',
                        'circle-stroke-width': ['case', ['==', ['get', 'isTarget'], true], 3, 1.5]
                    }
                });
                map.addLayer({
                    id: 'device-labels',
                    type: 'symbol',
                    source: deviceSourceId,
                    filter: ['==', ['get', 'featureType'], 'device'],
                    layout: {
                        'text-field': ['get', 'label'],
                        'text-size': 12,
                        'text-offset': [0, 1.2],
                        'text-font': ['DIN Offc Pro Medium', 'Arial Unicode MS Bold']
                    },
                    paint: {
                        'text-color': '#e2e8f0',
                        'text-halo-color': '#0f172a',
                        'text-halo-width': 1.2
                    }
                });

                map.on('click', 'device-points', event => {
                    if (!event.features || !event.features.length) return;
                    const feature = event.features[0];
                    const properties = feature.properties || {};
                    const coordinate = feature.geometry.coordinates.slice();
                    const popupHtml = `
                <div style="min-width:220px">
                    <strong style="display:block;margin-bottom:0.35rem;">${properties.name || 'Device'}</strong>
                    <div class="subtle">Signal: ${properties.signal || '—'}</div>
                    <div class="subtle">Range: ${properties.range || '—'}</div>
                    <div class="subtle">CEP: ${properties.cep || '—'}</div>
                    <div class="subtle">Address: ${properties.address || '—'}</div>
                    <div class="subtle">Last seen: ${properties.lastSeen || '—'}</div>
                    <div class="subtle">Coordinate: ${properties.coordinate || '—'}</div>
                </div>
            `;
                    popup.setLngLat(coordinate).setHTML(popupHtml).addTo(map);
                });

                map.on('mouseenter', 'device-points', () => { map.getCanvas().style.cursor = 'pointer'; });
                map.on('mouseleave', 'device-points', () => { map.getCanvas().style.cursor = ''; });
            }
        }

        function applyTerrainIfNeeded() {
            if (!mapIs3D || !mapReady) { return; }
            if (!map.getSource(terrainSourceId)) {
                map.addSource(terrainSourceId, {
                    type: 'raster-dem',
                    url: 'mapbox://mapbox.mapbox-terrain-dem-v1',
                    tileSize: 512,
                    maxzoom: 14
                });
            }
            map.setTerrain({ source: terrainSourceId, exaggeration: 1.2 });
            if (!map.getLayer('sky')) {
                map.addLayer({
                    id: 'sky',
                    type: 'sky',
                    paint: {
                        'sky-type': 'atmosphere',
                        'sky-atmosphere-sun': [0.0, 0.0],
                        'sky-atmosphere-sun-intensity': 15
                    }
                });
            }
        }

        function emptyCollection() {
            return { type: 'FeatureCollection', features: [] };
        }

        function buildMapFeatures(teamLocation, devices, targetId) {
            const deviceFeatures = [];
            let bounds = null;
            const zoom = map.getZoom();

            const teamLat = toNumber(teamLocation?.latitude);
            const teamLon = toNumber(teamLocation?.longitude);
            const teamAccuracy = toNumber(teamLocation?.accuracy);
            let teamCollection = emptyCollection();
            if (Number.isFinite(teamLat) && Number.isFinite(teamLon)) {
                const point = [teamLon, teamLat];
                const pixelRadius = accuracyToPixels(teamAccuracy, teamLat, zoom);
                const teamProperties = {};
                if (Number.isFinite(teamAccuracy)) {
                    teamProperties.accuracy = teamAccuracy;
                }
                if (pixelRadius !== null && pixelRadius !== undefined) {
                    teamProperties.pixelRadius = pixelRadius;
                }
                teamCollection = {
                    type: 'FeatureCollection',
                    features: [{
                        type: 'Feature',
                        geometry: { type: 'Point', coordinates: point },
                        properties: teamProperties
                    }]
                };
                bounds = new mapboxgl.LngLatBounds(point, point);
            }

            (devices || []).forEach(device => {
                if (!device.locations || device.locations.length === 0) { return; }
                const color = device.mapColorHex || '#22d3ee';
                const sorted = [...device.locations].sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp));
                const trimmed = historyLimit > 0 ? sorted.slice(-historyLimit) : sorted;
                const path = trimmed.map(extractCoordinate).filter(Boolean);
                if (path.length > 0) {
                    if (!bounds) {
                        bounds = new mapboxgl.LngLatBounds(path[0], path[0]);
                    }
                    path.forEach(point => bounds.extend(point));
                }
                if (path.length > 1) {
                    deviceFeatures.push({
                        type: 'Feature',
                        geometry: { type: 'LineString', coordinates: path },
                        properties: {
                            featureType: 'trail',
                            id: device.id,
                            color,
                            isTarget: device.id === targetId
                        }
                    });
                }
                const latest = trimmed[trimmed.length - 1];
                const latestPoint = path[path.length - 1];
                if (latestPoint) {
                    const coordinateText = device.displayCoordinate || formatCoordinate(latest);
                    const cep = cepForDevice(device);
                    const accuracyValue = Number.isFinite(cep.value) ? cep.value : null;
                    const pixelRadius = accuracyToPixels(accuracyValue, latestPoint[1], zoom);
                    const rangeValue = toNumber(device.estimatedRange);
                    const rangeText = Number.isFinite(rangeValue) ? `${rangeValue.toFixed(1)} m` : '—';

                    const properties = {
                        featureType: 'device',
                        id: device.id,
                        name: device.name,
                        color,
                        isTarget: device.id === targetId,
                        label: device.name,
                        coordinate: coordinateText,
                        signal: device.signalDescription || `RSSI: ${device.lastRSSI} dBm`,
                        range: rangeText,
                        address: device.hardwareAddress || device.id,
                        lastSeen: device.lastSeen ? new Date(device.lastSeen).toLocaleTimeString() : '—',
                        cep: cep.text
                    };
                    if (accuracyValue !== null) {
                        properties.accuracy = accuracyValue;
                    }
                    if (pixelRadius !== null && pixelRadius !== undefined) {
                        properties.pixelRadius = pixelRadius;
                    }
                    deviceFeatures.push({
                        type: 'Feature',
                        geometry: { type: 'Point', coordinates: latestPoint },
                        properties
                    });
                }
                const historyFixes = trimmed.slice(0, -1);
                historyFixes.forEach((fix, index) => {
                    const point = extractCoordinate(fix);
                    if (!point) { return; }
                    deviceFeatures.push({
                        type: 'Feature',
                        id: `${device.id}-history-${fix.id || index}`,
                        geometry: { type: 'Point', coordinates: point },
                        properties: {
                            featureType: 'history',
                            id: device.id,
                            color,
                            isTarget: device.id === targetId,
                            timestamp: fix.timestamp || null
                        }
                    });
                });
            });

            return {
                deviceCollection: deviceFeatures.length ? { type: 'FeatureCollection', features: deviceFeatures } : emptyCollection(),
                teamCollection,
                bounds
            };
        }

        function focusMap(mapData) {
            if (!mapData) { return; }
            if (mapData.bounds) {
                const focusKey = `bounds:${mapData.bounds.toArray().flat().map(v => v.toFixed(4)).join(',')}:${mapIs3D ? '3d' : '2d'}`;
                if (focusKey !== lastFocusKey) {
                    map.fitBounds(mapData.bounds, { padding: mapIs3D ? 120 : 64, maxZoom: mapIs3D ? 18 : 17, duration: 450 });
                    lastFocusKey = focusKey;
                }
                return;
            }
            if (latestTeamLocation) {
                const lat = toNumber(latestTeamLocation.latitude);
                const lon = toNumber(latestTeamLocation.longitude);
                if (Number.isFinite(lat) && Number.isFinite(lon)) {
                    const focusKey = `center:${lat.toFixed(4)},${lon.toFixed(4)}`;
                    if (focusKey !== lastFocusKey) {
                        map.easeTo({ center: [lon, lat], duration: 450 });
                        lastFocusKey = focusKey;
                    }
                }
            }
        }

        function extractCoordinate(entry) {
            const lat = toNumber(entry.latitude ?? entry.coordinate?.latitude);
            const lon = toNumber(entry.longitude ?? entry.coordinate?.longitude);
            if (!Number.isFinite(lat) || !Number.isFinite(lon)) { return null; }
            return [lon, lat];
        }

        function formatCoordinate(location) {
            const lat = toNumber(location.latitude ?? location.coordinate?.latitude);
            const lon = toNumber(location.longitude ?? location.coordinate?.longitude);
            if (!Number.isFinite(lat) || !Number.isFinite(lon)) { return '—'; }
            return `${lat.toFixed(5)}, ${lon.toFixed(5)}`;
        }

        function getLatestFix(device) {
            if (!device || !Array.isArray(device.locations) || device.locations.length === 0) { return null; }
            return device.locations[device.locations.length - 1];
        }

        function cepForDevice(device) {
            const fix = getLatestFix(device);
            const accuracy = toNumber(fix?.accuracy);
            const range = toNumber(device.estimatedRange);
            const value = Number.isFinite(accuracy) ? accuracy : (Number.isFinite(range) ? range : null);
            if (!Number.isFinite(value)) {
                return { value: Number.POSITIVE_INFINITY, text: '—' };
            }
            return { value, text: `${value.toFixed(1)} m` };
        }

        function formatServiceList(device) {
            if (Array.isArray(device.serviceSummaries) && device.serviceSummaries.length) {
                return device.serviceSummaries.join(', ');
            }
            if (Array.isArray(device.services) && device.services.length) {
                return device.services.map(entry => entry.displayName || entry.id || entry).join(', ');
            }
            return '—';
        }

        function formatAdvertisedList(device) {
            if (Array.isArray(device.advertisedServiceSummaries) && device.advertisedServiceSummaries.length) {
                return device.advertisedServiceSummaries.join(', ');
            }
            if (Array.isArray(device.advertisedServiceUUIDs) && device.advertisedServiceUUIDs.length) {
                return device.advertisedServiceUUIDs.join(', ');
            }
            return '—';
        }

        function accuracyToPixels(accuracyMeters, latitude, zoom) {
            if (!Number.isFinite(accuracyMeters) || accuracyMeters <= 0) { return null; }
            if (!Number.isFinite(latitude)) { return null; }
            const zoomLevel = Number.isFinite(zoom) ? zoom : map.getZoom();
            const metersPerPixel = 156543.03392 * Math.cos(latitude * Math.PI / 180) / Math.pow(2, zoomLevel);
            if (!Number.isFinite(metersPerPixel) || metersPerPixel <= 0) { return null; }
            const radius = accuracyMeters / metersPerPixel;
            if (!Number.isFinite(radius)) { return null; }
            return Math.min(Math.max(radius, 6), 120);
        }

        function toNumber(value) {
            if (typeof value === 'number') { return value; }
            if (typeof value === 'string' && value.trim().length) { return parseFloat(value); }
            return NaN;
        }


        async function clearDeviceList() {
            await fetch('/api/devices/clear', { method: 'POST' });
            setTimeout(fetchState, 300);
        }

        async function selectLogFromDropdown(id) {
            if (!id) { return; }
            await fetch(`/api/logs/select?id=${id}`, { method: 'POST' });
            setTimeout(fetchState, 400);
        }

        async function renameActiveLog() {
            if (!logState.activeId) { return; }
            const input = document.getElementById('logNameInput');
            const name = input ? input.value.trim() : '';
            await fetch(`/api/logs/rename?id=${logState.activeId}&name=${encodeURIComponent(name)}`, { method: 'POST' });
            setTimeout(fetchState, 400);
        }

        async function createLogFromUI() {
            const input = document.getElementById('logNameInput');
            const fallback = input ? input.value.trim() : 'Untitled Log';
            const name = window.prompt('Name for new log', fallback) ?? null;
            if (name === null) { return; }
            await fetch(`/api/logs/create?name=${encodeURIComponent(name)}`, { method: 'POST' });
            setTimeout(fetchState, 500);
        }

        async function deleteActiveLog() {
            if (!logState.activeId) { return; }
            const active = logState.logs.find(log => log.id === logState.activeId);
            const confirmed = window.confirm(`Delete log "${active?.name ?? 'current'}"?`);
            if (!confirmed) { return; }
            const nameParam = active?.name ? `&name=${encodeURIComponent(active.name)}` : '';
            await fetch(`/api/logs/delete?id=${logState.activeId}${nameParam}`, { method: 'POST' });
            setTimeout(fetchState, 500);
        }

        async function deleteAllLogs() {
            const confirmed = window.confirm('Delete all logs? This cannot be undone.');
            if (!confirmed) { return; }
            await fetch('/api/logs/delete-all', { method: 'POST' });
            setTimeout(fetchState, 500);
        }

        async function promptForName(id, currentName) {
            const name = window.prompt('Device name', currentName || '');
            if (name === null) { return; }
            const trimmed = name.trim();
            if (!trimmed) {
                await clearDeviceName(id);
                return;
            }
            await fetch(`/api/device/${id}/name?value=${encodeURIComponent(trimmed)}`, { method: 'POST' });
            setTimeout(fetchState, 300);
        }

        async function clearDeviceName(id) {
            await fetch(`/api/device/${id}/name`, { method: 'POST' });
            setTimeout(fetchState, 300);
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

"""#

final class WebControlServer {
    enum WebCommand {
        case startScan(ScanMode)
        case stopScan
        case setTarget(UUID)
        case clearTarget
        case activeGeo(UUID)
        case getInfo(UUID)
        case setCoordinatePreference(CoordinateDisplayMode)
        case createLog(String)
        case selectLog(UUID)
        case renameLog(UUID, String)
        case deleteLog(UUID, String?)
        case deleteAllLogs
        case clearDevices
        case setCustomName(UUID, String?)
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

        if path == "/api/devices/clear" {
            commandHandler(.clearDevices)
            return httpResponse(status: "200 OK", body: Data("Devices cleared".utf8))
        }

        if path.hasPrefix("/api/logs/") {
            guard let components = URLComponents(string: path) else {
                return httpResponse(status: "400 Bad Request", body: Data("Invalid log command".utf8))
            }

            switch components.path {
            case "/api/logs/create":
                let name = components.queryItems?.first(where: { $0.name == "name" })?.value ?? "Untitled Log"
                commandHandler(.createLog(name))
                return httpResponse(status: "200 OK", body: Data("Log created".utf8))
            case "/api/logs/select":
                guard let idString = components.queryItems?.first(where: { $0.name == "id" })?.value,
                      let id = UUID(uuidString: idString) else {
                    return httpResponse(status: "400 Bad Request", body: Data("Invalid log identifier".utf8))
                }
                commandHandler(.selectLog(id))
                return httpResponse(status: "200 OK", body: Data("Log selected".utf8))
            case "/api/logs/rename":
                guard let idString = components.queryItems?.first(where: { $0.name == "id" })?.value,
                      let id = UUID(uuidString: idString) else {
                    return httpResponse(status: "400 Bad Request", body: Data("Invalid log identifier".utf8))
                }
                let name = components.queryItems?.first(where: { $0.name == "name" })?.value ?? ""
                commandHandler(.renameLog(id, name))
                return httpResponse(status: "200 OK", body: Data("Log renamed".utf8))
            case "/api/logs/delete":
                guard let idString = components.queryItems?.first(where: { $0.name == "id" })?.value,
                      let id = UUID(uuidString: idString) else {
                    return httpResponse(status: "400 Bad Request", body: Data("Invalid log identifier".utf8))
                }
                let name = components.queryItems?.first(where: { $0.name == "name" })?.value
                commandHandler(.deleteLog(id, name))
                return httpResponse(status: "200 OK", body: Data("Log deleted".utf8))
            case "/api/logs/delete-all":
                commandHandler(.deleteAllLogs)
                return httpResponse(status: "200 OK", body: Data("Logs cleared".utf8))
            default:
                return httpResponse(status: "404 Not Found", body: Data("Unknown log command".utf8))
            }
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
            case "name":
                let components = URLComponents(string: path)
                let value = components?.queryItems?.first(where: { $0.name == "value" })?.value
                commandHandler(.setCustomName(uuid, value))
                return httpResponse(status: "200 OK", body: Data("Device name updated".utf8))
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
        return httpResponse(status: "200 OK", body: data, contentType: "text/csv; charset=utf-8", additionalHeaders: ["Content-Disposition": "attachment; filename=mission-log.csv"])
    }

    private func htmlResponse() -> Data {
        let html = webConsoleHTML

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
