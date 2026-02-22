import SwiftUI

struct CalendarView: View {
    @Environment(AppState.self) private var appState
    @State private var hasScrolled = false

    // Zoom levels matching web
    private let zoomLevels: [Double] = [0.5, 0.75, 1, 1.5, 2, 3]

    private var extStartMin: Int { DateTimeUtils.timeToMinutes(appState.settings.extendedStart) }
    private var extEndMin: Int { DateTimeUtils.timeToMinutes(appState.settings.extendedEnd) }
    private var workStartMin: Int { DateTimeUtils.timeToMinutes(appState.settings.workdayStart) }
    private var workEndMin: Int { DateTimeUtils.timeToMinutes(appState.settings.workdayEnd) }
    private var totalVisibleMinutes: Int { extEndMin - extStartMin }

    private var pixelsPerMinute: CGFloat {
        CGFloat(appState.settings.zoomLevel) * 1.5
    }

    private var totalHeight: CGFloat {
        CGFloat(totalVisibleMinutes) * pixelsPerMinute
    }

    private let timeLabelWidth: CGFloat = 38
    private let gridLeftPadding: CGFloat = 40

    private var startHour: Int { extStartMin / 60 }
    // +1 ensures the final hour line is drawn when extEndMin falls exactly on an hour boundary
    private var endHour: Int { (extEndMin / 60) + 1 }

    var body: some View {
        GeometryReader { geo in
            let contentWidth = geo.size.width - gridLeftPadding

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        // Invisible hour anchors for ScrollViewReader scroll-to support.
                        // Uses VStack so each cell has a real layout position (unlike .offset).
                        VStack(spacing: 0) {
                            ForEach(startHour..<endHour, id: \.self) { hour in
                                Color.clear
                                    .frame(height: 60 * pixelsPerMinute)
                                    .id("hour-\(hour)")
                            }
                        }
                        .frame(width: 1)

                        // Dim zones (outside working hours)
                        dimZones(contentWidth: contentWidth)

                        // Hour grid lines
                        hourLines(contentWidth: contentWidth)

                        // Time labels
                        timeLabels()

                        // Calendar blocks
                        ForEach(appState.scheduledBlocks) { block in
                            CalendarBlockView(block: block, contentWidth: contentWidth)
                                .offset(
                                    x: gridLeftPadding + blockXOffset(block: block, contentWidth: contentWidth),
                                    y: yForMinute(block.startMin)
                                )
                        }

                        // Now line (today only)
                        if appState.isToday {
                            nowLine(contentWidth: contentWidth)
                        }
                    }
                    .frame(width: geo.size.width, height: totalHeight)
                }
                .onAppear {
                    if !hasScrolled {
                        hasScrolled = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            let targetHour: Int
                            if appState.isToday {
                                // Scroll to one hour before current time
                                targetHour = max(appState.currentTimeMinutes / 60 - 1, startHour)
                            } else {
                                // Scroll to workday start
                                targetHour = max(workStartMin / 60, startHour)
                            }
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo("hour-\(targetHour)", anchor: .top)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Dim Zones

    @ViewBuilder
    private func dimZones(contentWidth: CGFloat) -> some View {
        let dimColor = Color.gray.opacity(0.08)

        // Before working hours
        if extStartMin < workStartMin {
            Rectangle()
                .fill(dimColor)
                .frame(width: contentWidth, height: yForMinute(workStartMin))
                .offset(x: gridLeftPadding, y: 0)
        }

        // After working hours
        if workEndMin < extEndMin {
            Rectangle()
                .fill(dimColor)
                .frame(width: contentWidth, height: yForMinute(extEndMin) - yForMinute(workEndMin))
                .offset(x: gridLeftPadding, y: yForMinute(workEndMin))
        }
    }

    // MARK: - Hour Lines

    @ViewBuilder
    private func hourLines(contentWidth: CGFloat) -> some View {
        ForEach(startHour..<endHour, id: \.self) { hour in
            let minute = hour * 60
            if minute >= extStartMin && minute <= extEndMin {
                Rectangle()
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: contentWidth, height: 1)
                    .offset(x: gridLeftPadding, y: yForMinute(minute))
            }
        }
    }

    // MARK: - Time Labels

    @ViewBuilder
    private func timeLabels() -> some View {
        ForEach(startHour..<endHour, id: \.self) { hour in
            let minute = hour * 60
            if minute >= extStartMin && minute <= extEndMin {
                Text(formatHourLabel(hour))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: timeLabelWidth, alignment: .trailing)
                    .offset(x: 0, y: yForMinute(minute) - 7)
            }
        }
    }

    // MARK: - Now Line

    @ViewBuilder
    private func nowLine(contentWidth: CGFloat) -> some View {
        let nowMin = appState.currentTimeMinutes
        if nowMin >= extStartMin && nowMin <= extEndMin {
            ZStack(alignment: .leading) {
                // Red line
                Rectangle()
                    .fill(Color.red)
                    .frame(width: contentWidth, height: 2)

                // Red dot
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .offset(x: -4)

                // "Now" label
                Text("Now")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.red)
                    .offset(x: contentWidth - 24)
            }
            .offset(x: gridLeftPadding, y: yForMinute(nowMin) - 1)
        }
    }

    // MARK: - Helpers

    private func yForMinute(_ minute: Int) -> CGFloat {
        CGFloat(minute - extStartMin) * pixelsPerMinute
    }

    private func heightForRange(startMin: Int, endMin: Int) -> CGFloat {
        CGFloat(endMin - startMin) * pixelsPerMinute
    }

    private func blockXOffset(block: Block, contentWidth: CGFloat) -> CGFloat {
        guard block.type == .event && block.totalColumns > 1 else { return 0 }
        let colWidth = contentWidth / CGFloat(block.totalColumns)
        return colWidth * CGFloat(block.column)
    }

    private func formatHourLabel(_ hour: Int) -> String {
        let h = hour % 24
        if h == 0 { return "12 AM" }
        if h < 12 { return "\(h) AM" }
        if h == 12 { return "12 PM" }
        return "\(h - 12) PM"
    }
}
