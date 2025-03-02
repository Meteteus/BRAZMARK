//
//  PreviewController.swift
//  BRAZMARK
//

import Foundation
import AVFoundation
import SwiftUI

// Enum definitions to support PreviewController
enum PreviewStartPosition: Int, CaseIterable, Identifiable, Codable {
    case beginning = 0
    case middle = 1
    case end = 2
    
    var id: Int { rawValue }
    
    var displayName: String {
        switch self {
        case .beginning: return "Beginning"
        case .middle: return "Middle"
        case .end: return "End"
        }
    }
}

/// Handles preview generation and playback of watermarked audio
class PreviewController: ObservableObject {
    // Published state
    @Published var isGenerating = false
    @Published var isPlaying = false
    @Published var previewDuration: Double = 0
    @Published var currentPlaybackTime: Double = 0
    @Published var previewWaveformData: [Float] = []
    @Published var previewError: String?
    
    // Audio playback
    private var player: AVAudioPlayer?
    private var previewURL: URL?
    private var playbackTimer: Timer?
    
    // Preview settings
    var previewDurationSeconds: Double = 20.0
    var startPosition: PreviewStartPosition = .beginning
    
    // MARK: - Preview Generation
    
    /// Generate a preview of a watermarked audio file
    func generatePreview(
        songURL: URL,
        watermarkURL: URL,
        settings: WatermarkSettings
    ) async throws -> URL {
        await MainActor.run {
            isGenerating = true
            previewError = nil
        }
        
        do {
            // Clean up any previous preview first
            cleanup()
            
            // Load the audio assets
            let songAsset = AVURLAsset(url: songURL)
            let watermarkAsset = AVURLAsset(url: watermarkURL)
            
            // Get durations
            async let songDuration = songAsset.load(.duration)
            async let watermarkDuration = watermarkAsset.load(.duration)
            let durations = try await (song: songDuration, watermark: watermarkDuration)
            
            // Determine preview segment length
            let maxPreviewDuration = min(durations.song.seconds, previewDurationSeconds)
            
            // Determine start time based on preference
            let songStartTime: CMTime
            switch startPosition {
            case .beginning:
                songStartTime = .zero
                
            case .middle:
                let middleTime = durations.song.seconds / 2.0 - (maxPreviewDuration / 2.0)
                songStartTime = CMTime(seconds: max(0, middleTime), preferredTimescale: 600)
                
            case .end:
                let endTime = durations.song.seconds - maxPreviewDuration
                songStartTime = CMTime(seconds: max(0, endTime), preferredTimescale: 600)
            }
            
            // Create a time range for the preview segment
            let previewTimeRange = CMTimeRange(
                start: songStartTime,
                duration: CMTime(seconds: maxPreviewDuration, preferredTimescale: 600)
            )
            
            // Get audio tracks
            let songTracks = try await songAsset.loadTracks(withMediaType: .audio)
            let watermarkTracks = try await watermarkAsset.loadTracks(withMediaType: .audio)
            
            guard let songTrack = songTracks.first,
                  let watermarkTrack = watermarkTracks.first else {
                throw NSError(domain: "PreviewError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid audio tracks"])
            }
            
            // Create a composition for the preview
            let composition = AVMutableComposition()
            
            // Add song track (just the preview segment)
            guard let compositionSongTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw NSError(domain: "PreviewError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create composition track"])
            }
            
            try compositionSongTrack.insertTimeRange(
                previewTimeRange,
                of: songTrack,
                at: .zero
            )
            
            // Add watermark track
            guard let compositionWatermarkTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw NSError(domain: "PreviewError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create watermark track"])
            }
            
            // Apply the watermark pattern
            try settings.watermarkPattern.applyWatermark(
                track: compositionWatermarkTrack,
                watermarkTrack: watermarkTrack,
                songDuration: CMTime(seconds: maxPreviewDuration, preferredTimescale: 600),
                watermarkDuration: durations.watermark,
                settings: settings
            )
            
            // Create audio mix with volume settings
            let audioMix = AVMutableAudioMix()
            if let parameters = settings.watermarkPattern.createAudioMixParameters(
                track: compositionWatermarkTrack,
                composition: composition,
                settings: settings
            ) {
                audioMix.inputParameters = [parameters]
            }
            
            // Create a temporary file for the preview
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("preview_\(UUID().uuidString)")
                .appendingPathExtension("m4a")
            
            // Export the preview
            guard let exportSession = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetAppleM4A
            ) else {
                throw NSError(domain: "PreviewError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
            }
            
            exportSession.outputURL = tempURL
            exportSession.outputFileType = .m4a
            exportSession.audioMix = audioMix
            
            // Export the preview with timeout protection
            // Explicitly specify the generic type parameter
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // Create a timeout task
                let timeoutTask = Task {
                    do {
                        try await Task.sleep(nanoseconds: 30_000_000_000) // 30 second timeout
                        if exportSession.status != .completed {
                            exportSession.cancelExport()
                            continuation.resume(throwing: NSError(
                                domain: "PreviewError",
                                code: 5,
                                userInfo: [NSLocalizedDescriptionKey: "Preview generation timed out"]
                            ))
                        }
                    } catch {
                        // Handle cancellation
                    }
                }
                
                exportSession.exportAsynchronously {
                    // Cancel timeout task
                    timeoutTask.cancel()
                    
                    switch exportSession.status {
                    case .completed:
                        continuation.resume()
                    case .failed, .cancelled:
                        continuation.resume(throwing: exportSession.error ?? NSError(
                            domain: "PreviewError",
                            code: 6,
                            userInfo: [NSLocalizedDescriptionKey: "Export failed"]
                        ))
                    default:
                        continuation.resume(throwing: NSError(
                            domain: "PreviewError",
                            code: 7,
                            userInfo: [NSLocalizedDescriptionKey: "Unknown export error"]
                        ))
                    }
                }
            }
            
            // Generate waveform data
            let waveformData = try await generateWaveformData(from: tempURL)
            
            // Update state on main thread
            await MainActor.run {
                self.previewURL = tempURL
                self.previewDuration = maxPreviewDuration
                self.previewWaveformData = waveformData
                self.isGenerating = false
            }
            
            return tempURL
            
        } catch {
            await MainActor.run {
                self.previewError = error.localizedDescription
                self.isGenerating = false
            }
            throw error
        }
    }
    
    // MARK: - Playback Control
    
    /// Start playing the preview
    func playPreview() {
        guard let previewURL = previewURL else { return }
        
        do {
            // Create and configure audio player
            player = try AVAudioPlayer(contentsOf: previewURL)
            player?.prepareToPlay()
            player?.play()
            isPlaying = true
            
            // Start a timer to update playback position
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self = self, let player = self.player else { return }
                self.currentPlaybackTime = player.currentTime
                
                // Check if playback has completed
                if !player.isPlaying && self.isPlaying {
                    self.stopPlayback()
                }
            }
        } catch {
            previewError = "Failed to play preview: \(error.localizedDescription)"
        }
    }
    
    /// Pause the preview playback
    func pausePlayback() {
        player?.pause()
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    /// Stop the preview playback and reset
    func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
        currentPlaybackTime = 0
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    /// Seek to a specific position in the preview
    func seekTo(time: Double) {
        player?.currentTime = time
        currentPlaybackTime = time
    }
    
    // MARK: - Waveform Generation
    
    /// Generate waveform data from an audio file
    private func generateWaveformData(from url: URL) async throws -> [Float] {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let frameCount = UInt32(audioFile.length)
        
        // Cap the maximum number of data points to avoid memory issues
        let maxDataPoints = 300
        let samplesPerPixel = max(1, Int(frameCount / UInt32(maxDataPoints)))
        let bufferSize = samplesPerPixel
        
        // Create buffer
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(bufferSize)) else {
            throw NSError(domain: "WaveformError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio buffer"])
        }
        
        var waveformData: [Float] = []
        var isEOF = false
        
        // Read audio file in chunks and calculate peak values
        while !isEOF {
            do {
                try audioFile.read(into: buffer)
                
                // Check if we've reached the end of file
                if buffer.frameLength == 0 {
                    isEOF = true
                    continue
                }
                
                // Calculate peak value for this buffer
                if let channelData = buffer.floatChannelData?[0] {
                    var peak: Float = 0.0
                    for i in 0..<Int(buffer.frameLength) {
                        let sample = abs(channelData[i])
                        peak = max(peak, sample)
                    }
                    waveformData.append(peak)
                }
            } catch {
                // End of file or error
                isEOF = true
            }
        }
        
        // Normalize waveform data to 0.0-1.0 range
        if let maxValue = waveformData.max(), maxValue > 0 {
            waveformData = waveformData.map { $0 / maxValue }
        }
        
        return waveformData
    }
    
    // MARK: - Cleanup
    
    /// Clean up temporary files and resources
    func cleanup() {
        // Stop playback
        stopPlayback()
        
        // Delete temporary file
        if let previewURL = previewURL {
            try? FileManager.default.removeItem(at: previewURL)
            self.previewURL = nil
        }
        
        // Reset state
        previewWaveformData = []
        previewDuration = 0
        previewError = nil
        
        // Release memory
        player = nil
        
        // Force garbage collection hints
        autoreleasepool {
            // This helps release autoreleased objects
        }
    }
}
