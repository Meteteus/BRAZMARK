import SwiftUI
import Combine

struct WatermarkGroupView: View {
    @EnvironmentObject var processor: AudioProcessor
    @State private var showingNewGroupSheet = false
    @State private var newGroupName = ""
    @State private var editingGroup: WatermarkGroup?
    @State private var editedGroupName = ""
    @State private var showAddWatermarksHelp = false
    
    // Add this to track group changes
    @State private var refreshID = UUID()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row with group controls
            HStack {
                Text("Watermark Groups")
                    .font(.headline)
                
                Spacer()
                
                // Help button
                Button(action: {
                    showAddWatermarksHelp.toggle()
                }) {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showAddWatermarksHelp) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Using Watermark Groups")
                            .font(.headline)
                            .padding(.bottom, 5)
                        
                        Text("1. Create a group using the 'New Group' button")
                        Text("2. Select the group from the dropdown")
                        Text("3. Add watermarks to the group by clicking the + button next to each watermark file")
                        Text("4. When processing, only watermarks in the selected group will be used")
                        
                        Divider()
                        
                        Text("Groups let you organize watermarks and quickly switch between different sets of watermarks.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(width: 350)
                }
                
                Button("New Group") {
                    newGroupName = ""
                    showingNewGroupSheet = true
                }
                .buttonStyle(.bordered)
                .popover(isPresented: $showingNewGroupSheet) {
                    VStack(spacing: 15) {
                        Text("Create New Watermark Group")
                            .font(.headline)
                        
                        TextField("Group Name", text: $newGroupName)
                            .frame(width: 250)
                            .textFieldStyle(.roundedBorder)
                        
                        HStack {
                            Button("Cancel") {
                                newGroupName = ""
                                showingNewGroupSheet = false
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Create") {
                                if !newGroupName.isEmpty {
                                    let newGroup = processor.fileDatabase.createWatermarkGroup(name: newGroupName)
                                    processor.selectedWatermarkGroup = newGroup
                                    newGroupName = ""
                                    showingNewGroupSheet = false
                                    refreshID = UUID() // Force UI refresh
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newGroupName.isEmpty)
                        }
                        .padding()
                    }
                    .padding()
                }
            }
            
            // Group selection with active group info
            HStack(spacing: 15) {
                // Group selector with improved colors
                Menu {
                    Button("All Watermarks") {
                        processor.selectedWatermarkGroup = nil
                    }
                    
                    if !processor.fileDatabase.watermarkGroups.isEmpty {
                        Divider()
                        
                        ForEach(processor.fileDatabase.watermarkGroups) { group in
                            Button(group.name) {
                                processor.selectedWatermarkGroup = group
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(processor.selectedWatermarkGroup?.name ?? "All Watermarks")
                            .lineLimit(1)
                            .foregroundColor(processor.currentTheme.textColor)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(processor.currentTheme.secondaryTextColor)
                    }
                    .frame(width: 200)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(processor.currentTheme.borderColor, lineWidth: 1)
                            .background(processor.currentTheme.backgroundColor.opacity(0.8).cornerRadius(8))
                    )
                }
                .buttonStyle(.plain)
                
                if let selectedGroup = processor.selectedWatermarkGroup {
                    let watermarkCount = processor.fileDatabase.watermarksInGroup(selectedGroup).count
                    
                    // Info badge showing watermark count
                    Text("\(watermarkCount) watermark\(watermarkCount == 1 ? "" : "s")")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.blue.opacity(0.1))
                        )
                        .foregroundColor(.blue)
                    
                    Spacer()
                    
                    // Group actions when a group is selected
                    HStack(spacing: 15) {
                        Button("Rename") {
                            editingGroup = selectedGroup
                            editedGroupName = selectedGroup.name
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Delete") {
                            confirmDeleteGroup(selectedGroup)
                        }
                        .foregroundColor(.red)
                        .buttonStyle(.bordered)
                    }
                    
                    // Rename popup
                    .popover(item: $editingGroup) { group in
                        VStack(spacing: 15) {
                            Text("Rename Group")
                                .font(.headline)
                            
                            TextField("Group Name", text: $editedGroupName)
                                .frame(width: 250)
                                .textFieldStyle(.roundedBorder)
                            
                            HStack {
                                Button("Cancel") {
                                    editingGroup = nil
                                }
                                .buttonStyle(.bordered)
                                
                                Button("Save") {
                                    if !editedGroupName.isEmpty {
                                        processor.fileDatabase.updateGroupName(group, newName: editedGroupName)
                                        editingGroup = nil
                                        refreshID = UUID() // Force UI refresh
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(editedGroupName.isEmpty)
                            }
                            .padding(.top)
                        }
                        .padding()
                    }
                }
                else {
                    Text("Select or create a group above")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    
                    Spacer()
                }
            }
            
            // Show group instructions when a group is selected
            if let selectedGroup = processor.selectedWatermarkGroup {
                let watermarks = processor.fileDatabase.watermarksInGroup(selectedGroup)
                
                if watermarks.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("How to add watermarks to this group:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 2) {
                            Text("Look for the")
                            Image(systemName: "plus.circle")
                                .foregroundColor(.green)
                            Text("button next to each watermark in the list below.")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.1))
                    )
                } else {
                    // Group watermarks display with improved updates
                    Text("Watermarks in this group:")
                        .font(.subheadline)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(watermarks) { watermark in
                                HStack {
                                    Image(systemName: "music.note")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    
                                    Text(watermark.displayName)
                                        .font(.caption)
                                        .lineLimit(1)
                                    
                                    Button(action: {
                                        Task { @MainActor in
                                            processor.fileDatabase.removeWatermarkFromGroup(watermark, group: selectedGroup)
                                            // Force immediate UI refresh
                                            processor.objectWillChange.send()
                                            refreshID = UUID()
                                        }
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.gray.opacity(0.1))
                                )
                            }
                        }
                        .id("watermarkList-\(refreshID)") // Add an ID that changes with refreshID
                        .padding(.vertical, 4)
                    }
                    .frame(height: 32)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.05))
                .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal)
        .onReceive(processor.objectWillChange) { _ in
            // Force refresh when processor changes
            self.refreshID = UUID()
        }
        .id(refreshID) // This forces the view to refresh when refreshID changes
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
            refreshID = UUID() // Force UI refresh
        }
    }
}
