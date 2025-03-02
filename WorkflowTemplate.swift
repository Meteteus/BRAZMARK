//
//  WorkflowTemplate.swift
//  BRAZMARK
//
//  Created by Matheus Braz on 3/1/25.
//

import Foundation
import AVFoundation

// Define WorkflowTemplate with all needed protocol conformances
struct WorkflowTemplate: Identifiable, Codable, Hashable, Equatable {
    var id: UUID
    var name: String
    var description: String
    var dateCreated: Date
    var dateModified: Date
    
    // Processing settings
    var processingMode: ProcessingMode
    var outputFormat: OutputFormat
    var watermarkSettings: WatermarkSettings
    
    // Organization
    var watermarkGroupId: UUID?
    var outputFolder: String?
    var outputNamePattern: OutputNamePattern
    
    // Explicitly implement Equatable protocol
    static func == (lhs: WorkflowTemplate, rhs: WorkflowTemplate) -> Bool {
        return lhs.id == rhs.id
    }
    
    // Explicitly implement Hashable protocol
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // CodingKeys for Codable
    enum CodingKeys: String, CodingKey {
        case id, name, description, dateCreated, dateModified
        case processingMode, outputFormat, watermarkSettings
        case watermarkGroupId, outputFolder, outputNamePattern
    }
    
    // Initializer
    init(
        name: String,
        description: String = "",
        processingMode: ProcessingMode = .allCombinations,
        outputFormat: OutputFormat = .mp3,
        watermarkSettings: WatermarkSettings = WatermarkSettings(),
        watermarkGroupId: UUID? = nil,
        outputFolder: String? = nil,
        outputNamePattern: OutputNamePattern = .default
    ) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.dateCreated = Date()
        self.dateModified = Date()
        self.processingMode = processingMode
        self.outputFormat = outputFormat
        self.watermarkSettings = watermarkSettings
        self.watermarkGroupId = watermarkGroupId
        self.outputFolder = outputFolder
        self.outputNamePattern = outputNamePattern
    }
    
    // Explicit encoder/decoder implementation
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        dateCreated = try container.decode(Date.self, forKey: .dateCreated)
        dateModified = try container.decode(Date.self, forKey: .dateModified)
        processingMode = try container.decode(ProcessingMode.self, forKey: .processingMode)
        outputFormat = try container.decode(OutputFormat.self, forKey: .outputFormat)
        watermarkSettings = try container.decode(WatermarkSettings.self, forKey: .watermarkSettings)
        watermarkGroupId = try container.decodeIfPresent(UUID.self, forKey: .watermarkGroupId)
        outputFolder = try container.decodeIfPresent(String.self, forKey: .outputFolder)
        outputNamePattern = try container.decode(OutputNamePattern.self, forKey: .outputNamePattern)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(dateCreated, forKey: .dateCreated)
        try container.encode(dateModified, forKey: .dateModified)
        try container.encode(processingMode, forKey: .processingMode)
        try container.encode(outputFormat, forKey: .outputFormat)
        try container.encode(watermarkSettings, forKey: .watermarkSettings)
        try container.encodeIfPresent(watermarkGroupId, forKey: .watermarkGroupId)
        try container.encodeIfPresent(outputFolder, forKey: .outputFolder)
        try container.encode(outputNamePattern, forKey: .outputNamePattern)
    }
    
    /// Apply this workflow template to the current app state
    func apply(to processor: AudioProcessor) {
        Task { @MainActor in
            // Apply processing settings
            processor.settings.processingMode = processingMode
            processor.settings.outputFormat = outputFormat
            processor.settings.watermarkVolume = watermarkSettings.watermarkVolume
            processor.settings.initialDelay = watermarkSettings.initialDelay
            processor.settings.loopInterval = watermarkSettings.loopInterval
            
            // Apply watermark pattern
            processor.settings.watermarkSettings.watermarkPattern = watermarkSettings.watermarkPattern
            
            // Select watermark group if specified
            if let groupId = watermarkGroupId {
                processor.selectedWatermarkGroup = processor.fileDatabase.watermarkGroups.first(where: { $0.id == groupId })
            }
            
            // Set output folder if specified
            if let folderPath = outputFolder {
                let url = URL(fileURLWithPath: folderPath)
                if FileManager.default.fileExists(atPath: url.path) {
                    processor.outputFolder = url
                }
            }
            
            // Apply output naming pattern
            processor.outputNamePattern = outputNamePattern
        }
    }
    
    // MARK: - Templates
    
    /// Create a standard template for podcast production
    static var podcastTemplate: WorkflowTemplate {
        WorkflowTemplate(
            name: "Podcast Production",
            description: "Optimized for podcast episodes with subtle watermarking",
            processingMode: .allCombinations,
            outputFormat: .mp3,
            watermarkSettings: WatermarkSettings(
                watermarkVolume: 0.15,
                watermarkPattern: .fadeInOut,
                initialDelay: 15.0,
                loopInterval: 120.0,
                fadeDuration: 1.0
            ),
            outputNamePattern: OutputNamePattern(
                name: "Podcast Format",
                includeOriginalFilename: true,
                includeWatermarkName: true,
                includeDate: true,
                dateFormat: .standard,
                customSuffix: "_Protected"
            )
        )
    }
    
    /// Create a template for music protection
    static var musicTemplate: WorkflowTemplate {
        WorkflowTemplate(
            name: "Music Protection",
            description: "Frequent watermarking for music track protection",
            processingMode: .allCombinations,
            outputFormat: .mp3,
            watermarkSettings: WatermarkSettings(
                watermarkVolume: 0.25,
                watermarkPattern: .regularInterval,
                initialDelay: 5.0,
                loopInterval: 30.0
            ),
            outputNamePattern: OutputNamePattern(
                name: "Music Format",
                includeOriginalFilename: true,
                includeWatermarkName: true,
                includeDate: false,
                customSuffix: "_WM"
            )
        )
    }
    
    /// Create a template for commercial audio
    static var commercialTemplate: WorkflowTemplate {
        WorkflowTemplate(
            name: "Commercial Audio",
            description: "Start and end watermarking for commercial audio files",
            processingMode: .allCombinations,
            outputFormat: .wav,
            watermarkSettings: WatermarkSettings(
                watermarkVolume: 0.3,
                watermarkPattern: .singleAtEnd,
                initialDelay: 3.0
            ),
            outputNamePattern: OutputNamePattern(
                name: "Commercial Format",
                includeOriginalFilename: true,
                includeWatermarkName: true,
                includeDate: true,
                dateFormat: .detailed,
                customPrefix: "DEMO_"
            )
        )
    }
}
