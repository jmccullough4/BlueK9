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
            }
            Map(coordinateRegion: $region, interactionModes: [.all], showsUserLocation: false, userTrackingMode: nil, annotationItems: controller.location.map { [MissionLocationPin(coordinate: $0)] } ?? []) { pin in
                MapAnnotation(coordinate: pin.coordinate) {
                    ZStack {
                        Circle().fill(Color.blue.opacity(0.3)).frame(width: 44, height: 44)
                        Circle().fill(Color.blue).frame(width: 16, height: 16)
                    }
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Color.blue.opacity(0.25), lineWidth: 1)
            }
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

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Devices", systemImage: "dot.radiowaves.left.and.right")
                .font(.title2.bold())
            ForEach(controller.devices) { device in
                MissionDeviceRow(device: device)
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

private struct MissionLocationPin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

#Preview {
    MissionDashboardView()
        .environmentObject(MissionController(preview: true))
}
