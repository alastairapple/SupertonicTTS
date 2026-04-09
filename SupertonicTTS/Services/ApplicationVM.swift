//
//  TTSViewModel.swift
//  SupertonicTTS


import SwiftUI
import Observation



@MainActor
@Observable
final class ApplicationVM {
    var userText: String = "This morning, I took a walk in the park, and the sound of the birds and the breeze was so pleasant that I stopped for a long time just to listen."
    var userTextIsEmpty: Bool { userText.isEmpty }
    var totalWords: Int { userText.split(separator: " ").count }
    
    
    var voice: Voice = .engMale
    var language: Language = .en
    var steps: Double = 10
    var speed: Float = 1.05
    var silenceDuration: Float = 0.3
    
    
    var isGenerating: Bool = false
    var isPlaying: Bool = false
    var errorMessage: String?
    var results: SynthesisResult?
    
    var isEngineLoaded: Bool = false
    var shakeTrigger: CGFloat = 0
    
    
    @ObservationIgnored private var service: TTSService!
    @ObservationIgnored private var player = TTSAudioPlayer()


    func run() async {
        do {
            service = try await lightweightWarmup()
            
            withAnimation {
                isEngineLoaded = true
            }
        } catch {
            errorMessage = "Failed to init TTS: \(error.localizedDescription)"
        }
    }

    
    func generate() {
        guard isAllowedToGenerate else {
            Haptics.impact(style: .medium)
            withAnimation {
                shakeTrigger += 1
            }
            return
        }
        
        isGenerating = true
        errorMessage = nil
        
        if Preferences.savePromptsOnNewGeneration {
            let prompt = Prompt(text: self.userText, date: .now)
            PromptStorage.shared.storePrompt(prompt)
        }
        
        Task {
            do {
                let request = SynthesisRequest(
                    text: userText,
                    language: language,
                    voice: voice,
                    steps: Int(steps),
                    speed: speed,
                    silenceDuration: silenceDuration
                )

                let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                let writeLocation = cachesDirectory.appendingPathComponent(
                    "SuperTonic_\(UUID().uuidString.prefix(12)).wav"
                )
                
                let result = try await service.synthesize(request, writeTo: writeLocation)
                

                self.isGenerating = false
                self.results = result
                
                if Preferences.autoPlayOnNewGeneration {
                    self.play(url: result.url)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isGenerating = false
                }
            }
        }
    }
    
    func clearPrompt() {
        Haptics.impact(style: .rigid)
        withAnimation {
            self.userText = ""
        }
    }
    
    func togglePlay() {
        if isPlaying {
            player.stop()
            isPlaying = false
        } else if let results {
            play(url: results.url)
        }
    }

    private func play(url: URL) {
        player.play(url: url) { [weak self] in
            DispatchQueue.main.async { self?.isPlaying = false }
        }
        isPlaying = true
    }
    
    
    var isAllowedToGenerate: Bool {
        return userText.isEmpty == false && service != nil && isGenerating == false
    }
    
    
    func pasteFromClipboard() {
        guard let text = UIPasteboard.general.string else { return }
        self.userText = text
    }
}

// the warmup function should run on a background thread to let the UI efficiently load
fileprivate nonisolated func lightweightWarmup() async throws -> TTSService {
    try await Task.detached {
        let service = try TTSService()
        await service.warmup()
        return service
    }.value
}
