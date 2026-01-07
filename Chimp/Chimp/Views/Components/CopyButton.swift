import SwiftUI
import UIKit

/// Reusable copy-to-clipboard button with visual feedback
struct CopyButton: View {
    let text: String
    let label: String
    
    @State private var copied = false
    
    init(_ text: String, label: String = "Copy") {
        self.text = text
        self.label = label
    }
    
    var body: some View {
        Button(action: copy) {
            Label(copied ? "Copied" : label, systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.subheadline.weight(.medium))
                .foregroundColor(copied ? .green : .chimpYellow)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "Copied to clipboard" : "Copy \(label.lowercased())")
    }
    
    private func copy() {
        UIPasteboard.general.string = text
        
        withAnimation(.easeInOut(duration: 0.2)) {
            copied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                copied = false
            }
        }
    }
}

