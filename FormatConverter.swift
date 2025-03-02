//
//  FormatConverter.swift
//  BRAZMARK
//

import Foundation
import AVFoundation

/// Handles conversion of audio files to compatible formats
class FormatConverter {
    /// Supported input formats
    static let supportedInputFormats = [
        "mp3", "wav", "m4a", "aiff", "aac", "flac", "ogg", "wma", "aif"
    ]
    
    /// Formats that can be directly used without conversion
    static let directlyUsableFormats = [
        "mp3", "wav", "m4a", "aiff", "aac"
    ]
    
    // Add a file extension cache to avoid redundant checks
    private static var formatCache: [URL: Bool] = [:]
    private static let cacheQueue = DispatchQueue(label: "com.brazmark.formatCacheQueue")
    
    // Clear cache method
    static func clearFormatCache() {
        cacheQueue.async {
            formatCache.removeAll()
        }
    }
    
    // Optimized needsConversion method with caching
    static func needsConversion(url: URL) -> Bool {
        return cacheQueue.sync {
            if let cachedResult = formatCache[url] {
                return cachedResult
            }
            
            let fileExtension = url.pathExtension.lowercased()
            let result = supportedInputFormats.contains(fileExtension) &&
                       !directlyUsableFormats.contains(fileExtension)
            
            // Cache the result
            formatCache[url] = result
            return result
        }
    }
    
    // Optimized convertFile method
    static func convertFile(url: URL) async throws -> URL {
        // Get file extension
        let fileExtension = url.pathExtension.lowercased()
        
        // Check if conversion is needed
        guard needsConversion(url: url) else {
            return url
        }
        
        // Determine target format based on input
        let targetFormat: String
        switch fileExtension {
        case "flac", "ogg", "wma":
            targetFormat = "wav" // Lossless/high quality conversion
        default:
            targetFormat = "m4a" // Default conversion
        }
        
        // Create unique output path using hash of input URL for stability
        let fileName = url.deletingPathExtension().lastPathComponent
        let fileHash = String(url.absoluteString.hash, radix: 16, uppercase: false)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(fileName)_\(fileHash)")
            .appendingPathExtension(targetFormat)
        
        // If the file already exists, return it (conversion was already done)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            return outputURL
        }
        
        // Create a temporary output path for processing to avoid partial files
        let tempOutputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(fileName)_\(fileHash)_temp")
            .appendingPathExtension(targetFormat)
        
        // Choose conversion method based on file type
        if fileExtension == "flac" {
            try await convertUsingFFmpeg(input: url, output: tempOutputURL)
        } else {
            try await convertUsingAVAsset(input: url, output: tempOutputURL)
        }
        
        // Move the completed file to the final location
        try FileManager.default.moveItem(at: tempOutputURL, to: outputURL)
        
        return outputURL
    }
    
    /// Convert using AVAsset (works for most formats)
    private static func convertUsingAVAsset(input: URL, output: URL) async throws {
        // Create asset
        let asset = AVURLAsset(url: input)
        
        // Create export session
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: output.pathExtension.lowercased() == "wav" ?
                AVAssetExportPresetAppleProRes422LPCM : AVAssetExportPresetAppleM4A
        ) else {
            throw NSError(
                domain: "FormatConverterError",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"]
            )
        }
        
        // Configure export session
        exportSession.outputURL = output
        exportSession.outputFileType = output.pathExtension.lowercased() == "wav" ?
            AVFileType.wav : AVFileType.m4a
        
        // Remove existing file if needed
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        
        // Perform export with timeout protection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Set up timeout
            let timeoutTask = Task {
                do {
                    try await Task.sleep(nanoseconds: 60_000_000_000) // 1 minute timeout
                    if exportSession.status != .completed {
                        exportSession.cancelExport()
                        continuation.resume(throwing: NSError(
                            domain: "FormatConverterError",
                            code: 3,
                            userInfo: [NSLocalizedDescriptionKey: "Conversion timed out"]
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
                        domain: "FormatConverterError",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Export failed"]
                    ))
                default:
                    continuation.resume(throwing: NSError(
                        domain: "FormatConverterError",
                        code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "Unknown export error"]
                    ))
                }
            }
        }
        
        // Verify output exists
        guard FileManager.default.fileExists(atPath: output.path) else {
            throw NSError(
                domain: "FormatConverterError",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Output file was not created"]
            )
        }
    }
    
    /// Convert using FFmpeg (for formats not supported by AVAsset)
    private static func convertUsingFFmpeg(input: URL, output: URL) async throws {
        // Create process
        let process = Process()
        
        // Look for ffmpeg in different locations
        let possiblePaths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        
        // Find the first valid ffmpeg path
        guard let ffmpegPath = possiblePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw NSError(
                domain: "FormatConverterError",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "FFmpeg not found. Please install FFmpeg."]
            )
        }
        
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        
        // Configure arguments
        var arguments = [
            "-i", input.path,  // Input file
            "-y"               // Overwrite output
        ]
        
        // Add specific format options
        if output.pathExtension.lowercased() == "wav" {
            arguments.append(contentsOf: [
                "-acodec", "pcm_s16le",  // 16-bit PCM
                "-ar", "44100"           // 44.1kHz sample rate
            ])
        } else {
            arguments.append(contentsOf: [
                "-acodec", "aac",        // AAC codec
                "-b:a", "256k"           // 256k bitrate
            ])
        }
        
        // Add output path
        arguments.append(output.path)
        
        // Set arguments
        process.arguments = arguments
        
        // Setup pipes
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Remove existing file if needed
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        
        // Run the process with timeout
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Create a timeout task
            let timeoutTask = Task {
                do {
                    try await Task.sleep(nanoseconds: 120_000_000_000) // 2-minute timeout
                    if process.isRunning {
                        process.terminate()
                        continuation.resume(throwing: NSError(
                            domain: "FormatConverterError",
                            code: 6,
                            userInfo: [NSLocalizedDescriptionKey: "FFmpeg conversion timed out"]
                        ))
                    }
                } catch {
                    // Handle cancellation
                }
            }
            
            // Run the process in a background queue
            DispatchQueue.global().async {
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    // Cancel timeout task
                    timeoutTask.cancel()
                    
                    // Check exit status
                    if process.terminationStatus != 0 {
                        // Read error output
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        
                        continuation.resume(throwing: NSError(
                            domain: "FFmpegError",
                            code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: "FFmpeg error: \(errorMessage)"]
                        ))
                    } else {
                        // Verify output exists
                        if FileManager.default.fileExists(atPath: output.path) {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: NSError(
                                domain: "FormatConverterError",
                                code: 7,
                                userInfo: [NSLocalizedDescriptionKey: "Output file was not created by FFmpeg"]
                            ))
                        }
                    }
                } catch {
                    timeoutTask.cancel()
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Get a unique path for output to avoid overwriting files
    private static func getUniqueOutputPath(_ url: URL) -> URL {
        var finalURL = url
        var counter = 1
        
        // Try appending numbers until we find a unique name
        while FileManager.default.fileExists(atPath: finalURL.path) {
            finalURL = url.deletingPathExtension()
                .appendingPathComponent("_\(counter)")
                .appendingPathExtension(url.pathExtension)
            counter += 1
        }
        
        return finalURL
    }
}
