import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            Section {
                Text("Manage NFTs on the Stellar blockchain using NFC chips.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } header: {
                Text("About")
            }
            
            Section {
                HelpRow(
                    icon: "photo.fill",
                    title: "Load NFT",
                    description: "View NFT details and metadata."
                )
                
                HelpRow(
                    icon: "hand.raised.fill",
                    title: "Claim NFT",
                    description: "Claim ownership of an unclaimed NFT."
                )
                
                HelpRow(
                    icon: "arrow.right.circle.fill",
                    title: "Transfer NFT",
                    description: "Send an NFT to another Stellar address."
                )
                
                HelpRow(
                    icon: "signature",
                    title: "Sign Message",
                    description: "Create a cryptographic signature with the chip."
                )
                
            } header: {
                Text("Operations")
            }
            
            Section {
                HelpFAQ(
                    question: "Operation failed?",
                    answer: "Check your internet connection and wallet balance."
                )
                
                HelpFAQ(
                    question: "Can't claim NFT?",
                    answer: "It may already be claimed or restricted to specific addresses."
                )
                
                HelpFAQ(
                    question: "Chip not detected?",
                    answer: "Hold steady, move slightly, and try again."
                )
            } header: {
                Text("Troubleshooting")
            }
        }
        .navigationTitle("Help & Support")
        .navigationBarTitleDisplayMode(.inline)
            .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct HelpRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.chimpYellow)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct HelpFAQ: View {
    let question: String
    let answer: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(question)
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Text(answer)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

