import Foundation
import Combine
import AVFoundation

/// Manages the queue of audio processing operations with better performance characteristics
actor AudioProcessingQueue {
    // Active processing tasks
    private var activeTasks: [UUID: Task<Void, Error>] = [:]
    private var processingPairs: [(song: URL, watermark: URL)] = []
    private var currentProgress: (completed: Double, total: Double) = (0, 0)
    private var progressUpdater: ((Double, Double) -> Void)?
    private var fileUpdater: ((URL, URL) -> Void)?
    private var completionHandler: ((Int, [String]) -> Void)?
    
    // Processing settings
    private var settings: AppSettings
    private var outputFolder: URL
    private var cancellationToken: CancellationToken
    
    // Performance metrics
    private var startTime: Date?
    private var successfullyProcessed: Int = 0
    private var errors: [String] = []
    
    // Memory management
    private var tempFiles: [URL] = []
    
    init(settings: AppSettings,
         outputFolder: URL,
         cancellationToken: CancellationToken) {
        self.settings = settings
        self.outputFolder = outputFolder
        self.cancellationToken = cancellationToken
    }
    
    /// Set the progress update handler
    func setProgressUpdater(_ updater: @escaping (Double, Double) -> Void) {
        self.progressUpdater = updater
    }
    
    /// Set the current file updater
    func setFileUpdater(_ updater: @escaping (URL, URL) -> Void) {
        self.fileUpdater = updater
    }
    
    /// Set the completion handler
    func setCompletionHandler(_ handler: @escaping (Int, [String]) -> Void) {
        self.completionHandler = handler
    }
    
    /// Queue file pairs for processing
    func queueFilePairs(_ pairs: [(song: URL, watermark: URL)]) {
        self.processingPairs = pairs
        self.currentProgress = (0, Double(pairs.count))
        self.startTime = Date()
        self.successfullyProcessed = 0
        self.errors = []
    }
    
    /// Start processing the queue
    func startProcessing() async {
        // Process in groups if background processing is enabled
        let maxConcurrent = settings.useBackgroundProcessing ?
                           settings.maxConcurrentProcessingTasks : 1
        
        // Create semaphore to limit concurrent operations
        let semaphore = DispatchSemaphore(value: maxConcurrent)
        
        // Process in batches for better memory management
        let batchSize = min(maxConcurrent * 2, 8) // Double the concurrent tasks, but capped
        
        for i in stride(from: 0, to: processingPairs.count, by: batchSize) {
            guard !cancellationToken.isCancelled else { break }
            
            let end = min(i + batchSize, processingPairs.count)
            let batch = Array(processingPairs[i..<end])
            
            // Process batch with better error handling
            await withTaskGroup(of: ProcessingResult.self) { group in
                for pair in batch {
                    group.addTask {
                        // Acquire semaphore to limit concurrency
                        do {
                            try await Task.detached {
                                semaphore.wait()
                            }.value
                        } catch {
                            // Handle any errors
                            semaphore.signal()
                            return ProcessingResult.failure(pair, error)
                        }
                        
                        defer {
                            // Always release semaphore when done
                            semaphore.signal()
                        }
                        
                        do {
                            // Update currently processing files
                            if let fileUpdater = await self.fileUpdater {
                                await MainActor.run {
                                    fileUpdater(pair.song, pair.watermark)
                                }
                            }
                            
                            // Process with improved error handling and timeout protection
                            try await self.processFilePair(
                                songURL: pair.song,
                                watermarkURL: pair.watermark,
                                outputFolder: self.outputFolder
                            )
                            
                            return ProcessingResult.success(pair)
                        } catch {
                            return ProcessingResult.failure(pair, error)
                        }
                    }
                }
                
                // Process results as they complete
                for await result in group {
                    switch result {
                    case .success:
                        self.successfullyProcessed += 1
                    case .failure(let pair, let error):
                        self.errors.append("\(pair.song.lastPathComponent) + \(pair.watermark.lastPathComponent): \(error.localizedDescription)")
                    }
                    
                    // Update progress
                    await self.updateProgress()
                }
            }
        }
        
        // Clean up temp files
        await self.cleanupTempFiles()
        
        // Call completion handler
        if let completionHandler = self.completionHandler {
            // Copy actor-isolated properties before sending to main actor
            let finalSuccessCount = self.successfullyProcessed
            let finalErrors = self.errors
            
            await MainActor.run {
                completionHandler(finalSuccessCount, finalErrors)
            }
        }
    }
    
    /// Cancel all active tasks
    func cancelProcessing() {
        for (_, task) in activeTasks {
            task.cancel()
        }
        activeTasks.removeAll()
        
        // Clean up temp files
        Task {
            await cleanupTempFiles()
        }
    }
    
    // MARK: - Private Methods
    
    private func updateProgress() async {
        let completed = currentProgress.completed + 1
        let total = currentProgress.total
        
        currentProgress.completed = completed
        
        if let progressUpdater = progressUpdater {
            // Limit UI updates to avoid overwhelming the main thread
            if completed.truncatingRemainder(dividingBy: 1) == 0 || completed == total {
                await MainActor.run {
                    progressUpdater(completed, total)
                }
            }
        }
    }
    
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
            var conversionFiles: [URL] = []
            
            // Use a defer block to ensure cleanup happens regardless of result
            defer {
                // If keeping original files is disabled, clean up converted files
                for url in conversionFiles {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            
            // Perform conversions concurrently if needed
            if settings.automaticallyConvertInputFormats {
                async let songConversion: URL = FormatConverter.needsConversion(url: songURL) ?
                    await FormatConverter.convertFile(url: songURL) : songURL
                    
                async let watermarkConversion: URL = FormatConverter.needsConversion(url: watermarkURL) ?
                    await FormatConverter.convertFile(url: watermarkURL) : watermarkURL
                
                // Wait for both conversions to complete
                (finalSongURL, finalWatermarkURL) = try await (songConversion, watermarkConversion)
                
                // Track temp files for cleanup
                if finalSongURL != songURL {
                    conversionFiles.append(finalSongURL)
                    await trackTempFile(finalSongURL)
                }
                
                if finalWatermarkURL != watermarkURL {
                    conversionFiles.append(finalWatermarkURL)
                    await trackTempFile(finalWatermarkURL)
                }
            } else {
                finalSongURL = songURL
                finalWatermarkURL = watermarkURL
            }
            
            // Load assets concurrently
            let songAsset = AVURLAsset(url: finalSongURL)
            let watermarkAsset = AVURLAsset(url: finalWatermarkURL)
            
            // Perform multiple asset operations concurrently
            async let songDuration = songAsset.load(.duration)
            async let watermarkDuration = watermarkAsset.load(.duration)
            async let songTracks = songAsset.loadTracks(withMediaType: .audio)
            async let watermarkTracks = watermarkAsset.loadTracks(withMediaType: .audio)
            
            // Wait for all asset operations to complete
            let durations = try await (song: songDuration, watermark: watermarkDuration)
            let tracks = try await (song: songTracks, watermark: watermarkTracks)
            
            guard let songTrack = tracks.song.first,
                  let watermarkTrack = tracks.watermark.first else {
                throw ProcessingError.invalidInputFile
            }
            
            // Create composition
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
            let personFolder = try await createOutputFolder(
                outputFolder: outputFolder,
                personName: personName
            )
            
            // Get output filename from pattern (use processor's pattern)
            let outputFileName = settings.outputNamePattern.generateFilename(
                songName: songName,
                watermarkName: personName,
                fileExtension: "m4a" // Temporary format
            )
            
            // Create temp file with generated name
            let tempURL = personFolder
                .appendingPathComponent("temp_\(outputFileName)")
            
            let tempExt = settings.outputFormat == .wav ? "aiff" : "m4a"
            let tempURLWithExt = tempURL.appendingPathExtension(tempExt)
            await trackTempFile(tempURLWithExt)
            
            // Export the composition
            try await exportComposition(
                composition: composition,
                tempURL: tempURLWithExt
            )
            
            // Get final filename from pattern with correct extension
            let finalFileName = settings.outputNamePattern.generateFilename(
                songName: songName,
                watermarkName: personName,
                fileExtension: settings.outputFormat.rawValue
            )
            
            let finalURL = personFolder
                .appendingPathComponent(finalFileName)
            
            // Convert to final format
            try await convertToFinalFormat(
                tempURL: tempURLWithExt,
                format: settings.outputFormat,
                finalURL: finalURL
            )
            
            // Clean up temp files
            try? FileManager.default.removeItem(at: tempURLWithExt)
            
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
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let timeoutTask = Task {
                do {
                    try await Task.sleep(nanoseconds: 60_000_000_000) // 60 second timeout
                    if exportSession.status != .completed {
                        exportSession.cancelExport()
                        continuation.resume(throwing: ProcessingError.timeout)
                    }
                } catch {
                    // Task was cancelled
                }
            }
            
            exportSession.exportAsynchronously {
                // Cancel timeout
                timeoutTask.cancel()
                
                switch exportSession.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(throwing: exportSession.error ?? ProcessingError.exportError(reason: "Unknown export failure"))
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
    ) async throws {
        guard FileManager.default.fileExists(atPath: tempURL.path) else {
            throw ProcessingError.conversionError(code: -1, message: "Temporary file missing")
        }
        
        // Improved process handling with timeout protection
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task {
                do {
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
                        
                        // Setup pipes
                        let ffmpegErrorPipe = Pipe()
                        ffmpegProcess.standardError = ffmpegErrorPipe
                        
                        // Create timeout task
                        let timeoutTask = Task {
                            do {
                                try await Task.sleep(nanoseconds: 30_000_000_000) // 30 second timeout
                                if ffmpegProcess.isRunning {
                                    ffmpegProcess.terminate()
                                    continuation.resume(throwing: ProcessingError.timeout)
                                }
                            } catch {
                                // Task was cancelled
                            }
                        }
                        
                        try ffmpegProcess.run()
                        ffmpegProcess.waitUntilExit()
                        
                        // Cancel timeout
                        timeoutTask.cancel()
                        
                        guard ffmpegProcess.terminationStatus == 0 else {
                            let errorData = ffmpegErrorPipe.fileHandleForReading.readDataToEndOfFile()
                            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                            continuation.resume(throwing: ProcessingError.conversionError(
                                code: Int(ffmpegProcess.terminationStatus),
                                message: "FFmpeg error: \(errorMessage)"
                            ))
                            return
                        }
                        
                        continuation.resume()
                        
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
                        
                        // Setup pipes
                        let afconvertErrorPipe = Pipe()
                        afconvertProcess.standardError = afconvertErrorPipe
                        
                        // Create timeout task
                        let timeoutTask = Task {
                            do {
                                try await Task.sleep(nanoseconds: 30_000_000_000) // 30 second timeout
                                if afconvertProcess.isRunning {
                                    afconvertProcess.terminate()
                                    continuation.resume(throwing: ProcessingError.timeout)
                                }
                            } catch {
                                // Task was cancelled
                            }
                        }
                        
                        try afconvertProcess.run()
                        afconvertProcess.waitUntilExit()
                        
                        // Cancel timeout
                        timeoutTask.cancel()
                        
                        guard afconvertProcess.terminationStatus == 0 else {
                            let errorData = afconvertErrorPipe.fileHandleForReading.readDataToEndOfFile()
                            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                            continuation.resume(throwing: ProcessingError.conversionError(
                                code: Int(afconvertProcess.terminationStatus),
                                message: "afconvert error: \(errorMessage)"
                            ))
                            return
                        }
                        
                        continuation.resume()
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func createOutputFolder(
        outputFolder: URL,
        personName: String
    ) async throws -> URL {
        let personFolder = outputFolder.appendingPathComponent(personName)
        
        return try await Task.detached { () -> URL in
            try FileManager.default.createDirectory(
                at: personFolder,
                withIntermediateDirectories: true
            )
            return personFolder
        }.value
    }
    
    private func trackTempFile(_ url: URL) async {
        tempFiles.append(url)
    }
    
    private func cleanupTempFiles() async {
        let fileManager = FileManager.default
        
        // Use Task.detached to avoid blocking the actor
        do {
            try await Task.detached {
                for url in await self.tempFiles {
                    try? fileManager.removeItem(at: url)
                }
            }.value
        } catch {
            print("Error cleaning up temp files: \(error.localizedDescription)")
        }
        
        tempFiles.removeAll()
    }
}
