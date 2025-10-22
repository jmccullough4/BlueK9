import SwiftUI
import MapKit
import Combine
#if canImport(UIKit)
import UIKit
#endif

struct MissionDashboardView: View {
    @EnvironmentObject private var controller: MissionController
    @Environment(\.openURL) private var openURL
    @State private var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090), span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
    @State private var mapScope: MissionMapScope = .all
    @State private var isMapExpanded = false
    @State private var selectedDeviceForDetails: BluetoothDevice?
    @State private var deviceIDRequestingRename: UUID?
    @State private var sortOrder: DeviceSortOrder = .signal
    @State private var isFollowingMissionRegion = true
    @State private var isDeviceListFrozen = false
    @State private var frozenDevicesSnapshot: [BluetoothDevice] = []
    @State private var logNameDraft: String = ""
    @State private var showDeleteLogConfirmation = false
    @State private var showDeleteAllLogsConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                missionSystemsCard
                missionMap
                scanControls
                deviceSection
                logSection
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .onReceive(controller.$location.compactMap { $0 }) { coordinate in
            guard isFollowingMissionRegion else { return }
            withAnimation {
                region.center = coordinate
            }
        }
        .onChange(of: controller.devices, initial: true) { _, newDevices in
            if isDeviceListFrozen {
                var updatedSnapshot = frozenDevicesSnapshot
                for index in updatedSnapshot.indices {
                    if let replacement = newDevices.first(where: { $0.id == updatedSnapshot[index].id }) {
                        updatedSnapshot[index] = replacement
                    }
                }
                frozenDevicesSnapshot = updatedSnapshot
            } else {
                frozenDevicesSnapshot = newDevices
                updateRegionToFitAnnotations()
            }
        }
        .onChange(of: mapScope, initial: false) { _, _ in
            isFollowingMissionRegion = true
            updateRegionToFitAnnotations(force: true)
        }
        .onAppear {
            frozenDevicesSnapshot = controller.devices
            logNameDraft = controller.activeLog.name
            updateRegionToFitAnnotations(force: true)
        }
        .onChange(of: controller.activeLog, initial: false) { _, active in
            logNameDraft = active.name
        }
        .fullScreenCover(isPresented: $isMapExpanded) {
            MissionMapDetailView(
                region: $region,
                scope: $mapScope,
                selectedDevice: $selectedDeviceForDetails,
                isFollowing: $isFollowingMissionRegion,
                onUserInteraction: {
                    isFollowingMissionRegion = false
                },
                onRecenter: recenterMap,
                onDeviceSelected: { _ in deviceIDRequestingRename = nil }
            )
                .environmentObject(controller)
        }
        .sheet(item: $selectedDeviceForDetails, onDismiss: { deviceIDRequestingRename = nil }) { device in
            MissionDeviceInfoSheet(
                device: device,
                coordinateMode: controller.coordinateDisplayMode,
                isTarget: controller.targetDeviceID == device.id,
                hasCustomName: controller.hasCustomName(for: device.id),
                shouldFocusNameField: deviceIDRequestingRename == device.id,
                onMarkTarget: { controller.setTarget(device) },
                onClearTarget: { controller.clearTarget() },
                onActiveGeo: { controller.performActiveGeo(on: device.id) },
                onGetInfo: { controller.requestDeviceInfo(for: device.id) },
                onRename: { newName in
                    controller.renameDevice(device, to: newName)
                    deviceIDRequestingRename = nil
                    if let updated = controller.devices.first(where: { $0.id == device.id }) {
                        selectedDeviceForDetails = updated
                    }
                },
                onClearName: {
                    controller.clearDeviceName(device)
                    deviceIDRequestingRename = nil
                    if let updated = controller.devices.first(where: { $0.id == device.id }) {
                        selectedDeviceForDetails = updated
                    } else {
                        selectedDeviceForDetails = nil
                    }
                }
            )
            .onDisappear {
                deviceIDRequestingRename = nil
            }
        }
    }

    private var missionSystemsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Mission Systems", systemImage: "shield.checkerboard")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 12) {
                systemStatusRow(
                    title: "Location Access",
                    systemImage: "location.circle",
                    status: locationStatusText,
                    tint: locationStatusColor
                )

                systemStatusRow(
                    title: "Bluetooth Radio",
                    systemImage: "dot.radiowaves.right",
                    status: bluetoothStatusText,
                    tint: bluetoothStatusColor
                )
            }

            VStack(spacing: 12) {
                if controller.locationAuthorizationStatus == .notDetermined || controller.locationAuthorizationStatus == .authorizedWhenInUse {
                    Button {
                        controller.requestLocationAuthorization()
                    } label: {
                        Label("Request Always-On Location", systemImage: "location.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MissionPrimaryButtonStyle(isSelected: false))
                }

                if controller.locationAuthorizationStatus == .denied || controller.locationAuthorizationStatus == .restricted {
#if canImport(UIKit)
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        Button {
                            openURL(settingsURL)
                        } label: {
                            Label("Open Settings", systemImage: "gear")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(MissionSecondaryButtonStyle())
                    }
#endif
                }

                Button {
                    controller.engageMissionSystems()
                } label: {
                    Label("Engage Mission Systems", systemImage: "play.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MissionSecondaryButtonStyle())
                .disabled(controller.isScanning)
            }
        }
        .padding()
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func systemStatusRow(title: String, systemImage: String, status: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var locationStatusText: String {
        switch controller.locationAuthorizationStatus {
        case .authorizedAlways:
            return "Always-on location enabled"
        case .authorizedWhenInUse:
            return "Only active while in use - upgrade recommended"
        case .denied:
            return "Permission denied - enable in Settings"
        case .restricted:
            return "Restricted - check device management"
        case .notDetermined:
            return "Awaiting permission"
        @unknown default:
            return "Unknown status"
        }
    }

    private var locationStatusColor: Color {
        switch controller.locationAuthorizationStatus {
        case .authorizedAlways:
            return .green
        case .authorizedWhenInUse:
            return .orange
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .yellow
        @unknown default:
            return .gray
        }
    }

    private var bluetoothStatusText: String {
        switch controller.bluetoothState {
        case .poweredOn:
            return "Bluetooth radio ready"
        case .poweredOff:
            return "Bluetooth is powered off"
        case .resetting:
            return "Bluetooth resetting"
        case .unauthorized:
            return "Permission denied - enable in Settings"
        case .unsupported:
            return "Unsupported on this device"
        case .unknown:
            fallthrough
        @unknown default:
            return "Checking Bluetooth status"
        }
    }

    private var bluetoothStatusColor: Color {
        switch controller.bluetoothState {
        case .poweredOn:
            return .green
        case .poweredOff:
            return .orange
        case .unauthorized:
            return .red
        case .unsupported:
            return .gray
        case .resetting, .unknown:
            fallthrough
        @unknown default:
            return .yellow
        }
    }

    private var missionMap: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Mission Map", systemImage: "map")
                    .font(.title2.bold())
                Spacer()
                if let locationAccuracy = controller.locationAccuracy {
                    Text(String(format: "± %.0f m", locationAccuracy))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.2))
                        .clipShape(Capsule())
                }
                Menu {
                    Button("Show All") { mapScope = .all }
                    if let targetID = controller.targetDeviceID, let target = controller.devices.first(where: { $0.id == targetID }) {
                        Button("Target Only: \(target.name)") { mapScope = .target }
                    }
                    if !controller.devices.isEmpty {
                        Section("Devices") {
                            ForEach(controller.devices) { device in
                                Button(device.name) { mapScope = .device(device.id) }
                            }
                        }
                    }
                } label: {
                    Label(mapScope.menuTitle(with: controller, fallback: "Filter"), systemImage: "line.3.horizontal.decrease.circle")
                        .labelStyle(.titleAndIcon)
                }
                .tint(.primary)
            }
            Picker("Coordinate Mode", selection: Binding(get: { controller.coordinateDisplayMode }, set: { controller.setCoordinateDisplayMode($0) })) {
                ForEach(CoordinateDisplayMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            missionMapContent
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(alignment: .topTrailing) {
                    Button {
                        isMapExpanded = true
                    } label: {
                        Label("Expand", systemImage: "arrow.up.left.and.arrow.down.right")
                            .labelStyle(.iconOnly)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .padding(10)
                }
                .overlay(alignment: .bottomLeading) {
                    if !isFollowingMissionRegion {
                        Button(action: recenterMap) {
                            Label("Recenter", systemImage: "location.fill.viewfinder")
                                .labelStyle(.iconOnly)
                                .padding(10)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .padding(10)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16).strokeBorder(Color.blue.opacity(0.25), lineWidth: 1)
                }
                .mapStyle(.standard)
                .gesture(TapGesture().onEnded { isMapExpanded = true })
        }
        .padding()
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var scanControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Scan Control", systemImage: "antenna.radiowaves.left.and.right")
                .font(.title2.bold())
            Text(controller.scanMode.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                ForEach(ScanMode.allCases) { mode in
                    Button {
                        controller.startScanning(mode: mode)
                    } label: {
                        Label(mode.displayName, systemImage: mode == .passive ? "ear" : "bolt.horizontal")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MissionPrimaryButtonStyle(isSelected: controller.scanMode == mode && controller.isScanning))
                }
            }
            Button(role: .cancel) {
                controller.stopScanning()
            } label: {
                Label("Stop Scan", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MissionSecondaryButtonStyle())
            .disabled(!controller.isScanning)

            if let webURL = missionWebURLDescription {
                Label(webURL, systemImage: "link")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var missionWebURLDescription: String? {
        guard let ip = NetworkMonitor.shared.localIPAddress else { return nil }
        return "Remote console: http://\(ip):8080"
    }

    private var mapData: MissionMapData {
        MissionMapData(
            teamCoordinate: controller.location,
            teamAccuracy: controller.locationAccuracy,
            devices: controller.devices,
            coordinateMode: controller.coordinateDisplayMode,
            targetDeviceID: controller.targetDeviceID,
            scope: mapScope
        )
    }

    @ViewBuilder
    private var missionMapContent: some View {
        MissionCompactMapView(
            region: $region,
            annotations: mapAnnotations,
            onSelectDevice: {
                deviceIDRequestingRename = nil
                selectedDeviceForDetails = $0
            },
            onUserInteraction: { isFollowingMissionRegion = false }
        )
    }

    private var mapAnnotations: [MissionMapAnnotation] {
        mapData.annotations
    }

    private var mapCoordinates: [CLLocationCoordinate2D] {
        mapData.coordinates
    }

    private var displayedDevices: [BluetoothDevice] {
        isDeviceListFrozen ? frozenDevicesSnapshot : controller.devices
    }

    private var sortedDevices: [BluetoothDevice] {
        switch sortOrder {
        case .signal:
            return displayedDevices.sorted { $0.lastRSSI > $1.lastRSSI }
        case .recent:
            return displayedDevices.sorted { $0.lastSeen > $1.lastSeen }
        case .name:
            return displayedDevices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .range:
            return displayedDevices.sorted {
                let lhs = $0.estimatedRange ?? .greatestFiniteMagnitude
                let rhs = $1.estimatedRange ?? .greatestFiniteMagnitude
                if lhs == rhs {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return lhs < rhs
            }
        case .target:
            return displayedDevices.sorted { lhs, rhs in
                let lhsIsTarget = lhs.id == controller.targetDeviceID
                let rhsIsTarget = rhs.id == controller.targetDeviceID
                if lhsIsTarget != rhsIsTarget {
                    return lhsIsTarget && !rhsIsTarget
                }
                if lhs.lastSeen == rhs.lastSeen {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.lastSeen > rhs.lastSeen
            }
        }
    }

    private func updateRegionToFitAnnotations(force: Bool = false) {
        guard force || isFollowingMissionRegion else { return }
        let coordinates = mapCoordinates
        guard !coordinates.isEmpty else { return }
        let minLat = coordinates.map { $0.latitude }.min() ?? region.center.latitude
        let maxLat = coordinates.map { $0.latitude }.max() ?? region.center.latitude
        let minLon = coordinates.map { $0.longitude }.min() ?? region.center.longitude
        let maxLon = coordinates.map { $0.longitude }.max() ?? region.center.longitude
        let span = MKCoordinateSpan(latitudeDelta: max(0.002, (maxLat - minLat) * 1.5), longitudeDelta: max(0.002, (maxLon - minLon) * 1.5))
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2.0, longitude: (minLon + maxLon) / 2.0)
        region = MKCoordinateRegion(center: center, span: span)
    }

    private func recenterMap() {
        isFollowingMissionRegion = true
        updateRegionToFitAnnotations(force: true)
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Devices", systemImage: "dot.radiowaves.left.and.right")
                    .font(.title2.bold())
                Spacer()
                Button {
                    isDeviceListFrozen.toggle()
                    if isDeviceListFrozen {
                        frozenDevicesSnapshot = controller.devices
                    } else {
                        updateRegionToFitAnnotations(force: true)
                    }
                } label: {
                    Label(isDeviceListFrozen ? "Unfreeze" : "Freeze", systemImage: isDeviceListFrozen ? "play.circle" : "pause.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(MissionSecondaryButtonStyle())

                Button {
                    controller.clearDevices()
                    isDeviceListFrozen = false
                    frozenDevicesSnapshot.removeAll()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(MissionSecondaryButtonStyle())
            }
            Picker("Sort", selection: $sortOrder) {
                ForEach(DeviceSortOrder.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)

            ForEach(sortedDevices) { device in
                MissionDeviceRow(
                    device: device,
                    coordinateMode: controller.coordinateDisplayMode,
                    isTarget: controller.targetDeviceID == device.id,
                    hasCustomName: controller.hasCustomName(for: device.id),
                    onMarkTarget: { controller.setTarget(device) },
                    onClearTarget: { controller.clearTarget() },
                    onActiveGeo: { controller.performActiveGeo(on: device.id) },
                    onGetInfo: { controller.requestDeviceInfo(for: device.id) },
                    onRename: {
                        deviceIDRequestingRename = device.id
                        selectedDeviceForDetails = controller.devices.first(where: { $0.id == device.id }) ?? device
                    },
                    onClearName: {
                        controller.clearDeviceName(device)
                        deviceIDRequestingRename = nil
                        if let updated = controller.devices.first(where: { $0.id == device.id }) {
                            selectedDeviceForDetails = updated
                        }
                    },
                    onShowDetails: {
                        deviceIDRequestingRename = nil
                        selectedDeviceForDetails = controller.devices.first(where: { $0.id == device.id }) ?? device
                    }
                )
            }
            if displayedDevices.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("No Devices")
                        .font(.headline)
                    Text("Start a scan to locate Bluetooth devices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding()
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Mission Log", systemImage: "doc.text")
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: 10) {
                Picker("Active Log", selection: Binding(get: { controller.activeLog.id }, set: { controller.selectLog(id: $0) })) {
                    ForEach(controller.logs) { descriptor in
                        Text(descriptor.name).tag(descriptor.id)
                    }
                }
                .pickerStyle(.menu)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Log name", text: $logNameDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { controller.renameActiveLog(to: logNameDraft) }

                    HStack(spacing: 10) {
                        Button {
                            controller.renameActiveLog(to: logNameDraft)
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .buttonStyle(MissionSecondaryButtonStyle())

                        Button {
                            controller.createLog(named: logNameDraft.isEmpty ? "Untitled Log" : logNameDraft)
                        } label: {
                            Label("New Log", systemImage: "plus")
                        }
                        .buttonStyle(MissionSecondaryButtonStyle())

                        Button(role: .destructive) {
                            showDeleteLogConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(MissionSecondaryButtonStyle())
                        .disabled(controller.logs.count <= 1)

                        Button(role: .destructive) {
                            showDeleteAllLogsConfirmation = true
                        } label: {
                            Label("Delete All", systemImage: "trash.slash")
                        }
                        .buttonStyle(MissionSecondaryButtonStyle())
                    }
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(controller.logEntries.reversed()) { entry in
                        MissionLogEntryRow(entry: entry)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 180, maxHeight: 260)

            MissionLogShareButton(logURL: controller.logFileURL())
        }
        .confirmationDialog("Delete current log?", isPresented: $showDeleteLogConfirmation, titleVisibility: .visible) {
            Button("Delete Log", role: .destructive) {
                controller.deleteLog(controller.activeLog)
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete all logs?", isPresented: $showDeleteAllLogsConfirmation, titleVisibility: .visible) {
            Button("Delete All Logs", role: .destructive) {
                controller.deleteAllLogs()
            }
            Button("Cancel", role: .cancel) {}
        }
        .padding()
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct MissionPrimaryButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.vertical, 12)
            .background(
                LinearGradient(colors: isSelected ? [Color.blue, Color.indigo] : [Color.blue.opacity(0.6), Color.indigo.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct MissionSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
            .foregroundStyle(Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct MissionMapAnnotation: Identifiable {
    enum Kind {
        case team(accuracy: CLLocationAccuracy?)
        case latest(device: BluetoothDevice, coordinateText: String, accuracy: CLLocationAccuracy?)
        case history(deviceID: UUID)
    }

    static let teamIdentifier = UUID()

    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let color: Color
    let kind: Kind
    let accuracy: CLLocationAccuracy?

    init(id: UUID = UUID(), coordinate: CLLocationCoordinate2D, color: Color, kind: Kind, accuracy: CLLocationAccuracy? = nil) {
        self.id = id
        self.coordinate = coordinate
        self.color = color
        self.kind = kind
        self.accuracy = accuracy
    }
}

private struct MissionMapData {
    let annotations: [MissionMapAnnotation]
    let coordinates: [CLLocationCoordinate2D]

    init(teamCoordinate: CLLocationCoordinate2D?, teamAccuracy: CLLocationAccuracy?, devices: [BluetoothDevice], coordinateMode: CoordinateDisplayMode, targetDeviceID: UUID?, scope: MissionMapScope) {
        var annotations: [MissionMapAnnotation] = []
        var coordinates: [CLLocationCoordinate2D] = []

        if let teamCoordinate {
            annotations.append(MissionMapAnnotation(id: MissionMapAnnotation.teamIdentifier, coordinate: teamCoordinate, color: .blue, kind: .team(accuracy: teamAccuracy), accuracy: teamAccuracy))
            coordinates.append(teamCoordinate)
        }

        let filteredDevices = scope.filteredDevices(from: devices, targetID: targetDeviceID)

        for device in filteredDevices {
            guard !device.locations.isEmpty else { continue }
            let sortedLocations = device.locations.sorted(by: { $0.timestamp < $1.timestamp })
            guard let latest = sortedLocations.last else { continue }
            let baseColor: Color = (targetDeviceID == device.id) ? .red : DeviceColorPalette.color(for: device.id)
            let historyColor = baseColor.opacity(0.35)

            for geo in sortedLocations {
                coordinates.append(geo.coordinate)
                if geo.id == latest.id {
                    let coordinateText = device.displayCoordinate ?? CoordinateFormatter.shared.string(from: geo.coordinate, mode: coordinateMode)
                    let accuracy = geo.accuracy ?? device.estimatedRange
                    annotations.append(MissionMapAnnotation(id: geo.id, coordinate: geo.coordinate, color: baseColor, kind: .latest(device: device, coordinateText: coordinateText, accuracy: accuracy), accuracy: accuracy))
                } else {
                    annotations.append(MissionMapAnnotation(id: geo.id, coordinate: geo.coordinate, color: historyColor, kind: .history(deviceID: device.id), accuracy: geo.accuracy))
                }
            }
        }

        self.annotations = annotations
        self.coordinates = coordinates
    }
}

private func formattedCEP(_ accuracy: CLLocationAccuracy?) -> String? {
    guard let accuracy, accuracy.isFinite, accuracy > 0 else { return nil }
    let formatted = accuracy.formatted(.number.precision(.fractionLength(0...1)))
    return "CEP ±\(formatted) m"
}

private enum MissionMapScope: Hashable, Identifiable {
    case all
    case target
    case device(UUID)

    var id: String {
        switch self {
        case .all:
            return "all"
        case .target:
            return "target"
        case .device(let id):
            return "device-\(id.uuidString)"
        }
    }

    func filteredDevices(from devices: [BluetoothDevice], targetID: UUID?) -> [BluetoothDevice] {
        switch self {
        case .all:
            return devices
        case .target:
            guard let targetID, let target = devices.first(where: { $0.id == targetID }) else { return devices }
            return [target]
        case .device(let id):
            if let device = devices.first(where: { $0.id == id }) {
                return [device]
            }
            return devices
        }
    }

    @MainActor
    func menuTitle(with controller: MissionController, fallback: String) -> String {
        switch self {
        case .all:
            return "All Geos"
        case .target:
            if let targetID = controller.targetDeviceID, let device = controller.devices.first(where: { $0.id == targetID }) {
                return "Target: \(device.name)"
            }
            return fallback
        case .device(let id):
            if let device = controller.devices.first(where: { $0.id == id }) {
                return device.name
            }
            return fallback
        }
    }
}

private enum DeviceSortOrder: String, CaseIterable, Identifiable {
    case signal
    case recent
    case name
    case range
    case target

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .signal:
            return "Signal"
        case .recent:
            return "Recent"
        case .name:
            return "Name"
        case .range:
            return "Range"
        case .target:
            return "Target"
        }
    }
}

private struct MissionMapDetailView: View {
    @EnvironmentObject private var controller: MissionController
    @Environment(\.dismiss) private var dismiss
    @Binding var region: MKCoordinateRegion
    @Binding var scope: MissionMapScope
    @Binding var selectedDevice: BluetoothDevice?
    @Binding var isFollowing: Bool
    let onUserInteraction: () -> Void
    let onRecenter: () -> Void
    let onDeviceSelected: (BluetoothDevice) -> Void

    private var mapData: MissionMapData {
        MissionMapData(
            teamCoordinate: controller.location,
            teamAccuracy: controller.locationAccuracy,
            devices: controller.devices,
            coordinateMode: controller.coordinateDisplayMode,
            targetDeviceID: controller.targetDeviceID,
            scope: scope
        )
    }

    @ViewBuilder
    private var mapViewContent: some View {
        MissionDetailMapView(
            region: $region,
            annotations: mapData.annotations,
            selectedDevice: $selectedDevice,
            onUserInteraction: onUserInteraction,
            onSelectDevice: onDeviceSelected
        )
    }

    var body: some View {
        NavigationStack {
            mapViewContent
                .ignoresSafeArea()
                .overlay(alignment: .bottomTrailing) {
                    if !isFollowing {
                        Button(action: onRecenter) {
                            Label("Recenter", systemImage: "location.fill.viewfinder")
                                .labelStyle(.iconOnly)
                                .padding(12)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .shadow(radius: 4)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 40)
                    }
                }
                .background(Color(.systemBackground))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Show All") { scope = .all }
                        if let targetID = controller.targetDeviceID, let target = controller.devices.first(where: { $0.id == targetID }) {
                            Button("Target Only: \(target.name)") { scope = .target }
                        }
                        if !controller.devices.isEmpty {
                            Section("Devices") {
                                ForEach(controller.devices) { device in
                                    Button(device.name) { scope = .device(device.id) }
                                }
                            }
                        }
                    } label: {
                        Label(scope.menuTitle(with: controller, fallback: "Filter"), systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }
}

private struct MissionDeviceInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let device: BluetoothDevice
    let coordinateMode: CoordinateDisplayMode
    let isTarget: Bool
    let hasCustomName: Bool
    let shouldFocusNameField: Bool
    let onMarkTarget: () -> Void
    let onClearTarget: () -> Void
    let onActiveGeo: () -> Void
    let onGetInfo: () -> Void
    let onRename: (String) -> Void
    let onClearName: () -> Void

    @State private var nameDraft: String
    @FocusState private var nameFieldFocused: Bool

    init(device: BluetoothDevice,
         coordinateMode: CoordinateDisplayMode,
         isTarget: Bool,
         hasCustomName: Bool,
         shouldFocusNameField: Bool,
         onMarkTarget: @escaping () -> Void,
         onClearTarget: @escaping () -> Void,
         onActiveGeo: @escaping () -> Void,
         onGetInfo: @escaping () -> Void,
         onRename: @escaping (String) -> Void,
         onClearName: @escaping () -> Void) {
        self.device = device
        self.coordinateMode = coordinateMode
        self.isTarget = isTarget
        self.hasCustomName = hasCustomName
        self.shouldFocusNameField = shouldFocusNameField
        self.onMarkTarget = onMarkTarget
        self.onClearTarget = onClearTarget
        self.onActiveGeo = onActiveGeo
        self.onGetInfo = onGetInfo
        self.onRename = onRename
        self.onClearName = onClearName
        _nameDraft = State(initialValue: device.name)
    }

    private var coordinateText: String? {
        if let display = device.displayCoordinate {
            return display
        }
        guard let location = device.lastKnownLocation?.coordinate else { return nil }
        return CoordinateFormatter.shared.string(from: location, mode: coordinateMode)
    }

    private var trimmedName: String {
        nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSaveName: Bool {
        !trimmedName.isEmpty && trimmedName != device.name
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Device Alias")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Enter custom name", text: $nameDraft)
                            .textFieldStyle(.roundedBorder)
                            .focused($nameFieldFocused)
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)
                        HStack(spacing: 12) {
                            Button {
                                nameFieldFocused = false
                                onRename(trimmedName)
                            } label: {
                                Label("Save", systemImage: "checkmark.circle")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canSaveName)

                            Button(role: .destructive) {
                                nameFieldFocused = false
                                onClearName()
                            } label: {
                                Label("Clear", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                            .disabled(!hasCustomName)
                        }
                        if hasCustomName {
                            Text("Custom alias synced across devices.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Add an alias to recognize this emitter at a glance.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    infoRow(label: "Bluetooth Address", value: device.hardwareAddress)
                    infoRow(label: "UUID", value: device.id.uuidString)
                    infoRow(label: "Last RSSI", value: "\(device.lastRSSI) dBm")
                    if let range = device.estimatedRange {
                        infoRow(label: "Estimated Range", value: String(format: "%.1f m", range))
                    }
                    if let coordinateText {
                        infoRow(label: "Coordinate", value: coordinateText)
                    }
                    if let manufacturer = device.manufacturerData {
                        infoRow(label: "Manufacturer", value: manufacturer)
                    }
                    if !device.advertisedServiceUUIDs.isEmpty {
                        infoRow(label: "Advertised UUIDs", value: device.advertisedServiceUUIDs.map { $0.uuidString }.joined(separator: ", "))
                    }
                    if !device.services.isEmpty {
                        infoRow(label: "Services", value: device.services.map { $0.id.uuidString }.joined(separator: ", "))
                    }

                    Divider()

                    if isTarget {
                        Button(role: .destructive, action: onClearTarget) {
                            Label("Clear Target", systemImage: "xmark.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button(action: onMarkTarget) {
                            Label("Mark as Target", systemImage: "scope")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }

                    HStack {
                        Button(action: onActiveGeo) {
                            Label("Active Geo", systemImage: "bolt")
                        }
                        .buttonStyle(.bordered)

                        Button(action: onGetInfo) {
                            Label("Get Info", systemImage: "info.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            .navigationTitle(device.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            if shouldFocusNameField {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    nameFieldFocused = true
                }
            }
        }
        .onChange(of: device) { _, updated in
            nameDraft = updated.name
        }
        .onChange(of: shouldFocusNameField) { _, newValue in
            if newValue {
                DispatchQueue.main.async {
                    nameFieldFocused = true
                }
            }
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.semibold))
                .textSelection(.enabled)
        }
    }
}

private struct RegionSignature: Equatable {
    let centerLatitude: Double
    let centerLongitude: Double
    let spanLatitudeDelta: Double
    let spanLongitudeDelta: Double

    init(_ region: MKCoordinateRegion) {
        centerLatitude = region.center.latitude
        centerLongitude = region.center.longitude
        spanLatitudeDelta = region.span.latitudeDelta
        spanLongitudeDelta = region.span.longitudeDelta
    }
}

private struct CameraPositionSignature: Equatable {
    private enum Kind: Equatable {
        case region(RegionSignature)
        case other
    }

    private let kind: Kind

    init(_ position: MapCameraPosition) {
        if let region = mapCameraRegion(from: position) {
            kind = .region(RegionSignature(region))
        } else {
            kind = .other
        }
    }
}

private func regionsAreApproximatelyEqual(_ lhs: MKCoordinateRegion, _ rhs: MKCoordinateRegion) -> Bool {
    let threshold = 1e-6
    return abs(lhs.center.latitude - rhs.center.latitude) < threshold &&
        abs(lhs.center.longitude - rhs.center.longitude) < threshold &&
        abs(lhs.span.latitudeDelta - rhs.span.latitudeDelta) < threshold &&
        abs(lhs.span.longitudeDelta - rhs.span.longitudeDelta) < threshold
}

private func mapCameraRegion(from position: MapCameraPosition) -> MKCoordinateRegion? {
#if compiler(>=6.0)
    return position.region
#else
    if case .region(let region) = position {
        return region
    }
    return nil
#endif
}

private func mapCameraPosition(from region: MKCoordinateRegion) -> MapCameraPosition {
    MapCameraPosition.region(region)
}

private struct MissionCompactMapView: View {
    @Binding var region: MKCoordinateRegion
    let annotations: [MissionMapAnnotation]
    let onSelectDevice: (BluetoothDevice) -> Void
    let onUserInteraction: () -> Void

    @State private var cameraPosition: MapCameraPosition
    @State private var lastCameraRegion: MKCoordinateRegion
    @State private var isProgrammaticCameraChange = false

    init(region: Binding<MKCoordinateRegion>, annotations: [MissionMapAnnotation], onSelectDevice: @escaping (BluetoothDevice) -> Void, onUserInteraction: @escaping () -> Void) {
        _region = region
        self.annotations = annotations
        self.onSelectDevice = onSelectDevice
        self.onUserInteraction = onUserInteraction
        _cameraPosition = State(initialValue: mapCameraPosition(from: region.wrappedValue))
        _lastCameraRegion = State(initialValue: region.wrappedValue)
    }

    var body: some View {
        Map(position: $cameraPosition, interactionModes: .all) {
            ForEach(annotations) { annotation in
                Annotation("", coordinate: annotation.coordinate) {
                    compactAnnotationView(for: annotation)
                }
            }
        }
        .mapStyle(.standard)
        .onChange(of: CameraPositionSignature(cameraPosition), initial: false) { _, _ in
            guard let newRegion = mapCameraRegion(from: cameraPosition) else { return }

            if isProgrammaticCameraChange {
                isProgrammaticCameraChange = false
            } else {
                onUserInteraction()
            }

            if regionsAreApproximatelyEqual(newRegion, lastCameraRegion) {
                return
            }

            lastCameraRegion = newRegion
            region = newRegion
        }
        .onChange(of: RegionSignature(region), initial: false) { _, _ in
            if regionsAreApproximatelyEqual(region, lastCameraRegion) {
                return
            }

            lastCameraRegion = region
            isProgrammaticCameraChange = true
            cameraPosition = mapCameraPosition(from: region)
        }
    }

    @ViewBuilder
    private func compactAnnotationView(for annotation: MissionMapAnnotation) -> some View {
        switch annotation.kind {
        case .team(let accuracy):
            VStack(spacing: 4) {
                ZStack {
                    Circle().fill(Color.blue.opacity(0.28)).frame(width: 44, height: 44)
                    Circle().fill(Color.blue).frame(width: 16, height: 16)
                }
                Text("Team")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                if let cep = formattedCEP(accuracy) {
                    Text(cep)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        case .latest(let device, let coordinateText, let accuracy):
            Button {
                onSelectDevice(device)
            } label: {
                VStack(spacing: 4) {
                    ZStack {
                        Circle().fill(annotation.color.opacity(0.32)).frame(width: 48, height: 48)
                        Circle().fill(annotation.color).frame(width: 20, height: 20)
                    }
                    VStack(spacing: 2) {
                        Text(device.name)
                            .multilineTextAlignment(.center)
                            .font(.caption2.weight(.semibold))
                        Text(coordinateText)
                            .multilineTextAlignment(.center)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let cep = formattedCEP(accuracy) {
                            Text(cep)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .buttonStyle(.plain)
        case .history:
            Circle()
                .fill(annotation.color)
                .frame(width: 10, height: 10)
        }
    }
}

private struct MissionDetailMapView: View {
    @Binding var region: MKCoordinateRegion
    let annotations: [MissionMapAnnotation]
    @Binding var selectedDevice: BluetoothDevice?
    let onUserInteraction: () -> Void
    let onSelectDevice: (BluetoothDevice) -> Void

    @State private var cameraPosition: MapCameraPosition
    @State private var lastCameraRegion: MKCoordinateRegion
    @State private var isProgrammaticCameraChange = false

    init(region: Binding<MKCoordinateRegion>, annotations: [MissionMapAnnotation], selectedDevice: Binding<BluetoothDevice?>, onUserInteraction: @escaping () -> Void, onSelectDevice: @escaping (BluetoothDevice) -> Void) {
        _region = region
        self.annotations = annotations
        _selectedDevice = selectedDevice
        self.onUserInteraction = onUserInteraction
        self.onSelectDevice = onSelectDevice
        _cameraPosition = State(initialValue: mapCameraPosition(from: region.wrappedValue))
        _lastCameraRegion = State(initialValue: region.wrappedValue)
    }

    var body: some View {
        Map(position: $cameraPosition, interactionModes: .all) {
            ForEach(annotations) { annotation in
                Annotation("", coordinate: annotation.coordinate) {
                    detailAnnotationView(for: annotation)
                }
            }
        }
        .mapStyle(.standard)
        .onChange(of: CameraPositionSignature(cameraPosition), initial: false) { _, _ in
            guard let newRegion = mapCameraRegion(from: cameraPosition) else { return }

            if isProgrammaticCameraChange {
                isProgrammaticCameraChange = false
            } else {
                onUserInteraction()
            }

            if regionsAreApproximatelyEqual(newRegion, lastCameraRegion) {
                return
            }

            lastCameraRegion = newRegion
            region = newRegion
        }
        .onChange(of: RegionSignature(region), initial: false) { _, _ in
            if regionsAreApproximatelyEqual(region, lastCameraRegion) {
                return
            }

            lastCameraRegion = region
            isProgrammaticCameraChange = true
            cameraPosition = mapCameraPosition(from: region)
        }
    }

    @ViewBuilder
    private func detailAnnotationView(for annotation: MissionMapAnnotation) -> some View {
        switch annotation.kind {
        case .team(let accuracy):
            VStack(spacing: 6) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 22, height: 22)
                Text("Team")
                    .font(.caption.weight(.semibold))
                    .padding(6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                if let cep = formattedCEP(accuracy) {
                    Text(cep)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        case .latest(let device, let coordinateText, let accuracy):
            Button {
                selectedDevice = device
                onSelectDevice(device)
            } label: {
                VStack(spacing: 6) {
                    Circle()
                        .fill(annotation.color)
                        .frame(width: 26, height: 26)
                        .shadow(color: annotation.color.opacity(0.5), radius: 6, x: 0, y: 3)
                    VStack(spacing: 2) {
                        Text(device.name)
                            .multilineTextAlignment(.center)
                            .font(.caption.weight(.semibold))
                        Text(coordinateText)
                            .multilineTextAlignment(.center)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let cep = formattedCEP(accuracy) {
                            Text(cep)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(6)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .buttonStyle(.plain)
        case .history:
            Circle()
                .fill(annotation.color)
                .frame(width: 12, height: 12)
        }
    }
}

#Preview {
    MissionDashboardView()
        .environmentObject(MissionController(preview: true))
}
