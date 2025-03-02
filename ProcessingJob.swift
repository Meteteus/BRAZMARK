//
//  ProcessingJob.swift
//  BRAZMARK
//
//  Created by Matheus Braz on 3/1/25.
//


import Foundation

/// Represents a completed processing job
struct ProcessingJob: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var songCount: Int
    var watermarkCount: Int
    var totalFilesProcessed: Int
    var watermarkGroup: String?
    var outputFormat: String
    var outputFolder: String
    var isCompleted: Bool
    var duration: TimeInterval
    var error: String?
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "\(minutes)m \(seconds)s"
    }
}
