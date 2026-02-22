import SwiftUI

struct CalendarView: View {
    @Environment(AppState.self) private var appState
    @State private var hasScrolled = false
    @State private var dragOffset: CGFloat = 0

    // Zoom levels matching web
    private let zoomLevels: [Double] = [0.5, 0.75, 1, 1.5, 2, 3]

    // Visible range respects useExtendedHours toggle.
    // Uses effectiveExtended* which clamp to always encompass working hours.
    private var viewStartMin: Int {
        let raw = appState.settings.useExtendedHours
            ? DateTimeUtils.timeToMinutes(appState.settings.effectiveExtendedStart)
            : DateTimeUtils.timeToMinutes(appState.settings.workdayStart)
        // Floor to the hour so the first hour line always shows
        return (raw / 60) * 60
    }
    private var viewEndMin: Int {
        let raw = appState.settings.useExtendedHours
            ? DateTimeUtils.timeToMinutes(appState.settings.effectiveExtendedEnd)
            : DateTimeUtils.timeToMinutes(appState.settings.workdayEnd)
        // Ceil to the next hour so the last hour line always shows
        return min(((raw + 59) / 60) * 60, 1439)
    }
    private var workStartMin: Int { DateTimeUtils.timeToMinutes(appState.settings.workdayStart) }
    private var workEndMin: Int { DateTimeUtils.timeToMinutes(appState.settings.workdayEnd) }
    private var totalVisibleMinutes: Int { max(1, viewEndMin - viewStartMin) }

    private var pixelsPerMinute: CGFloat {
        CGFloat(appState.settings.zoomLevel) * 1.5
    }

    private var totalHeight: CGFloat {
        CGFloat(totalVisibleMinutes) * pixelsPerMinute
    }

    // Time labels sit at x:0 with natural width; grid starts after this gap
    private let gridLeftPadding: CGFloat = 34

    private var startHour: Int { viewStartMin / 60 }
    private var endHour: Int { (viewEndMin / 60) + 1 }

    var body: some View {
        GeometryReader { geo in
            // Right margin so blocks don't touch the screen edge
            let contentWidth = geo.size.width - gridLeftPadding - 16

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

                        // Dim zones (outside working hours, only when extended hours are on)
                        if appState.settings.useExtendedHours {
                            dimZones(contentWidth: contentWidth)
                        }

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
                    .clipped()
                }
                .contentMargins(0, for: .scrollContent)
                .onAppear {
                    if !hasScrolled {
                        hasScrolled = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            let targetHour: Int
                            if appState.isToday {
                                targetHour = max(appState.currentTimeMinutes / 60 - 1, startHour)
                            } else {
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
        .offset(x: dragOffset)
        // Swipe left/right to change days with animation
        .gesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onChanged { value in
                    // Only track horizontal movement when clearly horizontal
                    if abs(value.translation.width) > abs(value.translation.height) {
                        dragOffset = value.translation.width * 0.4
                    }
                }
                .onEnded { value in
                    let threshold: CGFloat = 50
                    if abs(value.translation.width) > abs(value.translation.height),
                       abs(value.translation.width) > threshold {
                        let goingLeft = value.translation.width < 0
                        // Slide off screen in swipe direction
                        withAnimation(.easeIn(duration: 0.15)) {
                            dragOffset = goingLeft ? -UIScreen.main.bounds.width * 0.3 : UIScreen.main.bounds.width * 0.3
                        }
                        // Change day and slide in from opposite side
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            if goingLeft {
                                appState.goToNextDay()
                            } else {
                                appState.goToPreviousDay()
                            }
                            dragOffset = goingLeft ? UIScreen.main.bounds.width * 0.3 : -UIScreen.main.bounds.width * 0.3
                            withAnimation(.easeOut(duration: 0.15)) {
                                dragOffset = 0
                            }
                        }
                    } else {
                        // Snap back
                        withAnimation(.easeOut(duration: 0.2)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }

    // MARK: - Dim Zones

    @ViewBuilder
    private func dimZones(contentWidth: CGFloat) -> some View {
        let dimColor = Color.gray.opacity(0.08)

        // Before working hours
        if viewStartMin < workStartMin {
            Rectangle()
                .fill(dimColor)
                .frame(width: contentWidth, height: yForMinute(workStartMin))
                .offset(x: gridLeftPadding, y: 0)
        }

        // After working hours
        if workEndMin < viewEndMin {
            Rectangle()
                .fill(dimColor)
                .frame(width: contentWidth, height: yForMinute(viewEndMin) - yForMinute(workEndMin))
                .offset(x: gridLeftPadding, y: yForMinute(workEndMin))
        }
    }

    // MARK: - Hour Lines

    @ViewBuilder
    private func hourLines(contentWidth: CGFloat) -> some View {
        ForEach(startHour..<endHour, id: \.self) { hour in
            let minute = hour * 60
            if minute >= viewStartMin && minute <= viewEndMin {
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
            if minute >= viewStartMin && minute <= viewEndMin {
                Text(formatHourLabel(hour))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: gridLeftPadding - 4, alignment: .trailing)
                    .offset(x: 0, y: yForMinute(minute) - 7)
            }
        }
    }

    // MARK: - Now Line

    @ViewBuilder
    private func nowLine(contentWidth: CGFloat) -> some View {
        let nowMin = appState.currentTimeMinutes
        if nowMin >= viewStartMin && nowMin <= viewEndMin {
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.red)
                    .frame(width: contentWidth, height: 2)

                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .offset(x: -4)

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
        CGFloat(minute - viewStartMin) * pixelsPerMinute
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
