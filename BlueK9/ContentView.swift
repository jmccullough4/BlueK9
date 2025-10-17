import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var controller: MissionController

    var body: some View {
        NavigationStack {
            MissionDashboardView()
                .environmentObject(controller)
                .navigationTitle("BlueK9 Mission Console")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(MissionController(preview: true))
}
