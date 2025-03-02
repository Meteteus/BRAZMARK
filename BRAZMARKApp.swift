import SwiftUI

@main
struct BRAZMARKApp: App {
    @StateObject private var processor = AudioProcessor()
    @Environment(\.scenePhase) private var scenePhase
    
    // Use AppDelegate for app lifecycle monitoring
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(processor)
                .frame(minWidth: 920, minHeight: 820) // Set minimum size
                .onAppear {
                    // Apply theme after the view appears
                    processor.currentTheme.apply()
                    
                    // Initialize app delegate with processor reference
                    appDelegate.processor = processor
                }
        }
        // Monitor app state changes
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                break
            case .inactive:
                // Save state when app becomes inactive
                processor.saveApplicationState()
            case .background:
                // Save state when app goes to background
                processor.saveApplicationState()
            @unknown default:
                break
            }
        }
    }
}

// AppDelegate for lifecycle and exception handling
class AppDelegate: NSObject, NSApplicationDelegate {
    var processor: AudioProcessor?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up global exception handler
        NSSetUncaughtExceptionHandler { exception in
            // Log the exception
            print("UNCAUGHT EXCEPTION: \(exception)")
            print("Stack trace: \(exception.callStackSymbols.joined(separator: "\n"))")
            
            // Log to file
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let crashLogURL = documentsDirectory.appendingPathComponent("BRAZMARK_crash_log.txt")
            
            let timestamp = Date().ISO8601Format()
            let crashLog = """
            
            ===== Crash Report =====
            Timestamp: \(timestamp)
            Exception: \(exception)
            Reason: \(exception.reason ?? "Unknown")
            
            Stack Trace:
            \(exception.callStackSymbols.joined(separator: "\n"))
            =======================
            
            """
            
            try? crashLog.write(to: crashLogURL, atomically: true, encoding: .utf8)
            
            // Mark app as terminated unexpectedly
            UserDefaults.standard.set(true, forKey: "AppTerminatedUnexpectedly")
        }
        
        // Register for termination notification
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationWillTerminate(_:)),
            name: NSWorkspace.willPowerOffNotification,
            object: nil
        )
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Save state on app termination
        processor?.saveApplicationState()
    }
    
    // Handle unexpected termination recovery
    func applicationDidBecomeActive(_ notification: Notification) {
        // Check if we need to recover from unexpected termination
        if UserDefaults.standard.bool(forKey: "AppTerminatedUnexpectedly") {
            // Clear the flag
            UserDefaults.standard.set(false, forKey: "AppTerminatedUnexpectedly")
            
            // Show recovery dialog
            let alert = NSAlert()
            alert.messageText = "Application Recovery"
            alert.informativeText = "The application was terminated unexpectedly. Would you like to recover your last saved state?"
            alert.addButton(withTitle: "Recover")
            alert.addButton(withTitle: "Start Fresh")
            
            if alert.runModal() == .alertFirstButtonReturn {
                processor?.restoreApplicationState()
            }
        }
    }
}

// Debug view for performance monitoring
#if DEBUG
struct DebugTabView: View {
    @State private var performanceStats: [PerformanceStatistics] = []
    @State private var selectedTab = 0
    
    var body: some View {
        VStack {
            Picker("", selection: $selectedTab) {
                Text("Performance").tag(0)
                Text("Error Log").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            if selectedTab == 0 {
                PerformanceView()
            } else {
                ErrorLogView()
            }
        }
        .padding()
    }
}

struct PerformanceView: View {
    @State private var performanceStats: [PerformanceStatistics] = []
    @State private var refreshTimer: Timer?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Performance Metrics")
                .font(.headline)
            
            HStack {
                Button("Refresh") {
                    updateStats()
                }
                
                Button("Reset Stats") {
                    PerformanceMonitor.shared.resetMeasurements()
                    updateStats()
                }
            }
            
            if performanceStats.isEmpty {
                Text("No performance data collected yet")
                    .foregroundColor(.gray)
                    .italic()
            } else {
                // Stats table
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Operation")
                            .font(.headline)
                            .frame(width: 200, alignment: .leading)
                        Text("Avg (s)")
                            .font(.headline)
                            .frame(width: 80, alignment: .trailing)
                        Text("Min (s)")
                            .font(.headline)
                            .frame(width: 80, alignment: .trailing)
                        Text("Max (s)")
                            .font(.headline)
                            .frame(width: 80, alignment: .trailing)
                        Text("Count")
                            .font(.headline)
                            .frame(width: 60, alignment: .trailing)
                    }
                    .padding(.bottom, 5)
                    
                    Divider()
                    
                    ForEach(performanceStats, id: \.operationName) { stat in
                        HStack {
                            Text(stat.operationName)
                                .frame(width: 200, alignment: .leading)
                            Text(stat.formattedAverage)
                                .frame(width: 80, alignment: .trailing)
                            Text(stat.formattedMin)
                                .frame(width: 80, alignment: .trailing)
                            Text(stat.formattedMax)
                                .frame(width: 80, alignment: .trailing)
                            Text("\(stat.numberOfMeasurements)")
                                .frame(width: 60, alignment: .trailing)
                        }
                        .padding(.vertical, 3)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .onAppear {
            updateStats()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                updateStats()
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }
    
    private func updateStats() {
        performanceStats = PerformanceMonitor.shared.getAllStatistics()
            .sorted(by: { $0.averageDuration > $1.averageDuration })
    }
}
#endif
