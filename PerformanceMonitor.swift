//
//  PerformanceMonitor.swift
//  BRAZMARK
//
//  Created by Matheus Braz on 3/2/25.
//


import Foundation
import os.log

class PerformanceMonitor {
    static let shared = PerformanceMonitor()
    
    private let logger = Logger(subsystem: "com.brazmark", category: "performance")
    private var measurements: [String: [TimeInterval]] = [:]
    private let queue = DispatchQueue(label: "com.brazmark.performanceMonitor")
    
    // Start a performance measurement
    func startMeasurement(for operation: String) -> PerformanceTracker {
        return PerformanceTracker(operation: operation)
    }
    
    // Record a measurement
    func recordMeasurement(operation: String, duration: TimeInterval) {
        queue.async {
            if self.measurements[operation] == nil {
                self.measurements[operation] = []
            }
            self.measurements[operation]?.append(duration)
            
            // Log the measurement
            self.logger.debug("Performance: \(operation) took \(duration) seconds")
        }
    }
    
    // Get statistics for an operation
    func getStatistics(for operation: String) -> PerformanceStatistics? {
        return queue.sync {
            guard let durations = measurements[operation], !durations.isEmpty else {
                return nil
            }
            
            let totalDuration = durations.reduce(0, +)
            let avgDuration = totalDuration / Double(durations.count)
            let minDuration = durations.min() ?? 0
            let maxDuration = durations.max() ?? 0
            
            return PerformanceStatistics(
                operationName: operation,
                averageDuration: avgDuration,
                minDuration: minDuration,
                maxDuration: maxDuration,
                numberOfMeasurements: durations.count
            )
        }
    }
    
    // Get all statistics
    func getAllStatistics() -> [PerformanceStatistics] {
        return queue.sync {
            return measurements.compactMap { operation, durations in
                guard !durations.isEmpty else { return nil }
                
                let totalDuration = durations.reduce(0, +)
                let avgDuration = totalDuration / Double(durations.count)
                let minDuration = durations.min() ?? 0
                let maxDuration = durations.max() ?? 0
                
                return PerformanceStatistics(
                    operationName: operation,
                    averageDuration: avgDuration,
                    minDuration: minDuration,
                    maxDuration: maxDuration,
                    numberOfMeasurements: durations.count
                )
            }
        }
    }
    
    // Reset measurements
    func resetMeasurements() {
        queue.async {
            self.measurements.removeAll()
        }
    }
}

// Performance tracker for timing operations
class PerformanceTracker {
    private let operation: String
    private let startTime: Date
    
    init(operation: String) {
        self.operation = operation
        self.startTime = Date()
    }
    
    func stop() {
        let duration = Date().timeIntervalSince(startTime)
        PerformanceMonitor.shared.recordMeasurement(operation: operation, duration: duration)
    }
}

// Statistics struct for reporting
struct PerformanceStatistics {
    let operationName: String
    let averageDuration: TimeInterval
    let minDuration: TimeInterval
    let maxDuration: TimeInterval
    let numberOfMeasurements: Int
    
    var formattedAverage: String {
        return String(format: "%.2f", averageDuration)
    }
    
    var formattedMin: String {
        return String(format: "%.2f", minDuration)
    }
    
    var formattedMax: String {
        return String(format: "%.2f", maxDuration)
    }
}

// Memory monitor class
class MemoryMonitor {
    static let shared = MemoryMonitor()
    
    private let logger = Logger(subsystem: "com.brazmark", category: "memory")
    private var timer: Timer?
    
    func startMonitoring(interval: TimeInterval = 10.0) {
        stopMonitoring()
        
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.logMemoryUsage()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    func logMemoryUsage() {
        let usedMemory = memoryUsage()
        logger.debug("Memory usage: \(usedMemory) MB")
    }
    
    private func memoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / (1024 * 1024) // Convert to MB
        } else {
            return 0
        }
    }
}