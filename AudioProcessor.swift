import AVFoundation
import Combine
import AppKit

@MainActor
class AudioProcessor: ObservableObject {
    // MARK: - Published Properties
    @Published var songURLs = [URL]()
    @Published var watermarkURLs = [URL]()
    @Published var outputFolder: URL?
    @Published var isProcessing = false
    @Published var progress: Double = 0
    @Published var currentFile = ""
    @Published var currentWatermark = ""
    
    // MARK: - User Settings
    @Published var settings = AppSettings() {
        didSet { saveSettings() }
    }
    
    // MARK: - Processing State
    private var cancellationToken = CancellationToken()
    private var processingTask: Task<Void, Never>?
    
    // MARK: - Preset Management
    private let settingsKey = "WatermarkSettings"
    
    init() {
        loadSettings()
        loadPresets()
    }
    
    func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        }
    }
    
    func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }
    
    // MARK: - Processing Control
    func startProcessing() {
        guard let outputFolder = outputFolder else { return }
        
        processingTask = Task {
            isProcessing = true
            cancellationToken.isCancelled = false
            
            var totalWork: Double
            var filePairs: [(song: URL, watermark: URL)] = []
            
            // Create file pairs based on the processing mode
            switch settings.processingMode {
            case .allCombinations:
                totalWork = Double(songURLs.count * watermarkURLs.count)
                // Create all possible combinations
                for songURL in songURLs {
                    for watermarkURL in watermarkURLs {
                        filePairs.append((song: songURL, watermark: watermarkURL))
                    }
                }
                
            case .oneToOne:
                // Pair files in sequence, limited by the smaller array
                let pairCount = min(songURLs.count, watermarkURLs.count)
                totalWork = Double(pairCount)
                
                for i in 0..<pairCount {
                    filePairs.append((song: songURLs[i], watermark: watermarkURLs[i]))
                }
            }
            
            var completedWork: Double = 0
            
            do {
                for pair in filePairs {
                    guard !cancellationToken.isCancelled else { break }
                    
                    await updateCurrentFiles(pair.song, pair.watermark)
                    
                    try await processFilePair(
                        songURL: pair.song,
                        watermarkURL: pair.watermark,
                        outputFolder: outputFolder
                    )
                    
                    completedWork += 1
                    await updateProgress(completedWork, totalWork)
                }
            } catch {
                handleError(error)
            }
            
            await finishProcessing()
        }
    }

    @MainActor
    private func updateProcessingProgress(_ completed: Double, _ total: Double) {
        progress = (completed / total) * 100
        print("Progress: \(progress)%") // Debug logging
    }
    
    func cancelProcessing() {
        cancellationToken.isCancelled = true
        processingTask?.cancel()
        isProcessing = false
        resetCurrentFiles()
    }
    
    // MARK: - Core Processing
    private func processFilePair(
        songURL: URL,
        watermarkURL: URL,
        outputFolder: URL
    ) async throws {
        let songAsset = AVURLAsset(url: songURL)
        let watermarkAsset = AVURLAsset(url: watermarkURL)
        
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
        
        let personName = watermarkURL.deletingPathExtension().lastPathComponent
        let personFolder = try createOutputFolder(
            outputFolder: outputFolder,
            personName: personName
        )
        
        let tempURL = try await exportComposition(
            composition: composition,
            songURL: songURL,
            personName: personName,
            personFolder: personFolder
        )
        
        try convertToFinalFormat(
            tempURL: tempURL,
            format: settings.outputFormat,
            personFolder: personFolder,
            songURL: songURL,
            personName: personName
        )
    }
    
    // MARK: - Audio Processing
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
        
        try insertWatermark(
            track: compositionWatermarkTrack,
            watermarkTrack: watermarkTrack,
            songDuration: songDuration,
            watermarkDuration: watermarkDuration
        )
        
        return composition
    }
    
    private func insertWatermark(
        track: AVMutableCompositionTrack,
        watermarkTrack: AVAssetTrack,
        songDuration: CMTime,
        watermarkDuration: CMTime
    ) throws {
        let delayTime = CMTime(seconds: settings.initialDelay, preferredTimescale: 600)
        let intervalTime = CMTime(seconds: settings.loopInterval, preferredTimescale: 600)
        
        switch settings.watermarkPosition {
        case .start:
            try track.insertTimeRange(
                CMTimeRange(start: .zero, duration: watermarkDuration),
                of: watermarkTrack,
                at: delayTime
            )
            
        case .end:
            let startTime = songDuration - watermarkDuration - delayTime
            try track.insertTimeRange(
                CMTimeRange(start: .zero, duration: watermarkDuration),
                of: watermarkTrack,
                at: max(.zero, startTime)
            )
        case .loop:
            var currentTime = delayTime
            while currentTime < songDuration {
                try track.insertTimeRange(
                    CMTimeRange(start: .zero, duration: watermarkDuration),
                    of: watermarkTrack,
                    at: currentTime
                )
                currentTime = CMTimeAdd(currentTime, watermarkDuration + intervalTime)
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
    
    private func exportComposition(
        composition: AVMutableComposition,
        songURL: URL,
        personName: String,
        personFolder: URL
    ) async throws -> URL {
        let tempURL = personFolder
            .appendingPathComponent("temp_\(songURL.deletingPathExtension().lastPathComponent)_\(personName)")
            .appendingPathExtension("m4a")
        
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw ProcessingError.exportError(reason: "Export session creation failed")
        }
        
        exportSession.outputURL = tempURL
        exportSession.outputFileType = .m4a
        exportSession.audioMix = createAudioMix(for: composition)
        
        try await exportSession.exportWithContinuation()
        return tempURL
    }
    
    private func createAudioMix(for composition: AVMutableComposition) -> AVMutableAudioMix? {
        guard let watermarkTrack = composition.tracks(withMediaType: .audio).last else {
            return nil
        }
        
        let audioMix = AVMutableAudioMix()
        let parameters = AVMutableAudioMixInputParameters(track: watermarkTrack)
        parameters.setVolume(settings.watermarkVolume, at: .zero)
        audioMix.inputParameters = [parameters]
        return audioMix
    }
    
    private func convertToFinalFormat(
        tempURL: URL,
        format: OutputFormat,
        personFolder: URL,
        songURL: URL,
        personName: String
    ) throws {
        let finalURL = personFolder
            .appendingPathComponent("\(songURL.deletingPathExtension().lastPathComponent)_\(personName)_WM")
            .appendingPathExtension(format.rawValue)
        
        guard FileManager.default.fileExists(atPath: tempURL.path) else {
            throw ProcessingError.conversionError(code: -1, message: "Temporary file missing")
        }
        
        switch format {
        case .mp3:
            // Step 1: Convert M4A to WAV using afconvert
            let wavURL = tempURL.deletingPathExtension().appendingPathExtension("wav")
            
            let afconvertProcess = Process()
            afconvertProcess.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
            afconvertProcess.arguments = [
                "-f", "WAVE",          // Output format: WAV
                "-d", "LEI16@44100",  // 16-bit PCM, 44.1kHz
                tempURL.path,          // Input file (M4A)
                wavURL.path            // Output file (WAV)
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
            
            // Step 2: Convert WAV to MP3 using FFmpeg
            let ffmpegProcess = Process()
            ffmpegProcess.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
            ffmpegProcess.arguments = [
                "-i", wavURL.path,      // Input WAV file
                "-codec:a", "libmp3lame", // Use LAME encoder
                "-q:a", "2",            // Quality setting (2 is good balance)
                finalURL.path           // Output MP3 file
            ]
            
            let ffmpegErrorPipe = Pipe()
            ffmpegProcess.standardError = ffmpegErrorPipe
            
            try ffmpegProcess.run()
            ffmpegProcess.waitUntilExit()
            
            // Clean up temporary WAV file
            try? FileManager.default.removeItem(at: wavURL)
            
            guard ffmpegProcess.terminationStatus == 0 else {
                let errorData = ffmpegErrorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw ProcessingError.conversionError(
                    code: Int(ffmpegProcess.terminationStatus),
                    message: "FFmpeg error: \(errorMessage)"
                )
            }
            
            // Clean up temporary M4A file
            try? FileManager.default.removeItem(at: tempURL)
            
        case .wav:
            // Directly convert M4A to WAV using afconvert
            let afconvertProcess = Process()
            afconvertProcess.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
            afconvertProcess.arguments = [
                "-f", "WAVE",          // Output format: WAV
                "-d", "LEI16@44100",  // 16-bit PCM, 44.1kHz
                tempURL.path,          // Input file (M4A)
                finalURL.path          // Output file (WAV)
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
            
            // Clean up temporary M4A file
            try? FileManager.default.removeItem(at: tempURL)
        }
    }
    
    // MARK: - UI Helpers
    private func updateCurrentFiles(_ songURL: URL, _ watermarkURL: URL) {
        currentFile = songURL.lastPathComponent
        currentWatermark = watermarkURL.lastPathComponent
    }
    
    @MainActor
    private func updateProgress(_ completed: Double, _ total: Double) {
        progress = (completed / total) * 100
        print("Progress: \(progress)%") // Debug logging
    }
    
    private func finishProcessing() {
        isProcessing = false
        resetCurrentFiles()
        
        let alert = NSAlert()
        alert.messageText = "Processing Complete"
        alert.informativeText = "All files have been processed successfully."
        alert.runModal()
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
        alert.runModal()
    }
}

// MARK: - Supporting Types
enum OutputFormat: String, CaseIterable, Codable {
    case mp3 = "mp3"
    case wav = "wav"
}

enum WatermarkPosition: Int, CaseIterable, Codable {
    case start, end, loop
}

enum ProcessingMode: Int, CaseIterable, Codable {
    case allCombinations, oneToOne
}

struct AppSettings: Codable {
    var watermarkVolume: Float = 0.3
    var outputFormat: OutputFormat = .mp3
    var watermarkPosition: WatermarkPosition = .loop
    var processingMode: ProcessingMode = .allCombinations
    var initialDelay: Double = 9.0
    var loopInterval: Double = 7.0
}

enum ProcessingError: Error, LocalizedError {
    case invalidInputFile
    case compositionError
    case exportError(reason: String)
    case conversionError(code: Int, message: String)
    case cancelled
    case invalidOutputFolder
    
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
        }
    }
}

class CancellationToken {
    var isCancelled = false
}

extension AVAssetExportSession {
    @MainActor
    func exportWithContinuation() async throws {
        try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<Void, Error>) in
            guard let self else {
                continuation.resume(throwing: CancellationError())
                return
            }
            
            self.exportAsynchronously {
                switch self.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(throwing: self.error ?? NSError(
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
}
// MARK: - Preset Management Extension
extension AudioProcessor {
    struct SettingsPreset: Identifiable, Codable {
        var id = UUID()
        var name: String
        var settings: AppSettings
        
        init(name: String, settings: AppSettings) {
            self.name = name
            self.settings = settings
        }
    }
    
    @Published var presets: [SettingsPreset] = [] {
        didSet { savePresets() }
    }
    private let presetsKey = "WatermarkPresets"
    
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
    }
    
    func applyPreset(_ preset: SettingsPreset) {
        settings = preset.settings
    }
    
    func deletePreset(_ preset: SettingsPreset) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets.remove(at: index)
        }
    }
}
