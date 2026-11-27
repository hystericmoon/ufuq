import SwiftUI
import UfuqCore

@MainActor
enum TimerControl {
    static var module: TimerModule?
    static var onChanged: () -> Void = {}

    static func startFocus() {
        module?.startPomodoroFocus()
        onChanged()
    }

    static func togglePause() {
        module?.togglePause()
        onChanged()
    }

    static func advance() {
        module?.advancePomodoro()
        onChanged()
    }

    static func stop() {
        module?.stop()
        onChanged()
    }
}

/// Small bento tile (144 × 112): CPU, RAM, Network rates + Stay Awake, Timer, and Voice quick actions.
struct SystemTile: View {
    let stats: SystemStatsSnapshot
    let stayAwakeActive: Bool
    let timerActive: Bool
    let transcribeActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("SYSTEM")
                    .font(Tokens.Typography.tileLabel)
                    .tracking(0.4)
                    .foregroundStyle(Tokens.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                Text(stats.formattedCPU)
                    .font(Tokens.Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(stats.cpuPercent >= 85 ? Tokens.stateWarning : Tokens.textSecondary)
            }
            .frame(minHeight: 16)

            HStack(spacing: 4) {
                Text("RAM")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.textSecondary)
                Spacer(minLength: 2)
                Text(stats.formattedMemory)
                    .font(Tokens.Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(Tokens.textPrimary)
                    .lineLimit(1)
            }

            HStack(spacing: 4) {
                Text("↓ \(compactRate(stats.downloadBytesPerSec))")
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text("↑ \(compactRate(stats.uploadBytesPerSec))")
                    .lineLimit(1)
            }
            .font(Tokens.Typography.caption)
            .monospacedDigit()
            .foregroundStyle(Tokens.textSecondary)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                tileActionButton(
                    symbol: "cup.and.saucer.fill",
                    active: stayAwakeActive,
                    label: stayAwakeActive ? "Turn off Stay Awake" : "Keep Mac awake"
                ) {
                    StayAwakeController.shared.toggle()
                }
                tileActionButton(
                    symbol: "timer",
                    active: timerActive,
                    label: timerActive ? "Stop Focus Timer" : "Start 25 minute Focus Timer"
                ) {
                    if timerActive {
                        TimerControl.stop()
                    } else {
                        TimerControl.startFocus()
                    }
                }
                tileActionButton(
                    symbol: "waveform",
                    active: transcribeActive,
                    label: transcribeActive ? "Stop Voice Transcribe" : "Start Voice Transcribe"
                ) {
                    SpeechTranscriber.shared.toggleRecording()
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("System")
        .accessibilityValue("CPU \(stats.formattedCPU), memory \(stats.formattedMemory)")
    }

    private func compactRate(_ bytesPerSec: Double) -> String {
        let rate = max(0, bytesPerSec)
        if rate < 1024 { return "\(Int(rate.rounded()))B/s" }
        let kb = rate / 1024
        if kb < 1024 { return "\(Int(kb.rounded()))K/s" }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1fM/s", mb) }
        return String(format: "%.1fG/s", mb / 1024)
    }

    private func tileActionButton(symbol: String, active: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? Tokens.notchBg : Tokens.textPrimary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? Tokens.accent : Tokens.Fill.tile)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Small bento tile (144 × 112): active countdown or Pomodoro focus/break cycle.
struct TimerTile: View {
    let snapshot: TimerSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.mode.displayName.uppercased())
                    .font(Tokens.Typography.tileLabel)
                    .tracking(0.4)
                    .foregroundStyle(Tokens.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                if snapshot.mode != .countdown {
                    Text("#\(snapshot.cycleCount + 1)")
                        .font(Tokens.Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(Tokens.textSecondary)
                }
            }
            .frame(minHeight: 16)

            Text(snapshot.formattedRemaining)
                .font(.system(size: 22, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(snapshot.status == .finished ? Tokens.accent : Tokens.textPrimary)
                .lineLimit(1)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Tokens.Fill.track)
                    Capsule()
                        .fill(Tokens.accent)
                        .frame(width: max(4, geo.size.width * snapshot.progress))
                }
            }
            .frame(height: 4)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                if snapshot.status != .finished {
                    Button {
                        TimerControl.togglePause()
                    } label: {
                        Image(systemName: snapshot.status == .running ? "pause.fill" : "play.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Tokens.notchBg)
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Tokens.accent))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(snapshot.status == .running ? "Pause timer" : "Resume timer")
                }

                if snapshot.mode != .countdown {
                    Button {
                        TimerControl.advance()
                    } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Tokens.textPrimary)
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Tokens.Fill.tile))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Next Pomodoro phase")
                }

                Spacer(minLength: 0)

                Button {
                    TimerControl.stop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Tokens.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Tokens.Fill.tile))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop timer")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(snapshot.mode.displayName)
        .accessibilityValue("\(TimerFormat.accessibilityDuration(snapshot.remaining)) remaining")
    }
}

/// Small bento tile (144 × 112): live Speech transcription and quick copy.
struct TranscribeTile: View {
    let isRecording: Bool
    let transcript: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("VOICE")
                    .font(Tokens.Typography.tileLabel)
                    .tracking(0.4)
                    .foregroundStyle(Tokens.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                Text(isRecording ? "REC" : "READY")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(isRecording ? Tokens.stateCritical : Tokens.accent)
            }
            .frame(minHeight: 16)

            Text(transcript.isEmpty ? (isRecording ? "Listening…" : "No text yet") : transcript)
                .font(Tokens.Typography.caption)
                .foregroundStyle(transcript.isEmpty ? Tokens.textSecondary : Tokens.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Button {
                    SpeechTranscriber.shared.toggleRecording()
                } label: {
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Tokens.notchBg)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isRecording ? Tokens.stateCritical : Tokens.accent)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")

                Button {
                    SpeechTranscriber.shared.copyTranscript()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Tokens.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Tokens.Fill.tile))
                }
                .buttonStyle(.plain)
                .disabled(transcript.isEmpty)
                .accessibilityLabel("Copy transcript")

                Spacer(minLength: 0)

                Button {
                    SpeechTranscriber.shared.clear()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Tokens.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Tokens.Fill.tile))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close voice tile")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Voice Transcribe")
        .accessibilityValue(isRecording ? "Recording" : transcript)
    }
}
