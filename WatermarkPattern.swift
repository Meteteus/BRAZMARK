import Foundation
import AVFoundation

/// Represents different patterns for applying watermarks to audio files
enum WatermarkPattern: Int, Codable, CaseIterable, Identifiable, Hashable {
    case singleAtStart = 0
    case singleAtEnd = 1
    case regularInterval = 2
    case randomInterval = 3
    case fadeInOut = 4
    case varyingVolume = 5

    var id: Int { rawValue }

    /// Display name for the watermark pattern
    var displayName: String {
        switch self {
        case .singleAtStart: return "Single at Start"
        case .singleAtEnd: return "Single at End"
        case .regularInterval: return "Regular Interval"
        case .randomInterval: return "Random Interval"
        case .fadeInOut: return "Fade In/Out"
        case .varyingVolume: return "Varying Volume"
        }
    }

    /// Describes the pattern
    var description: String {
        switch self {
        case .singleAtStart: return "Watermark plays once at the beginning"
        case .singleAtEnd: return "Watermark plays once at the end"
        case .regularInterval: return "Watermark repeats at fixed intervals"
        case .randomInterval: return "Watermark plays at random intervals"
        case .fadeInOut: return "Watermark fades in and out"
        case .varyingVolume: return "Watermark volume varies periodically"
        }
    }

    /// Create audio mix parameters for this watermark pattern
    func createAudioMixParameters(
        track: AVMutableCompositionTrack,
        composition: AVMutableComposition,
        settings: WatermarkSettings
    ) -> AVMutableAudioMixInputParameters? {
        let parameters = AVMutableAudioMixInputParameters(track: track)

        switch self {
        case .singleAtStart, .singleAtEnd, .regularInterval, .randomInterval:
            parameters.setVolume(settings.watermarkVolume, at: .zero)

        case .fadeInOut:
            parameters.setVolume(settings.watermarkVolume, at: .zero)

            let timeRanges = track.segments.compactMap { segment in
                return segment.timeMapping.target
            }

            for segment in timeRanges {
                let startTime = segment.start
                let endTime = segment.end
                let duration = segment.duration

                let fadeInDuration = min(CMTime(seconds: settings.fadeDuration, preferredTimescale: 600), duration)
                let fadeOutDuration = min(CMTime(seconds: settings.fadeDuration, preferredTimescale: 600), duration)

                parameters.setVolumeRamp(
                    fromStartVolume: 0.0,
                    toEndVolume: settings.watermarkVolume,
                    timeRange: CMTimeRange(
                        start: startTime,
                        duration: fadeInDuration
                    )
                )

                parameters.setVolumeRamp(
                    fromStartVolume: settings.watermarkVolume,
                    toEndVolume: 0.0,
                    timeRange: CMTimeRange(
                        start: CMTimeSubtract(endTime, fadeOutDuration),
                        duration: fadeOutDuration
                    )
                )
            }

        case .varyingVolume:
            parameters.setVolume(settings.watermarkVolume, at: .zero)

            let timeRanges = track.segments.compactMap { segment in
                return segment.timeMapping.target
            }

            for (index, segment) in timeRanges.enumerated() {
                let startTime = segment.start

                let volumeFactor = 0.7 + 0.3 * sin(Double(index) * 0.7)
                let adjustedVolume = Float(volumeFactor) * settings.watermarkVolume

                parameters.setVolume(adjustedVolume, at: startTime)
            }
        }

        return parameters
    }

    /// Apply watermark to a track based on the selected pattern
    func applyWatermark(
        track: AVMutableCompositionTrack,
        watermarkTrack: AVAssetTrack,
        songDuration: CMTime,
        watermarkDuration: CMTime,
        settings: WatermarkSettings
    ) throws {
        switch self {
        case .singleAtStart:
            // Watermark at very start
            try track.insertTimeRange(
                CMTimeRange(start: .zero, duration: min(watermarkDuration, songDuration)),
                of: watermarkTrack,
                at: .zero
            )

        case .singleAtEnd:
            // Watermark at the very end
            let endTime = CMTimeSubtract(songDuration, watermarkDuration)
            try track.insertTimeRange(
                CMTimeRange(start: .zero, duration: min(watermarkDuration, songDuration)),
                of: watermarkTrack,
                at: endTime
            )

        case .regularInterval:
            // Watermark at regular intervals
            var currentTime = CMTime(seconds: settings.initialDelay, preferredTimescale: 600)
            
            while currentTime < songDuration {
                let insertDuration = min(watermarkDuration, CMTimeSubtract(songDuration, currentTime))
                
                if insertDuration > .zero {
                    try track.insertTimeRange(
                        CMTimeRange(start: .zero, duration: insertDuration),
                        of: watermarkTrack,
                        at: currentTime
                    )
                }
                
                // Move to next interval
                currentTime = CMTimeAdd(
                    currentTime,
                    CMTime(seconds: settings.loopInterval, preferredTimescale: 600)
                )
            }

        case .randomInterval:
            // Watermark at random intervals
            var currentTime = CMTime(seconds: settings.initialDelay, preferredTimescale: 600)
            let randomness = settings.randomnessAmount
            
            while currentTime < songDuration {
                let insertDuration = min(watermarkDuration, CMTimeSubtract(songDuration, currentTime))
                
                if insertDuration > .zero {
                    try track.insertTimeRange(
                        CMTimeRange(start: .zero, duration: insertDuration),
                        of: watermarkTrack,
                        at: currentTime
                    )
                }
                
                // Calculate next interval with randomness
                let baseInterval = settings.loopInterval
                let randomFactor = Double.random(in: 1.0 - randomness...1.0 + randomness)
                let nextInterval = baseInterval * randomFactor
                
                currentTime = CMTimeAdd(
                    currentTime,
                    CMTime(seconds: nextInterval, preferredTimescale: 600)
                )
            }

        case .fadeInOut:
            // Watermark inserted at regular intervals with fading
            var currentTime = CMTime(seconds: settings.initialDelay, preferredTimescale: 600)
            
            while currentTime < songDuration {
                let insertDuration = min(watermarkDuration, CMTimeSubtract(songDuration, currentTime))
                
                if insertDuration > .zero {
                    try track.insertTimeRange(
                        CMTimeRange(start: .zero, duration: insertDuration),
                        of: watermarkTrack,
                        at: currentTime
                    )
                }
                
                // Move to next interval
                currentTime = CMTimeAdd(
                    currentTime,
                    CMTime(seconds: settings.loopInterval, preferredTimescale: 600)
                )
            }

        case .varyingVolume:
            // Watermark inserted at regular intervals
            var currentTime = CMTime(seconds: settings.initialDelay, preferredTimescale: 600)
            
            while currentTime < songDuration {
                let insertDuration = min(watermarkDuration, CMTimeSubtract(songDuration, currentTime))
                
                if insertDuration > .zero {
                    try track.insertTimeRange(
                        CMTimeRange(start: .zero, duration: insertDuration),
                        of: watermarkTrack,
                        at: currentTime
                    )
                }
                
                // Move to next interval
                currentTime = CMTimeAdd(
                    currentTime,
                    CMTime(seconds: settings.loopInterval, preferredTimescale: 600)
                )
            }
        }
    }
}
