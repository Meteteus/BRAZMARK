//
//  AppTheme.swift
//  BRAZMARK
//
//  Created by Matheus Braz on 3/1/25.
//


import SwiftUI

/// Represents the app theme and appearance settings
enum AppTheme: String, CaseIterable, Codable, Identifiable {
    case system
    case light
    case dark
    case sepia
    case ocean
    case forest
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .system: return "System Default"
        case .light: return "Light"
        case .dark: return "Dark"
        case .sepia: return "Sepia"
        case .ocean: return "Ocean Blue"
        case .forest: return "Forest Green"
        }
    }

    var accentColor: Color {
        switch self {
        case .system, .light, .dark: return Color.blue
        case .sepia: return Color(red: 0.8, green: 0.4, blue: 0.1)
        case .ocean: return Color(red: 0.0, green: 0.5, blue: 0.8)
        case .forest: return Color(red: 0.2, green: 0.6, blue: 0.3)
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .system:
            return Color(.windowBackgroundColor)
        case .light:
            return Color(white: 0.98)
        case .dark:
            return Color(white: 0.15)
        case .sepia:
            return Color(red: 0.98, green: 0.95, blue: 0.9)
        case .ocean:
            return Color(red: 0.95, green: 0.98, blue: 1.0)
        case .forest:
            return Color(red: 0.95, green: 0.98, blue: 0.95)
        }
    }
    
    var textColor: Color {
        switch self {
        case .system:
            return Color(.labelColor)
        case .light, .sepia, .ocean, .forest:
            return Color.black
        case .dark:
            return Color.white
        }
    }
    
    var secondaryTextColor: Color {
        switch self {
        case .system:
            return Color(.secondaryLabelColor)
        case .light, .sepia, .ocean, .forest:
            return Color.gray
        case .dark:
            return Color(white: 0.7)
        }
    }
    
    var borderColor: Color {
        switch self {
        case .system:
            return Color(.separatorColor)
        case .light:
            return Color(white: 0.8)
        case .dark:
            return Color(white: 0.3)
        case .sepia:
            return Color(red: 0.8, green: 0.7, blue: 0.6)
        case .ocean:
            return Color(red: 0.7, green: 0.8, blue: 0.9)
        case .forest:
            return Color(red: 0.7, green: 0.8, blue: 0.7)
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil // Follow system
        case .light, .sepia, .ocean, .forest:
            return .light
        case .dark:
            return .dark
        }
    }
    
    /// Apply this theme to the app interface
    func apply() {
        // We need to defer setting the appearance until the app has fully launched
        // Store the setting in UserDefaults immediately
        UserDefaults.standard.set(self.rawValue, forKey: "AppTheme")
        
        // Use DispatchQueue.main.async to defer setting the appearance until after initialization
        DispatchQueue.main.async {
            NSApplication.shared.appearance = self.nsAppearance
        }
        
        // Store selected theme in UserDefaults
        UserDefaults.standard.set(self.rawValue, forKey: "AppTheme")
    }
    
    private var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            return nil // Follow system
        case .light, .sepia, .ocean, .forest:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }
    
    /// Load the saved theme from UserDefaults
    static func loadSavedTheme() -> AppTheme {
        if let themeName = UserDefaults.standard.string(forKey: "AppTheme"),
           let theme = AppTheme(rawValue: themeName) {
            return theme
        }
        return .system
    }
}
