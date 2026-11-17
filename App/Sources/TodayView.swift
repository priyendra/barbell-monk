import Engine
import SwiftUI

struct TodayView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Nothing here yet",
                systemImage: "figure.strengthtraining.traditional",
                description: Text("Weight and activity are coming next.")
            )
            .navigationTitle("Today")
            .toolbar {
                Text("Engine \(Engine.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    TodayView()
}
