import SwiftUI

@main
struct BlueK9App: App {
    @StateObject private var controller = MissionController()
    @State private var isShowingSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(controller)
                    .opacity(isShowingSplash ? 0 : 1)

                if isShowingSplash {
                    SplashScreenView()
                        .transition(.opacity)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        isShowingSplash = false
                    }
                }
            }
        }
    }
}
