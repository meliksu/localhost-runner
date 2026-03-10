import Foundation
import SwiftUI
import Combine

@MainActor
public class ProjectListViewModel: ObservableObject {
    @Published public var projects: [LocalProject] = []
    @Published public var isScanning = false
    @Published public var errorMessage: String?

    private var scanner: PortScanner
    private var timerCancellable: AnyCancellable?
    private var settingsObserver: NSObjectProtocol?

    public init(scanner: PortScanner = PortScanner()) {
        self.scanner = scanner
        setupSettingsObserver()
        updateTimer()
    }

    private func setupSettingsObserver() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateTimer()
            }
        }
    }

    private func updateTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil

        let interval = UserDefaults.standard.double(forKey: "scanInterval")
        guard interval > 0 else { return }

        timerCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.refresh() }
            }
    }

    public func refresh() async {
        isScanning = true
        errorMessage = nil

        var portMin = UserDefaults.standard.integer(forKey: "portRangeMin")
        var portMax = UserDefaults.standard.integer(forKey: "portRangeMax")
        if portMin == 0 { portMin = 3000 }
        if portMax == 0 { portMax = 9000 }
        portMin = Swift.max(1024, Swift.min(65535, portMin))
        portMax = Swift.max(1024, Swift.min(65535, portMax))
        if portMin > portMax { swap(&portMin, &portMax) }

        let range = portMin...portMax
        scanner = PortScanner(portRange: range)

        let result = await scanner.scan()
        switch result {
        case .success(let found):
            projects = found
            errorMessage = nil
        case .error(let message):
            projects = []
            errorMessage = message
        }

        isScanning = false
    }

    public func openInBrowser(_ project: LocalProject) {
        NSWorkspace.shared.open(project.url)
    }

    public func killProject(_ project: LocalProject) {
        kill(pid_t(project.pid), SIGTERM)
        projects.removeAll { $0.id == project.id }
    }

    public var projectCount: Int { projects.count }
}
