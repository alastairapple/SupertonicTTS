//
//  Preferences.swift
//  SupertonicTTS
    

import SwiftUI


struct Preferences {
    @AppStorage("AutoPlayOnNewGeneration")
    static var autoPlayOnNewGeneration: Bool = true
    
    
    @AppStorage("WarmupOnLaunch")
    static var warmupOnLaunch: Bool = false
    
    
    @AppStorage("HapticsEnabled")
    static var hapticsEnabled: Bool = true
    
    
    @AppStorage("SavePromptsOnNewGeneration")
    static var savePromptsOnNewGeneration: Bool = true
    
    
    @AppStorage("AutoPasteOnLaunch")
    static var autoPasteOnLaunch: Bool = false
    
    
    static func resetToDefaults() {
        Preferences.autoPlayOnNewGeneration = true
        Preferences.warmupOnLaunch = false
        
        Preferences.hapticsEnabled = true
        Preferences.savePromptsOnNewGeneration = true
        Preferences.autoPasteOnLaunch = false
    }
}
