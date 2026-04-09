//
//  TTSService.swift
//  SupertonicTTS


import Foundation
import OnnxRuntimeBindings


final class TTSService {
    private let env: ORTEnv
    private let synthesizer: SupertonicSynthesizerEngine
    
    private let bundleOnnxDir: String
    private let sampleRate: Int
    
    // Cached style per voice (precomputed at startup or on first use)
    private var cachedStyle: [Voice: VoiceStyle] = [:]
    
    init() throws {
        bundleOnnxDir = try Self.locateOnnxDirInBundle()
        env = try ORTEnv(loggingLevel: .warning)
        synthesizer = try loadSynthesizer(bundleOnnxDir, false, env)
        sampleRate = synthesizer.sampleRate
    }
    
    /// Pre-Compute styles and run a quick generation to warm models
    func warmup() async {
        do {
            try precomputeStyle(for: .engMale)
            try precomputeStyle(for: .engFemale)
            
            // Run a tiny synthesis to JIT/warm up kernels; discard file
            let req = SynthesisRequest(text: "Warm up", language: .en, voice: .engMale, steps: 1, speed: 1.0, silenceDuration: 0.01)
            let res = try await synthesize(req)
            try FileManager.default.removeItem(at: res.url)
        } catch {
            print("Warmup synth error: \(error)")
        }
    }
    
    func synthesize(_ request: SynthesisRequest, writeTo fileURL: URL? = nil) async throws -> SynthesisResult {
        let tic = Date()
        
        // 1) Get or compute style for the selected voice
        let style = try getStyle(voice: request.voice)
        
        // 2) Synthesize via packed TextToSpeech component
        let (wav, duration) = try synthesizer.call(request.text, request.language.rawValue, style, request.steps, speed: request.speed, silenceDuration: request.silenceDuration)
        
        let audioSeconds = Double(duration)
        let wavLenSample = min(Int(Double(sampleRate) * audioSeconds), wav.count)
        let wavOut = Array(wav[0..<wavLenSample])
        
        let tmpURL = fileURL ?? FileManager.default.temporaryDirectory.appendingPathComponent("supertonic_tts_\(UUID().uuidString).wav")
        try writeWavFile(tmpURL.path, wavOut, sampleRate)
        
        let elapsed = Date().timeIntervalSince(tic)
        return SynthesisResult(url: tmpURL, elapsedSeconds: elapsed, audioSeconds: audioSeconds)
    }
    
    
    private func precomputeStyle(for voice: Voice) throws {
        if cachedStyle[voice] != nil { return }
        let styleURL = try Self.locateVoiceStyleURL(voice: voice)
        let style = try loadVoiceStyle([styleURL.path], verbose: false)
        
        cachedStyle[voice] = style
    }
    
    
    private func getStyle(voice: Voice) throws -> VoiceStyle {
        if let style = cachedStyle[voice] { return style }
        try precomputeStyle(for: voice)
        return cachedStyle[voice]!
    }
}

extension TTSService {
    private static func locateOnnxDirInBundle() throws -> String {
        let bundle = Bundle.main

        var candidates: [URL] = []
        if let url = bundle.url(forResource: "tts", withExtension: "json", subdirectory: nil) { candidates.append(url.deletingLastPathComponent()) }
        if let dir = bundle.resourceURL?.appendingPathComponent("Resources", isDirectory: true) { candidates.append(dir) }
        if let root = bundle.resourceURL { candidates.append(root) }

        for dir in candidates {
            if dirHasRequiredFiles(dir) { return dir.path }
        }
        throw NSError(
            domain: "TTS",
            code: -100,
            userInfo: [NSLocalizedDescriptionKey: "Could not find the onnx directory in the bundle. Please make sure the onnx folder (as a folder reference) is included in Copy Bundle Resources in Xcode."]
        )
    }
    
    private static func dirHasRequiredFiles(_ dir: URL) -> Bool {
        let fileManager = FileManager.default
        let configFiles = ["tts.json", "unicode_indexer.json"]
        let flatOnnxFiles = [
            "duration_predictor.onnx",
            "text_encoder.onnx",
            "text_encoder.onnx.1",
            "vector_estimator.onnx",
            "vocoder.onnx",
        ]
        let nestedOnnxDir = dir.appendingPathComponent("onnx", isDirectory: true)

        let hasConfigFiles = configFiles.allSatisfy {
            fileManager.fileExists(atPath: dir.appendingPathComponent($0).path)
        }
        let hasFlatOnnxFiles = flatOnnxFiles.allSatisfy {
            fileManager.fileExists(atPath: dir.appendingPathComponent($0).path)
        }
        let hasNestedOnnxFiles = flatOnnxFiles.allSatisfy {
            fileManager.fileExists(atPath: nestedOnnxDir.appendingPathComponent($0).path)
        }

        return hasConfigFiles && (hasFlatOnnxFiles || hasNestedOnnxFiles)
    }

    private static func locateVoiceStyleURL(voice: Voice) throws -> URL {
        let fileName = voice.identifier
        let bundle = Bundle.main
        let candidates: [URL?] = [
            bundle.url(forResource: fileName, withExtension: "json", subdirectory: "Resources/voice_styles"),
            bundle.url(forResource: fileName, withExtension: "json", subdirectory: "voice_styles"),
            bundle.url(forResource: fileName, withExtension: "json", subdirectory: "assets/voice_styles"),
            bundle.url(forResource: fileName, withExtension: "json", subdirectory: nil)
        ]
        for url in candidates {
            if let url = url { return url }
        }
        // Fallback: scan folders if needed
        if let folder1 = bundle.resourceURL?.appendingPathComponent("voice_styles", isDirectory: true) {
            let file = folder1.appendingPathComponent("\(fileName).json")
            if FileManager.default.fileExists(atPath: file.path) { return file }
        }
        if let folderResources = bundle.resourceURL?.appendingPathComponent("Resources/voice_styles", isDirectory: true) {
            let file = folderResources.appendingPathComponent("\(fileName).json")
            if FileManager.default.fileExists(atPath: file.path) { return file }
        }
        if let folder2 = bundle.resourceURL?.appendingPathComponent("assets/voice_styles", isDirectory: true) {
            let file = folder2.appendingPathComponent("\(fileName).json")
            if FileManager.default.fileExists(atPath: file.path) { return file }
        }
        throw NSError(
            domain: "TTS",
            code: -102,
            userInfo: [NSLocalizedDescriptionKey: "Could not find the voice style JSON (\(fileName).json) in the bundle. Ensure voice_styles folder is included in Copy Bundle Resources."]
        )
    }
}
