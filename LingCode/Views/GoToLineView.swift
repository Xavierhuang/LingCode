//
//  GoToLineView.swift
//  LingCode
//
//  Created by Weijia Huang on 11/23/25.
//

import SwiftUI

struct GoToLineView: View {
    @Binding var isPresented: Bool
    let maxLines: Int
    let onGoToLine: (Int) -> Void
    @State private var lineNumber: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Go to Line")
                .font(.headline)
            
            HStack {
                Text("Line:")
                TextField("", text: $lineNumber)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .focused($isFocused)
                    .onSubmit {
                        goToLine()
                    }
                
                Text("of \(maxLines)")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Go") {
                    goToLine()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            isFocused = true
        }
    }
    
    private func goToLine() {
        guard let line = Int(lineNumber),
              line > 0 && line <= maxLines else {
            return
        }
        onGoToLine(line)
        isPresented = false
    }
}








