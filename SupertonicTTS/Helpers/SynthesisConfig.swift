//
//  SynthesisConfig.swift
//  SupertonicTTS
    

import Foundation


struct EngineConfig: Codable {
    let ae: AEConfig
    let ttl: TTLConfig
    
    struct AEConfig: Codable {
        let sample_rate: Int
        let base_chunk_size: Int
    }
    
    struct TTLConfig: Codable {
        let chunk_compress_factor: Int
        let latent_dim: Int
    }
}


struct SynthesisRequest {
    let text: String
    let language: Language
    let voice: Voice
    let steps: Int
    let speed: Float
    let silenceDuration: Float
}


struct SynthesisResult {
    let url: URL
    let elapsedSeconds: Double
    let audioSeconds: Double
    var rtf: Double { elapsedSeconds / max(audioSeconds, 1e-6) }
    
    static var mock: SynthesisResult {
        .init(
            url: URL(fileURLWithPath: "/Library/Audio/SystemSounds/1007.caf"),
            elapsedSeconds: 0.1,
            audioSeconds: 0.4
        )
    }
}
