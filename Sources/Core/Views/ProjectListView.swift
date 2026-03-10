import SwiftUI

public struct ProjectListView: View {
    @ObservedObject var viewModel: ProjectListViewModel

    public init(viewModel: ProjectListViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.errorMessage {
                EmptyStateView(message: error)
            } else if viewModel.projects.isEmpty && !viewModel.isScanning {
                EmptyStateView()
            } else if viewModel.isScanning && viewModel.projects.isEmpty {
                EmptyStateView(message: "Scanning...")
            } else {
                ForEach(viewModel.projects) { project in
                    ProjectRowView(project: project, onKill: {
                        viewModel.killProject(project)
                    })
                        .onTapGesture {
                            viewModel.openInBrowser(project)
                        }
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }

                    if project.id != viewModel.projects.last?.id {
                        Divider().padding(.horizontal, 8)
                    }
                }
            }

            Divider()

            HStack {
                Button(action: {
                    Task { await viewModel.refresh() }
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isScanning)

                Spacer()

                Button(action: {
                    SettingsWindowController.shared.showSettings()
                }) {
                    Label("Settings", systemImage: "gear")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Text("Quit")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 260)
        .onAppear {
            Task { await viewModel.refresh() }
        }
    }
}
