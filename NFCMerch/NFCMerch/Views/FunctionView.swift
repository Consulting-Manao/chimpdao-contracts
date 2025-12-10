import SwiftUI

struct FunctionView: View {
    let functionType: ContentView.ContractFunctionType
    let onDismiss: () -> Void
    @EnvironmentObject var appData: AppData
    
    var body: some View {
        Group {
            switch functionType {
            case .transfer:
                TransferView(onDismiss: onDismiss)
            }
        }
    }
}
