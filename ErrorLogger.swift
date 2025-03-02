//
//  ErrorLogger.swift
//  BRAZMARK
//
//  Created by Matheus Braz on 3/2/25.
//


import Foundation

/// Error logger for tracking and saving errors
class ErrorLogger {
    static let shared = ErrorLogger()
    
    private let logURL: URL
    private var logFileHandle: FileHandle?
    private let queue = DispatchQueue(label: "com.brazmark.errorLogger")
    
    init() {
        // Get app's documents directory
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        logURL = documentsDirectory.appendingPathComponent("BRAZMARK_error_log.txt")
        
        // Setup log file
        setupLogFile()
    }
    
    private func setupLogFile() {
        // Create log file if it doesn't exist
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        
        // Open file for appending
        do {
            logFileHandle = try FileHandle(forWritingTo: logURL)
            logFileHandle?.seekToEndOfFile()
        } catch {
            print("Failed to open log file: \(error)")
        }
    }
    
    func logError(_ error: Error, context: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let timestamp = Date().ISO8601Format()
            let errorDescription = (error as NSError).localizedDescription
            let errorCode = (error as NSError).code
            let errorDomain = (error as NSError).domain
            
            let logEntry = """

            ===== Error Log Entry =====
            Timestamp: \(timestamp)
            Context: \(context)
            Error: \(errorDescription)
            Code: \(errorCode)
            Domain: \(errorDomain)
            ============================

            """
            
            if let data = logEntry.data(using: .utf8) {
                self.logFileHandle?.write(data)
            }
        }
    }
    
    func getLogContents() -> String {
        do {
            return try String(contentsOf: logURL, encoding: .utf8)
        } catch {
            return "Error reading log file: \(error.localizedDescription)"
        }
    }
    
    func clearLog() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // Close existing file handle
            self.logFileHandle?.closeFile()
            
            // Create new empty file
            FileManager.default.createFile(atPath: self.logURL.path, contents: nil, attributes: nil)
            
            // Reopen file handle
            do {
                self.logFileHandle = try FileHandle(forWritingTo: self.logURL)
            } catch {
                print("Failed to reopen log file: \(error)")
            }
        }
    }
    
    deinit {
        logFileHandle?.closeFile()
    }
}

// Add a debug view for displaying error logs
#if DEBUG
import SwiftUI

struct ErrorLogView: View {
    @State private var logContent: String = ""
    @State private var refreshTimer: Timer?
    
    var body: some View {
        VStack(spacing: 15) {
            HStack {
                Text("Error Log")
                    .font(.headline)
                
                Spacer()
                
                Button("Refresh") {
                    updateLogContent()
                }
                
                Button("Clear Log") {
                    ErrorLogger.shared.clearLog()
                    updateLogContent()
                }
                .foregroundColor(.red)
            }
            
            if logContent.isEmpty {
                Text("No errors logged")
                    .foregroundColor(.gray)
                    .italic()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(logContent)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(Color.black.opacity(0.05))
                .cornerRadius(8)
            }
        }
        .padding()
        .onAppear {
            updateLogContent()
            
            // Set up refresh timer
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
                updateLogContent()
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }
    
    private func updateLogContent() {
        logContent = ErrorLogger.shared.getLogContents()
    }
}
#endif