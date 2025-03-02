import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var processor: AudioProcessor
    
    var body: some View {
        VStack(spacing: 20) {
            HeaderView()
            
            FormatControlsView()
                .padding(.horizontal)
            
            FileSelectionView(title: "Songs", files: $processor.songURLs)
            FileSelectionView(title: "Watermarks", files: $processor.watermarkURLs)
            
            OutputFolderView(outputFolder: $processor.outputFolder)
            
            CustomProgressView(
                progress: processor.progress,
                currentFile: processor.currentFile,
                currentWatermark: processor.currentWatermark
            )
            
            ProcessingControlsView()
        }
        .padding()
        .frame(minWidth: 600, minHeight: 500)
    }
}

struct HeaderView: View {
    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Text("Braz Mark")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            Text("Batch Watermark Processor")
                .font(.system(size: 18, weight: .medium, design: .default))
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 20)
    }
}

struct FormatControlsView: View {
    @EnvironmentObject var processor: AudioProcessor
    
    var body: some View {
        VStack(spacing: 15) {
            HStack {
                Picker("Output Format:", selection: $processor.settings.outputFormat) {
                    Text("MP3").tag(OutputFormat.mp3)
                    Text("WAV").tag(OutputFormat.wav)
                }
                
                Picker("Processing Mode:", selection: $processor.settings.processingMode) {
                    Text("All Combinations").tag(ProcessingMode.allCombinations)
                    Text("1:1 Pairing").tag(ProcessingMode.oneToOne)
                }
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Picker("Watermark Position:", selection: $processor.settings.watermarkPosition) {
                    Text("Start").tag(WatermarkPosition.start)
                    Text("End").tag(WatermarkPosition.end)
                    Text("Loop").tag(WatermarkPosition.loop)
                }
                .pickerStyle(.segmented)
                
                HStack {
                    Text("Initial Delay:")
                    TextField("Seconds", value: $processor.settings.initialDelay, format: .number)
                        .frame(width: 60)
                    Text("seconds")
                }
                
                if processor.settings.watermarkPosition == .loop {
                    HStack {
                        Text("Loop Interval:")
                        TextField("Seconds", value: $processor.settings.loopInterval, format: .number)
                            .frame(width: 60)
                        Text("seconds")
                    }
                }
            }
            
            HStack {
                Text("Watermark Volume:")
                Slider(value: $processor.settings.watermarkVolume, in: 0.1...1.0, step: 0.1)
                Text("\(Int(processor.settings.watermarkVolume * 100))%")
            }
        }
    }
}

struct FileSelectionView: View {
    let title: String
    @Binding var files: [URL]
    @State private var isDragging = false
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("\(title): \(files.count)")
                .font(.headline)
            
            HStack {
                Button("Add \(title)") { selectFiles() }
                Button("Clear") { files.removeAll() }
                if !files.isEmpty {
                    AudioPreviewPlayer(url: files.first)
                }
            }
            
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(files, id: \.self) { url in
                        Text(url.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .frame(height: 80)
            .overlay(
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isDragging ? Color.blue : Color.clear, lineWidth: 2)
                    
                    if files.isEmpty && !isDragging {
                        Text("Drag and drop \(title.lowercased()) here")
                            .foregroundColor(.secondary)
                    }
                }
            )
            .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers -> Bool
                var succeeded = false
                for provider in providers {
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                        guard let data = item as? Data,
                              let path = String(data: data, encoding: .utf8),
                              let url = URL(string: path),
                              url.startAccessingSecurityScopedResource() else {
                            return
                        }
                        
                        // Check if the file is an audio file
                        let fileExtension = url.pathExtension.lowercased()
                        let validExtensions = ["mp3", "m4a", "wav", "aiff", "aac"]
                        
                        if validExtensions.contains(fileExtension) {
                            DispatchQueue.main.async {
                                self.files.append(url)
                            }
                            succeeded = true
                        }
                        
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                return succeeded
            }
        }
        .padding(.horizontal)
    }
    
    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        
        var allowedTypes = [UTType.audio]
        let additionalTypes = ["mp3", "m4a", "wav", "aiff", "aac"].compactMap { UTType(filenameExtension: $0) }
        allowedTypes.append(contentsOf: additionalTypes)
        panel.allowedContentTypes = allowedTypes
        
        guard panel.runModal() == .OK else { return }
        files.append(contentsOf: panel.urls)
    }
}

struct OutputFolderView: View {
    @Binding var outputFolder: URL?
    
    var body: some View {
        HStack {
            Text("Output Folder:")
            Text(outputFolder?.lastPathComponent ?? "Not Selected")
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 200)
            
            Button("Choose...") { selectFolder() }
        }
    }
    
    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Select Output Folder"
        
        guard panel.runModal() == .OK else { return }
        outputFolder = panel.urls.first
    }
}

struct CustomProgressView: View {
    let progress: Double
    let currentFile: String
    let currentWatermark: String
    
    var body: some View {
        VStack(spacing: 8) {
            SwiftUI.ProgressView(value: progress, total: 100)
                .progressViewStyle(.linear)
                .frame(width: 400)
                .animation(.easeInOut, value: progress)
            
            HStack {
                Text("Processing: \(currentFile)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("+")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(currentWatermark)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 10)
    }
}

struct ProcessingControlsView: View {
    @EnvironmentObject var processor: AudioProcessor
    
    var body: some View {
        HStack {
            if processor.isProcessing {
                Button("Cancel", action: processor.cancelProcessing)
                    .foregroundColor(.red)
            } else {
                Button("Start Processing") { processor.startProcessing() }
                    .disabled(!canStartProcessing)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
    
    private var canStartProcessing: Bool {
        !processor.songURLs.isEmpty &&
        !processor.watermarkURLs.isEmpty &&
        processor.outputFolder != nil &&
        (processor.settings.processingMode == .allCombinations ||
         processor.songURLs.count == processor.watermarkURLs.count)
    }
}

struct AudioPreviewPlayer: NSViewRepresentable {
    var url: URL?
    
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            title: "Preview",
            target: context.coordinator,
            action: #selector(Coordinator.playPause)
        )
        button.bezelStyle = .rounded
        return button
    }
    
    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.url = url
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var player: AVAudioPlayer?
        var url: URL? {
            didSet {
                guard let url else { return }
                player = try? AVAudioPlayer(contentsOf: url)
            }
        }
        
        @objc func playPause() {
            guard let player else { return }
            if player.isPlaying {
                player.pause()
            } else {
                player.play()
            }
        }
    }
}

struct PresetManagementView: View {
    @EnvironmentObject var processor: AudioProcessor
    @State private var newPresetName = ""
    @State private var showingNameDialog = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Presets")
                    .font(.headline)
                
                Spacer()
                
                Button("Save Current") {
                    showingNameDialog = true
                }
                
                Button("Load") {
                    // This will be handled by the menu
                }
                .disabled(processor.presets.isEmpty)
                .popover(isPresented: $showingNameDialog) {
                    VStack(spacing: 15) {
                        Text("Save Current Settings as Preset")
                            .font(.headline)
                        
                        TextField("Preset Name", text: $newPresetName)
                            .frame(width: 250)
                        
                        HStack {
                            Button("Cancel") {
                                newPresetName = ""
                                showingNameDialog = false
                            }
                            
                            Button("Save") {
                                if !newPresetName.isEmpty {
                                    processor.saveCurrentSettingsAsPreset(name: newPresetName)
                                    newPresetName = ""
                                    showingNameDialog = false
                                }
                            }
                            .disabled(newPresetName.isEmpty)
                        }
                        .padding()
                    }
                    .padding()
                }
                
                Menu {
                    ForEach(processor.presets) { preset in
                        Button(preset.name) {
                            processor.applyPreset(preset)
                        }
                    }
                    
                    if !processor.presets.isEmpty {
                        Divider()
                        
                        Menu("Delete...") {
                            ForEach(processor.presets) { preset in
                                Button(preset.name) {
                                    processor.deletePreset(preset)
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "list.bullet")
                        .imageScale(.large)
                }
                .disabled(processor.presets.isEmpty)
            }
        }
        .padding(.horizontal)
    }
}
