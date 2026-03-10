import SwiftUI

public struct EmptyStateView: View {
    let message: String

    public init(message: String = "No projects running") {
        self.message = message
    }

    public var body: some View {
        Text(message)
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
    }
}
