import SwiftUI

struct MainWindowView: View {
    var body: some View {
        ZStack {
            Color.windowBg
                .ignoresSafeArea()
            Text("Welcome to meet-notes")
                .foregroundStyle(.primary)
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}
