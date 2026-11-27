import AppKit
import SwiftUI
import UfuqCore

/// Formatting helpers for the Meetings bento tile.
enum MeetingsTileFormat {
    static func timingBadge(for meeting: MeetingEvent, at now: Date) -> String {
        if meeting.isOngoing(at: now) { return "Now" }
        let until = meeting.timeUntilStart(at: now)
        if until < 60 { return "Soon" }
        let mins = Int((until / 60).rounded(.up))
        if mins < 60 { return "in \(mins)m" }
        return PrayerFormat.clock(meeting.startDate, in: .current)
    }

    static func spokenSummary(
        meeting: MeetingEvent?,
        devices: MediaDeviceSnapshot,
        dndActive: Bool,
        now: Date
    ) -> String {
        var parts: [String] = []
        if let meeting {
            parts.append("\(meeting.title), \(timingBadge(for: meeting, at: now))")
            if meeting.canJoin(at: now), let provider = meeting.provider?.displayName {
                parts.append("Join \(provider) ready")
            }
        } else {
            parts.append("Call devices active")
        }
        parts.append(devices.isMicMuted ? "Microphone muted" : (devices.isMicInUse ? "Microphone active" : "Microphone idle"))
        parts.append(devices.isCameraInUse ? "Camera active" : "Camera idle")
        if dndActive { parts.append("Do Not Disturb active") }
        return parts.joined(separator: ". ")
    }
}

/// Small bento tile (144 × 112): next meeting, Join button (5 min before), mic/camera & DND status.
struct MeetingsTile: View {
    let meeting: MeetingEvent?
    let devices: MediaDeviceSnapshot
    let isDNDActive: Bool
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("MEETINGS")
                    .font(Tokens.Typography.tileLabel)
                    .tracking(0.4)
                    .foregroundStyle(Tokens.textSecondary)
                    .fixedSize()
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 2)
                if let meeting {
                    let badge = MeetingsTileFormat.timingBadge(for: meeting, at: now)
                    let text = isDNDActive ? "DND · \(shortBadge(badge))" : badge
                    Text(text)
                        .font(Tokens.Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(meeting.canJoin(at: now) || isDNDActive ? Tokens.accentPrayer : Tokens.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                } else if isDNDActive {
                    Text("DND")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.accentPrayer)
                        .fixedSize()
                }
            }
            .frame(minHeight: 16)

            if let meeting {
                Text(meeting.title)
                    .font(Tokens.Typography.value)
                    .foregroundStyle(Tokens.textPrimary)
                    .lineLimit(1)
                Text(subtitle(for: meeting))
                    .font(Tokens.Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(Tokens.textSecondary)
                    .lineLimit(1)
            } else {
                Text(devices.isCameraInUse || devices.isMicInUse ? "Call active" : "No meetings")
                    .font(Tokens.Typography.value)
                    .foregroundStyle(Tokens.textPrimary)
                    .lineLimit(1)
                Text(devices.isCameraInUse ? "Camera in use" : "Microphone in use")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Button {
                    MediaDeviceMonitor.shared.toggleMicMute()
                } label: {
                    Image(systemName: devices.isMicMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(micColor)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Tokens.Fill.tile))
                }
                .buttonStyle(.plain)
                .disabled(!devices.canMuteMic)
                .accessibilityLabel(devices.isMicMuted ? "Unmute microphone" : "Mute microphone")

                Image(systemName: devices.isCameraInUse ? "video.fill" : "video.slash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(devices.isCameraInUse ? Tokens.accentPrayer : Tokens.textMuted)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Tokens.Fill.tile))
                    .accessibilityLabel(devices.isCameraInUse ? "Camera active" : "Camera idle")

                Spacer(minLength: 2)

                if let meeting, meeting.canJoin(at: now), let url = meeting.joinURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Text("Join")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Tokens.notchBg)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 28)
                            .background(Capsule().fill(Tokens.accentPrayer))
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .accessibilityLabel("Join \(meeting.title)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Meetings")
        .accessibilityValue(MeetingsTileFormat.spokenSummary(
            meeting: meeting, devices: devices, dndActive: isDNDActive, now: now))
    }

    private func shortBadge(_ badge: String) -> String {
        badge.hasPrefix("in ") ? String(badge.dropFirst(3)) : badge
    }

    private var micColor: Color {
        if devices.isMicMuted { return Tokens.stateCritical }
        return devices.isMicInUse ? Tokens.accentPrayer : Tokens.textSecondary
    }

    private func subtitle(for meeting: MeetingEvent) -> String {
        let time = PrayerFormat.clock(meeting.startDate, in: .current)
        if let provider = meeting.provider?.displayName {
            return "\(provider) · \(time)"
        }
        return time
    }
}
