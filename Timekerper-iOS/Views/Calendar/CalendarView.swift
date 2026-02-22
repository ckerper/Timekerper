import SwiftUI

struct CalendarView: View {
    @Environment(AppState.self) private var appState
    @State private var hasScrolled = false
    @State private var dragOffset: CGFloat = 0
    @State private var isDraggingHorizontally: Bool = false

    // Top padding so the first time label (offset y: -7) isn't clipped
    private let topInset: CGFloat = 10

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

    /// The adjacent date that would slide in based on current drag direction
    private var incomingDate: String {
        if dragOffset < 0 {
            return DateTimeUtils.addDays(appState.selectedDate, days: 1)
        } else {
            return DateTimeUtils.addDays(appState.selectedDate, days: -1)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let contentWidth = geo.size.width - gridLeftPadding - 16
            let screenWidth = geo.size.width

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        // Invisible hour anchors for ScrollViewReader scroll-to support.
                        VStack(spacing: 0) {
                            Color.clear.frame(height: topInset)
                            ForEach(startHour..<endHour, id: \.self) { hour in
                                Color.clear
                                    .frame(height: 60 * pixelsPerMinute)
                                    .id("hour-\(hour)")
                            }
                        }
                        .frame(width: 1)

                        // === Current day (moves with drag) ===
                        dayContent(
                            blocks: appState.scheduledBlocks,
                            showNowLine: appState.isToday,
                            contentWidth: contentWidth
                        )
                        .offset(x: dragOffset)

                        // === Incoming day (adjacent, only during drag) ===
                        if isDraggingHorizontally && dragOffset != 0 {
                            let incomingDateStr = incomingDate
                            let incomingIsToday = incomingDateStr == DateTimeUtils.todayStr()
                            dayContent(
                                blocks: appState.blocksForDate(incomingDateStr),
                                showNowLine: incomingIsToday,
                                contentWidth: contentWidth
                            )
                            .offset(x: dragOffset + (dragOffset < 0 ? screenWidth : -screenWidth))
                        }
                    }
                    .frame(width: screenWidth, height: totalHeight + topInset)
                    .clipped()
                }
                .contentMargins(0, for: .scrollContent)
                .onAppear {
                    if !hasScrolled {
                        hasScrolled = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            let targetHour: Int
                            if appState.isToday {
                                // Scroll to current hour, positioned at 1/3 of viewport
                                targetHour = max(appState.currentTimeMinutes / 60, startHour)
                            } else {
                                targetHour = max(workStartMin / 60, startHour)
                            }
                            let anchor: UnitPoint = appState.isToday
                                ? UnitPoint(x: 0.5, y: 0.33)
                                : .top
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo("hour-\(targetHour)", anchor: anchor)
                            }
                        }
                    }
                }
            }
        }
        // Swipe left/right to change days — follows finger, shows incoming day
        .simultaneousGesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                .onChanged { value in
                    if !isDraggingHorizontally {
                        if abs(value.translation.width) > 15 &&
                           abs(value.translation.width) > abs(value.translation.height) * 1.5 {
                            isDraggingHorizontally = true
                        }
                    }
                    if isDraggingHorizontally {
                        dragOffset = value.translation.width
                    }
                }
                .onEnded { value in
                    guard isDraggingHorizontally else {
                        isDraggingHorizontally = false
                        return
                    }
                    let screenWidth = UIScreen.main.bounds.width
                    let threshold: CGFloat = screenWidth * 0.2
                    let velocity = value.predictedEndTranslation.width - value.translation.width

                    if abs(value.translation.width) > threshold || abs(velocity) > 200 {
                        let goingLeft = value.translation.width < 0
                        // Animate current day off-screen (incoming follows)
                        withAnimation(.easeOut(duration: 0.2)) {
                            dragOffset = goingLeft ? -screenWidth : screenWidth
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            // Switch the actual date and reset
                            if goingLeft {
                                appState.goToNextDay()
                            } else {
                                appState.goToPreviousDay()
                            }
                            isDraggingHorizontally = false
                            dragOffset = 0
                        }
                    } else {
                        // Snap back
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = 0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isDraggingHorizontally = false
                        }
                    }
                }
        )
    }

    // MARK: - Day Content (everything that swipes with the day)

    @ViewBuilder
    private func dayContent(
        blocks: [Block],
        showNowLine: Bool,
        contentWidth: CGFloat
    ) -> some View {
        Group {
            if appState.settings.useExtendedHours {
                dimZones(contentWidth: contentWidth)
            }
            hourLines(contentWidth: contentWidth)
            timeLabels()

            ForEach(blocks) { block in
                CalendarBlockView(block: block, contentWidth: contentWidth)
                    .offset(
                        x: gridLeftPadding + blockXOffset(block: block, contentWidth: contentWidth),
                        y: topInset + yForMinute(block.startMin)
                    )
            }

            if showNowLine {
                nowLine(contentWidth: contentWidth)
            }
        }
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
                .offset(x: gridLeftPadding, y: topInset)
        }

        // After working hours
        if workEndMin < viewEndMin {
            Rectangle()
                .fill(dimColor)
                .frame(width: contentWidth, height: yForMinute(viewEndMin) - yForMinute(workEndMin))
                .offset(x: gridLeftPadding, y: topInset + yForMinute(workEndMin))
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
                    .offset(x: gridLeftPadding, y: topInset + yForMinute(minute))
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
                    .fixedSize()
                    .offset(x: 2, y: topInset + yForMinute(minute) - 7)
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
            .offset(x: gridLeftPadding, y: topInset + yForMinute(nowMin) - 1)
        }
    }

    // MARK: - Helpers

    private func yForMinute(_ minute: Int) -> CGFloat {
        CGFloat(minute - viewStartMin) * pixelsPerMinute
    }

    private func blockXOffset(block: Block, contentWidth: CGFloat) -> CGFloat {
        guard block.type == .event && block.totalColumns > 1 else { return 0 }
        let gap: CGFloat = 2
        let colWidth = (contentWidth - gap * CGFloat(block.totalColumns - 1)) / CGFloat(block.totalColumns)
        return (colWidth + gap) * CGFloat(block.column)
    }

    private func formatHourLabel(_ hour: Int) -> String {
        let h = hour % 24
        if h == 0 { return "12 AM" }
        if h < 12 { return "\(h) AM" }
        if h == 12 { return "12 PM" }
        return "\(h - 12) PM"
    }
}
