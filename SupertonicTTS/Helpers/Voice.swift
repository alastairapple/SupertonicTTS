//
//  Voice.swift
//  SupertonicTTS
    

import Foundation
import OnnxRuntimeBindings


enum Language: String, CaseIterable {
    case en = "en"

    var displayName: String {
        switch self {
        case .en:
            return "English"
        }
    }
}


enum Voice {
    case engMale
    case engFemale
    case britMale
    case britFemale
    case male3
    case male4
    case male5
    case female3
    case female4
    case female5
    
    var displayName: String {
        switch self {
        case .engMale: return "Tim"
        case .britMale: return "Charlie"
        case .male3: return "M3"
        case .male4: return "M4"
        case .male5: return "M5"
            
        case .engFemale: return "Ellen"
        case .britFemale: return "Tina"
        case .female3: return "F3"
        case .female4: return "F4"
        case .female5: return "F5"
        }
    }
    
    var localizedAccent: String {
        switch self {
        case .engMale, .engFemale, .male3, .male4, .male5, .female3, .female4, .female5:
            return "American"
        case .britMale, .britFemale:
            return "British"
        }
    }
    
    var gender: String {
        switch self {
        case .engMale, .britMale, .male3, .male4, .male5:
            return "Male"
        case .engFemale, .britFemale, .female3, .female4, .female5:
            return "Female"
        }
    }
    
    var identifier: String {
        switch self {
        case .engMale: return "M1"
        case .britMale: return "M2"
        case .male3: return "M3"
        case .male4: return "M4"
        case .male5: return "M5"
            
        case .engFemale: return "F1"
        case .britFemale: return "F2"
        case .female3: return "F3"
        case .female4: return "F4"
        case .female5: return "F5"
        }
    }
}

enum VoiceAccent: String {
    case american = "American"
    case british = "British"
}

struct VoiceStyle {
    let ttl: ORTValue
    let dp: ORTValue
}

struct VoiceRawData: Codable {
    let style_ttl: StyleComponent
    let style_dp: StyleComponent
    
    struct StyleComponent: Codable {
        let data: [[[Float]]]
        let dims: [Int]
        let type: String
    }
}
