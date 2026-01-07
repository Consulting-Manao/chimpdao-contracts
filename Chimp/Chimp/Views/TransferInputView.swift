import SwiftUI

struct TransferInputView: View {
    @Binding var isPresented: Bool
    @State private var recipientAddress: String = ""
    @State private var errorMessage: String?
    @State private var showConfirmation = false
    @FocusState private var isAddressFocused: Bool
    
    let tokenId: UInt64
    let onTransfer: (String) -> Void
    
    private var isRecipientValid: Bool {
        !recipientAddress.isEmpty && AppConfig.shared.validateStellarAddress(recipientAddress)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("NFT Information")) {
                    HStack {
                        Text("Token ID")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(tokenId)")
                            .fontWeight(.medium)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Token ID: \(tokenId)")
                }
                
                Section(header: Text("Transfer Details")) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Recipient Stellar Address (G...)", text: $recipientAddress)
                            .font(.custom("SFMono-Regular", size: 14))
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .focused($isAddressFocused)
                            .submitLabel(.done)
                            .onSubmit {
                                if isRecipientValid {
                                    validateAndShowConfirmation()
                                }
                            }
                            .accessibilityLabel("Recipient address")
                            .accessibilityHint("Enter the Stellar address starting with G")
                        
                        if !recipientAddress.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: isRecipientValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(isRecipientValid ? .green : .red)
                                Text(isRecipientValid ? "Valid address" : "Invalid address format")
                                    .font(.caption)
                                    .foregroundColor(isRecipientValid ? .green : .red)
                            }
                        }
                    }
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
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Transfer NFT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Transfer") {
                        validateAndShowConfirmation()
                    }
                    .disabled(!isRecipientValid)
                }
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") {
                            isAddressFocused = false
                        }
                    }
                }
            }
            .alert("Confirm Transfer", isPresented: $showConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Transfer", role: .destructive) {
                    transfer()
                }
            } message: {
                Text("You are about to transfer this NFT. This action cannot be undone.\n\nRecipient: \(recipientAddress)\nToken ID: \(tokenId)")
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
    
    private func validateAndShowConfirmation() {
        errorMessage = nil
        
        guard !recipientAddress.isEmpty else {
            errorMessage = "Please enter a recipient address"
            return
        }
        
        guard AppConfig.shared.validateStellarAddress(recipientAddress) else {
            errorMessage = "Please enter a valid Stellar address (56 characters starting with 'G')"
            return
        }
        
        showConfirmation = true
    }
    
    private func transfer() {
        isPresented = false
        onTransfer(recipientAddress)
    }
}

