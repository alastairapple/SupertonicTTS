//
//  PreferencesView.swift
//  SupertonicTTS
    

import SwiftUI


struct PreferencesView: View {
    @Environment(ApplicationVM.self) private var vm
    private let cacheController = CacheController.shared
    
    @State private var showResetConfirmation: Bool = false
    @State private var showClearConfirmation: Bool = false
    
    @State private var rerenderID: UUID? = nil
    
    
    var body: some View {
        @Bindable var vm = vm

        NavigationStack {
            Form {
                Section("Synthesis") {
                    Picker("Language", selection: $vm.language) {
                        ForEach(Language.allCases, id: \.rawValue) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Flags") {
                    Toggle("Haptics", isOn: Preferences.$hapticsEnabled)
                    Toggle("Warmup Engine on Launch", isOn: Preferences.$warmupOnLaunch)
                    Toggle("Save Prompts on New Generation", isOn: Preferences.$savePromptsOnNewGeneration)
                    Toggle("Auto Play on New Generation", isOn: Preferences.$autoPlayOnNewGeneration)
                    Toggle("Auto Paste on Launch", isOn: Preferences.$autoPasteOnLaunch)
                }

                Section {
                    LabeledContent {
                        Text(cacheController.cacheSizeString).id(rerenderID)
                    } label: {
                        Button("Clear Cache") {
                            if cacheController.isCacheEmpty { return }
                            showClearConfirmation = true
                        }
                    }
                }
                
                Section("Links") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            Link(destination: githubLink) {
                                Label("GitHub Repo", systemImage: "")
                            }
                            
                            Link(destination: previewLink) {
                                Label("Product Page", systemImage: "")
                            }
                            
                            Link(destination: livePlaygroundLink) {
                                Label("Live Playground", systemImage: "")
                            }
                        }
                        .labelStyle(LinkLabelStyle())
                    }
                    .listRowInsets(.zero)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(Text("Preferences"))
            .navigationBarItems(trailing: resetButton)
            .confirmationDialog("", isPresented: $showResetConfirmation) {
                Button("Reset", role: .destructive, action: Preferences.resetToDefaults)
            }
            .confirmationDialog("", isPresented: $showClearConfirmation) {
                Button("Clear", role: .destructive) {
                    cacheController.clearCache()
                    rerenderID = UUID()
                }
            }
        }
    }
    
    private var resetButton: some View {
        Button("", systemImage: "arrow.clockwise") {
           showResetConfirmation = true
        }
    }
    
    
    private var githubLink: URL {
        URL(string: "https://github.com/supertone-inc/supertonic")!
    }
    
    private var previewLink: URL {
        URL(string: "https://huggingface.co/spaces/Supertone/supertonic")!
    }
    
    private var livePlaygroundLink: URL {
        URL(string: "https://huggingface.co/spaces/akhaliq/supertonic")!
    }
}


fileprivate struct LinkLabelStyle: LabelStyle {
    @Environment(\.colorScheme) private var scheme
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.title
                .foregroundStyle(Color.primary.gradient)
                .font(.subheadline.weight(.medium))
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.blue.gradient)
                .imageScale(.small)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .buttonStyle(.plain)
        .background(
            scheme == .light ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.primary.quinary),
            in: .capsule
        )
        .overlay(
            Capsule()
                .stroke(Color.secondary.opacity(0.15))
        )
    }
}
