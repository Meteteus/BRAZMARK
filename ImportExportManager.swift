//
//  ImportExportManager.swift
//  BRAZMARK
//

import Foundation
import SwiftUI

/// Manages importing and exporting of app settings, presets, and workflows
@MainActor
class ImportExportManager {
    // The processor to import settings to
    private let processor: AudioProcessor
    
    // Structure to contain all app data for export
    private struct ExportData: Codable {
        var appVersion: String
        var exportDate: Date
        var settings: AppSettings
        var presets: [AudioProcessor.SettingsPreset]
        var workflowTemplates: [WorkflowTemplate]
        var watermarkGroups: [WatermarkGroup]
        var outputNamePatterns: [OutputNamePattern]
        var processingHistory: [ProcessingJob]
    }
    
    init(processor: AudioProcessor) {
        self.processor = processor
    }
    
    // MARK: - Export Functions
    
    /// Export all app data to a file
    func exportAllSettings() -> URL? {
        let tracker = PerformanceMonitor.shared.startMeasurement(for: "export_all_settings")
        defer { tracker.stop() }
        
        let exportData = ExportData(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            exportDate: Date(),
            settings: processor.settings,
            presets: processor.presets,
            workflowTemplates: processor.workflowTemplates,
            watermarkGroups: processor.fileDatabase.watermarkGroups,
            outputNamePatterns: processor.savedNamePatterns,
            processingHistory: processor.processingHistory
        )
        
        do {
            // Encode data
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(exportData)
            
            // Create temp file
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
            let dateStr = dateFormatter.string(from: Date())
            
            let fileName = "BrazMark_Settings_\(dateStr).brazmark"
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            
            // Write to file
            try data.write(to: fileURL)
            return fileURL
            
        } catch {
            print("Export error: \(error)")
            ErrorLogger.shared.logError(error, context: "Exporting all settings")
            return nil
        }
    }
    
    /// Export just workflow templates
    func exportWorkflowTemplates() -> URL? {
        let tracker = PerformanceMonitor.shared.startMeasurement(for: "export_workflow_templates")
        defer { tracker.stop() }
        
        do {
            // Encode data
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(processor.workflowTemplates)
            
            // Create temp file
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
            let dateStr = dateFormatter.string(from: Date())
            
            let fileName = "BrazMark_Workflows_\(dateStr).brazworkflow"
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            
            // Write to file
            try data.write(to: fileURL)
            return fileURL
            
        } catch {
            print("Export error: \(error)")
            ErrorLogger.shared.logError(error, context: "Exporting workflow templates")
            return nil
        }
    }
    
    /// Export just presets
    func exportPresets() -> URL? {
        let tracker = PerformanceMonitor.shared.startMeasurement(for: "export_presets")
        defer { tracker.stop() }
        
        do {
            // Encode data
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(processor.presets)
            
            // Create temp file
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
            let dateStr = dateFormatter.string(from: Date())
            
            let fileName = "BrazMark_Presets_\(dateStr).brazpreset"
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            
            // Write to file
            try data.write(to: fileURL)
            return fileURL
            
        } catch {
            print("Export error: \(error)")
            ErrorLogger.shared.logError(error, context: "Exporting presets")
            return nil
        }
    }
    
    // MARK: - Import Functions
    
    /// Import settings from a file
    func importSettings(from url: URL) -> ImportResult {
        let tracker = PerformanceMonitor.shared.startMeasurement(for: "import_settings")
        defer { tracker.stop() }
        
        do {
            // Read file
            let data = try Data(contentsOf: url)
            
            // Determine file type based on extension
            let fileExtension = url.pathExtension.lowercased()
            
            switch fileExtension {
            case "brazmark":
                return importAllSettings(from: data)
            case "brazworkflow":
                return importWorkflows(from: data)
            case "brazpreset":
                return importPresets(from: data)
            default:
                // Try to determine type from content
                if let _ = try? JSONDecoder().decode(ExportData.self, from: data) {
                    return importAllSettings(from: data)
                } else if let _ = try? JSONDecoder().decode([WorkflowTemplate].self, from: data) {
                    return importWorkflows(from: data)
                } else if let _ = try? JSONDecoder().decode([AudioProcessor.SettingsPreset].self, from: data) {
                    return importPresets(from: data)
                } else {
                    return .failure("Unrecognized file format")
                }
            }
        } catch {
            ErrorLogger.shared.logError(error, context: "Importing settings from \(url.lastPathComponent)")
            return .failure("Import error: \(error.localizedDescription)")
        }
    }
    
    /// Import all settings from data
    private func importAllSettings(from data: Data) -> ImportResult {
        do {
            let importData = try JSONDecoder().decode(ExportData.self, from: data)
            
            // Import settings
            processor.settings = importData.settings
            processor.settings.syncWatermarkSettings() // Make sure settings are compatible
            
            // Import presets
            processor.presets = importData.presets
            
            // Import workflow templates
            processor.workflowTemplates = importData.workflowTemplates
            
            // Import watermark groups
            importWatermarkGroups(importData.watermarkGroups)
            
            // Import name patterns
            processor.savedNamePatterns = importData.outputNamePatterns
            
            // Import history if present and enabled
            if processor.settings.showProcessingHistory {
                processor.processingHistory = importData.processingHistory
            }
            
            return .success("Imported all settings successfully")
            
        } catch {
            ErrorLogger.shared.logError(error, context: "Importing all settings")
            return .failure("Failed to import settings: \(error.localizedDescription)")
        }
    }
    
    // Helper function to import watermark groups
    private func importWatermarkGroups(_ groups: [WatermarkGroup]) {
        // We'll implement a simple method to import the groups
        for group in groups {
            if !processor.fileDatabase.watermarkGroups.contains(where: { $0.id == group.id }) {
                processor.fileDatabase.watermarkGroups.append(group)
            }
        }
    }
    
    /// Import workflow templates from data
    private func importWorkflows(from data: Data) -> ImportResult {
        do {
            let workflows = try JSONDecoder().decode([WorkflowTemplate].self, from: data)
            processor.workflowTemplates.append(contentsOf: workflows)
            return .success("Imported \(workflows.count) workflow templates")
        } catch {
            ErrorLogger.shared.logError(error, context: "Importing workflows")
            return .failure("Failed to import workflows: \(error.localizedDescription)")
        }
    }
    
    /// Import presets from data
    private func importPresets(from data: Data) -> ImportResult {
        do {
            let presets = try JSONDecoder().decode([AudioProcessor.SettingsPreset].self, from: data)
            processor.presets.append(contentsOf: presets)
            return .success("Imported \(presets.count) presets")
        } catch {
            ErrorLogger.shared.logError(error, context: "Importing presets")
            return .failure("Failed to import presets: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helper Functions
    
    /// Show share sheet to export a file
    func showShareSheet(for url: URL) {
        // Create a SwiftUI view for our share sheet
        let contentView = ShareSheet(url: url)
        
        // Create a hosting controller and window
        let controller = NSHostingController(rootView: contentView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Export File"
        window.contentViewController = controller
        window.center()
        window.makeKeyAndOrderFront(nil)
        
        // Make it a modal window
        NSApp.runModal(for: window)
    }
    
    /// Show open panel to import a file
    func showImportPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        // Use string-based allowedFileTypes instead of UTType
        panel.allowedFileTypes = ["brazmark", "brazworkflow", "brazpreset", "json"]
        
        guard panel.runModal() == .OK,
              let url = panel.url else {
            return nil
        }
        
        return url
    }
}

/// Result of an import operation
enum ImportResult {
    case success(String)
    case failure(String)
    
    var message: String {
        switch self {
        case .success(let msg), .failure(let msg):
            return msg
        }
    }
    
    var isSuccess: Bool {
        switch self {
        case .success:
            return true
        case .failure:
            return false
        }
    }
}

/// Simple share sheet view for exporting files
struct ShareSheet: View {
    let url: URL
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            
            Text("Export File")
                .font(.headline)
            
            Text("Your file has been created and is ready to share or save.")
                .multilineTextAlignment(.center)
            
            Button("Save As...") {
                saveFile()
            }
            .buttonStyle(.borderedProminent)
            
            Button("Close") {
                closeWindow()
            }
            .buttonStyle(.bordered)
        }
        .frame(width: 300, height: 200)
        .padding()
    }
    
    private func saveFile() {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = url.lastPathComponent
        
        if savePanel.runModal() == .OK, let saveURL = savePanel.url {
            do {
                if FileManager.default.fileExists(atPath: saveURL.path) {
                    try FileManager.default.removeItem(at: saveURL)
                }
                try FileManager.default.copyItem(at: url, to: saveURL)
                
                closeWindow()
            } catch {
                // Handle error
                print("Save error: \(error)")
                ErrorLogger.shared.logError(error, context: "Saving export file")
            }
        }
    }
    
    private func closeWindow() {
        // End the modal session
        NSApp.stopModal()
    }
}
