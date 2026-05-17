import SwiftUI

/// Formatting for an estimated duration. Mirrors `FocusDurationFormatter`'s
/// abbreviated style so estimate and actual focus read consistently, but
/// estimates are always whole minutes/hours so we keep it minute-grained.
enum EstimateFormatter {
    static func string(from seconds: TimeInterval) -> String {
        let safe = max(0, seconds)
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.allowedUnits = safe >= 3600 ? [.hour, .minute] : [.minute]
        if safe < 60 { return "<1m" }
        return formatter.string(from: safe) ?? "\(Int(safe / 60))m"
    }
}

/// Optional estimated-duration input shared by the create and edit flows.
///
/// Design: preset chips (15m / 30m / 1h / 2h / 4h) plus a "Custom…" sheet with
/// hour + minute wheels, matching mDone's native-row UX. Selecting the active
/// chip again clears the estimate — the field is always optional and clearable
/// (there is also an explicit Clear control when a value is set). `nil` binding
/// == no estimate; nothing is persisted until the user picks something.
struct EstimatePicker: View {
    @Binding var estimateSeconds: TimeInterval?

    @State private var showingCustom = false

    /// Preset durations in seconds.
    private let presets: [TimeInterval] = [15 * 60, 30 * 60, 60 * 60, 120 * 60, 240 * 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Estimated duration")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let seconds = estimateSeconds {
                    Text(EstimateFormatter.string(from: seconds))
                        .font(.subheadline.weight(.semibold))
                    Button {
                        estimateSeconds = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear estimate")
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { preset in
                        chip(
                            label: EstimateFormatter.string(from: preset),
                            isSelected: estimateSeconds == preset
                        ) {
                            // Re-tapping the active preset clears it.
                            estimateSeconds = (estimateSeconds == preset) ? nil : preset
                        }
                    }
                    chip(
                        label: "Custom…",
                        isSelected: isCustomValue
                    ) {
                        showingCustom = true
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .sheet(isPresented: $showingCustom) {
            CustomEstimateSheet(estimateSeconds: $estimateSeconds)
        }
    }

    /// True when an estimate is set but isn't one of the presets.
    private var isCustomValue: Bool {
        guard let s = estimateSeconds else { return false }
        return !presets.contains(s)
    }

    @ViewBuilder
    private func chip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.15),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Hour + minute wheels for an arbitrary estimate. Confirm writes back; the
/// caller's binding stays untouched until then so Cancel is lossless.
private struct CustomEstimateSheet: View {
    @Binding var estimateSeconds: TimeInterval?
    @Environment(\.dismiss) private var dismiss

    @State private var hours: Int
    @State private var minutes: Int

    init(estimateSeconds: Binding<TimeInterval?>) {
        _estimateSeconds = estimateSeconds
        let seed = estimateSeconds.wrappedValue ?? 1800
        let totalMinutes = Int(seed / 60)
        // Minutes wheel only contains 0..55 in 5-minute increments. A non-
        // 5-multiple seed (e.g. a 27m suggestion from focus history) has no
        // matching tag, so we snap to the nearest 5 minutes.
        var snapped = Int(((Double(totalMinutes) / 5).rounded()) * 5)
        // ...but never snap a positive seed down to 0, or the user opens
        // the custom sheet on an existing tiny estimate (an agent-set 2m,
        // or even a sub-minute 30s) and tapping Set silently clears it.
        // The guard is on the original seconds — not on `totalMinutes` —
        // because anything 0 < seed < 60s already has totalMinutes == 0.
        if seed > 0, snapped == 0 { snapped = 5 }
        // Clamp into the picker's representable range so an agent-set
        // estimate larger than the hours wheel (currently up to 12h) lands
        // on a valid tag instead of leaving the picker in a no-selection
        // state. The wire-format value remains whatever was set; this only
        // affects what gets seeded into the wheels.
        let clampedHours = min(snapped / 60, Self.maxHours)
        let clampedMinutes = clampedHours == Self.maxHours ? 0 : snapped % 60
        _hours = State(initialValue: clampedHours)
        _minutes = State(initialValue: clampedMinutes)
    }

    /// Inclusive upper bound for the hours wheel — kept in one place so the
    /// init's clamp and the picker's `ForEach` range can't drift apart.
    fileprivate static let maxHours = 12

    var body: some View {
        NavigationStack {
            Form {
                Section("Estimated duration") {
                    HStack {
                        Picker("Hours", selection: $hours) {
                            ForEach(0 ... CustomEstimateSheet.maxHours, id: \.self) { Text("\($0) h").tag($0) }
                        }
                        #if os(iOS)
                        .pickerStyle(.wheel)
                        #endif
                        Picker("Minutes", selection: $minutes) {
                            ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) {
                                Text("\($0) m").tag($0)
                            }
                        }
                        #if os(iOS)
                        .pickerStyle(.wheel)
                        #endif
                    }
                }
            }
            .navigationTitle("Custom Estimate")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Set") {
                            let total = TimeInterval(hours * 3600 + minutes * 60)
                            estimateSeconds = total > 0 ? total : nil
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
    }
}
