//
//  OutputNamePattern.swift
//  BRAZMARK
//
//  Created by Matheus Braz on 3/1/25.
//

import Foundation

struct OutputNamePattern: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var includeOriginalFilename: Bool = true
    var includeWatermarkName: Bool = true
    var includeDate: Bool = false
    var dateFormat: DateFormat = .compact
    var customPrefix: String = ""
    var customSuffix: String = "_WM"
    var replaceSeparatorsWithUnderscores: Bool = true  // Missing property added
    
    enum DateFormat: String, Codable, CaseIterable {
        case compact = "yyyyMMdd"
        case standard = "yyyy-MM-dd"
        case detailed = "yyyy-MM-dd_HHmm"
        
        func formattedDate() -> String {
            let formatter = DateFormatter()
            formatter.dateFormat = self.rawValue
            return formatter.string(from: Date())
        }
    }
    
    // ✅ Static properties properly placed inside the struct
    static let `default` = OutputNamePattern(
        name: "Default"
    )

    static let dated = OutputNamePattern(
        name: "Date Based",
        includeOriginalFilename: true,
        includeWatermarkName: true,
        includeDate: true,
        dateFormat: .compact
    )

    static let clean = OutputNamePattern(
        name: "Clean Names",
        includeOriginalFilename: true,
        includeWatermarkName: false,
        customSuffix: "_Watermarked"
    )
    
    // Add the generateFilename method that is used in the code
    func generateFilename(songName: String, watermarkName: String, fileExtension: String) -> String {
        var components: [String] = []
        
        if !customPrefix.isEmpty {
            components.append(customPrefix)
        }
        
        if includeOriginalFilename {
            components.append(songName)
        }
        
        if includeWatermarkName {
            components.append(watermarkName)
        }
        
        if includeDate {
            components.append(dateFormat.formattedDate())
        }
        
        if !customSuffix.isEmpty {
            components.append(customSuffix)
        }
        
        let separator = replaceSeparatorsWithUnderscores ? "_" : "-"
        let baseFilename = components.joined(separator: separator)
        
        return "\(baseFilename).\(fileExtension)"
    }
}
