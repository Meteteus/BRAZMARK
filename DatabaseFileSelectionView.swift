import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct DatabaseFileSelectionView: View {
    let title: String
    let fileType: AudioFileType
    @EnvironmentObject var processor: AudioProcessor
    @State private var isDragging = false
    @State private var isExpanded = false
    @State private var importingFiles = false
    
    // Add a refresh ID to force view updates
    @State private var refreshID = UUID()
    @State private var isLoading = false
    
    // Get files from database based on type
    private var files: [AudioFile] {
        if fileType == .song {
            return processor.fileDatabase.songs
        } else {
            return processor.fileDatabase.watermarks
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            // Header
            HStack {
                Text("\(title): \(files.count)")
                    .font(.headline)
                
                Spacer()
                
                // Expand/collapse button
                Button(action: {
                    isExpanded.toggle()
                }) {
                    Image(systemName: isExpanded ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                        .foregroundColor(.blue)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Collapse list" : "Expand list")
            }
            
            // Action buttons
            HStack {
                Button("Add \(title)") {
                    selectFiles()
                }
                
                Button("Clear") {
                    confirmClearFiles()
                }
                
                if !files.isEmpty {
                    AudioPreviewPlayer(url: files.first?.url)
                }
            }
            
            // File list with loading indicator
            ZStack {
                fileListView
                
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.7)
                        .background(Color.white.opacity(0.7))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(.horizontal)
        .onReceive(processor.fileDatabase.objectWillChange) { _ in
            // Use smart refresh with animation
            withAnimation {
                self.refreshID = UUID()
            }
        }
        .id(refreshID) // This forces a view redraw
    }
    
    // Extracted file list view to simplify
    private var fileListView: some View {
        VStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(files) { file in
                        fileRow(file)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: isExpanded ? min(CGFloat(files.count * 18 + 10), 300) : 70)
            .animation(.spring(), value: isExpanded)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isDragging ? Color.blue : Color.gray.opacity(0.3), lineWidth: isDragging ? 3 : 1)
                    .background(Color.gray.opacity(0.05).cornerRadius(8))
            )
            .overlay(emptyStateOverlay)
            .animation(.easeInOut(duration: 0.2), value: isDragging)
            .onDrop(of: [UTType.fileURL], isTargeted: $isDragging) { providers in
                handleFileDrop(providers)
                return true
            }
        }
    }
    
    // Empty state overlay
    @ViewBuilder
    private var emptyStateOverlay: some View {
        if files.isEmpty {
            VStack {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 24))
                    .foregroundColor(.blue.opacity(0.6))
                
                Text("Drag and drop \(title.lowercased()) here")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // Individual file row
    private func fileRow(_ file: AudioFile) -> some View {
        HStack {
            Image(systemName: "music.note")
                .foregroundColor(.blue)
                .font(.system(size: 12))
            
            Text(file.displayName)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
            
            // Group controls for watermarks
            groupControls(for: file)
            
            // Delete button
            Button(action: {
                confirmDeleteFile(file)
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("Remove file")
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
    }
    
    // Group controls for watermarks with immediate updates
    @ViewBuilder
    private func groupControls(for file: AudioFile) -> some View {
        if fileType == .watermark, let selectedGroup = processor.selectedWatermarkGroup {
            let isInGroup = processor.fileDatabase.isWatermarkInGroup(file, group: selectedGroup)
            
            Button(action: {
                Task { @MainActor in
                    if isInGroup {
                        processor.fileDatabase.removeWatermarkFromGroup(file, group: selectedGroup)
                    } else {
                        processor.fileDatabase.addWatermarkToGroup(file, group: selectedGroup)
                    }
                    // Force UI update immediately
                    processor.objectWillChange.send()
                    refreshID = UUID()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: isInGroup ? "checkmark.circle.fill" : "plus.circle")
                        .foregroundColor(isInGroup ? .green : .blue)
                        .font(.system(size: 14))
                    
                    Text(isInGroup ? "In Group" : "Add")
                        .font(.system(size: 10))
                        .foregroundColor(isInGroup ? .green : .blue)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isInGroup ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
            .help(isInGroup ? "Remove from group" : "Add to group")
        }
    }
    
    // Improved file drop handling
    private func handleFileDrop(_ providers: [NSItemProvider]) {
        let validExtensions = ["mp3", "m4a", "wav", "aiff", "aac"]
        
        Task {
            await MainActor.run {
                self.isLoading = true
            }
            
            // Process files in batches to prevent UI freezing
            for provider in providers {
                // Get file URL from provider
                if let url = await withCheckedContinuation({ continuation in
                    provider.loadObject(ofClass: URL.self) { url, error in
                        continuation.resume(returning: url)
                    }
                }), validExtensions.contains(url.pathExtension.lowercased()) {
                    // Defer UI updates to next runloop to keep UI responsive
                    await Task.yield()
                    
                    do {
                        if fileType == .song {
                            _ = try await processor.fileDatabase.importSong(url: url)
                        } else {
                            _ = try await processor.fileDatabase.importWatermark(url: url)
                        }
                    } catch {
                        await MainActor.run {
                            showErrorAlert("Failed to import file: \(error.localizedDescription)")
                        }
                    }
                }
            }
            
            await MainActor.run {
                self.isLoading = false
                self.refreshID = UUID()
            }
        }
    }
    
    // Open file picker with improved handling
    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        
        var allowedTypes = [UTType.audio]
        let additionalTypes = ["mp3", "m4a", "wav", "aiff", "aac"].compactMap { UTType(filenameExtension: $0) }
        allowedTypes.append(contentsOf: additionalTypes)
        panel.allowedContentTypes = allowedTypes
        
        if panel.runModal() == .OK {
            importSelectedFiles(panel.urls)
        }
    }
    
    // Import selected files with better feedback
    private func importSelectedFiles(_ urls: [URL]) {
        Task {
            await MainActor.run {
                self.isLoading = true
            }
            
            // Process in batches to keep UI responsive
            for (index, url) in urls.enumerated() {
                // Add periodic yield to keep UI responsive
                if index % 3 == 0 {
                    await Task.yield()
                }
                
                do {
                    if fileType == .song {
                        _ = try await processor.fileDatabase.importSong(url: url)
                    } else {
                        _ = try await processor.fileDatabase.importWatermark(url: url)
                    }
                } catch {
                    await MainActor.run {
                        showErrorAlert("Failed to import file: \(error.localizedDescription)")
                    }
                }
            }
            
            await MainActor.run {
                self.isLoading = false
                self.refreshID = UUID()
            }
        }
    }
    
    // Improved file deletion with immediate UI update
    private func confirmDeleteFile(_ file: AudioFile) {
        let alert = NSAlert()
        alert.messageText = "Remove this file?"
        alert.informativeText = "Are you sure you want to remove '\(file.displayName)'?"
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Remove")
        alert.alertStyle = .warning
        
        if alert.runModal() == .alertSecondButtonReturn {
            Task { @MainActor in
                processor.fileDatabase.removeFile(file)
                // Force refresh
                self.refreshID = UUID()
            }
        }
    }
    
    // Confirm before removing all files
    private func confirmClearFiles() {
        if files.isEmpty { return }
        
        let alert = NSAlert()
        alert.messageText = "Remove all \(title.lowercased())?"
        alert.informativeText = "This will remove all \(title.lowercased()) from the database. This cannot be undone."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Remove All")
        alert.alertStyle = .warning
        
        if alert.runModal() == .alertSecondButtonReturn {
            Task { @MainActor in
                for file in files {
                    processor.fileDatabase.removeFile(file)
                }
                self.refreshID = UUID() // Force UI refresh
            }
        }
    }
    
    // Show error alert
    private func showErrorAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Import Error"
        alert.informativeText = message
        alert.runModal()
    }
}
