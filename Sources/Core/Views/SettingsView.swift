import SwiftUI
import ServiceManagement

public struct SettingsView: View {
    @AppStorage("scanInterval") private var scanInterval: Double = 0
    @AppStorage("portRangeMin") private var portRangeMin: Int = 3000
    @AppStorage("portRangeMax") private var portRangeMax: Int = 9000
    @AppStorage("autostart") private var autostart: Bool = true

    public init() {}

    public var body: some View {
        Form {
            Section("Scanning") {
                Picker("Scan Interval", selection: $scanInterval) {
                    Text("Manual").tag(0.0)
                    Text("5 seconds").tag(5.0)
                    Text("15 seconds").tag(15.0)
                    Text("30 seconds").tag(30.0)
                }

                HStack {
                    Text("Port Range")
                    TextField("Min", value: $portRangeMin, format: .number)
                        .frame(width: 80)
                        .onChange(of: portRangeMin) { _, newValue in
                            portRangeMin = max(1024, min(65535, newValue))
                        }
                    Text("–")
                    TextField("Max", value: $portRangeMax, format: .number)
                        .frame(width: 80)
                        .onChange(of: portRangeMax) { _, newValue in
                            portRangeMax = max(1024, min(65535, newValue))
                        }
                }
            }

            Section("General") {
                Toggle("Start at Login", isOn: $autostart)
                    .onChange(of: autostart) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            print("Failed to update login item: \(error)")
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 250)
    }
}
