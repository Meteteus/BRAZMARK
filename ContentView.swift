import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var processor: AudioProcessor
    @State private var selectedTab: TabType = .files
    @State private var showingPreview = false
    
    enum TabType: String, CaseIterable {
        case files = "Files"
        case settings = "Settings"
        case history = "History"
        case workflows = "Workflows"
        #if DEBUG
        case debug = "Debug"
        #endif
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HeaderView()
                .frame(height: 80) // Fixed height for header
            
            // Tab Selection
            TabSelectionView(selectedTab: $selectedTab)
                .frame(height: 55) // Fixed height for tab bar
            
            // Main Content Area - scrollable if needed
            ScrollView {
                Group {
                    switch selectedTab {
                    case .files:
                        FilesTabView(showingPreview: $showingPreview)
                    case .settings:
                        SettingsTabView()
                    case .history:
                        HistoryTabView()
                    case .workflows:
                        WorkflowsTabView()
                    #if DEBUG
                    case .debug:
                        DebugTabView()
                    #endif
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(processor.currentTheme.backgroundColor)
        }
        .sheet(isPresented: $showingPreview) {
            PreviewView()
                .environmentObject(processor)
                .frame(width: 600, height: 500)
                .task {
                    // Ensure preview generation happens after view appears
                    if let songURL = processor.fileDatabase.songs.first?.url,
                       let watermarkURL = processor.fileDatabase.watermarks.first?.url {
                        await processor.generateWatermarkPreview(
                            songURL: songURL,
                            watermarkURL: watermarkURL
                        )
                    }
                }
        }
        .frame(minWidth: 920, minHeight: 820) // Set minimum size constraints
    }
}

// MARK: - Tab Selection View
struct TabSelectionView: View {
    @Binding var selectedTab: ContentView.TabType
    @EnvironmentObject var processor: AudioProcessor
    
    var body: some View {
        GeometryReader { geometry in
            // Calculate tab width based on available space
            let tabWidth = geometry.size.width / CGFloat(ContentView.TabType.allCases.count)
            
            HStack(spacing: 0) {
                ForEach(ContentView.TabType.allCases, id: \.self) { tab in
                    // Use a Button with a larger hit area instead of a ZStack with onTapGesture
                    Button(action: {
                        selectedTab = tab
                    }) {
                        // Fill entire available space (this is the hit area)
                        VStack(spacing: 4) {
                            Image(systemName: iconForTab(tab))
                                .font(.system(size: 16))
                            
                            Text(tab.rawValue)
                                .font(.system(size: 12))
                        }
                        .frame(width: tabWidth, height: 55) // Explicit size
                        .contentShape(Rectangle()) // Makes entire area clickable
                    }
                    .buttonStyle(TabButtonStyle(isSelected: selectedTab == tab, theme: processor.currentTheme))
                }
            }
        }
        .frame(height: 55) // Fixed height for the tab bar
        .background(Color.gray.opacity(0.1))
    }
    
    private func iconForTab(_ tab: ContentView.TabType) -> String {
        switch tab {
        case .files: return "music.note.list"
        case .settings: return "gear"
        case .history: return "clock.arrow.circlepath"
        case .workflows: return "rectangle.stack.fill"
        #if DEBUG
        case .debug: return "speedometer"
        #endif
        }
    }
}

// Custom button style for tabs
struct TabButtonStyle: ButtonStyle {
    let isSelected: Bool
    let theme: AppTheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isSelected ? theme.accentColor : theme.secondaryTextColor)
            .background(
                isSelected ?
                theme.accentColor.opacity(0.1) :
                Color.clear
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0) // Subtle press effect
    }
}

// MARK: - Header View
struct HeaderView: View {
    @EnvironmentObject var processor: AudioProcessor
    @State private var showingImportExport = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Braz Mark")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(processor.currentTheme.textColor)
                
                Text("Batch Watermark Processor")
                    .font(.system(size: 18, weight: .medium, design: .default))
                    .foregroundColor(processor.currentTheme.secondaryTextColor)
            }
            
            Spacer()
            
            // Actions menu
            Menu {
                Button("Import Settings...") {
                    processor.showImportPanel()
                }
                
                Menu("Export") {
                    Button("Export All Settings...") {
                        processor.exportAllSettings()
                    }
                    
                    Button("Export Presets...") {
                        processor.exportPresets()
                    }
                    
                    Button("Export Workflows...") {
                        processor.exportWorkflowTemplates()
                    }
                }
                
                Divider()
                
                // Theme selection
                Menu("Theme") {
                    ForEach(AppTheme.allCases) { theme in
                        Button(theme.displayName) {
                            processor.setTheme(theme)
                        }
                        .foregroundColor(theme == processor.currentTheme ? theme.accentColor : nil)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20))
                    .foregroundColor(processor.currentTheme.accentColor)
            }
        }
        .padding()
        .background(processor.currentTheme.backgroundColor)
    }
}

// MARK: - Files Tab
struct FilesTabView: View {
    @EnvironmentObject var processor: AudioProcessor
    @Binding var showingPreview: Bool
    
    var body: some View {
        VStack(spacing: 15) {
            // Settings section
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Output Settings")
                        .font(.headline)
                        .foregroundColor(processor.currentTheme.textColor)
                    
                    Spacer()
                    
                    Button("Preview") {
                        Task {
                            await processor.generateWatermarkPreview()
                            showingPreview = true
                        }
                    }
                    .disabled(processor.fileDatabase.songs.isEmpty || processor.fileDatabase.watermarks.isEmpty)
                }
                
                // Format Controls
                FormatControlsView()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(processor.currentTheme.backgroundColor)
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
            
            // Watermark Groups View
            WatermarkGroupView()
                .environmentObject(processor)
            
            // File Selection
            HStack(alignment: .top, spacing: 12) {
                DatabaseFileSelectionView(title: "Songs", fileType: .song)
                    .environmentObject(processor)
                    .frame(maxWidth: .infinity)
                
                DatabaseFileSelectionView(title: "Watermarks", fileType: .watermark)
                    .environmentObject(processor)
                    .frame(maxWidth: .infinity)
            }
            
            // Output folder and processing
            VStack(spacing: 15) {
                HStack {
                    // Output folder
                    OutputFolderView(outputFolder: $processor.outputFolder)
                    
                    Spacer()
                    
                    // Name pattern selection
                    Menu {
                        ForEach(processor.savedNamePatterns) { pattern in
                            Button(pattern.name) {
                                processor.outputNamePattern = pattern
                            }
                        }
                        
                        Divider()
                        
                        Button("Save Current Pattern...") {
                            // Show save dialog
                            let alert = NSAlert()
                            alert.messageText = "Save Name Pattern"
                            alert.informativeText = "Enter a name for this pattern:"
                            
                            let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
                            textField.placeholderString = "Pattern Name"
                            
                            alert.accessoryView = textField
                            alert.addButton(withTitle: "Save")
                            alert.addButton(withTitle: "Cancel")
                            
                            if alert.runModal() == .alertFirstButtonReturn {
                                let patternName = textField.stringValue
                                if !patternName.isEmpty {
                                    processor.saveCurrentNamePattern(name: patternName)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text("Name Pattern: \(processor.outputNamePattern.name)")
                                .lineLimit(1)
                            
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(processor.currentTheme.borderColor, lineWidth: 1)
                        )
                    }
                }
                
                // Progress bar
                CustomProgressView(
                    progress: processor.progress,
                    currentFile: processor.currentFile,
                    currentWatermark: processor.currentWatermark,
                    isProcessing: processor.isProcessing
                )
                
                // Start/Cancel button
                HStack {
                    if processor.isProcessing {
                        Button("Cancel", action: processor.cancelProcessing)
                            .foregroundColor(.red)
                    } else {
                        Button("Start Processing") { processor.startProcessing() }
                            .disabled(!canStartProcessing)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(processor.currentTheme.backgroundColor)
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
        }
    }
    
    private var canStartProcessing: Bool {
        !processor.fileDatabase.songs.isEmpty &&
        !processor.fileDatabase.watermarks.isEmpty &&
        processor.outputFolder != nil &&
        (processor.settings.processingMode == .allCombinations ||
         processor.fileDatabase.songs.count == processor.fileDatabase.watermarks.count)
    }
}

// MARK: - Settings Tab
struct SettingsTabView: View {
    @EnvironmentObject var processor: AudioProcessor
    @State private var newPresetName = ""
    @State private var showingNewPresetDialog = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Presets Section
            VStack(alignment: .leading, spacing: 15) {
                Text("Presets")
                    .font(.headline)
                    .foregroundColor(processor.currentTheme.textColor)
                
                HStack {
                    Text("Manage saved settings presets")
                        .foregroundColor(processor.currentTheme.secondaryTextColor)
                    
                    Spacer()
                    
                    Button("Save Current") {
                        showingNewPresetDialog = true
                    }
                    .popover(isPresented: $showingNewPresetDialog) {
                        VStack(spacing: 15) {
                            Text("Save Current Settings as Preset")
                                .font(.headline)
                            
                            TextField("Preset Name", text: $newPresetName)
                                .frame(width: 250)
                            
                            HStack {
                                Button("Cancel") {
                                    newPresetName = ""
                                    showingNewPresetDialog = false
                                }
                                
                                Button("Save") {
                                    if !newPresetName.isEmpty {
                                        processor.saveCurrentSettingsAsPreset(name: newPresetName)
                                        newPresetName = ""
                                        showingNewPresetDialog = false
                                    }
                                }
                                .disabled(newPresetName.isEmpty)
                            }
                            .padding()
                        }
                        .padding()
                    }
                }
                
                // Presets list
                if processor.presets.isEmpty {
                    Text("No presets saved")
                        .italic()
                        .foregroundColor(processor.currentTheme.secondaryTextColor)
                        .padding()
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(processor.presets) { preset in
                                HStack {
                                    Text(preset.name)
                                        .foregroundColor(processor.currentTheme.textColor)
                                    
                                    Spacer()
                                    
                                    Button("Apply") {
                                        processor.applyPreset(preset)
                                    }
                                    .buttonStyle(.bordered)
                                    
                                    Button(action: {
                                        // Show confirmation dialog
                                        let alert = NSAlert()
                                        alert.messageText = "Delete Preset"
                                        alert.informativeText = "Are you sure you want to delete the preset '\(preset.name)'?"
                                        alert.addButton(withTitle: "Delete")
                                        alert.addButton(withTitle: "Cancel")
                                        alert.alertStyle = .warning
                                        
                                        if alert.runModal() == .alertFirstButtonReturn {
                                            processor.deletePreset(preset)
                                        }
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(.vertical, 5)
                                .padding(.horizontal, 10)
                                .background(Color.gray.opacity(0.1).cornerRadius(5))
                            }
                        }
                    }
                    .frame(height: 200)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(processor.currentTheme.backgroundColor)
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
            
            // Advanced Settings
            VStack(alignment: .leading, spacing: 15) {
                Text("Advanced Settings")
                    .font(.headline)
                    .foregroundColor(processor.currentTheme.textColor)
                
                Group {
                    Toggle("Automatically Convert Input Formats", isOn: $processor.settings.automaticallyConvertInputFormats)
                    Toggle("Keep Original Files", isOn: $processor.settings.keepOriginalFiles)
                    Toggle("Use Background Processing", isOn: $processor.settings.useBackgroundProcessing)
                    Toggle("Show Notifications When Complete", isOn: $processor.settings.showNotificationsWhenComplete)
                    Toggle("Show Processing History", isOn: $processor.settings.showProcessingHistory)
                    Toggle("Confirm Before Deleting Files", isOn: $processor.settings.confirmBeforeDeleting)
                }
                .foregroundColor(processor.currentTheme.textColor)
                
                // Max concurrent tasks
                HStack {
                    Text("Maximum Concurrent Processing Tasks:")
                        .foregroundColor(processor.currentTheme.textColor)
                    
                    Slider(
                        value: Binding<Double>(
                            get: { Double(processor.settings.maxConcurrentProcessingTasks) },
                            set: { processor.settings.maxConcurrentProcessingTasks = Int($0) }
                        ),
                        in: 1...8,
                        step: 1
                    )
                    .disabled(!processor.settings.useBackgroundProcessing)
                    
                    Text("\(processor.settings.maxConcurrentProcessingTasks)")
                        .foregroundColor(processor.currentTheme.textColor)
                        .frame(width: 30)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(processor.currentTheme.backgroundColor)
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
        }
    }
}

// MARK: - History Tab
struct HistoryTabView: View {
    @EnvironmentObject var processor: AudioProcessor
    @State private var searchText = ""
    
    var filteredJobs: [ProcessingJob] {
        if searchText.isEmpty {
            return processor.processingHistory
        } else {
            return processor.processingHistory.filter { job in
                job.formattedDate.lowercased().contains(searchText.lowercased()) ||
                job.outputFormat.lowercased().contains(searchText.lowercased()) ||
                (job.watermarkGroup?.lowercased().contains(searchText.lowercased()) ?? false) ||
                job.outputFolder.lowercased().contains(searchText.lowercased())
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 15) {
            HStack {
                Text("Processing History")
                    .font(.headline)
                    .foregroundColor(processor.currentTheme.textColor)
                
                Spacer()
                
                TextField("Search", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 200)
                
                Button("Clear History") {
                    // Show confirmation
                    let alert = NSAlert()
                    alert.messageText = "Clear History"
                    alert.informativeText = "Are you sure you want to clear all processing history?"
                    alert.addButton(withTitle: "Clear")
                    alert.addButton(withTitle: "Cancel")
                    alert.alertStyle = .warning
                    
                    if alert.runModal() == .alertFirstButtonReturn {
                        processor.clearProcessingHistory()
                    }
                }
                .disabled(processor.processingHistory.isEmpty)
            }
            
            if processor.processingHistory.isEmpty {
                Spacer()
                Text("No processing history found")
                    .foregroundColor(processor.currentTheme.secondaryTextColor)
                    .italic()
                Spacer()
            } else {
                // Column headers
                HStack {
                    Text("Date")
                        .frame(width: 180, alignment: .leading)
                    Text("Details")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Files")
                        .frame(width: 100, alignment: .trailing)
                    Text("Duration")
                        .frame(width: 100, alignment: .trailing)
                }
                .foregroundColor(processor.currentTheme.secondaryTextColor)
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 8)
                
                // Job list
                List {
                    ForEach(filteredJobs) { job in
                        HStack {
                            Text(job.formattedDate)
                                .foregroundColor(processor.currentTheme.textColor)
                                .frame(width: 180, alignment: .leading)
                            
                            VStack(alignment: .leading) {
                                HStack {
                                    Text("Format: \(job.outputFormat.uppercased())")
                                        .foregroundColor(processor.currentTheme.textColor)
                                    
                                    if let group = job.watermarkGroup {
                                        Text("Group: \(group)")
                                            .foregroundColor(processor.currentTheme.accentColor)
                                    }
                                }
                                
                                Text(job.outputFolder)
                                    .font(.system(size: 12))
                                    .foregroundColor(processor.currentTheme.secondaryTextColor)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text("\(job.totalFilesProcessed) / \(job.songCount * job.watermarkCount)")
                                .foregroundColor(processor.currentTheme.textColor)
                                .frame(width: 100, alignment: .trailing)
                            
                            Text(job.formattedDuration)
                                .foregroundColor(processor.currentTheme.textColor)
                                .frame(width: 100, alignment: .trailing)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
    }
}

// MARK: - Workflows Tab
struct WorkflowsTabView: View {
    @EnvironmentObject var processor: AudioProcessor
    @State private var selectedWorkflow: WorkflowTemplate?
    @State private var newWorkflowName = ""
    @State private var newWorkflowDescription = ""
    @State private var showingNewWorkflowDialog = false
    
    var body: some View {
        VStack(spacing: 15) {
            HStack {
                Text("Workflow Templates")
                    .font(.headline)
                    .foregroundColor(processor.currentTheme.textColor)
                
                Spacer()
                
                Button("Save Current Workflow") {
                    showingNewWorkflowDialog = true
                }
                .popover(isPresented: $showingNewWorkflowDialog) {
                    VStack(spacing: 15) {
                        Text("Save Current Settings as Workflow")
                            .font(.headline)
                        
                        TextField("Workflow Name", text: $newWorkflowName)
                            .frame(width: 300)
                        
                        TextField("Description (optional)", text: $newWorkflowDescription)
                            .frame(width: 300)
                        
                        HStack {
                            Button("Cancel") {
                                newWorkflowName = ""
                                newWorkflowDescription = ""
                                showingNewWorkflowDialog = false
                            }
                            
                            Button("Save") {
                                if !newWorkflowName.isEmpty {
                                    processor.saveCurrentAsWorkflowTemplate(
                                        name: newWorkflowName,
                                        description: newWorkflowDescription
                                    )
                                    newWorkflowName = ""
                                    newWorkflowDescription = ""
                                    showingNewWorkflowDialog = false
                                }
                            }
                            .disabled(newWorkflowName.isEmpty)
                        }
                        .padding()
                    }
                    .padding()
                }
            }
            
            HStack(alignment: .top, spacing: 20) {
                // Workflow list
                VStack(alignment: .leading, spacing: 10) {
                    Text("Available Workflows")
                        .font(.headline)
                        .foregroundColor(processor.currentTheme.secondaryTextColor)
                    
                    List(processor.workflowTemplates, selection: $selectedWorkflow) { workflow in
                        VStack(alignment: .leading) {
                            Text(workflow.name)
                                .foregroundColor(processor.currentTheme.textColor)
                                .font(.headline)
                            
                            if !workflow.description.isEmpty {
                                Text(workflow.description)
                                    .font(.caption)
                                    .foregroundColor(processor.currentTheme.secondaryTextColor)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(PlainListStyle())
                    .background(processor.currentTheme.backgroundColor)
                }
                .frame(width: 250)
                
                // Workflow details
                VStack(alignment: .leading, spacing: 15) {
                    if let workflow = selectedWorkflow {
                        Text("Workflow Details")
                            .font(.headline)
                            .foregroundColor(processor.currentTheme.secondaryTextColor)
                        
                        Group {
                            detailRow("Name", workflow.name)
                            detailRow("Description", workflow.description.isEmpty ? "No description" : workflow.description)
                            detailRow("Created", formatDate(workflow.dateCreated))
                            detailRow("Modified", formatDate(workflow.dateModified))
                            detailRow("Output Format", workflow.outputFormat.rawValue.uppercased())
                            detailRow("Processing Mode", processingModeString(workflow.processingMode))
                            detailRow("Watermark Pattern", workflow.watermarkSettings.watermarkPattern.displayName)
                            detailRow("Output Naming", workflow.outputNamePattern.name)
                        }
                        
                        HStack {
                            Button("Apply This Workflow") {
                                processor.applyWorkflowTemplate(workflow)
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Spacer()
                            
                            Button(action: {
                                // Show confirmation dialog
                                let alert = NSAlert()
                                alert.messageText = "Delete Workflow"
                                alert.informativeText = "Are you sure you want to delete '\(workflow.name)'?"
                                alert.addButton(withTitle: "Delete")
                                alert.addButton(withTitle: "Cancel")
                                alert.alertStyle = .warning
                                
                                if alert.runModal() == .alertFirstButtonReturn {
                                    processor.deleteWorkflowTemplate(workflow)
                                    selectedWorkflow = nil
                                }
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.top, 10)
                    } else {
                        Spacer()
                        Text("Select a workflow to view details")
                            .foregroundColor(processor.currentTheme.secondaryTextColor)
                            .italic()
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(processor.currentTheme.backgroundColor.opacity(0.5))
                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                )
            }
        }
    }
    
    // Helper function for displaying details
    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .foregroundColor(processor.currentTheme.textColor)
                .frame(width: 120, alignment: .trailing)
                .font(.system(size: 14, weight: .semibold))
            
            Text(value)
                .foregroundColor(processor.currentTheme.textColor)
                .font(.system(size: 14))
        }
        .padding(.vertical, 2)
    }
    
    // Helper for formatting dates
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // Helper for processing mode string
    private func processingModeString(_ mode: ProcessingMode) -> String {
        switch mode {
        case .allCombinations: return "All Combinations"
        case .oneToOne: return "One-to-One"
        }
    }
}

// MARK: - Format Controls
struct FormatControlsView: View {
    @EnvironmentObject var processor: AudioProcessor
    
    var body: some View {
        VStack(spacing: 15) {
            HStack {
                Picker("Output Format:", selection: $processor.settings.outputFormat) {
                    Text("MP3").tag(OutputFormat.mp3)
                    Text("WAV").tag(OutputFormat.wav)
                }
                
                Picker("Processing Mode:", selection: $processor.settings.processingMode) {
                    Text("All Combinations").tag(ProcessingMode.allCombinations)
                    Text("1:1 Pairing").tag(ProcessingMode.oneToOne)
                }
            }
            
            // Watermark Pattern Controls
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Watermark Pattern:")
                    
                    Picker("", selection: $processor.settings.watermarkSettings.watermarkPattern) {
                        ForEach(WatermarkPattern.allCases) { pattern in
                            Text(pattern.displayName).tag(pattern)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)
                    
                    Spacer()
                    
                    Text(processor.settings.watermarkSettings.watermarkPattern.description)
                        .font(.caption)
                        .foregroundColor(processor.currentTheme.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                HStack {
                    Text("Initial Delay:")
                    TextField("Seconds", value: $processor.settings.initialDelay, format: .number)
                        .frame(width: 60)
                    Text("seconds")
                }
                
                if processor.settings.watermarkSettings.watermarkPattern == .regularInterval ||
                   processor.settings.watermarkSettings.watermarkPattern == .randomInterval {
                    HStack {
                        Text("Interval:")
                        TextField("Seconds", value: $processor.settings.loopInterval, format: .number)
                            .frame(width: 60)
                        Text("seconds")
                    }
                }
                
                if processor.settings.watermarkSettings.watermarkPattern == .randomInterval {
                    HStack {
                        Text("Randomness:")
                        Slider(value: $processor.settings.watermarkSettings.randomnessAmount, in: 0.1...1.0, step: 0.1)
                        Text("\(Int(processor.settings.watermarkSettings.randomnessAmount * 100))%")
                    }
                }
                
                if processor.settings.watermarkSettings.watermarkPattern == .fadeInOut {
                    HStack {
                        Text("Fade Duration:")
                        TextField("Seconds", value: $processor.settings.watermarkSettings.fadeDuration, format: .number)
                            .frame(width: 60)
                        Text("seconds")
                    }
                }
            }
            
            HStack {
                Text("Watermark Volume:")
                Slider(value: $processor.settings.watermarkVolume, in: 0.01...1.0, step: 0.01)
                Text("\(Int(processor.settings.watermarkVolume * 100))%")
                
                // Keep watermark settings synced
                Spacer()
                    .onChange(of: processor.settings.watermarkVolume) { _ in
                        processor.settings.watermarkSettings.watermarkVolume = processor.settings.watermarkVolume
                    }
            }
        }
    }
}

// MARK: - Output Folder View
struct OutputFolderView: View {
    @Binding var outputFolder: URL?
    @EnvironmentObject var processor: AudioProcessor
    
    var body: some View {
        HStack {
            Text("Output Folder:")
                .foregroundColor(processor.currentTheme.textColor)
            
            Text(outputFolder?.lastPathComponent ?? "Not Selected")
                .foregroundColor(processor.currentTheme.secondaryTextColor)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 200)
            
            Button("Choose...") { selectFolder() }
        }
    }
    
    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Select Output Folder"
        
        guard panel.runModal() == .OK else { return }
        outputFolder = panel.urls.first
    }
}

// MARK: - Progress View
struct CustomProgressView: View {
    let progress: Double
    let currentFile: String
    let currentWatermark: String
    let isProcessing: Bool
    @State private var isAnimating = false
    @EnvironmentObject var processor: AudioProcessor
    @State private var timer: Timer?
    @State private var currentTime = Date()
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                SwiftUI.ProgressView(value: progress, total: 100)
                    .progressViewStyle(.linear)
                    .frame(width: 260)
                    .animation(.easeInOut, value: progress)
                
                Text("\(Int(progress))%")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(processor.currentTheme.accentColor)
                    .frame(width: 40, alignment: .leading)
                
                if isProcessing && progress > 0 && progress < 100 {
                    Text(estimatedTimeRemainingText())
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(processor.currentTheme.secondaryTextColor)
                        .frame(width: 110, alignment: .trailing)
                }
                
                // Activity indicator that shows when processing is active
                if isProcessing {
                    Circle()
                        .fill(processor.currentTheme.accentColor.opacity(0.7))
                        .frame(width: 12, height: 12)
                        .scaleEffect(isAnimating ? 0.7 : 1)
                        .opacity(isAnimating ? 0.6 : 1)
                        .animation(
                            isProcessing ?
                                Animation.easeInOut(duration: 0.8)
                                    .repeatForever(autoreverses: true) :
                                .default,
                            value: isAnimating
                        )
                        .onAppear {
                            isAnimating = true
                        }
                        .onDisappear {
                            isAnimating = false
                        }
                }
            }
            
            HStack {
                Text("Processing: \(currentFile)")
                    .font(.caption)
                    .foregroundColor(processor.currentTheme.secondaryTextColor)
                
                if !currentFile.isEmpty && !currentWatermark.isEmpty {
                    Text("+")
                        .font(.caption)
                        .foregroundColor(processor.currentTheme.secondaryTextColor)
                    
                    Text(currentWatermark)
                        .font(.caption)
                        .foregroundColor(processor.currentTheme.secondaryTextColor)
                }
            }
        }
        .padding(.vertical, 10)
        .onAppear {
            setupTimer()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
    
    private func setupTimer() {
        // Start a timer to update current time every second for accurate ETA
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            currentTime = Date()
        }
    }
    
    private func estimatedTimeRemainingText() -> String {
        guard let startTime = processor.processingStartTime, progress > 0 else {
            return ""
        }
        
        let elapsedTime = currentTime.timeIntervalSince(startTime)
        let totalEstimatedTime = elapsedTime / (progress / 100.0)
        let remainingSeconds = Int(totalEstimatedTime - elapsedTime)
        
        // Don't show unrealistic estimates
        if remainingSeconds < 0 || remainingSeconds > 3600 * 24 { // More than a day is likely wrong
            return "Estimating..."
        }
        
        return "ETA: \(formatTime(remainingSeconds))"
    }
    
    // Format seconds into MM:SS
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

// MARK: - Preview View
struct PreviewView: View {
    @EnvironmentObject var processor: AudioProcessor
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Watermark Preview")
                .font(.headline)
                .foregroundColor(processor.currentTheme.textColor)
            
            if processor.previewController.isGenerating {
                ProgressView("Generating preview...")
                    .progressViewStyle(.circular)
                    .foregroundColor(processor.currentTheme.textColor)
            } else if processor.previewController.previewError != nil {
                Text("Error: \(processor.previewController.previewError ?? "Unknown error")")
                    .foregroundColor(.red)
                    .padding()
            } else if processor.previewController.previewDuration > 0 {
                // Waveform display
                WaveformView(data: processor.previewController.previewWaveformData)
                    .frame(height: 100)
                    .padding(.horizontal)
                
                // Playback controls
                HStack(spacing: 20) {
                    Text(formatTime(processor.previewController.currentPlaybackTime))
                        .monospacedDigit()
                        .foregroundColor(processor.currentTheme.textColor)
                    
                    Button(action: {
                        if processor.previewController.isPlaying {
                            processor.previewController.pausePlayback()
                        } else {
                            processor.previewController.playPreview()
                        }
                    }) {
                        Image(systemName: processor.previewController.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(processor.currentTheme.accentColor)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        processor.previewController.stopPlayback()
                    }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(processor.currentTheme.accentColor)
                    }
                    .buttonStyle(.plain)
                    
                    Text(formatTime(processor.previewController.previewDuration))
                        .monospacedDigit()
                        .foregroundColor(processor.currentTheme.textColor)
                }
                .padding()
                
                // Preview options
                HStack {
                    Text("Preview Position:")
                        .foregroundColor(processor.currentTheme.textColor)
                    
                    Picker("", selection: $processor.previewController.startPosition) {
                        ForEach(PreviewStartPosition.allCases) { position in
                            Text(position.displayName).tag(position)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: processor.previewController.startPosition) { _ in
                        // Regenerate preview when position changes
                        Task {
                            await processor.generateWatermarkPreview()
                        }
                    }
                }
                .padding(.horizontal)
            } else {
                Text("No preview available. Generate a preview to listen to your watermark.")
                    .foregroundColor(processor.currentTheme.secondaryTextColor)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            
            Button("Close") {
                dismiss()
                processor.previewController.cleanup()
            }
            .padding(.top, 10)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            processor.previewController.cleanup()
        }
    }
    
    // Format time in MM:SS format
    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

// MARK: - Waveform View
struct WaveformView: View {
    let data: [Float]
    @EnvironmentObject var processor: AudioProcessor
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                ForEach(0..<min(300, data.count), id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(processor.currentTheme.accentColor)
                        .frame(width: 2, height: CGFloat(data[index] * 100))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}
