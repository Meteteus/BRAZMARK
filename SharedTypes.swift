//  SharedTypes.swift
//  BRAZMARK
//
//  Created by Matheus Braz on 3/1/25.
//

import Foundation

// Enum for processing modes
enum ProcessingMode: Int, Codable, CaseIterable {
    case allCombinations
    case oneToOne
}

// Enum for output formats
enum OutputFormat: String, Codable, CaseIterable {
    case mp3
    case wav
}

// Struct for watermark settings
struct WatermarkSettings: Codable, Hashable, Equatable {
    var watermarkVolume: Float = 0.3
    var watermarkPattern: WatermarkPattern = .regularInterval
    var initialDelay: Double = 9.0
    var loopInterval: Double = 7.0
    var randomnessAmount: Double = 0.5
    var fadeDuration: Double = 0.5
}

// Note: OutputNamePattern is now removed from this file, as it's defined in OutputNamePattern.swift
