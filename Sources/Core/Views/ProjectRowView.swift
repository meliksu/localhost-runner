import SwiftUI

public struct ProjectRowView: View {
    let project: LocalProject

    public init(project: LocalProject) {
        self.project = project
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(project.name)
                .font(.system(size: 13, weight: .semibold))
            Text("localhost:\(project.port) · \(project.processType)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
