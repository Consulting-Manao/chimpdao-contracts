import SwiftUI

struct ContentView: View {
    var body: some View {
        ViewControllerWrapper()
    }
}

struct ViewControllerWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ViewController {
        return ViewController()
    }
    
    func updateUIViewController(_ uiViewController: ViewController, context: Context) {
        // No updates needed
    }
}

#Preview {
    ContentView()
}
