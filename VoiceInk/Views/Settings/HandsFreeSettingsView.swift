import SwiftUI
import KeyboardShortcuts

// MARK: - HandsFreeSettingsView (W12.D)
//
// Settings for the hotkey-toggleable continuous-listening mode. Five sections:
//   1. Activation     — KeyboardShortcuts.Recorder for the toggle hotkey.
//   2. VAD threshold  — segmented Low/Medium/High + advanced raw slider.
//   3. Silence dur.   — segmented Quick/Standard/Patient.
//   4. Voice triggers — list editor for "press enter" / "submit" / etc.
//   5. Session cap    — read-only display (20-min hard-coded v1, lead Q6).
//
// Persistence: AppStorage-backed UserDefaults keys registered in `AppDefaults`.
// Trigger phrase list round-trips JSON via `HandsFreeMode.saveTriggerPhrases`.
// Idiom matches SettingsView.swift: ScrollView { LazyVStack of SettingsCards }.

struct HandsFreeSettingsView: View {
    @AppStorage("HandsFreeVADThresholdDb") private var vadThresholdDb: Double = -40.0
    @AppStorage("HandsFreeSilenceDurationMs") private var silenceMs: Int = 1500
    @State private var triggerPhrases: [String] = []
    @State private var isAdvancedThresholdExpanded = false

    private enum ThresholdPreset: Double, CaseIterable {
        case low = -50.0
        case medium = -40.0
        case high = -30.0

        var displayName: String {
            switch self {
            case .low:    return "Low"
            case .medium: return "Medium"
            case .high:   return "High"
            }
        }

        static func nearest(_ db: Double) -> ThresholdPreset? {
            allCases.first(where: { abs($0.rawValue - db) < 0.5 })
        }
    }

    private enum SilencePreset: Int, CaseIterable {
        case quick = 1000
        case standard = 1500
        case patient = 2500

        var displayName: String {
            switch self {
            case .quick:    return "Quick"
            case .standard: return "Standard"
            case .patient:  return "Patient"
            }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                activationCard
                thresholdCard
                silenceCard
                triggersCard
                sessionCapCard
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .adaptiveGlassBackground()
        .onAppear {
            triggerPhrases = HandsFreeMode.current().triggerPhrases
        }
    }

    // MARK: - Activation

    private var activationCard: some View {
        SettingsCard(
            iconSystemName: "ear.fill",
            iconTint: Palette.accent,
            title: "Hands-free Mode",
            subtitle: "Continuous dictation; voice triggers fire Enter for you."
        ) {
            SettingsRow(
                iconSystemName: "command",
                label: "Toggle Hotkey",
                subtitle: "Press once to start, again to stop. Sessions auto-end at 20 minutes.",
                iconTint: Palette.accent
            ) {
                KeyboardShortcuts.Recorder(for: .handsFreeToggle)
                    .controlSize(.small)
            }
        }
    }

    // MARK: - VAD threshold

    private var thresholdCard: some View {
        SettingsCard(
            iconSystemName: "waveform.badge.mic",
            iconTint: Palette.accent,
            title: "Voice Activity Threshold",
            subtitle: "How loud speech must be to count as voice."
        ) {
            Picker("Threshold", selection: presetThresholdBinding) {
                ForEach(ThresholdPreset.allCases, id: \.self) { preset in
                    Text(preset.displayName).tag(preset as ThresholdPreset?)
                }
                Text("Custom").tag(ThresholdPreset?.none)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(presetHint)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup("Advanced", isExpanded: $isAdvancedThresholdExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Slider(value: $vadThresholdDb, in: -60.0...(-20.0), step: 1.0)
                        Text("\(Int(vadThresholdDb)) dBFS")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 70, alignment: .trailing)
                    }
                    Text("Negative values are quieter. -60 picks up whispers; -20 only loud speech.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
            }
            .font(.system(size: 12))
        }
    }

    private var presetThresholdBinding: Binding<ThresholdPreset?> {
        Binding(
            get: { ThresholdPreset.nearest(vadThresholdDb) },
            set: { newValue in
                if let preset = newValue {
                    vadThresholdDb = preset.rawValue
                }
                // Custom (nil) → no-op; user changes via the Advanced slider.
            }
        )
    }

    private var presetHint: String {
        switch ThresholdPreset.nearest(vadThresholdDb) {
        case .low:    return "Low (-50 dBFS) — picks up quiet speech; may segment on long pauses."
        case .medium: return "Medium (-40 dBFS) — balanced default."
        case .high:   return "High (-30 dBFS) — only loud speech; avoids background hum."
        case .none:   return "Custom (\(Int(vadThresholdDb)) dBFS)."
        }
    }

    // MARK: - Silence duration

    private var silenceCard: some View {
        SettingsCard(
            iconSystemName: "timer",
            iconTint: Palette.accent,
            title: "Silence Duration",
            subtitle: "How long a pause must last to commit an utterance."
        ) {
            Picker("Silence", selection: presetSilenceBinding) {
                ForEach(SilencePreset.allCases, id: \.self) { preset in
                    Text(preset.displayName).tag(preset as SilencePreset?)
                }
                Text("Custom").tag(SilencePreset?.none)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(silenceHint)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var presetSilenceBinding: Binding<SilencePreset?> {
        Binding(
            get: { SilencePreset(rawValue: silenceMs) },
            set: { newValue in
                if let preset = newValue { silenceMs = preset.rawValue }
            }
        )
    }

    private var silenceHint: String {
        switch SilencePreset(rawValue: silenceMs) {
        case .quick:    return "Quick (1.0s) — snappy; segments on 1-second pauses."
        case .standard: return "Standard (1.5s) — balanced default."
        case .patient:  return "Patient (2.5s) — tolerates longer thinking pauses."
        case .none:     return "Custom (\(silenceMs) ms)."
        }
    }

    // MARK: - Voice triggers

    private var triggersCard: some View {
        SettingsCard(
            iconSystemName: "text.bubble",
            iconTint: Palette.accent,
            title: "Voice Triggers",
            subtitle: "Phrases that, at the END of an utterance, press Enter for you."
        ) {
            ForEach(triggerPhrases.indices, id: \.self) { i in
                HStack(spacing: 8) {
                    TextField("Trigger phrase", text: Binding(
                        get: { triggerPhrases.indices.contains(i) ? triggerPhrases[i] : "" },
                        set: { newValue in
                            guard triggerPhrases.indices.contains(i) else { return }
                            triggerPhrases[i] = newValue
                            HandsFreeMode.saveTriggerPhrases(triggerPhrases)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)

                    Button(role: .destructive) {
                        guard triggerPhrases.indices.contains(i) else { return }
                        triggerPhrases.remove(at: i)
                        HandsFreeMode.saveTriggerPhrases(triggerPhrases)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }

            Button {
                triggerPhrases.append("")
                HandsFreeMode.saveTriggerPhrases(triggerPhrases)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Trigger")
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(Palette.accent)

            Text("Detected at the END of an utterance; mid-utterance occurrences are ignored. Each match strips the phrase from your text and presses Enter ~500ms after the paste.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    // MARK: - Session cap

    private var sessionCapCard: some View {
        SettingsCard(
            iconSystemName: "clock.fill",
            iconTint: Palette.neutral,
            title: "Session Cap",
            subtitle: "Hands-free auto-stops after a fixed duration."
        ) {
            SettingsRow(
                iconSystemName: "hourglass",
                label: "Auto-stop after",
                iconTint: Palette.neutral
            ) {
                Text("20 minutes")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Text("Matches Wispr's 20-minute cap. Configurable in a future release.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }
}

#if DEBUG
#Preview("Hands-free Settings — Onyx") {
    HandsFreeSettingsView()
        .frame(width: 720, height: 720)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("Hands-free Settings — Light") {
    HandsFreeSettingsView()
        .frame(width: 720, height: 720)
        .background(Color(red: 0.93, green: 0.94, blue: 0.96))
}
#endif
