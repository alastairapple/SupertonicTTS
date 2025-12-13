//
//  ContentView.swift
//  SupertonicTTS


import SwiftUI
import CompactSlider



struct ContentView: View {
    @State private var vm = ApplicationVM()
    private var kdObserver = KeyboardObserver()
    
    @State private var showPerformanceHud = false
    @State private var isEngineLoading: Bool = false
    @State private var selectedAccent: VoiceAccent = .american
    
    @Environment(\.colorScheme) private var scheme
    
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 30) {
                TextInputView().environment(vm)
                
                if Preferences.warmupOnLaunch == false, vm.isEngineLoaded == false {
                    loadEngineButton
                }
                
                stepsSlider
                
                
                voicePicker
                
                
                if let results = vm.results {
                    GeneratedAudioView(results: results).environment(vm)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, showPerformanceHud ? 125 : 70) // push down from the top
            .padding(.bottom, 90)
            .buttonStyle(.plain)
        }
        .animation(.spring(response: 0.3), value: vm.isGenerating)
        .overlay(alignment: .top) { HeaderView($showPerformanceHud) }
        .overlay(alignment: .bottom) { generateButton }
        .task {
            guard Preferences.warmupOnLaunch else { return }
            isEngineLoading = true
            await vm.run()
            isEngineLoading = false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            guard Preferences.autoPasteOnLaunch else { return }
            vm.pasteFromClipboard()
        }
        .alert(item: $vm.errorMessage) {
            Alert(title: Text("Error"), message: Text($0), dismissButton: .cancel())
        }
    }
    
    var voicesBasedOnAccent: [Voice] {
        selectedAccent == .american ? [.engMale, .engFemale] : [.britMale, .britFemale]
    }
}


extension ContentView {
    private var stepsSlider: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading) {
                    Text("NFE Steps")
                        .font(.callout.weight(.semibold))
                    
                    Text("Higher steps produces better results")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("\(Int(vm.steps))")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.blue.gradient)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color(.systemGray6), in: .capsule)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            CompactSlider(value: $vm.steps, in: 5...25, step: 1)
                .frame(height: 37)
                .sensoryFeedback(.selection, trigger: vm.steps)
        }
    }
    
    
    private var voicePicker: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading) {
                Text("Voice Asset")
                    .font(.callout.weight(.semibold))
                
                Button {
                    Haptics.selection()
                    
                    withAnimation {
                        selectedAccent = selectedAccent == .american ? .british : .american
                        vm.voice = voicesBasedOnAccent[0]
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.turn.down.right")
                            
                        Text(selectedAccent.rawValue)
                            .contentTransition(.numericText())
                            .foregroundColor(.secondary)
                    }
                    .font(.footnote)
                }
            }
            .padding(.leading, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            
            HStack(spacing: 12) {
                ForEach(voicesBasedOnAccent, id: \.identifier) { voice in
                    Button(voice.displayName, systemImage: "") {
                        Haptics.impact(style: .soft)
                        
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            vm.voice = voice
                        }
                    }
                    .labelStyle(VoiceOptionLabelStyle(isSelected: vm.voice == voice))
                }
            }
        }
    }
    
    
    private var generateButton: some View {
        Button(action: vm.generate) {
            HStack(spacing: 10) {
                if vm.isGenerating {
                    ProgressView()
                        .tint(scheme == .light ? .white : .black)
                        .scaleEffect(0.9)
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.title3)
                }
                
                Text(vm.isGenerating ? "Generating.." : "Generate Speech")
                    .fontWeight(.semibold)
                    .font(.body)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(.background)
            .background(Capsule())
            .shadow(
                color: Color.accentColor.opacity(scheme == .light ? 0.3 : 0.0),
                radius: 9, x: 0, y: 4
            )
        }
        .buttonStyle(.plain)
        .modifier(ShakeEffect(animatableData: vm.shakeTrigger))
        .padding(.horizontal, 22)
        .padding(.top, 30)
        .background(alignment: .center) {
            ProgressiveBlurView(maxBlurRadius: 35, overshoot: 1.5)
                .rotationEffect(.init(degrees: 180))
                .ignoresSafeArea(edges: .bottom)
        }
        .padding(.bottom, -kdObserver.height)
    }
    
    
    private var loadEngineButton: some View {
        Button {
            Task {
                isEngineLoading = true
                await vm.run()
                isEngineLoading = false
            }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(scheme == .dark ? Color.tangerine.gradient : Color.blue.gradient)
                    .fontWeight(.bold)
                    .symbolEffect(.bounce, value: isEngineLoading)
                
                Text("Load Engine")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.linear.repeatForever(autoreverses: false).speed(0.8).delay(0.2), value: isEngineLoading)
            .background(
                Color.secondary.opacity(scheme == .light ? 0.08 : 0.25),
                in: .rect(cornerRadius: 17.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 17.5)
                    .stroke(Color.secondary.opacity(0.15))
            )
        }
    }
}
