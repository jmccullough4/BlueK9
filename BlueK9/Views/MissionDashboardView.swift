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
    @State private var sortOrder: DeviceSortOrder = .signal

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
            withAnimation {
                region.center = coordinate
            }
        }
        .onChange(of: controller.devices) { _ in
            updateRegionToFitAnnotations()
        }
        .onChange(of: mapScope) { _ in
            updateRegionToFitAnnotations()
        }
        .onAppear {
            updateRegionToFitAnnotations()
        }
        .fullScreenCover(isPresented: $isMapExpanded) {
            MissionMapDetailView(region: $region, scope: $mapScope, selectedDevice: $selectedDeviceForDetails)
                .environmentObject(controller)
        }
        .sheet(item: $selectedDeviceForDetails) { device in
            MissionDeviceInfoSheet(
                device: device,
                coordinateMode: controller.coordinateDisplayMode,
                isTarget: controller.targetDeviceID == device.id,
                onMarkTarget: { controller.setTarget(device) },
                onClearTarget: { controller.clearTarget() },
                onActiveGeo: { controller.performActiveGeo(on: device.id) },
                onGetInfo: { controller.requestDeviceInfo(for: device.id) }
            )
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

            Map(coordinateRegion: $region, interactionModes: [.all], showsUserLocation: false, userTrackingMode: nil, annotationItems: mapAnnotations) { annotation in
                MapAnnotation(coordinate: annotation.coordinate) {
                    switch annotation.kind {
                    case .team:
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
                        }
                    case .latest(let device, let coordinateText):
                        Button {
                            selectedDeviceForDetails = device
                        } label: {
                            VStack(spacing: 4) {
                                ZStack {
                                    Circle().fill(annotation.color.opacity(0.32)).frame(width: 48, height: 48)
                                    Circle().fill(annotation.color).frame(width: 20, height: 20)
                                }
                                Text("\(device.name)\n\(coordinateText)")
                                    .multilineTextAlignment(.center)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
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
            devices: controller.devices,
            coordinateMode: controller.coordinateDisplayMode,
            targetDeviceID: controller.targetDeviceID,
            scope: mapScope
        )
    }

    private var mapAnnotations: [MissionMapAnnotation] {
        mapData.annotations
    }

    private var mapCoordinates: [CLLocationCoordinate2D] {
        mapData.coordinates
    }

    private var sortedDevices: [BluetoothDevice] {
        switch sortOrder {
        case .signal:
            return controller.devices.sorted { $0.lastRSSI > $1.lastRSSI }
        case .recent:
            return controller.devices.sorted { $0.lastSeen > $1.lastSeen }
        case .name:
            return controller.devices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .range:
            return controller.devices.sorted {
                let lhs = $0.estimatedRange ?? .greatestFiniteMagnitude
                let rhs = $1.estimatedRange ?? .greatestFiniteMagnitude
                if lhs == rhs {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return lhs < rhs
            }
        }
    }

    private func updateRegionToFitAnnotations() {
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

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Devices", systemImage: "dot.radiowaves.left.and.right")
                .font(.title2.bold())
            Picker("Sort", selection: $sortOrder) {
                ForEach(DeviceSortOrder.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)

            ForEach(sortedDevices) { device in
                MissionDeviceRow(device: device, coordinateMode: controller.coordinateDisplayMode, isTarget: controller.targetDeviceID == device.id, onMarkTarget: { controller.setTarget(device) }, onClearTarget: { controller.clearTarget() }, onActiveGeo: { controller.performActiveGeo(on: device.id) }, onGetInfo: { controller.requestDeviceInfo(for: device.id) })
            }
            if controller.devices.isEmpty {
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
        case team
        case latest(device: BluetoothDevice, coordinateText: String)
        case history(deviceID: UUID)
    }

    static let teamIdentifier = UUID()

    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let color: Color
    let kind: Kind

    init(id: UUID = UUID(), coordinate: CLLocationCoordinate2D, color: Color, kind: Kind) {
        self.id = id
        self.coordinate = coordinate
        self.color = color
        self.kind = kind
    }
}

private struct MissionMapData {
    let annotations: [MissionMapAnnotation]
    let coordinates: [CLLocationCoordinate2D]

    init(teamCoordinate: CLLocationCoordinate2D?, devices: [BluetoothDevice], coordinateMode: CoordinateDisplayMode, targetDeviceID: UUID?, scope: MissionMapScope) {
        var annotations: [MissionMapAnnotation] = []
        var coordinates: [CLLocationCoordinate2D] = []

        if let teamCoordinate {
            annotations.append(MissionMapAnnotation(id: MissionMapAnnotation.teamIdentifier, coordinate: teamCoordinate, color: .blue, kind: .team))
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
                    annotations.append(MissionMapAnnotation(id: geo.id, coordinate: geo.coordinate, color: baseColor, kind: .latest(device: device, coordinateText: coordinateText)))
                } else {
                    annotations.append(MissionMapAnnotation(id: geo.id, coordinate: geo.coordinate, color: historyColor, kind: .history(deviceID: device.id)))
                }
            }
        }

        self.annotations = annotations
        self.coordinates = coordinates
    }
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
        }
    }
}

private struct MissionMapDetailView: View {
    @EnvironmentObject private var controller: MissionController
    @Environment(\.dismiss) private var dismiss
    @Binding var region: MKCoordinateRegion
    @Binding var scope: MissionMapScope
    @Binding var selectedDevice: BluetoothDevice?

    private var mapData: MissionMapData {
        MissionMapData(
            teamCoordinate: controller.location,
            devices: controller.devices,
            coordinateMode: controller.coordinateDisplayMode,
            targetDeviceID: controller.targetDeviceID,
            scope: scope
        )
    }

    var body: some View {
        NavigationStack {
            Map(coordinateRegion: $region, interactionModes: [.all], showsUserLocation: false, userTrackingMode: nil, annotationItems: mapData.annotations) { annotation in
                MapAnnotation(coordinate: annotation.coordinate) {
                    switch annotation.kind {
                    case .team:
                        VStack(spacing: 6) {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 22, height: 22)
                            Text("Team")
                                .font(.caption.weight(.semibold))
                                .padding(6)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                        }
                    case .latest(let device, let coordinateText):
                        Button {
                            selectedDevice = device
                        } label: {
                            VStack(spacing: 6) {
                                Circle()
                                    .fill(annotation.color)
                                    .frame(width: 26, height: 26)
                                    .shadow(color: annotation.color.opacity(0.5), radius: 6, x: 0, y: 3)
                                Text("\(device.name)\n\(coordinateText)")
                                    .multilineTextAlignment(.center)
                                    .font(.caption.weight(.semibold))
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
            .mapStyle(.standard)
            .ignoresSafeArea()
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
    let onMarkTarget: () -> Void
    let onClearTarget: () -> Void
    let onActiveGeo: () -> Void
    let onGetInfo: () -> Void

    private var coordinateText: String? {
        if let display = device.displayCoordinate {
            return display
        }
        guard let location = device.lastKnownLocation?.coordinate else { return nil }
        return CoordinateFormatter.shared.string(from: location, mode: coordinateMode)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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

private struct MissionMapAnnotation: Identifiable {
    enum Kind {
        case user
        case device(BluetoothDevice)
    }

    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let label: String?
    let color: Color
    let kind: Kind
}

#Preview {
    MissionDashboardView()
        .environmentObject(MissionController(preview: true))
}
