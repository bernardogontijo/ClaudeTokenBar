import SwiftUI

@main
struct ClaudeTokenBarApp: App {
    @State private var usageService = UsageService()
    @State private var costService = CostService()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(usageService: usageService, costService: costService)
        } label: {
            MenuBarLabel(usageService: usageService)
        }
        .menuBarExtraStyle(.window)
    }

    init() {
        // Services are started via onAppear in the label
    }
}

struct MenuBarLabel: View {
    let usageService: UsageService

    var body: some View {
        let data = usageService.data
        let hasError = data.error != nil

        HStack(spacing: 4) {
            Image(systemName: hasError ? "exclamationmark.circle" : "brain.head.profile")
            if !hasError {
                Text("\(Int(data.fiveHourUtilization))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                Text("|")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text("\(Int(data.sevenDayUtilization))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
        }
        .onAppear {
            usageService.start()
        }
    }
}
