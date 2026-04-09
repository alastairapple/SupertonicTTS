//
//  Helpers.swift
//  SupertonicTTS


import Foundation
import Accelerate
import OnnxRuntimeBindings


fileprivate let AVAILABLE_LANGS = ["en"]


fileprivate func isValidLang(_ lang: String) -> Bool {
    AVAILABLE_LANGS.contains(lang)
}


func preprocessText(_ text: String, lang: String) -> String {
    var text = text.decomposedStringWithCompatibilityMapping

    text = text.unicodeScalars.filter { scalar in
        let value = scalar.value
        return !((value >= 0x1F600 && value <= 0x1F64F) ||
                 (value >= 0x1F300 && value <= 0x1F5FF) ||
                 (value >= 0x1F680 && value <= 0x1F6FF) ||
                 (value >= 0x1F700 && value <= 0x1F77F) ||
                 (value >= 0x1F780 && value <= 0x1F7FF) ||
                 (value >= 0x1F800 && value <= 0x1F8FF) ||
                 (value >= 0x1F900 && value <= 0x1F9FF) ||
                 (value >= 0x1FA00 && value <= 0x1FA6F) ||
                 (value >= 0x1FA70 && value <= 0x1FAFF) ||
                 (value >= 0x2600 && value <= 0x26FF) ||
                 (value >= 0x2700 && value <= 0x27BF) ||
                 (value >= 0x1F1E6 && value <= 0x1F1FF))
    }.map(String.init).joined()

    let replacements: [String: String] = [
        "–": "-",
        "‑": "-",
        "—": "-",
        "_": " ",
        "\u{201C}": "\"",
        "\u{201D}": "\"",
        "\u{2018}": "'",
        "\u{2019}": "'",
        "´": "'",
        "`": "'",
        "[": " ",
        "]": " ",
        "|": " ",
        "/": " ",
        "#": " ",
        "→": " ",
        "←": " ",
    ]

    for (old, new) in replacements {
        text = text.replacingOccurrences(of: old, with: new)
    }

    let specialSymbols = ["♥", "☆", "♡", "©", "\\"]
    for symbol in specialSymbols {
        text = text.replacingOccurrences(of: symbol, with: "")
    }

    let expressionReplacements: [String: String] = [
        "@": " at ",
        "e.g.,": "for example, ",
        "i.e.,": "that is, ",
    ]

    for (old, new) in expressionReplacements {
        text = text.replacingOccurrences(of: old, with: new)
    }

    text = text.replacingOccurrences(of: " ,", with: ",")
    text = text.replacingOccurrences(of: " .", with: ".")
    text = text.replacingOccurrences(of: " !", with: "!")
    text = text.replacingOccurrences(of: " ?", with: "?")
    text = text.replacingOccurrences(of: " ;", with: ";")
    text = text.replacingOccurrences(of: " :", with: ":")
    text = text.replacingOccurrences(of: " '", with: "'")

    while text.contains("\"\"") {
        text = text.replacingOccurrences(of: "\"\"", with: "\"")
    }
    while text.contains("''") {
        text = text.replacingOccurrences(of: "''", with: "'")
    }
    while text.contains("``") {
        text = text.replacingOccurrences(of: "``", with: "`")
    }

    let whitespacePattern = try! NSRegularExpression(pattern: "\\s+")
    let whitespaceRange = NSRange(text.startIndex..., in: text)
    text = whitespacePattern.stringByReplacingMatches(in: text, range: whitespaceRange, withTemplate: " ")
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)

    if !text.isEmpty {
        let punctPattern = try! NSRegularExpression(pattern: "[.!?;:,'\"\\u201C\\u201D\\u2018\\u2019)\\]}…。」』】〉》›»]$")
        let punctRange = NSRange(text.startIndex..., in: text)
        if punctPattern.firstMatch(in: text, range: punctRange) == nil {
            text += "."
        }
    }

    guard isValidLang(lang) else {
        fatalError("Invalid language: \(lang). Available: \(AVAILABLE_LANGS.joined(separator: ", "))")
    }

    return "<\(lang)>\(text)</\(lang)>"
}



// MARK: - Unicode Text Processor

class UnicodeProcessor {
    let indexer: [Int64]
    
    init(unicodeIndexerPath: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: unicodeIndexerPath))
        self.indexer = try JSONDecoder().decode([Int64].self, from: data)
    }
    
    func call(_ textList: [String], _ langList: [String]) -> (textIds: [[Int64]], textMask: [[[Float]]]) {
        var processedTexts = [String]()
        for (index, text) in textList.enumerated() {
            processedTexts.append(preprocessText(text, lang: langList[index]))
        }
        
        var textIdsLengths = [Int]()
        for text in processedTexts {
            textIdsLengths.append(text.unicodeScalars.count)
        }
        
        let maxLen = textIdsLengths.max() ?? 0
        
        var textIds = [[Int64]]()
        for text in processedTexts {
            var row = Array(repeating: Int64(0), count: maxLen)
            let unicodeValues = Array(text.unicodeScalars.map { Int($0.value) })
            for (j, val) in unicodeValues.enumerated() {
                if val < indexer.count {
                    row[j] = indexer[val]
                } else {
                    row[j] = -1
                }
            }
            textIds.append(row)
        }
        
        let textMask = getTextMask(textIdsLengths)
        return (textIds, textMask)
    }
    
    func getTextMask(_ textIdsLengths: [Int]) -> [[[Float]]] {
        let maxLen = textIdsLengths.max() ?? 0
        return lengthToMask(textIdsLengths, maxLen: maxLen)
    }
}


func lengthToMask(_ lengths: [Int], maxLen: Int? = nil) -> [[[Float]]] {
    let actualMaxLen = maxLen ?? (lengths.max() ?? 0)
    
    var mask = [[[Float]]]()
    for len in lengths {
        var row = Array(repeating: Float(0.0), count: actualMaxLen)
        for j in 0..<min(len, actualMaxLen) {
            row[j] = 1.0
        }
        mask.append([row])
    }
    return mask
}


func sampleNoisyLatent(duration: [Float], sampleRate: Int, baseChunkSize: Int, chunkCompress: Int, latentDim: Int) -> (noisyLatent: [[[Float]]], latentMask: [[[Float]]]) {
    let bsz = duration.count
    let maxDur = duration.max() ?? 0.0
    
    let wavLenMax = Int(maxDur * Float(sampleRate))
    var wavLengths = [Int]()
    for d in duration {
        wavLengths.append(Int(d * Float(sampleRate)))
    }
    
    let chunkSize = baseChunkSize * chunkCompress
    let latentLen = (wavLenMax + chunkSize - 1) / chunkSize
    let latentDimVal = latentDim * chunkCompress
    
    var noisyLatent = [[[Float]]]()
    for _ in 0..<bsz {
        var batch = [[Float]]()
        for _ in 0..<latentDimVal {
            var row = [Float]()
            for _ in 0..<latentLen {
                // Box-Muller transform
                let u1 = Float.random(in: 0.0001...1.0)
                let u2 = Float.random(in: 0.0...1.0)
                let val = sqrt(-2.0 * log(u1)) * cos(2.0 * Float.pi * u2)
                row.append(val)
            }
            batch.append(row)
        }
        noisyLatent.append(batch)
    }
    
    var latentLengths = [Int]()
    for len in wavLengths {
        latentLengths.append((len + chunkSize - 1) / chunkSize)
    }
    
    let latentMask = lengthToMask(latentLengths, maxLen: latentLen)
    
    // Apply mask
    for b in 0..<bsz {
        for d in 0..<latentDimVal {
            for t in 0..<latentLen {
                noisyLatent[b][d][t] *= latentMask[b][0][t]
            }
        }
    }
    
    return (noisyLatent, latentMask)
}




// MARK: - WAV File I/O
func writeWavFile(_ filename: String, _ audioData: [Float], _ sampleRate: Int) throws {
    let url = URL(fileURLWithPath: filename)
    
    // Convert float to int16
    let int16Data = audioData.map { sample -> Int16 in
        let clamped = max(-1.0, min(1.0, sample))
        return Int16(clamped * 32767.0)
    }
    
    // Create WAV header
    let numChannels: UInt16 = 1
    let bitsPerSample: UInt16 = 16
    let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample) / 8
    let blockAlign = numChannels * bitsPerSample / 8
    let dataSize = UInt32(int16Data.count * 2)
    
    var data = Data()
    
    // RIFF chunk
    data.append("RIFF".data(using: .ascii)!)
    withUnsafeBytes(of: UInt32(36 + dataSize).littleEndian) { data.append(contentsOf: $0) }
    data.append("WAVE".data(using: .ascii)!)
    
    // fmt chunk
    data.append("fmt ".data(using: .ascii)!)
    withUnsafeBytes(of: UInt32(16).littleEndian) { data.append(contentsOf: $0) }
    withUnsafeBytes(of: UInt16(1).littleEndian) { data.append(contentsOf: $0) } // PCM
    withUnsafeBytes(of: numChannels.littleEndian) { data.append(contentsOf: $0) }
    withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { data.append(contentsOf: $0) }
    withUnsafeBytes(of: byteRate.littleEndian) { data.append(contentsOf: $0) }
    withUnsafeBytes(of: blockAlign.littleEndian) { data.append(contentsOf: $0) }
    withUnsafeBytes(of: bitsPerSample.littleEndian) { data.append(contentsOf: $0) }
    
    // data chunk
    data.append("data".data(using: .ascii)!)
    withUnsafeBytes(of: dataSize.littleEndian) { data.append(contentsOf: $0) }
    
    // audio data
    int16Data.withUnsafeBytes { data.append(contentsOf: $0) }
    
    try data.write(to: url)
}




// MARK: - Component Loading Functions

func loadVoiceStyle(_ voiceStylePaths: [String], verbose: Bool) throws -> VoiceStyle {
    let bsz = voiceStylePaths.count
    
    // Read first file to get dimensions
    let firstData = try Data(contentsOf: URL(fileURLWithPath: voiceStylePaths[0]))
    let firstStyle = try JSONDecoder().decode(VoiceRawData.self, from: firstData)
    
    let ttlDims = firstStyle.style_ttl.dims
    let dpDims = firstStyle.style_dp.dims
    
    let ttlDim1 = ttlDims[1]
    let ttlDim2 = ttlDims[2]
    let dpDim1 = dpDims[1]
    let dpDim2 = dpDims[2]
    
    // Pre-allocate arrays with full batch size
    let ttlSize = bsz * ttlDim1 * ttlDim2
    let dpSize = bsz * dpDim1 * dpDim2
    var ttlFlat = [Float](repeating: 0.0, count: ttlSize)
    var dpFlat = [Float](repeating: 0.0, count: dpSize)
    
    // Fill in the data
    for (i, path) in voiceStylePaths.enumerated() {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let voiceStyle = try JSONDecoder().decode(VoiceRawData.self, from: data)
        
        // Flatten TTL data
        let ttlOffset = i * ttlDim1 * ttlDim2
        var idx = 0
        for batch in voiceStyle.style_ttl.data {
            for row in batch {
                for val in row {
                    ttlFlat[ttlOffset + idx] = val
                    idx += 1
                }
            }
        }
        
        // Flatten DP data
        let dpOffset = i * dpDim1 * dpDim2
        idx = 0
        for batch in voiceStyle.style_dp.data {
            for row in batch {
                for val in row {
                    dpFlat[dpOffset + idx] = val
                    idx += 1
                }
            }
        }
    }
    
    let ttlShape: [NSNumber] = [NSNumber(value: bsz), NSNumber(value: ttlDim1), NSNumber(value: ttlDim2)]
    let dpShape: [NSNumber] = [NSNumber(value: bsz), NSNumber(value: dpDim1), NSNumber(value: dpDim2)]
    
    let ttlValue = try ORTValue(tensorData: NSMutableData(bytes: &ttlFlat, length: ttlFlat.count * MemoryLayout<Float>.size),
                                elementType: .float,
                                shape: ttlShape)
    let dpValue = try ORTValue(tensorData: NSMutableData(bytes: &dpFlat, length: dpFlat.count * MemoryLayout<Float>.size),
                               elementType: .float,
                               shape: dpShape)
    
    if verbose {
        print("Loaded \(bsz) voice styles\n")
    }
    
    return VoiceStyle(ttl: ttlValue, dp: dpValue)
}


func loadSynthesizer(_ onnxDir: String, _ useGpu: Bool, _ env: ORTEnv) throws -> SupertonicSynthesizerEngine {
    if useGpu {
        throw NSError(domain: "TTS", code: 1, userInfo: [NSLocalizedDescriptionKey: "GPU mode is not supported yet"])
    }
    print("Using CPU for inference\n")
    
    let cfgs = try loadCfgs(onnxDir)
    let modelDirURL = resolveModelDirectory(from: onnxDir)
    
    let sessionOptions = try ORTSessionOptions()
    
    let dpPath = modelDirURL.appendingPathComponent("duration_predictor.onnx").path
    let textEncPath = modelDirURL.appendingPathComponent("text_encoder.onnx").path
    let vectorEstPath = modelDirURL.appendingPathComponent("vector_estimator.onnx").path
    let vocoderPath = modelDirURL.appendingPathComponent("vocoder.onnx").path
    
    let dpOrt = try ORTSession(env: env, modelPath: dpPath, sessionOptions: sessionOptions)
    let textEncOrt = try ORTSession(env: env, modelPath: textEncPath, sessionOptions: sessionOptions)
    let vectorEstOrt = try ORTSession(env: env, modelPath: vectorEstPath, sessionOptions: sessionOptions)
    let vocoderOrt = try ORTSession(env: env, modelPath: vocoderPath, sessionOptions: sessionOptions)
    
    let unicodeIndexerPath = "\(onnxDir)/unicode_indexer.json"
    let textProcessor = try UnicodeProcessor(unicodeIndexerPath: unicodeIndexerPath)
    
    return SupertonicSynthesizerEngine(cfgs: cfgs, textProcessor: textProcessor,
                       dpOrt: dpOrt, textEncOrt: textEncOrt,
                       vectorEstOrt: vectorEstOrt, vocoderOrt: vocoderOrt)
}


func loadCfgs(_ onnxDir: String) throws -> EngineConfig {
    let cfgPath = "\(onnxDir)/tts.json"
    let data = try Data(contentsOf: URL(fileURLWithPath: cfgPath))
    return try JSONDecoder().decode(EngineConfig.self, from: data)
}


private func resolveModelDirectory(from baseDir: String) -> URL {
    let baseURL = URL(fileURLWithPath: baseDir, isDirectory: true)
    let nestedOnnxURL = baseURL.appendingPathComponent("onnx", isDirectory: true)

    if FileManager.default.fileExists(atPath: nestedOnnxURL.appendingPathComponent("duration_predictor.onnx").path) {
        return nestedOnnxURL
    }

    return baseURL
}
