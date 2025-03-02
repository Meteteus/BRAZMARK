import Foundation
import AVFoundation

/// Manages a database of audio files stored in the app's internal storage
class AudioFileDatabase: ObservableObject {
    // Published collections for UI binding
    @Published var songs: [AudioFile] = []
    @Published var watermarks: [AudioFile] = []
    @Published var watermarkGroups: [WatermarkGroup] = []
    
    // File paths
    private let databaseURL: URL
    private let songsURL: URL
    private let watermarksURL: URL
    
    // Keys for persistence
    private let watermarkGroupsKey = "WatermarkGroups"
    private let songsMetadataKey = "SongsMetadata"
    private let watermarksMetadataKey = "WatermarksMetadata"
    
    init() {
        // Get the app's container directory
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Failed to access Application Support directory")
        }
        
        // Create our database folder structure
        databaseURL = appSupportURL.appendingPathComponent("BRAZMARK", isDirectory: true)
        songsURL = databaseURL.appendingPathComponent("Songs", isDirectory: true)
        watermarksURL = databaseURL.appendingPathComponent("Watermarks", isDirectory: true)
        
        // Create directories if needed
        try? FileManager.default.createDirectory(at: databaseURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: songsURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: watermarksURL, withIntermediateDirectories: true)
        
        // Load database
        loadDatabase()
    }
    
    // MARK: - File Management
    
    /// Import a song file by copying it to the internal database
    @MainActor
    func importSong(url: URL) async throws -> AudioFile {
        let file = try await importFile(url: url, destinationFolder: songsURL, collectionType: .song)
        // Force a UI update
        self.objectWillChange.send()
        return file
    }

    @MainActor
    func importWatermark(url: URL) async throws -> AudioFile {
        let file = try await importFile(url: url, destinationFolder: watermarksURL, collectionType: .watermark)
        // Force a UI update
        self.objectWillChange.send()
        return file
    }

    @MainActor
    func removeFile(_ file: AudioFile) {
        switch file.type {
        case .song:
            songs.removeAll { $0.id == file.id }
            
        case .watermark:
            watermarks.removeAll { $0.id == file.id }
            
            // Also remove from any groups
            for i in 0..<watermarkGroups.count {
                watermarkGroups[i].watermarkIds.removeAll { $0 == file.id }
            }
        }
        
        // Delete the actual file
        try? FileManager.default.removeItem(at: file.url)
        
        // Save changes
        saveDatabase()
        
        // Force UI update
        self.objectWillChange.send()
    }
    
    // MARK: - Group Management
    
    /// Create a new watermark group
    func createWatermarkGroup(name: String) -> WatermarkGroup {
        let newGroup = WatermarkGroup(id: UUID(), name: name, watermarkIds: [])
        watermarkGroups.append(newGroup)
        saveDatabase()
        return newGroup
    }
    
    /// Update the name of a watermark group
    func updateGroupName(_ group: WatermarkGroup, newName: String) {
        if let index = watermarkGroups.firstIndex(where: { $0.id == group.id }) {
            watermarkGroups[index].name = newName
            saveDatabase()
        }
    }
    
    /// Add a watermark to a group
    @MainActor
    func addWatermarkToGroup(_ watermark: AudioFile, group: WatermarkGroup) {
        guard watermark.type == .watermark else { return }
        
        if let index = watermarkGroups.firstIndex(where: { $0.id == group.id }) {
            // Only add if not already in the group
            if !watermarkGroups[index].watermarkIds.contains(watermark.id) {
                // Create a new array to trigger UI updates
                var updatedIds = watermarkGroups[index].watermarkIds
                updatedIds.append(watermark.id)
                
                // Force a UI update by replacing the entire group object
                let updatedGroup = WatermarkGroup(
                    id: group.id,
                    name: group.name,
                    watermarkIds: updatedIds
                )
                
                watermarkGroups[index] = updatedGroup
                saveDatabase()
                
                // Debug info
                print("Added watermark \(watermark.originalName) to group \(group.name)")
                print("Group now has \(watermarkGroups[index].watermarkIds.count) watermarks")
                
                // Force an UI refresh
                objectWillChange.send()
            }
        }
    }
    
    /// Remove a watermark from a group
    @MainActor
    func removeWatermarkFromGroup(_ watermark: AudioFile, group: WatermarkGroup) {
        if let index = watermarkGroups.firstIndex(where: { $0.id == group.id }) {
            // Create a new array without the item to force UI update
            let updatedIds = watermarkGroups[index].watermarkIds.filter { $0 != watermark.id }
            
            // Replace the entire group object
            let updatedGroup = WatermarkGroup(
                id: group.id,
                name: group.name,
                watermarkIds: updatedIds
            )
            
            watermarkGroups[index] = updatedGroup
            saveDatabase()
            
            // Debug info
            print("Removed watermark \(watermark.originalName) from group \(group.name)")
            print("Group now has \(watermarkGroups[index].watermarkIds.count) watermarks")
            
            // Force an UI refresh
            objectWillChange.send()
        }
    }
    
    /// Delete a watermark group (does not delete the files)
    func deleteWatermarkGroup(_ group: WatermarkGroup) {
        watermarkGroups.removeAll { $0.id == group.id }
        saveDatabase()
    }
    
    /// Get all watermarks in a specific group
    func watermarksInGroup(_ group: WatermarkGroup) -> [AudioFile] {
        return watermarks.filter { group.watermarkIds.contains($0.id) }
    }
    
    /// Check if a watermark is in a group
    func isWatermarkInGroup(_ watermark: AudioFile, group: WatermarkGroup) -> Bool {
        return group.watermarkIds.contains(watermark.id)
    }
    
    // MARK: - Private Helpers
    
    @MainActor
    private func importFile(url: URL, destinationFolder: URL, collectionType: AudioFileType) async throws -> AudioFile {
        // Generate a unique identifier
        let id = UUID()
        
        // Keep the original filename but ensure it's unique in our storage
        let originalFilename = url.lastPathComponent
        let fileExtension = url.pathExtension
        
        // Check if a file with same name already exists
        let baseFilename = url.deletingPathExtension().lastPathComponent
        let destinationURL = destinationFolder.appendingPathComponent(originalFilename)
        
        // If file exists, create a unique version with timestamp
        var finalDestinationURL = destinationURL
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            let timestamp = Int(Date().timeIntervalSince1970)
            finalDestinationURL = destinationFolder.appendingPathComponent("\(baseFilename)_\(timestamp).\(fileExtension)")
        }
        
        // Copy the file
        try FileManager.default.copyItem(at: url, to: finalDestinationURL)
        
        // Create audio file metadata
        let file = AudioFile(
            id: id,
            originalName: originalFilename,
            url: finalDestinationURL,
            type: collectionType
        )
        
        // Add to the appropriate collection
        switch collectionType {
        case .song:
            songs.append(file)
        case .watermark:
            watermarks.append(file)
        }
        
        saveDatabase()
        
        // Force UI update
        self.objectWillChange.send()
        
        return file
    }
    
    /// Load the database from UserDefaults and scan files
    private func loadDatabase() {
        // Load audio file metadata
        if let songsData = UserDefaults.standard.data(forKey: songsMetadataKey),
           let loadedSongs = try? JSONDecoder().decode([AudioFile].self, from: songsData) {
            // Verify files still exist
            songs = loadedSongs.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        }
        
        if let watermarksData = UserDefaults.standard.data(forKey: watermarksMetadataKey),
           let loadedWatermarks = try? JSONDecoder().decode([AudioFile].self, from: watermarksData) {
            // Verify files still exist
            watermarks = loadedWatermarks.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        }
        
        // Load watermark groups
        if let groupsData = UserDefaults.standard.data(forKey: watermarkGroupsKey),
           let loadedGroups = try? JSONDecoder().decode([WatermarkGroup].self, from: groupsData) {
            watermarkGroups = loadedGroups
        }
    }
    
    /// Save the database to UserDefaults
    private func saveDatabase() {
        // Save songs metadata
        if let encodedSongs = try? JSONEncoder().encode(songs) {
            UserDefaults.standard.set(encodedSongs, forKey: songsMetadataKey)
        }
        
        // Save watermarks metadata
        if let encodedWatermarks = try? JSONEncoder().encode(watermarks) {
            UserDefaults.standard.set(encodedWatermarks, forKey: watermarksMetadataKey)
        }
        
        // Save watermark groups
        if let encodedGroups = try? JSONEncoder().encode(watermarkGroups) {
            UserDefaults.standard.set(encodedGroups, forKey: watermarkGroupsKey)
        }
    }
}

// MARK: - Models

/// Represents an audio file in the database
struct AudioFile: Identifiable, Codable, Hashable {
    var id: UUID
    var originalName: String
    var url: URL
    var type: AudioFileType
    
    var displayName: String {
        originalName
    }
}

/// Types of audio files
enum AudioFileType: Int, Codable {
    case song
    case watermark
}

/// Represents a group of watermarks
struct WatermarkGroup: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var watermarkIds: [UUID]
}

extension AudioFileDatabase {
    /// Import watermark groups from another source
    func importWatermarkGroups(_ groups: [WatermarkGroup]) {
        for group in groups {
            if !watermarkGroups.contains(where: { $0.id == group.id }) {
                watermarkGroups.append(group)
            } else if let existingIndex = watermarkGroups.firstIndex(where: { $0.id == group.id }) {
                // Update existing group
                watermarkGroups[existingIndex] = group
            }
        }
        saveDatabase() // Make sure to save changes
    }
}
