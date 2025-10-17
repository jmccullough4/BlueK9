import SwiftUI

struct SplashScreenView: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color(.sRGB, red: 7/255, green: 23/255, blue: 43/255, opacity: 1),
                                             Color(.sRGB, red: 17/255, green: 61/255, blue: 98/255, opacity: 1)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Image("BlueK9Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 8)
                    .scaleEffect(animate ? 1.0 : 0.85)
                    .animation(.easeOut(duration: 0.8), value: animate)

                Text("BLUEK9 MISSION CONSOLE")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .kerning(2)
                    .foregroundColor(Color.white.opacity(0.9))
                    .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 4)

                Text("Situational awareness for the field and command center")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.75))
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .onAppear {
                animate = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("BlueK9 mission console is preparing your dashboard")
    }
}

#Preview {
    SplashScreenView()
}
