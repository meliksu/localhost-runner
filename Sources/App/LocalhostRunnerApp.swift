import SwiftUI
import ServiceManagement
import LocalhostRunnerCore

@main
struct LocalhostRunnerApp: App {
    @StateObject private var viewModel = ProjectListViewModel()

    init() {
        registerLoginItemIfFirstLaunch()
    }

    var body: some Scene {
        MenuBarExtra {
            ProjectListView(viewModel: viewModel)
        } label: {
            Text("\(viewModel.projectCount)")
                .foregroundColor(viewModel.projectCount > 0 ? .primary : .secondary)
        }
        .menuBarExtraStyle(.window)
    }

    private func registerLoginItemIfFirstLaunch() {
        let hasLaunched = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        guard !hasLaunched else { return }

        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        UserDefaults.standard.set(true, forKey: "autostart")

        do {
            try SMAppService.mainApp.register()
        } catch {
            print("Failed to register login item: \(error)")
        }
    }
}
