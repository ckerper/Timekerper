import SwiftUI

/// A time picker with three wheel columns: Hour (1-12), Minute (:00/:15/:30/:45), AM/PM.
/// Binds to an "HH:mm" 24-hour string (e.g. "09:00", "17:30").
struct TimeWheelPicker: View {
    let label: String
    @Binding var value: String

    private static let minuteOptions = [0, 15, 30, 45]

    // Parse "HH:mm" → (hour12, minute, isAM)
    private var parsed: (hour12: Int, minute: Int, isAM: Bool) {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return (9, 0, true) }
        let h24 = parts[0]
        let m = (parts[1] / 15) * 15 // snap to nearest 15
        let isAM = h24 < 12
        let h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24)
        return (h12, m, isAM)
    }

    private func writeBack(hour12: Int, minute: Int, isAM: Bool) {
        var h24: Int
        if isAM {
            h24 = hour12 == 12 ? 0 : hour12
        } else {
            h24 = hour12 == 12 ? 12 : hour12 + 12
        }
        value = String(format: "%02d:%02d", h24, minute)
    }

    var body: some View {
        let p = parsed

        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                // Hour wheel (1-12)
                Picker("Hour", selection: Binding(
                    get: { p.hour12 },
                    set: { writeBack(hour12: $0, minute: p.minute, isAM: p.isAM) }
                )) {
                    ForEach(1...12, id: \.self) { h in
                        Text("\(h)").tag(h)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 60)
                .clipped()

                // Minute wheel (:00, :15, :30, :45)
                Picker("Minute", selection: Binding(
                    get: { p.minute },
                    set: { writeBack(hour12: p.hour12, minute: $0, isAM: p.isAM) }
                )) {
                    ForEach(Self.minuteOptions, id: \.self) { m in
                        Text(String(format: ":%02d", m)).tag(m)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 70)
                .clipped()

                // AM/PM wheel
                Picker("Period", selection: Binding(
                    get: { p.isAM },
                    set: { writeBack(hour12: p.hour12, minute: p.minute, isAM: $0) }
                )) {
                    Text("AM").tag(true)
                    Text("PM").tag(false)
                }
                .pickerStyle(.wheel)
                .frame(width: 60)
                .clipped()
            }
            .frame(height: 120)
        }
    }
}
