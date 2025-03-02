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
