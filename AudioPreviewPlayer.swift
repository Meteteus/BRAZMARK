//
//  AudioPreviewPlayer.swift
//  BRAZMARK
//
//  Created by Matheus Braz on 3/1/25.
//


import SwiftUI
import AVFoundation

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
