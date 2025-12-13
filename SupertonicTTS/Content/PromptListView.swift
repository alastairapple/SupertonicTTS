//
//  PromptListView.swift
//  SupertonicTTS
    

import SwiftUI

struct PromptListView: View {
    var storage = PromptStorage.shared
    @Binding var selectedPrompt: String
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    
    
    var body: some View {
        NavigationStack {
            List {
                if storage.isEmpty {
                    emptyView
                } else {
                    Section {
                        Button("Clear All", systemImage: "trash", action: storage.clearPrompts)
                    }
                    .listRowBackground(listRowBackgroundStyle)
                    
                    Section {
                        ForEach(storage.prompts) { prompt in
                            Button {
                                self.selectedPrompt = prompt.text
                                dismiss()
                            } label: {
                                Text(prompt.text)
                            }
                        }
                        .onDelete(perform: storage.deletePrompt)
                    }
                    .listRowBackground(listRowBackgroundStyle)
                }
            }
            .navigationBarTitle(storage.isEmpty ? "" : "Prompts")
            .navigationBarItems(trailing: closeButton)
            .buttonStyle(.plain)
        }
    }
    
    private var listRowBackgroundStyle: Color {
        scheme == .light ? Color.white : Color.gray.opacity(0.12)
    }
    
    private var emptyView: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.primary, .blue.gradient)
                .font(.largeTitle)
                .symbolRenderingMode(.palette)
                .shadow(color: .blue, radius: 45)
            
            VStack(spacing: 5) {
                Text("No Prompts Yet")
                    .font(.title2.weight(.bold))
                
                Text("Synthesize new audios to store their prompts")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
        .listRowBackground(listRowBackgroundStyle)
    }
    
    private var closeButton: some View {
        Button {
            Haptics.impact(style: .light)
            dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.gray)
                .symbolRenderingMode(.hierarchical)
        }
    }
}
