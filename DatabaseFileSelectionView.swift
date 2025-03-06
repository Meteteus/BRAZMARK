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
    
    // State for controlling manual resize functionality
    @State private var viewHeight: CGFloat = 200 // Default starting height
    @State private var isDraggingResizer = false
    @State private var refreshID = UUID()
    @State private var isLoading = false
    
    // Constants for resize constraints
    private let minHeight: CGFloat = 120
    private let maxHeight: CGFloat = 600
    private let defaultCollapsedHeight: CGFloat = 120
    private let defaultExpandedHeight: CGFloat = 350
    
    // Get files from database based on type
    private var files: [AudioFile] {
        if fileType == .song {
            return processor.fileDatabase.songs
        } else {
            return processor.fileDatabase.watermarks
        }
    }
    
    // User defaults key for persisting heights
    private var heightUserDefaultsKey: String {
        "DatabaseFileViewHeight_\(title)"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with title and controls
            HStack {
                Text("\(title): \(files.count)")
                    .font(.headline)
                    .foregroundColor(processor.currentTheme.textColor)
                
                Spacer()
                
                // Expand/collapse button with better styling
                Button(action: {
                    isExpanded.toggle()
                    // Animate height change
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        viewHeight = isExpanded ? defaultExpandedHeight : defaultCollapsedHeight
                    }
                    // Save height preference
                    UserDefaults.standard.set(viewHeight, forKey: heightUserDefaultsKey)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                        Text(isExpanded ? "Collapse" : "Expand")
                            .font(.system(size: 12))
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(processor.currentTheme.accentColor.opacity(0.1))
                    )
                    .foregroundColor(processor.currentTheme.accentColor)
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Collapse view" : "Expand view")
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            
            // Action buttons
            HStack(spacing: 12) {
                Button("Add \(title)") {
                    selectFiles()
                }
                .buttonStyle(.bordered)
                
                Button("Clear") {
                    confirmClearFiles()
                }
                .buttonStyle(.bordered)
                
                if !files.isEmpty {
                    AudioPreviewPlayer(url: files.first?.url)
                }
                
                Spacer()
                
                // Show count indicator with clearer styling
                Text("\(files.count) \(files.count == 1 ? "file" : "files")")
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(processor.currentTheme.accentColor.opacity(0.15))
                    )
                    .foregroundColor(processor.currentTheme.accentColor)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            
            // File list with loading indicator
            ZStack {
                // Actual file list content
                fileListContentView
                    .frame(height: viewHeight)
                
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.7)
                        .background(Color.white.opacity(0.7))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(processor.currentTheme.backgroundColor.opacity(0.5))
                    
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isDragging ? processor.currentTheme.accentColor.opacity(0.7) :
                                        processor.currentTheme.borderColor.opacity(0.3),
                            lineWidth: isDragging ? 2 : 1
                        )
                        .animation(.easeOut(duration: 0.2), value: isDragging)
                }
            )
            .padding(.horizontal)
            
            // Resizing handle
            ResizeHandle(isDragging: $isDraggingResizer)
                .gesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { value in
                            isDraggingResizer = true
                            let newHeight = viewHeight + value.translation.height
                            // Apply constraints
                            viewHeight = min(maxHeight, max(minHeight, newHeight))
                            // We're using drag, so consider the view expanded
                            if !isExpanded && viewHeight > defaultCollapsedHeight + 50 {
                                isExpanded = true
                            } else if isExpanded && viewHeight < defaultCollapsedHeight + 30 {
                                isExpanded = false
                            }
                        }
                        .onEnded { _ in
                            isDraggingResizer = false
                            // Save height preference
                            UserDefaults.standard.set(viewHeight, forKey: heightUserDefaultsKey)
                        }
                )
                .padding(.horizontal)
        }
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(processor.currentTheme.backgroundColor.opacity(0.2))
        )
        .onReceive(processor.fileDatabase.objectWillChange) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                self.refreshID = UUID()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RefreshWatermarkGroups"))) { _ in
            // Force refresh when group membership changes
            self.refreshID = UUID()
        }
        .id("file-view-\(title)-\(refreshID)-\(processor.refreshID)")
        .onAppear {
            // Load saved height preference
            if let savedHeight = UserDefaults.standard.object(forKey: heightUserDefaultsKey) as? CGFloat {
                viewHeight = savedHeight
                isExpanded = savedHeight > defaultCollapsedHeight + 20
            } else {
                // Default to collapsed state if no saved preference
                viewHeight = defaultCollapsedHeight
                isExpanded = false
            }
        }
    }
    
    // Enhanced file list content view with group feedback
    private var fileListContentView: some View {
        VStack(spacing: 0) {
            // Show a header when a group is selected in the watermarks section
            if fileType == .watermark, let selectedGroup = processor.selectedWatermarkGroup {
                HStack {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                    
                    Text("Group: \(selectedGroup.name)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.blue)
                    
                    Spacer()
                    
                    let inGroupCount = processor.fileDatabase.watermarksInGroup(selectedGroup).count
                    let totalCount = files.count
                    
                    Text("\(inGroupCount)/\(totalCount) in group")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.05))
                .cornerRadius(4)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(files) { file in
                        FileRowView(file: file, fileType: fileType, processor: processor)
                            .transition(.opacity.combined(with: .slide))
                    }
                }
                .padding(10)
                .animation(.easeInOut(duration: 0.2), value: files.count)
            }
            .overlay(emptyStateOverlay)
            .contentShape(Rectangle()) // Make entire area droppable
            .onDrop(of: [UTType.fileURL], isTargeted: $isDragging) { providers in
                handleFileDrop(providers)
                return true
            }
            .onChange(of: isDragging) { newValue in
                if newValue {
                    // Trigger haptic feedback when dragging starts
                    let generator = NSHapticFeedbackManager.defaultPerformer
                    generator.perform(.alignment, performanceTime: .default)
                }
            }
        }
    }
    
    // Enhanced empty state overlay with animations
    @ViewBuilder
    private var emptyStateOverlay: some View {
        if files.isEmpty {
            VStack(spacing: 15) {
                // Animated icon that pulses gently
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 36))
                    .foregroundColor(processor.currentTheme.accentColor.opacity(0.7))
                    .shadow(color: processor.currentTheme.accentColor.opacity(0.3), radius: 2, x: 0, y: 1)
                    .scaleEffect(isDragging ? 1.2 : 1.0)
                    .animation(
                        Animation.easeInOut(duration: 1.2)
                            .repeatForever(autoreverses: true),
                        value: isDragging
                    )
                
                Text("Drag and drop \(title.lowercased()) here")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(processor.currentTheme.textColor.opacity(0.8))
                
                Text("or click Add \(title) button")
                    .font(.system(size: 14))
                    .foregroundColor(processor.currentTheme.secondaryTextColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(processor.currentTheme.backgroundColor.opacity(0.4))
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
                // Ensure height is appropriate for new content
                if !isExpanded && files.count > 3 {
                    withAnimation(.easeInOut) {
                        isExpanded = true
                        viewHeight = defaultExpandedHeight
                    }
                }
                self.refreshID = UUID()
                // Update processor refreshID to force child views to update
                processor.refreshID = UUID()
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
                // Auto-expand if we added multiple files
                if !isExpanded && urls.count > 1 {
                    withAnimation(.easeInOut) {
                        isExpanded = true
                        viewHeight = defaultExpandedHeight
                    }
                }
                self.refreshID = UUID()
                // Update processor refreshID to force child views to update
                processor.refreshID = UUID()
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
                processor.refreshID = UUID() // Update processor refreshID
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

// Updated FileRowView with improved group indicators
struct FileRowView: View {
    let file: AudioFile
    let fileType: AudioFileType
    let processor: AudioProcessor
    
    @State private var isHovering = false
    @State private var isClickAnimating = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 10) {
            // Icon with appropriate type indicator
            Image(systemName: fileType == .song ? "music.note" : "waveform")
                .foregroundColor(fileType == .song ? .blue : .green)
                .font(.system(size: 14))
                .frame(width: 24)
            
            // Filename with truncation
            Text(file.displayName)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
            
            // Group controls for watermarks - ALWAYS VISIBLE with enhanced visual feedback
            if fileType == .watermark, let selectedGroup = processor.selectedWatermarkGroup {
                let isInGroup = processor.fileDatabase.isWatermarkInGroup(file, group: selectedGroup)
                
                ZStack {
                    // Status indicator that's always visible
                    Circle()
                        .fill(isInGroup ? Color.green : Color.gray.opacity(0.2))
                        .frame(width: 8, height: 8)
                        .padding(.trailing, 75)
                    
                    Button(action: {
                        // Add haptic feedback
                        let generator = NSHapticFeedbackManager.defaultPerformer
                        generator.perform(.alignment, performanceTime: .default)
                        
                        // Visual feedback animation
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            isClickAnimating = true
                        }
                        
                        // Reset animation after a short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation {
                                isClickAnimating = false
                            }
                        }
                        
                        Task { @MainActor in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if isInGroup {
                                    processor.fileDatabase.removeWatermarkFromGroup(file, group: selectedGroup)
                                } else {
                                    processor.fileDatabase.addWatermarkToGroup(file, group: selectedGroup)
                                }
                                // Force UI update immediately
                                processor.objectWillChange.send()
                                processor.refreshID = UUID()
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: isInGroup ? "minus.circle.fill" : "plus.circle.fill")
                                .foregroundColor(isInGroup ? .red : .blue)
                                .font(.system(size: 15))
                                .symbolRenderingMode(.hierarchical)
                            
                            Text(isInGroup ? "Remove" : "Add")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(isInGroup ? .red : .blue)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isInGroup ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .strokeBorder(isInGroup ? Color.red.opacity(0.2) : Color.blue.opacity(0.2), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .help(isInGroup ? "Remove from group" : "Add to group")
                    .scaleEffect(isClickAnimating ? 0.9 : (isHovering ? 1.05 : 1.0))
                    .animation(.spring(response: 0.2), value: isHovering)
                    .animation(.spring(response: 0.2), value: isClickAnimating)
                    // Add ID to force refresh when membership changes
                    .id("membership-\(file.id)-\(selectedGroup.id)-\(isInGroup)-\(processor.refreshID)")
                }
            }
            
            // Delete button - always visible
            Button(action: {
                confirmDeleteFile(file)
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundColor(isHovering ? .red : .red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColorForRow())
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        // Add ID for the row to force refresh
        .id("file-row-\(file.id)-\(processor.refreshID)")
    }
    
    // Determine background color based on state
    private func backgroundColorForRow() -> Color {
        // If it's a watermark and a group is selected
        if fileType == .watermark,
           let selectedGroup = processor.selectedWatermarkGroup,
           processor.fileDatabase.isWatermarkInGroup(file, group: selectedGroup) {
            
            // In group - light green background
            return isHovering
                ? (colorScheme == .dark ? Color.green.opacity(0.15) : Color.green.opacity(0.08))
                : (colorScheme == .dark ? Color.green.opacity(0.08) : Color.green.opacity(0.05))
        }
        
        // Default hover state
        return isHovering
            ? (colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
            : Color.clear
    }
    
    // Confirm file deletion
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
            }
        }
    }
}

// Resize handle component
struct ResizeHandle: View {
    @Binding var isDragging: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 2) {
            Rectangle()
                .fill(isDragging ? Color.blue : (colorScheme == .dark ? Color.gray.opacity(0.4) : Color.gray.opacity(0.3)))
                .frame(width: 40, height: 2)
                .cornerRadius(1)
            
            Rectangle()
                .fill(isDragging ? Color.blue : (colorScheme == .dark ? Color.gray.opacity(0.4) : Color.gray.opacity(0.3)))
                .frame(width: 40, height: 2)
                .cornerRadius(1)
        }
        .frame(height: 12)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { isHovering in
            if isHovering {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
