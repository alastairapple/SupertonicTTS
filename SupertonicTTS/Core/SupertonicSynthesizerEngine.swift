//
//  TextToSpeech.swift
//  SupertonicTTS
    

import Foundation
import Accelerate
import OnnxRuntimeBindings



fileprivate let MAX_CHUNK_LENGTH = 300
fileprivate let ABBREVIATIONS = [
    "Dr.", "Mr.", "Mrs.", "Ms.", "Prof.", "Sr.", "Jr.",
    "St.", "Ave.", "Rd.", "Blvd.", "Dept.", "Inc.", "Ltd.",
    "Co.", "Corp.", "etc.", "vs.", "i.e.", "e.g.", "Ph.D."
]


class SupertonicSynthesizerEngine {
    let cfgs: EngineConfig
    let textProcessor: UnicodeProcessor
    let dpOrt: ORTSession
    let textEncOrt: ORTSession
    let vectorEstOrt: ORTSession
    let vocoderOrt: ORTSession
    let sampleRate: Int
    
    init(cfgs: EngineConfig, textProcessor: UnicodeProcessor,
         dpOrt: ORTSession, textEncOrt: ORTSession,
         vectorEstOrt: ORTSession, vocoderOrt: ORTSession) {
        self.cfgs = cfgs
        self.textProcessor = textProcessor
        self.dpOrt = dpOrt
        self.textEncOrt = textEncOrt
        self.vectorEstOrt = vectorEstOrt
        self.vocoderOrt = vocoderOrt
        self.sampleRate = cfgs.ae.sample_rate
    }
    
    
    func call(_ text: String, _ lang: String, _ style: VoiceStyle, _ totalStep: Int, speed: Float, silenceDuration: Float) throws -> (wav: [Float], duration: Float) {
        let maxLen = lang == "ko" ? 120 : MAX_CHUNK_LENGTH
        let chunks = chunkText(text, maxLen: maxLen)
        
        var wavCat = [Float]()
        var durCat: Float = 0.0
        
        for (i, chunk) in chunks.enumerated() {
            let result = try _infer([chunk], [lang], style, totalStep, speed: speed)
            
            let dur = result.duration[0]
            let wavLen = Int(Float(sampleRate) * dur)
            let wavChunk = Array(result.wav.prefix(wavLen))
            
            if i == 0 {
                wavCat = wavChunk
                durCat = dur
            } else {
                let silenceLen = Int(silenceDuration * Float(sampleRate))
                let silence = [Float](repeating: 0.0, count: silenceLen)
                
                wavCat.append(contentsOf: silence)
                wavCat.append(contentsOf: wavChunk)
                durCat += silenceDuration + dur
            }
        }
        
        return (wavCat, durCat)
    }

    
    
    private func _infer(_ textList: [String], _ langList: [String], _ style: VoiceStyle, _ totalStep: Int, speed: Float) throws -> (wav: [Float], duration: [Float]) {
        let bsz = textList.count
        
        // Process text
        let (textIds, textMask) = textProcessor.call(textList, langList)
        
        // Flatten text IDs
        let textIdsFlat = textIds.flatMap { $0 }
        let textIdsShape: [NSNumber] = [NSNumber(value: bsz), NSNumber(value: textIds[0].count)]
        let textIdsValue = try ORTValue(tensorData: NSMutableData(bytes: textIdsFlat, length: textIdsFlat.count * MemoryLayout<Int64>.size),
                                        elementType: .int64,
                                        shape: textIdsShape)
        
        // Flatten text mask
        let textMaskFlat = textMask.flatMap { $0.flatMap { $0 } }
        let textMaskShape: [NSNumber] = [NSNumber(value: bsz), 1, NSNumber(value: textMask[0][0].count)]
        let textMaskValue = try ORTValue(tensorData: NSMutableData(bytes: textMaskFlat, length: textMaskFlat.count * MemoryLayout<Float>.size),
                                         elementType: .float,
                                         shape: textMaskShape)
        
        // Predict duration
        let dpOutputs = try dpOrt.run(withInputs: ["text_ids": textIdsValue, "style_dp": style.dp, "text_mask": textMaskValue],
                                      outputNames: ["duration"],
                                      runOptions: nil)
        
        let durationData = try dpOutputs["duration"]!.tensorData() as Data
        var duration = durationData.withUnsafeBytes { ptr in
            Array(ptr.bindMemory(to: Float.self))
        }
        
        // Apply speed factor to duration
        for i in 0..<duration.count {
            duration[i] /= speed
        }
        
        // Encode text
        let textEncOutputs = try textEncOrt.run(withInputs: ["text_ids": textIdsValue, "style_ttl": style.ttl, "text_mask": textMaskValue],
                                                outputNames: ["text_emb"],
                                                runOptions: nil)
        
        let textEmbValue = textEncOutputs["text_emb"]!
        
        // Sample noisy latent
        var (xt, latentMask) = sampleNoisyLatent(duration: duration, sampleRate: sampleRate,
                                                 baseChunkSize: cfgs.ae.base_chunk_size,
                                                 chunkCompress: cfgs.ttl.chunk_compress_factor,
                                                 latentDim: cfgs.ttl.latent_dim)
        
        // Prepare constant arrays
        let totalStepArray = Array(repeating: Float(totalStep), count: bsz)
        let totalStepValue = try ORTValue(tensorData: NSMutableData(bytes: totalStepArray, length: totalStepArray.count * MemoryLayout<Float>.size),
                                          elementType: .float,
                                          shape: [NSNumber(value: bsz)])
        
        // Denoising loop
        for step in 0..<totalStep {
            let currentStepArray = Array(repeating: Float(step), count: bsz)
            let currentStepValue = try ORTValue(tensorData: NSMutableData(bytes: currentStepArray, length: currentStepArray.count * MemoryLayout<Float>.size),
                                                elementType: .float,
                                                shape: [NSNumber(value: bsz)])
            
            // Flatten xt
            let xtFlat = xt.flatMap { $0.flatMap { $0 } }
            let xtShape: [NSNumber] = [NSNumber(value: bsz), NSNumber(value: xt[0].count), NSNumber(value: xt[0][0].count)]
            let xtValue = try ORTValue(tensorData: NSMutableData(bytes: xtFlat, length: xtFlat.count * MemoryLayout<Float>.size),
                                       elementType: .float,
                                       shape: xtShape)
            
            // Flatten latent mask
            let latentMaskFlat = latentMask.flatMap { $0.flatMap { $0 } }
            let latentMaskShape: [NSNumber] = [NSNumber(value: bsz), 1, NSNumber(value: latentMask[0][0].count)]
            let latentMaskValue = try ORTValue(tensorData: NSMutableData(bytes: latentMaskFlat, length: latentMaskFlat.count * MemoryLayout<Float>.size),
                                               elementType: .float,
                                               shape: latentMaskShape)
            
            let vectorEstOutputs = try vectorEstOrt.run(withInputs: [
                "noisy_latent": xtValue,
                "text_emb": textEmbValue,
                "style_ttl": style.ttl,
                "latent_mask": latentMaskValue,
                "text_mask": textMaskValue,
                "current_step": currentStepValue,
                "total_step": totalStepValue
            ], outputNames: ["denoised_latent"], runOptions: nil)
            
            let denoisedData = try vectorEstOutputs["denoised_latent"]!.tensorData() as Data
            let denoisedFlat = denoisedData.withUnsafeBytes { ptr in
                Array(ptr.bindMemory(to: Float.self))
            }
            
            // Reshape to 3D
            let latentDimVal = xt[0].count
            let latentLen = xt[0][0].count
            xt = []
            var idx = 0
            for _ in 0..<bsz {
                var batch = [[Float]]()
                for _ in 0..<latentDimVal {
                    var row = [Float]()
                    for _ in 0..<latentLen {
                        row.append(denoisedFlat[idx])
                        idx += 1
                    }
                    batch.append(row)
                }
                xt.append(batch)
            }
        }
        
        // Generate waveform
        let finalXtFlat = xt.flatMap { $0.flatMap { $0 } }
        let finalXtShape: [NSNumber] = [NSNumber(value: bsz), NSNumber(value: xt[0].count), NSNumber(value: xt[0][0].count)]
        let finalXtValue = try ORTValue(tensorData: NSMutableData(bytes: finalXtFlat, length: finalXtFlat.count * MemoryLayout<Float>.size),
                                        elementType: .float,
                                        shape: finalXtShape)
        
        let vocoderOutputs = try vocoderOrt.run(withInputs: ["latent": finalXtValue],
                                                outputNames: ["wav_tts"],
                                                runOptions: nil)
        
        let wavData = try vocoderOutputs["wav_tts"]!.tensorData() as Data
        let wav = wavData.withUnsafeBytes { ptr in
            Array(ptr.bindMemory(to: Float.self))
        }
        
        return (wav, duration)
    }

    
    
    private func chunkText(_ text: String, maxLen: Int = 0) -> [String] {
        let actualMaxLen = maxLen > 0 ? maxLen : MAX_CHUNK_LENGTH
        let trimmedText = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        if trimmedText.isEmpty {
            return [""]
        }
        
        // Split by paragraphs using regex
        let paraPattern = try! NSRegularExpression(pattern: "\\n\\s*\\n")
        let paraRange = NSRange(trimmedText.startIndex..., in: trimmedText)
        var paragraphs = [String]()
        var lastEnd = trimmedText.startIndex
        
        paraPattern.enumerateMatches(in: trimmedText, range: paraRange) { match, _, _ in
            if let match = match, let range = Range(match.range, in: trimmedText) {
                paragraphs.append(String(trimmedText[lastEnd..<range.lowerBound]))
                lastEnd = range.upperBound
            }
        }
        if lastEnd < trimmedText.endIndex {
            paragraphs.append(String(trimmedText[lastEnd...]))
        }
        if paragraphs.isEmpty {
            paragraphs = [trimmedText]
        }
        
        var chunks = [String]()
        
        for para in paragraphs {
            let trimmedPara = para.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if trimmedPara.isEmpty {
                continue
            }
            
            if trimmedPara.count <= actualMaxLen {
                chunks.append(trimmedPara)
                continue
            }
            
            // Split by sentences
            let sentences = splitSentences(trimmedPara)
            var current = ""
            var currentLen = 0
            
            for sentence in sentences {
                let trimmedSentence = sentence.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if trimmedSentence.isEmpty {
                    continue
                }
                
                let sentenceLen = trimmedSentence.count
                if sentenceLen > actualMaxLen {
                    // If sentence is longer than maxLen, split by comma or space
                    if !current.isEmpty {
                        chunks.append(current.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))
                        current = ""
                        currentLen = 0
                    }
                    
                    // Try splitting by comma
                    let parts = trimmedSentence.components(separatedBy: ",")
                    for part in parts {
                        let trimmedPart = part.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                        if trimmedPart.isEmpty {
                            continue
                        }
                        
                        let partLen = trimmedPart.count
                        if partLen > actualMaxLen {
                            // Split by space as last resort
                            let words = trimmedPart.components(separatedBy: CharacterSet.whitespaces).filter { !$0.isEmpty }
                            var wordChunk = ""
                            var wordChunkLen = 0
                            
                            for word in words {
                                let wordLen = word.count
                                if wordChunkLen + wordLen + 1 > actualMaxLen && !wordChunk.isEmpty {
                                    chunks.append(wordChunk.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))
                                    wordChunk = ""
                                    wordChunkLen = 0
                                }
                                
                                if !wordChunk.isEmpty {
                                    wordChunk += " "
                                    wordChunkLen += 1
                                }
                                wordChunk += word
                                wordChunkLen += wordLen
                            }
                            
                            if !wordChunk.isEmpty {
                                chunks.append(wordChunk.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))
                            }
                        } else {
                            if currentLen + partLen + 1 > actualMaxLen && !current.isEmpty {
                                chunks.append(current.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))
                                current = ""
                                currentLen = 0
                            }
                            
                            if !current.isEmpty {
                                current += ", "
                                currentLen += 2
                            }
                            current += trimmedPart
                            currentLen += partLen
                        }
                    }
                    continue
                }
                
                if currentLen + sentenceLen + 1 > actualMaxLen && !current.isEmpty {
                    chunks.append(current.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))
                    current = ""
                    currentLen = 0
                }
                
                if !current.isEmpty {
                    current += " "
                    currentLen += 1
                }
                current += trimmedSentence
                currentLen += sentenceLen
            }
            
            if !current.isEmpty {
                chunks.append(current.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))
            }
        }
        
        return chunks.isEmpty ? [""] : chunks
    }

    
    
    private func splitSentences(_ text: String) -> [String] {
        // Swift's regex doesn't support lookbehind reliably, so we use a simpler approach
        // Split on sentence boundaries and then check if they're abbreviations
        let regex = try! NSRegularExpression(pattern: "([.!?])\\s+")
        let range = NSRange(text.startIndex..., in: text)
        
        // Find all matches
        let matches = regex.matches(in: text, range: range)
        if matches.isEmpty {
            return [text]
        }
        
        var sentences = [String]()
        var lastEnd = text.startIndex
        
        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }
            
            // Get the text before the punctuation
            let beforePunc = String(text[lastEnd..<matchRange.lowerBound])
            
            // Get the punctuation character
            let puncRange = Range(NSRange(location: match.range.location, length: 1), in: text)!
            let punc = String(text[puncRange])
            
            // Check if this ends with an abbreviation
            var isAbbrev = false
            let combined = beforePunc.trimmingCharacters(in: CharacterSet.whitespaces) + punc
            for abbrev in ABBREVIATIONS {
                if combined.hasSuffix(abbrev) {
                    isAbbrev = true
                    break
                }
            }
            
            if !isAbbrev {
                // This is a real sentence boundary
                sentences.append(String(text[lastEnd..<matchRange.upperBound]))
                lastEnd = matchRange.upperBound
            }
        }
        
        // Add the remaining text
        if lastEnd < text.endIndex {
            sentences.append(String(text[lastEnd...]))
        }
        
        return sentences.isEmpty ? [text] : sentences
    }
}
