import ActivityKit
import SwiftUI
import WidgetKit
import OpenTimeUI

struct AvailabilityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AvailabilityActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Theme.bg)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(context.state.currentStatus == "Free" ? Theme.accent : Theme.muted)
                            .frame(width: 3, height: 14)
                        Text(context.state.currentStatus.uppercased())
                            .font(Theme.Font.display(size: 11, weight: .bold))
                            .kerning(1.6)
                            .foregroundStyle(Theme.fg)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(durationText(context.state.totalFreeMinRemaining).uppercased())
                        .font(Theme.Font.display(size: 11, weight: .bold))
                        .kerning(1.4)
                        .foregroundStyle(Theme.accent)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.statusDetail.uppercased())
                            .font(Theme.Font.display(size: 9, weight: .regular))
                            .kerning(1.6)
                            .foregroundStyle(Theme.muted)
                        if !context.state.nextSlotLabel.isEmpty {
                            Text("\(context.state.nextSlotLabel) \(context.state.nextSlotTime)".uppercased())
                                .font(Theme.Font.display(size: 9, weight: .regular))
                                .kerning(1.6)
                                .foregroundStyle(Theme.dim)
                        }
                    }
                }
            } compactLeading: {
                Rectangle()
                    .fill(context.state.currentStatus == "Free" ? Theme.accent : Theme.muted)
                    .frame(width: 3, height: 14)
            } compactTrailing: {
                Text(durationText(context.state.totalFreeMinRemaining))
                    .font(Theme.Font.display(size: 12, weight: .medium))
                    .tnum()
                    .foregroundStyle(Theme.accent)
            } minimal: {
                Rectangle()
                    .fill(context.state.currentStatus == "Free" ? Theme.accent : Theme.muted)
                    .frame(width: 3, height: 14)
            }
        }
    }

    private func durationText(_ min: Int) -> String {
        if min < 60 { return "\(min)m" }
        let h = min / 60, m = min % 60
        return m > 0 ? "\(h)h\(m)m" : "\(h)h"
    }
}

struct LockScreenView: View {
    let state: AvailabilityActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(state.currentStatus == "Free" ? Theme.accent : Theme.muted)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .lastTextBaseline) {
                    Text("AVAILABILITY")
                        .font(Theme.Font.display(size: 10, weight: .bold))
                        .kerning(1.8)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Text(durationText(state.totalFreeMinRemaining).uppercased())
                        .font(Theme.Font.display(size: 10, weight: .bold))
                        .kerning(1.6)
                        .tnum()
                        .foregroundStyle(Theme.accent)
                }
                Rectangle().fill(Theme.rule).frame(height: 2)

                Text(state.currentStatus.uppercased())
                    .font(Theme.Font.display(size: 18, weight: .bold))
                    .kerning(-0.18)
                    .foregroundStyle(Theme.fg)

                Text(state.statusDetail.uppercased())
                    .font(Theme.Font.display(size: 10, weight: .regular))
                    .kerning(1.8)
                    .foregroundStyle(Theme.dim)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
    }

    private func durationText(_ min: Int) -> String {
        if min < 60 { return "\(min)m" }
        let h = min / 60, m = min % 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }
}
