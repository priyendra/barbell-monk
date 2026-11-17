import Engine
import SwiftUI

struct TodayView: View {
    let model: TodayModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Today")
        }
        .task { await model.load() }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
        case .needsAuthorization:
            ContentUnavailableView {
                Label("Connect Apple Health", systemImage: "heart.text.square")
            } description: {
                Text("barbellmonk reads your weight and activity from Apple Health.")
            } actions: {
                Button("Connect") { Task { await model.connect() } }
                    .buttonStyle(.borderedProminent)
            }
        case .failed(let message):
            ContentUnavailableView(
                "Couldn't read Apple Health",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .ready(let trend):
            if let current = trend.current {
                List {
                    WeightSection(trend: trend, current: current)
                }
            } else {
                noReadings
            }
        }
    }

    private var noReadings: some View {
        ContentUnavailableView {
            Label("No weight readings yet", systemImage: "scalemass")
        } description: {
            Text("Weigh in on your scale and it will show up here.")
        } actions: {
            #if DEBUG && targetEnvironment(simulator)
            Button("Add sample data to Health") { Task { await model.addSampleDataToHealth() } }
            #endif
        }
    }
}

private struct WeightSection: View {
    let trend: WeightTrend
    let current: Double

    var body: some View {
        Section("Weight") {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(current, format: .number.precision(.fractionLength(1))) lb")
                    .font(.largeTitle.bold())
                    .monospacedDigit()
                if let rate = trend.weeklyRate() {
                    RateLine(rate: rate)
                } else {
                    Text("Weekly rate shows after a week of readings")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            if let latest = trend.days.last(where: { !$0.needsReview }) {
                LabeledContent("Last weighed") {
                    Text("\(latest.reading.weight, format: .number.precision(.fractionLength(1))) lb, \(latest.reading.date, format: .relative(presentation: .named))")
                }
            }
            let reviewCount = trend.needingReview.count
            if reviewCount > 0 {
                Label(
                    "^[\(reviewCount) reading](inflect: true) to review",
                    systemImage: "questionmark.circle"
                )
                .foregroundStyle(.orange)
            }
        }
    }
}

private struct RateLine: View {
    let rate: WeightTrend.Rate

    var body: some View {
        let pounds = rate.perWeek.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()))
        let percent = rate.fractionPerWeek.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always()))
        HStack {
            Text("\(pounds) lb/week (\(percent))")
                .monospacedDigit()
            Spacer()
            Text(paceLabel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(paceColor)
        }
    }

    private var paceLabel: String {
        switch rate.pace() {
        case .slower: "Slower than target"
        case .onTarget: "On target"
        case .faster: "Faster than target"
        }
    }

    private var paceColor: Color {
        switch rate.pace() {
        case .slower, .faster: .orange
        case .onTarget: .green
        }
    }
}
