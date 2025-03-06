import AVFoundation
import Combine
import AppKit

@MainActor
class AudioProcessor: ObservableObject {
    // MARK: - Published Properties
    
    // Basic file references
    @Published var outputFolder: URL?
    @Published var isProcessing = false
    @Published var progress: Double = 0
    @Published var currentFile = ""
    @Published var currentWatermark = ""
    @Published var processingStartTime: Date?
    
    // File database
    let fileDatabase = AudioFileDatabase()
    @Published var selectedWatermarkGroup: WatermarkGroup?
    
    // Core app settings
    @Published var settings = AppSettings() {
        didSet { saveSettings() }
    }
    
    // Advanced features
    @Published var processingHistory: [ProcessingJob] = []
    @Published var workflowTemplates: [WorkflowTemplate] = []
    @Published var savedNamePatterns: [OutputNamePattern] = [.default, .dated, .clean]
    @Published var outputNamePattern: OutputNamePattern = .default
    @Published var currentTheme: AppTheme = AppTheme.loadSavedTheme()
    @Published var previewController = PreviewController()
    @Published var refreshID = UUID() // For forcing UI updates
    
    // Preset management
    struct SettingsPreset: Identifiable, Codable {
        var id = UUID()
        var name: String
        var settings: AppSettings
        
        init(name: String, settings: AppSettings) {
            self.name = name
            self.settings = settings
        }
    }
    @Published var presets: [SettingsPreset] = []
    
    // MARK: - Private Properties
    private var cancellationToken = CancellationToken()
    private var processingTask: Task<Void, Never>?
    private let settingsKey = "WatermarkSettings"
    private let presetsKey = "WatermarkPresets"
    private let processingHistoryKey = "ProcessingHistory"
    private let workflowTemplatesKey = "WorkflowTemplates"
    private let namePatternKey = "NamePatterns"
    private let appStateKey = "AppState"
    private var tempFilePaths: [URL] = []
    private var cancellables = Set<AnyCancellable>()
    private var processingQueue: AudioProcessingQueue?
    private var audioProcessingQueue: AudioProcessingQueue?
    
    // Auto-saver for application state
    private lazy var autoSaver = AutoSaver(processor: self)
    
    // Import/export manager (lazy to avoid initialization cycle)
    private lazy var importExportManager: ImportExportManager = {
        return ImportExportManager(processor: self)
    }()
    
    // MARK: - Initialization
    
    init() {
        // Now we can call methods
        loadSettings()
        loadPresets()
        loadProcessingHistory()
        loadWorkflowTemplates()
        loadNamePatterns()
        
        // Set up notification for group membership changes
        NotificationCenter.default.addObserver(forName: Notification.Name("RefreshWatermarkGroups"),
                                              object: nil,
                                              queue: .main) { [weak self] _ in
            // Update the refreshID to trigger UI updates
            self?.refreshID = UUID()
            // Also trigger object change
            self?.objectWillChange.send()
        }
        
        // Apply the current theme
        currentTheme.apply()
        
        // Set up change forwarding from fileDatabase to processor
        fileDatabase.objectWillChange
            .sink { [weak self] _ in
                // When the database changes, notify all views that depend on the processor
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // Start memory monitoring in debug builds
        #if DEBUG
        MemoryMonitor.shared.startMonitoring()
        #endif
    }
    
    // MARK: - Settings Management
    
    func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
            settings.syncWatermarkSettings() // Ensure compatibility
        }
    }
    
    func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }
    
    // MARK: - Preset Management
    
    func loadPresets() {
        if let data = UserDefaults.standard.data(forKey: presetsKey),
           let decoded = try? JSONDecoder().decode([SettingsPreset].self, from: data) {
            presets = decoded
        }
    }
    
    func savePresets() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: presetsKey)
        }
    }
    
    func saveCurrentSettingsAsPreset(name: String) {
        let preset = SettingsPreset(name: name, settings: settings)
        presets.append(preset)
        savePresets()
    }
    
    func applyPreset(_ preset: SettingsPreset) {
        settings = preset.settings
        settings.syncWatermarkSettings() // Ensure compatibility
    }
    
    func deletePreset(_ preset: SettingsPreset) {
        presets.removeAll { $0.id == preset.id }
        savePresets()
    }
    
    // MARK: - Processing Control
    
    func startProcessing() {
            guard let outputFolder = outputFolder else { return }
            
            // Record start time for performance tracking
            let startTime = Date()
            let tracker = PerformanceMonitor.shared.startMeasurement(for: "total_processing")
            
            // Create a dedicated task for processing
            processingTask = Task {
                do {
                    isProcessing = true
                    processingStartTime = Date()
                    cancellationToken.isCancelled = false
                    
                    // Pre-process all pairs to avoid doing work during the processing loop
                    let filePairs = try await prepareFilePairs()
                    
                    // Create optimized processing queue
                    let queue = AudioProcessingQueue(
                        settings: settings,
                        outputFolder: outputFolder,
                        cancellationToken: cancellationToken
                    )
                    
                    // Set callbacks for UI updates
                    await queue.setProgressUpdater { [weak self] completed, total in
                        guard let self = self else { return }
                        self.progress = (completed / total) * 100
                    }
                    
                    await queue.setFileUpdater { [weak self] songURL, watermarkURL in
                        guard let self = self else { return }
                        self.currentFile = songURL.lastPathComponent
                        self.currentWatermark = watermarkURL.lastPathComponent
                    }
                    
                    await queue.setCompletionHandler { [weak self] successfullyProcessed, errors in
                        guard let self = self else { return }
                        
                        // Calculate processing duration
                        let duration = Date().timeIntervalSince(startTime)
                        
                        // Add to processing history
                        self.addToProcessingHistory(
                            songCount: self.fileDatabase.songs.count,
                            watermarkCount: self.fileDatabase.watermarks.count,
                            totalFiles: successfullyProcessed,
                            duration: duration
                        )
                        
                        // Send notification if enabled
                        if self.settings.showNotificationsWhenComplete {
                            self.sendCompletionNotification(
                                totalProcessed: successfullyProcessed,
                                totalErrors: errors.count,
                                duration: duration
                            )
                        }
                        
                        // Show results with any errors
                        self.finishProcessing(success: successfullyProcessed, errors: errors)
                        
                        // Stop performance tracking
                        tracker.stop()
                    }
                    
                    // Store for potential cancellation
                    self.audioProcessingQueue = queue
                    
                    // Queue the file pairs and start processing
                    await queue.queueFilePairs(filePairs)
                    await queue.startProcessing()
                    
                } catch {
                    await MainActor.run {
                        isProcessing = false
                        tracker.stop()
                        handleError(error)
                    }
                }
            }
        }
        
        func cancelProcessing() {
            processingStartTime = nil
            cancellationToken.isCancelled = true
            
            // Cancel processing queue operations
            if let audioProcessingQueue = audioProcessingQueue {
                Task {
                    await audioProcessingQueue.cancelProcessing()
                }
            }
            
            processingTask?.cancel()
            isProcessing = false
            resetCurrentFiles()
            cleanupTempFiles() // Clean up any temporary files
        }
    
    // MARK: - Core Processing
    
    private func processFilePair(
        songURL: URL,
        watermarkURL: URL,
        outputFolder: URL
    ) async throws {
        let tracker = PerformanceMonitor.shared.startMeasurement(for: "process_file_pair")
        defer { tracker.stop() }
        
        do {
            // Check if input formats need conversion
            let finalSongURL: URL
            let finalWatermarkURL: URL
            var tempFiles: [URL] = []
            
            // Use a defer block to ensure cleanup happens
            defer {
                // If keeping original files is disabled, clean up converted files
                if !settings.keepOriginalFiles {
                    for url in tempFiles {
                        try? FileManager.default.removeItem(at: url)
                    }
                }
            }
            
            if settings.automaticallyConvertInputFormats {
                // Convert if needed
                if FormatConverter.needsConversion(url: songURL) {
                    finalSongURL = try await FormatConverter.convertFile(url: songURL)
                    tempFiles.append(finalSongURL)
                    trackTempFile(finalSongURL)
                } else {
                    finalSongURL = songURL
                }
                
                if FormatConverter.needsConversion(url: watermarkURL) {
                    finalWatermarkURL = try await FormatConverter.convertFile(url: watermarkURL)
                    tempFiles.append(finalWatermarkURL)
                    trackTempFile(finalWatermarkURL)
                } else {
                    finalWatermarkURL = watermarkURL
                }
            } else {
                finalSongURL = songURL
                finalWatermarkURL = watermarkURL
            }
            
            // Continue with the processing
            let songAsset = AVURLAsset(url: finalSongURL)
            let watermarkAsset = AVURLAsset(url: finalWatermarkURL)
            
            async let songDuration = songAsset.load(.duration)
            async let watermarkDuration = watermarkAsset.load(.duration)
            let durations = try await (song: songDuration, watermark: watermarkDuration)
            
            let songTracks = try await songAsset.loadTracks(withMediaType: .audio)
            let watermarkTracks = try await watermarkAsset.loadTracks(withMediaType: .audio)
            
            guard let songTrack = songTracks.first,
                  let watermarkTrack = watermarkTracks.first else {
                throw ProcessingError.invalidInputFile
            }
            
            let composition = try await createComposition(
                songTrack: songTrack,
                watermarkTrack: watermarkTrack,
                songDuration: durations.song,
                watermarkDuration: durations.watermark
            )
            
            // Generate filenames using pattern
            let personName = watermarkURL.deletingPathExtension().lastPathComponent
            let songName = songURL.deletingPathExtension().lastPathComponent
            
            // Create output folder with person name
            let personFolder = try createOutputFolder(
                outputFolder: outputFolder,
                personName: personName
            )
            
            // Get output filename from pattern
            let outputFileName = outputNamePattern.generateFilename(
                songName: songName,
                watermarkName: personName,
                fileExtension: "m4a" // Temporary format
            )
            
            // Create temp file with generated name
            let tempURL = personFolder
                .appendingPathComponent("temp_\(outputFileName)")
            
            let tempExt = settings.outputFormat == .wav ? "aiff" : "m4a"
            let tempURLWithExt = tempURL.appendingPathExtension(tempExt)
            trackTempFile(tempURLWithExt)
            
            // Export the composition
            try await exportComposition(
                composition: composition,
                tempURL: tempURLWithExt
            )
            
            // Get final filename from pattern with correct extension
            let finalFileName = outputNamePattern.generateFilename(
                songName: songName,
                watermarkName: personName,
                fileExtension: settings.outputFormat.rawValue
            )
            
            let finalURL = personFolder
                .appendingPathComponent(finalFileName)
            
            // Convert to final format
            try convertToFinalFormat(
                tempURL: tempURLWithExt,
                format: settings.outputFormat,
                finalURL: finalURL
            )
            
            // Clean up temp files
            try? FileManager.default.removeItem(at: tempURLWithExt)
            
            // Clean up converted input files if they were created
            if finalSongURL != songURL {
                try? FileManager.default.removeItem(at: finalSongURL)
            }
            
            if finalWatermarkURL != watermarkURL {
                try? FileManager.default.removeItem(at: finalWatermarkURL)
            }
        } catch {
            // Log error with context
            ErrorLogger.shared.logError(error, context: "Processing file pair - Song: \(songURL.lastPathComponent), Watermark: \(watermarkURL.lastPathComponent)")
            
            // Convert to app-specific error for better UX
            throw ProcessingError.fileProcessingFailed(
                song: songURL.lastPathComponent,
                watermark: watermarkURL.lastPathComponent,
                details: error.localizedDescription
            )
        }
    }
    
    private func createComposition(
        songTrack: AVAssetTrack,
        watermarkTrack: AVAssetTrack,
        songDuration: CMTime,
        watermarkDuration: CMTime
    ) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        
        guard let compositionSongTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ProcessingError.compositionError
        }
        
        try compositionSongTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: songDuration),
            of: songTrack,
            at: .zero
        )
        
        guard let compositionWatermarkTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ProcessingError.compositionError
        }
        
        // Apply appropriate watermark pattern
        let watermarkSettings = settings.enhancedWatermarkSettings
        
        try watermarkSettings.watermarkPattern.applyWatermark(
            track: compositionWatermarkTrack,
            watermarkTrack: watermarkTrack,
            songDuration: songDuration,
            watermarkDuration: watermarkDuration,
            settings: watermarkSettings
        )
        
        return composition
    }
    
    private func exportComposition(
        composition: AVMutableComposition,
        tempURL: URL
    ) async throws {
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: tempURL.pathExtension.lowercased() == "aiff" ?
                AVAssetExportPresetAppleProRes422LPCM : AVAssetExportPresetAppleM4A
        ) else {
            throw ProcessingError.exportError(reason: "Export session creation failed")
        }
        
        exportSession.outputURL = tempURL
        exportSession.outputFileType = tempURL.pathExtension.lowercased() == "aiff" ? .aiff : .m4a
        
        // Create audio mix with the appropriate pattern
        let audioMix = AVMutableAudioMix()
        let watermarkSettings = settings.enhancedWatermarkSettings
        
        if let watermarkTrack = composition.tracks(withMediaType: .audio).last,
           let parameters = watermarkSettings.watermarkPattern.createAudioMixParameters(
            track: watermarkTrack,
            composition: composition,
            settings: watermarkSettings
           ) {
            audioMix.inputParameters = [parameters]
            exportSession.audioMix = audioMix
        }
        
        try await exportWithContinuation(exportSession)
    }
    
    private func exportWithContinuation(_ exportSession: AVAssetExportSession) async throws {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(throwing: exportSession.error ?? NSError(
                        domain: "ExportError",
                        code: 0,
                        userInfo: [NSLocalizedDescriptionKey: "Export failed"]
                    ))
                default:
                    continuation.resume(throwing: CancellationError())
                }
            }
        }
    }
    
    private func convertToFinalFormat(
        tempURL: URL,
        format: BRAZMARK.OutputFormat,
        finalURL: URL
    ) throws {
        guard FileManager.default.fileExists(atPath: tempURL.path) else {
            throw ProcessingError.conversionError(code: -1, message: "Temporary file missing")
        }
        
        switch format {
        case .mp3:
            // Convert directly from input to MP3 using FFmpeg
            let ffmpegProcess = Process()
            ffmpegProcess.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
            ffmpegProcess.arguments = [
                "-i", tempURL.path,     // Input file
                "-codec:a", "libmp3lame", // Use LAME encoder
                "-q:a", "2",            // Quality setting (2 is good balance)
                "-y",                   // Overwrite if exists
                finalURL.path           // Output MP3 file
            ]
            
            let ffmpegErrorPipe = Pipe()
            ffmpegProcess.standardError = ffmpegErrorPipe
            
            try ffmpegProcess.run()
            ffmpegProcess.waitUntilExit()
            
            guard ffmpegProcess.terminationStatus == 0 else {
                let errorData = ffmpegErrorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw ProcessingError.conversionError(
                    code: Int(ffmpegProcess.terminationStatus),
                    message: "FFmpeg error: \(errorMessage)"
                )
            }
            
        case .wav:
            // Convert to WAV using afconvert
            let afconvertProcess = Process()
            afconvertProcess.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
            afconvertProcess.arguments = [
                "-f", "WAVE",          // Output format: WAV
                "-d", "LEI16@44100",  // 16-bit PCM, 44.1kHz
                tempURL.path,          // Input file
                finalURL.path          // Output WAV file
            ]
            
            let afconvertErrorPipe = Pipe()
            afconvertProcess.standardError = afconvertErrorPipe
            
            try afconvertProcess.run()
            afconvertProcess.waitUntilExit()
            
            guard afconvertProcess.terminationStatus == 0 else {
                let errorData = afconvertErrorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw ProcessingError.conversionError(
                    code: Int(afconvertProcess.terminationStatus),
                    message: "afconvert error: \(errorMessage)"
                )
            }
        }
    }
    
    private func createOutputFolder(
        outputFolder: URL,
        personName: String
    ) throws -> URL {
        let personFolder = outputFolder.appendingPathComponent(personName)
        try FileManager.default.createDirectory(
            at: personFolder,
            withIntermediateDirectories: true
        )
        return personFolder
    }
    
    // MARK: - File pair preparation
    
    private func prepareFilePairs() async throws -> [(song: URL, watermark: URL)] {
        var filePairs: [(song: URL, watermark: URL)] = []
        
        // Get URL pairs based on the processing mode
        switch settings.processingMode {
        case .allCombinations:
            // Get song URLs
            let songURLs = fileDatabase.songs.map { $0.url }
            
            // Use selected group or all watermarks
            let watermarkURLs: [URL]
            if let selectedGroup = selectedWatermarkGroup {
                watermarkURLs = fileDatabase.watermarksInGroup(selectedGroup).map { $0.url }
            } else {
                watermarkURLs = fileDatabase.watermarks.map { $0.url }
            }
            
            // Validate we have files to process
            guard !songURLs.isEmpty && !watermarkURLs.isEmpty else {
                throw ProcessingError.noFilesToProcess
            }
            
            // Create all possible combinations
            for songURL in songURLs {
                for watermarkURL in watermarkURLs {
                    filePairs.append((song: songURL, watermark: watermarkURL))
                }
            }
            
        case .oneToOne:
            // Get songs and watermarks
            let songURLs = fileDatabase.songs.map { $0.url }
            
            // Use selected group or all watermarks
            let watermarkURLs: [URL]
            if let selectedGroup = selectedWatermarkGroup {
                watermarkURLs = fileDatabase.watermarksInGroup(selectedGroup).map { $0.url }
            } else {
                watermarkURLs = fileDatabase.watermarks.map { $0.url }
            }
            
            // Validate we have files to process
            guard !songURLs.isEmpty && !watermarkURLs.isEmpty else {
                throw ProcessingError.noFilesToProcess
            }
            
            // Pair files in sequence, limited by the smaller array
            let pairCount = min(songURLs.count, watermarkURLs.count)
            
            for i in 0..<pairCount {
                filePairs.append((song: songURLs[i], watermark: watermarkURLs[i]))
            }
        }
        
        return filePairs
    }
    
    // MARK: - Preview Management
    
    /// Generate a watermark preview
    func generateWatermarkPreview() async {
        await generateWatermarkPreview(
            songURL: fileDatabase.songs.first?.url,
            watermarkURL: fileDatabase.watermarks.first?.url
        )
    }
    
    /// Generate a watermark preview with specified files
    func generateWatermarkPreview(songURL: URL?, watermarkURL: URL?) async {
        guard let songURL = songURL, let watermarkURL = watermarkURL else {
            return
        }
        
        do {
            // Apply current watermark settings
            let previewSettings = settings.enhancedWatermarkSettings
            _ = try await previewController.generatePreview(
                songURL: songURL,
                watermarkURL: watermarkURL,
                settings: previewSettings
            )
        } catch {
            print("Preview generation error: \(error)")
        }
    }
    
    // MARK: - Processing History
    
    /// Load processing history from UserDefaults
    private func loadProcessingHistory() {
        if let data = UserDefaults.standard.data(forKey: processingHistoryKey),
           let history = try? JSONDecoder().decode([ProcessingJob].self, from: data) {
            processingHistory = history
        } else {
            processingHistory = []
        }
    }
    
    /// Save processing history to UserDefaults
    private func saveProcessingHistory() {
        if let data = try? JSONEncoder().encode(processingHistory) {
            UserDefaults.standard.set(data, forKey: processingHistoryKey)
        }
    }
    
    /// Add a job to the processing history
    private func addToProcessingHistory(
        songCount: Int,
        watermarkCount: Int,
        totalFiles: Int,
        duration: TimeInterval
    ) {
        let job = ProcessingJob(
            date: Date(),
            songCount: songCount,
            watermarkCount: watermarkCount,
            totalFilesProcessed: totalFiles,
            watermarkGroup: selectedWatermarkGroup?.name,
            outputFormat: settings.outputFormat.rawValue,
            outputFolder: outputFolder?.path ?? "Unknown",
            isCompleted: true,
            duration: duration
        )
        
        processingHistory.insert(job, at: 0)
        
        // Keep history manageable
        if processingHistory.count > 100 {
            processingHistory = Array(processingHistory.prefix(100))
        }
        
        saveProcessingHistory()
    }
    
    /// Clear processing history
    func clearProcessingHistory() {
        processingHistory.removeAll()
        saveProcessingHistory()
    }
    
    // MARK: - Workflow Templates
    
    /// Load workflow templates from UserDefaults
    private func loadWorkflowTemplates() {
        if let data = UserDefaults.standard.data(forKey: workflowTemplatesKey),
           let templates = try? JSONDecoder().decode([WorkflowTemplate].self, from: data) {
            workflowTemplates = templates
        } else {
            // Add default templates
            workflowTemplates = [
                .podcastTemplate,
                .musicTemplate,
                .commercialTemplate
            ]
            saveWorkflowTemplates()
        }
    }
    
    /// Save workflow templates to UserDefaults
    private func saveWorkflowTemplates() {
        if let data = try? JSONEncoder().encode(workflowTemplates) {
            UserDefaults.standard.set(data, forKey: workflowTemplatesKey)
        }
    }
    
    /// Add a new workflow template
    func saveCurrentAsWorkflowTemplate(name: String, description: String) {
        let newTemplate = WorkflowTemplate(
            name: name,
            description: description,
            processingMode: settings.processingMode,
            outputFormat: settings.outputFormat,
            watermarkSettings: settings.enhancedWatermarkSettings,
            watermarkGroupId: selectedWatermarkGroup?.id,
            outputFolder: outputFolder?.path,
            outputNamePattern: outputNamePattern
        )
        
        workflowTemplates.append(newTemplate)
        saveWorkflowTemplates()
    }
    
    /// Apply a workflow template
    func applyWorkflowTemplate(_ template: WorkflowTemplate) {
        Task { @MainActor in
            // Apply processing settings
            self.settings.processingMode = template.processingMode
            self.settings.outputFormat = template.outputFormat
            self.settings.watermarkVolume = template.watermarkSettings.watermarkVolume
            self.settings.initialDelay = template.watermarkSettings.initialDelay
            self.settings.loopInterval = template.watermarkSettings.loopInterval
            
            // Apply watermark pattern
            self.settings.watermarkSettings.watermarkPattern = template.watermarkSettings.watermarkPattern
            
            // Select watermark group if specified
            if let groupId = template.watermarkGroupId {
                self.selectedWatermarkGroup = self.fileDatabase.watermarkGroups.first(where: { $0.id == groupId })
            }
            
            // Set output folder if specified
            if let folderPath = template.outputFolder {
                let url = URL(fileURLWithPath: folderPath)
                if FileManager.default.fileExists(atPath: url.path) {
                    self.outputFolder = url
                }
            }
            
            // Apply output naming pattern
            self.outputNamePattern = template.outputNamePattern
        }
    }
    
    /// Delete a workflow template
    func deleteWorkflowTemplate(_ template: WorkflowTemplate) {
        workflowTemplates.removeAll { $0.id == template.id }
        saveWorkflowTemplates()
    }
    
    // MARK: - Name Patterns
    
    /// Load name patterns from UserDefaults
    private func loadNamePatterns() {
        if let data = UserDefaults.standard.data(forKey: namePatternKey),
           let patterns = try? JSONDecoder().decode([OutputNamePattern].self, from: data) {
            savedNamePatterns = patterns
        }
    }
    
    /// Save name patterns to UserDefaults
    private func saveNamePatterns() {
        if let data = try? JSONEncoder().encode(savedNamePatterns) {
            UserDefaults.standard.set(data, forKey: namePatternKey)
        }
    }
    
    /// Add a new name pattern
    func saveCurrentNamePattern(name: String) {
        var newPattern = outputNamePattern
        newPattern.id = UUID()
        newPattern.name = name
        
        savedNamePatterns.append(newPattern)
        saveNamePatterns()
    }
    
    /// Delete a name pattern
    func deleteNamePattern(_ pattern: OutputNamePattern) {
        savedNamePatterns.removeAll { $0.id == pattern.id }
        saveNamePatterns()
    }
    
    // MARK: - Export/Import Functions
    
    /// Export all settings to a file
    func exportAllSettings() {
        if let url = importExportManager.exportAllSettings() {
            importExportManager.showShareSheet(for: url)
        }
    }
    
    /// Export workflow templates to a file
    func exportWorkflowTemplates() {
        if let url = importExportManager.exportWorkflowTemplates() {
            importExportManager.showShareSheet(for: url)
        }
    }
    
    /// Export presets to a file
    func exportPresets() {
        if let url = importExportManager.exportPresets() {
            importExportManager.showShareSheet(for: url)
        }
    }
    
    /// Show import panel
    func showImportPanel() {
        if let url = importExportManager.showImportPanel() {
            let result = importExportManager.importSettings(from: url)
            
            // Show result notification
            let alert = NSAlert()
            alert.messageText = result.isSuccess ? "Import Successful" : "Import Failed"
            alert.informativeText = result.message
            alert.runModal()
        }
    }
    
    // MARK: - Theme Management
    
    /// Set the app theme
    func setTheme(_ theme: AppTheme) {
        currentTheme = theme
        theme.apply()
    }
    
    // MARK: - Application State Management
    
    func saveApplicationState() {
        // Create state dictionary
        let state: [String: Any] = [
            "outputFolder": outputFolder?.path as Any,
            "selectedWatermarkGroupId": selectedWatermarkGroup?.id.uuidString as Any
        ]
        
        // Save to UserDefaults
        UserDefaults.standard.set(state, forKey: appStateKey)
        
        // Save all other settings
        saveSettings()
        savePresets()
        saveWorkflowTemplates()
        saveNamePatterns()
        saveProcessingHistory()
    }
    
    func restoreApplicationState() {
        // Restore from UserDefaults
        if let state = UserDefaults.standard.dictionary(forKey: appStateKey) {
            // Restore output folder
            if let folderPath = state["outputFolder"] as? String {
                let url = URL(fileURLWithPath: folderPath)
                if FileManager.default.fileExists(atPath: url.path) {
                    outputFolder = url
                }
            }
            
            // Restore selected watermark group
            if let groupIdString = state["selectedWatermarkGroupId"] as? String,
               let groupId = UUID(uuidString: groupIdString) {
                selectedWatermarkGroup = fileDatabase.watermarkGroups.first(where: { $0.id == groupId })
            }
        }
        
        // Other state is restored via the normal initialization process
    }
    
    // MARK: - Temp File Management
    
    private func trackTempFile(_ url: URL) {
        tempFilePaths.append(url)
    }
    
    private func cleanupTempFiles() {
        let fileManager = FileManager.default
        for url in tempFilePaths {
            try? fileManager.removeItem(at: url)
        }
        tempFilePaths.removeAll()
    }
    
    // MARK: - UI Helpers
    
    private func updateProgress(_ completed: Double, _ total: Double) {
        // Use Task to prevent blocking the processing thread
        Task { @MainActor in
            // Add small random delay to prevent too many rapid updates
            try? await Task.sleep(nanoseconds: UInt64.random(in: 10_000_000...50_000_000))
            
            progress = (completed / total) * 100
        }
    }
    
    private func updateCurrentFiles(_ songURL: URL, _ watermarkURL: URL) {
        Task { @MainActor in
            currentFile = songURL.lastPathComponent
            currentWatermark = watermarkURL.lastPathComponent
        }
    }
    
    private func finishProcessing(success: Int, errors: [String]) {
        // Calculate processing duration if we have a start time
        let duration: TimeInterval
        if let startTime = processingStartTime {
            duration = Date().timeIntervalSince(startTime)
        } else {
            duration = 0
        }
        
        // Format duration into minutes and seconds
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let timeString = "\(minutes) minute\(minutes == 1 ? "" : "s") and \(seconds) second\(seconds == 1 ? "" : "s")"
        
        processingStartTime = nil
        isProcessing = false
        resetCurrentFiles()
        cleanupTempFiles() // Clean up any temporary files
        
        let alert = NSAlert()
        
        if errors.isEmpty {
            alert.messageText = "Processing Complete"
            alert.informativeText = "All \(success) files have been processed successfully.\nIt took \(timeString)."
        } else {
            alert.messageText = "Processing Complete with Errors"
            
            if success > 0 {
                alert.informativeText = "Successfully processed \(success) files. \(errors.count) files had errors.\nIt took \(timeString)."
            } else {
                alert.informativeText = "No files were processed successfully. \(errors.count) files had errors.\nIt took \(timeString)."
            }
            
            // Add details button for errors
            alert.addButton(withTitle: "Show Details")
            alert.addButton(withTitle: "OK")
            
            let errorDetails = errors.joined(separator: "\n")
            
            // If user clicks "Show Details" button
            if alert.runModal() == .alertFirstButtonReturn {
                let detailsAlert = NSAlert()
                detailsAlert.messageText = "Processing Errors"
                detailsAlert.informativeText = errorDetails
                detailsAlert.runModal()
                return
            }
        }
        
        if errors.isEmpty {
            alert.runModal()
        }
    }
    
    private func resetCurrentFiles() {
        currentFile = ""
        currentWatermark = ""
        progress = 0
    }
    
    private func handleError(_ error: Error) {
        let message = (error as? ProcessingError)?.localizedDescription ?? error.localizedDescription
        let alert = NSAlert()
        alert.messageText = "Processing Error"
        alert.informativeText = message
        
        // Add recovery suggestion if available
        if let recoveryText = (error as? ProcessingError)?.recoverySuggestion {
            alert.informativeText += "\n\n" + recoveryText
        }
        
        alert.runModal()
    }
    
    // Send system notifications
    private func sendCompletionNotification(totalProcessed: Int, totalErrors: Int, duration: TimeInterval) {
        let notification = NSUserNotification()
        notification.title = "Braz Mark Processing Complete"
        
        if totalErrors == 0 {
            notification.informativeText = "Successfully processed \(totalProcessed) files in \(Int(duration)) seconds."
        } else {
            notification.informativeText = "Processed \(totalProcessed) files with \(totalErrors) errors in \(Int(duration)) seconds."
        }
        
        notification.soundName = NSUserNotificationDefaultSoundName
        
        NSUserNotificationCenter.default.deliver(notification)
    }
}

// MARK: - Supporting Types
enum WatermarkPosition: Int, CaseIterable, Codable {
    case start, end, loop
}

enum ProcessingError: Error, LocalizedError {
    case invalidInputFile
    case compositionError
    case exportError(reason: String)
    case conversionError(code: Int, message: String)
    case cancelled
    case invalidOutputFolder
    case timeout
    case noFilesToProcess
    case fileProcessingFailed(song: String, watermark: String, details: String)
    
    var errorDescription: String? {
        switch self {
        case .invalidInputFile:
            return "Invalid audio file format"
        case .compositionError:
            return "Failed to create audio composition"
        case .exportError(let reason):
            return "Export failed: \(reason)"
        case .conversionError(let code, let message):
            return "Format conversion failed (code \(code)): \(message)"
        case .cancelled:
            return "Processing was cancelled"
        case .invalidOutputFolder:
            return "Invalid output folder selected"
        case .timeout:
            return "Processing timed out"
        case .noFilesToProcess:
            return "No files to process"
        case .fileProcessingFailed(let song, let watermark, let details):
            return "Failed to process \(song) with watermark \(watermark): \(details)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .invalidInputFile:
            return "Try converting the file to a standard format like MP3 or WAV first."
        case .compositionError:
            return "Check that the audio files are valid and try again."
        case .exportError:
            return "Make sure the output folder is valid and you have permission to write to it."
        case .conversionError:
            return "Try a different output format or check if the input files are valid."
        case .cancelled:
            return "You can start processing again when ready."
        case .invalidOutputFolder:
            return "Select a different output folder that exists and is writable."
        case .timeout:
            return "Try processing fewer files at once or increase the processing timeout."
        case .noFilesToProcess:
            return "Add at least one song and one watermark to process."
        case .fileProcessingFailed:
            return "Check the error details and try again. If the problem persists, try a different file."
        }
    }
}

// Processing result for batch operations
enum ProcessingResult {
    case success((song: URL, watermark: URL))
    case failure((song: URL, watermark: URL), Error)
}

class CancellationToken {
    var isCancelled = false
}

// Auto-saver class
class AutoSaver {
    private var timer: Timer?
    private weak var processor: AudioProcessor?
    
    init(processor: AudioProcessor) {
        self.processor = processor
        startAutoSave()
    }
    
    func startAutoSave() {
        // Auto-save every 5 minutes
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.processor?.saveApplicationState()
        }
    }
    
    func stopAutoSave() {
        timer?.invalidate()
        timer = nil
    }
    
    deinit {
        stopAutoSave()
    }
}

// Extension for DispatchQueue with async/await
extension DispatchQueue {
    func asyncResult<T>(work: @escaping () throws -> T) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            self.async {
                do {
                    let result = try work()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
