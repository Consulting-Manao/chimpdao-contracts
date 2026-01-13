import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        List {
            Section {
                Text("Interact with your collectibles using NFC chips embedded in physical items.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } header: {
                Text("About")
            }
            
            Section {
                HelpRow(
                    icon: "hand.raised.fill",
                    title: "Claim",
                    description: "Take ownership of an item by tapping your phone on its chip."
                )
                
                HelpRow(
                    icon: "photo.fill",
                    title: "Load",
                    description: "View details and authenticity information."
                )
                
                HelpRow(
                    icon: "arrow.right.circle.fill",
                    title: "Transfer",
                    description: "Send ownership to someone else."
                )
            } header: {
                Text("How It Works")
            }
            
            Section {
                HelpFAQ(
                    question: "Chip not detected?",
                    answer: "Hold your phone steady near the chip. Try moving slightly if it doesn't respond. While scanning, the window provides some feedback."
                )
                
                HelpFAQ(
                    question: "Operation failed?",
                    answer: "Ensure you have a stable internet connection and try again. Check you have enough balance on your address for the smart contract execution."
                )
                
                HelpFAQ(
                    question: "Can't claim?",
                    answer: "The item may already be claimed by someone else."
                )
            } header: {
                Text("Troubleshooting")
            }
            
            Section {
                Button(action: openContactPage) {
                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(.chimpYellow)
                        Text("Contact Us")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Need More Help?")
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
    
    private func openContactPage() {
        guard let url = URL(string: "https://chimpdao.xyz/pages/contact") else { return }
        openURL(url)
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

