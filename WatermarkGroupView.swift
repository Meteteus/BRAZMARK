import SwiftUI
import Combine

struct WatermarkGroupView: View {
    @EnvironmentObject var processor: AudioProcessor
    @State private var showingNewGroupSheet = false
    @State private var newGroupName = ""
    @State private var editingGroup: WatermarkGroup?
    @State private var editedGroupName = ""
    @State private var showAddWatermarksHelp = false
    @State private var isAnimating = false
    
    // Multi-select groups
    @State private var selectedGroups: Set<UUID> = []
    
    // Track changes for UI refresh
    @State private var refreshID = UUID()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Compact header with group selection
            HStack {
                // Title and new group button
                HStack(spacing: 10) {
                    Image(systemName: "folder.fill.badge.person.crop")
                        .foregroundColor(processor.currentTheme.accentColor)
                        .font(.system(size: 16))
                        .symbolRenderingMode(.hierarchical)
                    
                    Text("Watermark Groups")
                        .font(.headline)
                        .foregroundColor(processor.currentTheme.textColor)
                }
                
                Spacer()
                
                // Group management buttons
                HStack(spacing: 8) {
                    // New group button
                    Button(action: {
                        newGroupName = ""
                        showingNewGroupSheet = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(ToolbarButtonStyle())
                    .help("Create new group")
                    
                    // If there's an active selection, show edit button
                    if selectedGroups.count == 1, let groupID = selectedGroups.first,
                       let group = processor.fileDatabase.watermarkGroups.first(where: { $0.id == groupID }) {
                        
                        Button(action: {
                            editingGroup = group
                            editedGroupName = group.name
                        }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(ToolbarButtonStyle())
                        .help("Rename group")
                        
                        Button(action: {
                            confirmDeleteGroup(group)
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(ToolbarButtonStyle(color: .red))
                        .help("Delete group")
                    }
                    
                    // Help button
                    Button(action: {
                        showAddWatermarksHelp.toggle()
                    }) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(ToolbarButtonStyle())
                    .help("Help with groups")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            // Groups horizontal scroller - multi-select chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // "All" option
                    GroupChip(
                        name: "All Watermarks",
                        isSelected: selectedGroups.isEmpty,
                        onSelect: {
                            selectedGroups.removeAll()
                            processor.selectedWatermarkGroup = nil
                        }
                    )
                    
                    ForEach(processor.fileDatabase.watermarkGroups) { group in
                        GroupChip(
                            name: group.name,
                            isSelected: selectedGroups.contains(group.id),
                            count: processor.fileDatabase.watermarksInGroup(group).count,
                            onSelect: {
                                // Toggle just this group in single selection mode
                                if selectedGroups.contains(group.id) {
                                    selectedGroups.remove(group.id)
                                    processor.selectedWatermarkGroup = nil
                                } else {
                                    // For now we'll keep just one selected to match existing functionality
                                    selectedGroups = [group.id]
                                    processor.selectedWatermarkGroup = group
                                }
                                
                                // Force refresh
                                processor.refreshID = UUID()
                            }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }
            .opacity(processor.fileDatabase.watermarkGroups.isEmpty ? 0.5 : 1.0)
            .overlay(
                Group {
                    if processor.fileDatabase.watermarkGroups.isEmpty {
                        Text("No groups yet - create one with the + button")
                            .font(.system(size: 12))
                            .foregroundColor(processor.currentTheme.secondaryTextColor)
                            .padding(6)
                    }
                }
            )
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(processor.currentTheme.backgroundColor.opacity(0.7))
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
        .onReceive(processor.objectWillChange) { _ in
            // Update state when processor changes
            self.refreshID = UUID()
            
            // Make sure selected groups are in sync with processor
            if let currentGroup = processor.selectedWatermarkGroup {
                selectedGroups = [currentGroup.id]
            } else {
                selectedGroups.removeAll()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RefreshWatermarkGroups"))) { _ in
            // Force refresh when group membership changes
            self.refreshID = UUID()
        }
        .id("watermark-group-view-\(refreshID)-\(processor.refreshID)")
        
        // Help popover content
        .popover(isPresented: $showAddWatermarksHelp) {
            CompactGroupHelpPopover()
        }
        
        // New group sheet
        .sheet(isPresented: $showingNewGroupSheet) {
            CreateGroupSheet(
                groupName: $newGroupName,
                onCancel: {
                    showingNewGroupSheet = false
                    newGroupName = ""
                },
                onSave: {
                    createNewGroup()
                }
            )
        }
        
        // Rename group sheet
        .sheet(item: $editingGroup) { group in
            RenameGroupSheet(
                groupName: $editedGroupName,
                onCancel: { editingGroup = nil },
                onSave: {
                    if !editedGroupName.isEmpty {
                        processor.fileDatabase.updateGroupName(group, newName: editedGroupName)
                        editingGroup = nil
                        refreshID = UUID()
                        processor.refreshID = UUID()
                    }
                }
            )
        }
    }
    
    // MARK: - Helper Methods
    
    // Create new group with validation
    private func createNewGroup() {
        if !newGroupName.isEmpty {
            let newGroup = processor.fileDatabase.createWatermarkGroup(name: newGroupName)
            processor.selectedWatermarkGroup = newGroup
            selectedGroups = [newGroup.id]
            newGroupName = ""
            showingNewGroupSheet = false
            refreshID = UUID()
            processor.refreshID = UUID() // Update processor refreshID
        }
    }
    
    private func confirmDeleteGroup(_ group: WatermarkGroup) {
        let alert = NSAlert()
        alert.messageText = "Delete Group"
        alert.informativeText = "Are you sure you want to delete the group '\(group.name)'? This will not delete the watermark files."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete")
        alert.alertStyle = .warning
        
        if alert.runModal() == .alertSecondButtonReturn {
            processor.fileDatabase.deleteWatermarkGroup(group)
            processor.selectedWatermarkGroup = nil
            selectedGroups.remove(group.id)
            refreshID = UUID()
            processor.refreshID = UUID() // Update processor refreshID
        }
    }
}

// MARK: - Supporting Views for WatermarkGroupView

// Group chip for horizontal selection
struct GroupChip: View {
    let name: String
    let isSelected: Bool
    var count: Int? = nil
    let onSelect: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering = false
    @State private var isClicking = false
    
    var body: some View {
        Button(action: {
            // Visual feedback
            withAnimation(.spring(response: 0.2)) {
                isClicking = true
            }
            
            // Reset after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation {
                    isClicking = false
                }
            }
            
            // Add haptic feedback
                        let generator = NSHapticFeedbackManager.defaultPerformer
                        generator.perform(.alignment, performanceTime: .default)
            
            onSelect()
        }) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                
                if let count = count {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.2) : Color.blue.opacity(0.2))
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.blue : (isHovering ? Color.gray.opacity(0.15) : Color.gray.opacity(0.08)))
            )
            .foregroundColor(isSelected ? .white : .primary)
            .scaleEffect(isClicking ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// Toolbar style button
struct ToolbarButtonStyle: ButtonStyle {
    var color: Color = .blue
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(color)
            .padding(6)
            .background(
                Circle()
                    .fill(configuration.isPressed ? color.opacity(0.2) : Color.clear)
            )
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
    }
}

// Compact group help popover
struct CompactGroupHelpPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Using Watermark Groups")
                .font(.headline)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Groups help you organize your watermarks:")
                    .font(.system(size: 13, weight: .medium))
                
                VStack(alignment: .leading, spacing: 8) {
                    HelpPoint(icon: "plus", text: "Create groups with the + button")
                    HelpPoint(icon: "checkmark.circle", text: "Click a group pill to select it")
                    HelpPoint(icon: "rectangle.on.rectangle", text: "Use \"Add\" in the watermarks section to add files to a group")
                    HelpPoint(icon: "arrow.counterclockwise", text: "You can quickly switch between different watermark sets")
                }
                
                Divider()
                    .padding(.vertical, 5)
                
                Text("Tips:")
                    .font(.system(size: 13, weight: .medium))
                
                Text("• Create different groups for different clients or projects")
                Text("• Groups make it easy to reuse watermarks across sessions")
                Text("• Add all your watermarks at once by selecting multiple files")
                Text("• The \"All Watermarks\" option processes without group filtering")
                    .font(.system(size: 13))
            }
        }
        .padding()
        .frame(width: 350, height: 300)
    }
}

// Help point for compact popover
struct HelpPoint: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(text)
                .font(.system(size: 13))
        }
    }
}

// Create group sheet
struct CreateGroupSheet: View {
    @Binding var groupName: String
    let onCancel: () -> Void
    let onSave: () -> Void
    @FocusState private var isNameFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Create New Group")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Group Name:")
                    .font(.system(size: 14, weight: .medium))
                
                TextField("Enter group name", text: $groupName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($isNameFieldFocused)
                    .frame(width: 250)
                    .onSubmit {
                        if !groupName.isEmpty {
                            onSave()
                        }
                    }
            }
            
            HStack(spacing: 15) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                
                Button("Create") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .disabled(groupName.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 10)
        }
        .padding(25)
        .frame(width: 300)
        .onAppear {
            isNameFieldFocused = true
        }
    }
}

// Rename group sheet
struct RenameGroupSheet: View {
    @Binding var groupName: String
    let onCancel: () -> Void
    let onSave: () -> Void
    @FocusState private var isNameFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Rename Group")
                .font(.headline)
            
            TextField("Group name", text: $groupName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .focused($isNameFieldFocused)
                .frame(width: 250)
                .onSubmit {
                    if !groupName.isEmpty {
                        onSave()
                    }
                }
            
            HStack(spacing: 15) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                
                Button("Save") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .disabled(groupName.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(25)
        .frame(width: 300)
        .onAppear {
            isNameFieldFocused = true
        }
    }
}
