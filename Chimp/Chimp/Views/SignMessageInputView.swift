import SwiftUI
import CryptoKit

struct SignMessageInputView: View {
    @Binding var isPresented: Bool
    @State private var messageText: String = ""
    @State private var errorMessage: String?
    
    let onSign: (Data) -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Message to Sign")) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("32-byte hex (64 chars) or any text message", text: $messageText)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .accessibilityLabel("Message to sign")
                            .accessibilityHint("Enter a 32-byte hex value or any text message")
                        
                        if !messageText.isEmpty {
                            let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
                            let hexString = trimmedText.hasPrefix("0x") ? String(trimmedText.dropFirst(2)) : trimmedText
                            let isHex = isValidHexString(hexString) && hexString.count == 64
                            
                            HStack(spacing: 4) {
                                Image(systemName: isHex ? "checkmark.circle.fill" : "info.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(isHex ? .green : .blue)
                                Text(isHex ? "32-byte hex value detected" : "Will be hashed with SHA256")
                                    .font(.caption)
                                    .foregroundColor(isHex ? .green : .blue)
                            }
                        }
                    }
                    
                    Text("Enter a 32-byte hex value (64 characters) to sign directly, or any text message to hash with SHA256.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .accessibilityLabel("Error: \(error)")
                    }
                }
            }
            .navigationTitle("Sign Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sign") {
                        sign()
                    }
                    .disabled(messageText.isEmpty)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
    
    private func sign() {
        errorMessage = nil
        
        guard !messageText.isEmpty else {
            errorMessage = "Please enter a message to sign"
            return
        }
        
        let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            errorMessage = "Please enter a message to sign"
            return
        }
        
        // Determine if input is a 32-byte hex value (64 hex characters)
        let hexString: String
        if trimmedText.hasPrefix("0x") {
            hexString = String(trimmedText.dropFirst(2))
        } else {
            hexString = trimmedText
        }
        
        var messageData: Data
        
        // Check if it's a valid 32-byte hex value (64 hex characters)
        if isValidHexString(hexString) && hexString.count == 64 {
            // Use 32-byte hex value directly
            guard let data = Data(hexString: hexString) else {
                errorMessage = "Invalid hexadecimal format"
                return
            }
            guard data.count == 32 else {
                errorMessage = "Hex value must be exactly 32 bytes (64 hex characters)"
                return
            }
            messageData = data
        } else {
            // Treat as generic text message - hash with SHA256 to get 32 bytes
            let textData = trimmedText.data(using: .utf8) ?? Data()
            messageData = Data(SHA256.hash(data: textData))
        }
        
        // Ensure we have exactly 32 bytes (required by the chip)
        guard messageData.count == 32 else {
            errorMessage = "Message digest must be exactly 32 bytes"
            return
        }
        
        isPresented = false
        onSign(messageData)
    }
    
    private func isValidHexString(_ string: String) -> Bool {
        let hexCharacters = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return string.unicodeScalars.allSatisfy { hexCharacters.contains($0) }
    }
}

