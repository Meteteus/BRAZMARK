//
//  AppSettings.swift
//  BRAZMARK
//
//  Created by Matheus Braz on 3/1/25.
//

import Foundation

struct AppSettings: Codable, Hashable {
    // Output settings
    var outputFormat: OutputFormat = .mp3
    var processingMode: ProcessingMode = .allCombinations
    
    // Legacy watermark settings (for backward compatibility)
    var watermarkVolume: Float = 0.3
    var watermarkPosition: WatermarkPosition = .loop
    var initialDelay: Double = 9.0
    var loopInterval: Double = 7.0
    
    // Enhanced watermark settings
    var watermarkSettings: WatermarkSettings = WatermarkSettings()
    
    // Naming and output settings
    var outputNamePattern: OutputNamePattern = .default
    
    // UI Settings
    var theme: AppTheme = .system
    var rememberLastOutputFolder: Bool = true
    var showProcessingHistory: Bool = true
    var confirmBeforeDeleting: Bool = true
    
    // Performance settings
    var useBackgroundProcessing: Bool = true
    var showNotificationsWhenComplete: Bool = true
    var maxConcurrentProcessingTasks: Int = 2
    
    // Additional features
    var automaticallyConvertInputFormats: Bool = true
    var keepOriginalFiles: Bool = true
    
    // Explicitly implement Equatable protocol
    static func == (lhs: AppSettings, rhs: AppSettings) -> Bool {
        // Compare critical properties for equality
        return lhs.outputFormat == rhs.outputFormat &&
               lhs.processingMode == rhs.processingMode &&
               lhs.watermarkVolume == rhs.watermarkVolume &&
               lhs.watermarkPosition == rhs.watermarkPosition &&
               lhs.initialDelay == rhs.initialDelay &&
               lhs.loopInterval == rhs.loopInterval &&
               lhs.watermarkSettings == rhs.watermarkSettings &&
               lhs.outputNamePattern.id == rhs.outputNamePattern.id &&
               lhs.theme == rhs.theme
    }
    
    // Explicitly implement Hashable protocol
    func hash(into hasher: inout Hasher) {
        hasher.combine(outputFormat)
        hasher.combine(processingMode)
        hasher.combine(watermarkVolume)
        hasher.combine(initialDelay)
        hasher.combine(loopInterval)
    }
    
    // Compatibility method to make sure watermark settings are synced
    mutating func syncWatermarkSettings() {
        // If we're loading older settings, update the enhanced watermark settings
        watermarkSettings.watermarkVolume = watermarkVolume
        watermarkSettings.initialDelay = initialDelay
        watermarkSettings.loopInterval = loopInterval
        
        // Map legacy position to pattern
        switch watermarkPosition {
        case .start:
            watermarkSettings.watermarkPattern = .singleAtStart
        case .end:
            watermarkSettings.watermarkPattern = .singleAtEnd
        case .loop:
            watermarkSettings.watermarkPattern = .regularInterval
        }
    }
    
    // Legacy compatibility method for getting watermark settings
    var enhancedWatermarkSettings: WatermarkSettings {
        var settings = watermarkSettings
        settings.watermarkVolume = watermarkVolume
        settings.initialDelay = initialDelay
        settings.loopInterval = loopInterval
        return settings
    }
    
    // Default presets
    static let standard = AppSettings()
    
    static let professional = AppSettings(
        outputFormat: .wav,
        processingMode: .allCombinations,
        watermarkVolume: 0.25,
        watermarkPosition: .loop,
        initialDelay: 15.0,
        loopInterval: 60.0,
        watermarkSettings: WatermarkSettings(
            watermarkVolume: 0.25,
            watermarkPattern: .fadeInOut,
            initialDelay: 15.0,
            loopInterval: 60.0,
            fadeDuration: 1.0
        ),
        outputNamePattern: OutputNamePattern.dated,
        theme: AppTheme.dark,
        maxConcurrentProcessingTasks: 4
    )
    
    static let minimal = AppSettings(
        outputFormat: .mp3,
        processingMode: .oneToOne,
        watermarkVolume: 0.15,
        watermarkPosition: .end,
        initialDelay: 5.0,
        watermarkSettings: WatermarkSettings(
            watermarkVolume: 0.15,
            watermarkPattern: .singleAtEnd,
            initialDelay: 5.0
        ),
        outputNamePattern: OutputNamePattern.clean
    )
}
