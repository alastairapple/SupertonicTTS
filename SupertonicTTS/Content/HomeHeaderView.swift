//
//  HeaderView.swift
//  SupertonicTTS
    

import SwiftUI

struct HeaderView: View {
    @Binding var showPerformance: Bool
    @State private var showPreferences = false
    @Environment(ApplicationVM.self) private var vm
    
    init(_ showPerformance: Binding<Bool>) {
        self._showPerformance = showPerformance
    }
    
    @Environment(\.colorScheme) private var scheme
    
    var body: some View {
        ZStack(alignment: .top) {
            ProgressiveBlurView()
                .frame(maxHeight: showPerformance ? 160 : 120) // Pins to the top
                .allowsHitTesting(false) // Avoids interference with touch interactions
                .edgesIgnoringSafeArea(.top) // Ensure it covers the status bar
            
            
            VStack(spacing: 8) {
                HStack(alignment: .center) { 
                    Text("SupertonicTTS")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            scheme == .dark ? darkModeGradient : lightModeGradient
                        )
                        .onTapGesture {
                            showPreferences.toggle()
                        }
                    
                    Spacer()
                    
                    Button(action: togglePerfHud) {
                        Image(systemName: showPerformance ? "chart.bar.fill" : "chart.bar")
                            .font(.title3)
                            .foregroundStyle(showPerformance ? .primary : .secondary)
                            .frame(width: 40, height: 40)
                    }
                }
                
                if showPerformance {
                    PerformanceMonitorView()
                        .id(scheme)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 22)
            .padding(.top, 4)
        }
        .sheet(isPresented: $showPreferences) {
            PreferencesView().environment(vm)
        }
    }
    
    func togglePerfHud() {
        withAnimation(.spring(response: 0.3)) {
            showPerformance.toggle()
        }
    }
    
    var darkModeGradient: LinearGradient {
        LinearGradient(
            colors: [Color(#colorLiteral(red: 0.2392156869, green: 0.6745098233, blue: 0.9686274529, alpha: 1)), Color(#colorLiteral(red: 0.9066100717, green: 0.9666207433, blue: 0.9741979241, alpha: 1))],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var lightModeGradient: LinearGradient {
        LinearGradient(
            colors: [.black, .black.opacity(0.4)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
