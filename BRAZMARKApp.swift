import SwiftUI

@main
struct BRAZMARKApp: App {
    @StateObject private var processor = AudioProcessor()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(processor)
                .frame(width: 800, height: 700) // Fixed window size
        }
        .windowResizability(.contentSize) // Disable resizing
    }
}
