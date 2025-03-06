//
//  Cache.swift
//  BRAZMARK
//
//  Created by Matheus Braz on 3/5/25.
//


import Foundation
import os.log

/// Generic memory cache with cost-based eviction
class Cache<KeyType: AnyObject & Hashable, ValueType: AnyObject> {
    // Cache with cost limit
    private let cache = NSCache<KeyType, ValueType>()
    private let logger = Logger(subsystem: "com.brazmark", category: "cache")
    private let concurrentQueue = DispatchQueue(label: "com.brazmark.cache", attributes: .concurrent)
    
    // Access timestamps for LRU behavior
    private var accessTimes = [KeyType: Date]()
    
    // Initialization with default settings
    init(name: String = "BrazmarkCache", countLimit: Int = 50, costLimit: Int = 50_000_000) {
        cache.name = name
        cache.countLimit = countLimit    // Maximum number of items
        cache.totalCostLimit = costLimit // Cost limit in bytes
        
        // Set up cache eviction delegate if needed
        cache.evictsObjectsWithDiscardedContent = true
        
        // Set up periodic cleanup
        scheduleCleanup()
    }
    
    // Schedule periodic cleanup to remove stale entries
    private func scheduleCleanup() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 300) { [weak self] in
            self?.removeStaleEntries()
            self?.scheduleCleanup()
        }
    }
    
    // Set an object in the cache with an estimated cost
    func setObject(_ object: ValueType, forKey key: KeyType, cost: Int = 0) {
        concurrentQueue.async(flags: .barrier) { [weak self] in
            self?.cache.setObject(object, forKey: key, cost: cost)
            self?.accessTimes[key] = Date()
            
            // Log cache statistics periodically
            if let self = self, arc4random_uniform(100) < 5 { // 5% chance to log
                self.logger.debug("Cache '\(self.cache.name)' stats - count: \(self.accessTimes.count)")
            }
        }
    }
    
    // Get an object from the cache
    func object(forKey key: KeyType) -> ValueType? {
        concurrentQueue.sync { [weak self] in
            // Update access time
            self?.accessTimes[key] = Date()
            return self?.cache.object(forKey: key)
        }
    }
    
    // Remove an object from the cache
    func removeObject(forKey key: KeyType) {
        concurrentQueue.async(flags: .barrier) { [weak self] in
            self?.cache.removeObject(forKey: key)
            self?.accessTimes.removeValue(forKey: key)
        }
    }
    
    // Remove all objects from the cache
    func removeAllObjects() {
        concurrentQueue.async(flags: .barrier) { [weak self] in
            self?.cache.removeAllObjects()
            self?.accessTimes.removeAll()
        }
    }
    
    // Remove stale entries that haven't been accessed in a while
    private func removeStaleEntries() {
        let staleInterval: TimeInterval = 60 * 30 // 30 minutes
        let now = Date()
        
        concurrentQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            // Find keys that haven't been accessed recently
            let staleKeys = self.accessTimes.filter { key, lastAccess in
                return now.timeIntervalSince(lastAccess) > staleInterval
            }.keys
            
            // Remove stale entries
            for key in staleKeys {
                self.cache.removeObject(forKey: key)
                self.accessTimes.removeValue(forKey: key)
            }
            
            if !staleKeys.isEmpty {
                self.logger.debug("Removed \(staleKeys.count) stale entries from cache '\(self.cache.name)'")
            }
        }
    }
    
    // Get the number of items in the cache
    var count: Int {
        return concurrentQueue.sync { accessTimes.count }
    }
}
