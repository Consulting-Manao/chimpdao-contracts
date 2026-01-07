import SwiftUI

struct ErrorBanner: View {
    let error: String
    let onDismiss: () -> Void
    let onRetry: (() -> Void)?
    let onCheckSettings: (() -> Void)?
    
    init(error: String, onDismiss: @escaping () -> Void, onRetry: (() -> Void)? = nil, onCheckSettings: (() -> Void)? = nil) {
        self.error = error
        self.onDismiss = onDismiss
        self.onRetry = onRetry
        self.onCheckSettings = onCheckSettings
    }
    
    private var isConfigurationError: Bool {
        error.lowercased().contains("contract") || 
        error.lowercased().contains("settings") ||
        error.lowercased().contains("configuration")
    }
    
    private var isTransientError: Bool {
        error.lowercased().contains("network") ||
        error.lowercased().contains("timeout") ||
        error.lowercased().contains("failed to connect")
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundColor(.red)
                
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Error: \(error)")
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Dismiss error")
            }
            
            // Recovery actions
            HStack(spacing: 12) {
                if let onRetry = onRetry, isTransientError {
                    Button(action: onRetry) {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                }
                
                if let onCheckSettings = onCheckSettings, isConfigurationError {
                    Button(action: onCheckSettings) {
                        Label("Check Settings", systemImage: "gearshape")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                }
                
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.1))
        )
    }
}

