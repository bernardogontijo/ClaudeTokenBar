import SwiftUI

struct UsageBar: View {
    let label: String
    let utilization: Double
    let resetIn: String

    private var barColor: Color {
        if utilization >= 80 { return Color(red: 0.97, green: 0.47, blue: 0.56) }
        if utilization >= 50 { return Color(red: 0.88, green: 0.69, blue: 0.41) }
        return Color(red: 0.62, green: 0.81, blue: 0.42)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(utilization))%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(barColor)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: max(geo.size.width * utilization / 100, 0), height: 6)
                }
            }
            .frame(height: 6)

            if !resetIn.isEmpty {
                Text("Resets in \(resetIn)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct MenuBarView: View {
    let usageService: UsageService
    let costService: CostService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.purple)
                Text("Claude Token Usage")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let date = usageService.data.lastUpdated {
                    Text(date, style: .time)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            if let error = usageService.data.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            } else {
                UsageBar(
                    label: "5-Hour Window",
                    utilization: usageService.data.fiveHourUtilization,
                    resetIn: usageService.data.fiveHourResetIn
                )

                UsageBar(
                    label: "7-Day Window",
                    utilization: usageService.data.sevenDayUtilization,
                    resetIn: usageService.data.sevenDayResetIn
                )

                Divider()

                HStack {
                    Image(systemName: "dollarsign.circle")
                        .foregroundStyle(costColor)
                    Text("Today's Cost")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "$%.2f", costService.dailyCost))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(costColor)
                }
            }

            Divider()

            HStack {
                Button("Refresh") {
                    usageService.fetch()
                    costService.calculate()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                .foregroundStyle(.red)
            }
        }
        .padding(12)
        .frame(width: 260)
    }

    private var costColor: Color {
        if costService.dailyCost >= 10 { return Color(red: 0.97, green: 0.47, blue: 0.56) }
        if costService.dailyCost >= 5 { return Color(red: 0.88, green: 0.69, blue: 0.41) }
        return Color(red: 0.45, green: 0.85, blue: 0.80)
    }
}
