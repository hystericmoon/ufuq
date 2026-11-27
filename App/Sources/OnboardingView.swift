import AppKit
import AVFoundation
import SwiftUI
import UfuqCore

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.accentKey) private var accentRaw = UfuqAccent.emerald.rawValue
    @AppStorage(AppSettings.glassStyleKey) private var glassRaw = UfuqGlassStyle.automatic.rawValue

    @State private var calendarGranted = EventKitCalendarSource.isAuthorized
    @State private var speechGranted = SpeechTranscriber.isAuthorized
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Permissions (only what you turn on)")
                    .font(.headline)

                permissionRow(
                    title: "Calendar & Meetings",
                    detail: "Shows your next meeting and Join button 5 min before.",
                    granted: calendarGranted
                ) {
                    Task {
                        calendarGranted = await EventKitCalendarSource.shared.requestAccess()
                        if calendarGranted { CalendarControl.refresh() }
                    }
                }

                permissionRow(
                    title: "Voice Transcribe",
                    detail: "On-device Speech transcription for voice notes and tray audio.",
                    granted: speechGranted
                ) {
                    Task {
                        speechGranted = await SpeechTranscriber.shared.requestAuthorization()
                    }
                }

                permissionRow(
                    title: "Microphone",
                    detail: "Used only while recording a voice note.",
                    granted: micGranted
                ) {
                    Task {
                        micGranted = await AVCaptureDevice.requestAccess(for: .audio)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Make It Yours")
                    .font(.headline)
                HStack(spacing: 12) {
                    Picker("Accent", selection: $accentRaw) {
                        ForEach(UfuqAccent.allCases, id: \.rawValue) { item in
                            Text(item.displayName).tag(item.rawValue)
                        }
                    }
                    Picker("Surface", selection: $glassRaw) {
                        ForEach(UfuqGlassStyle.allCases, id: \.rawValue) { item in
                            Text(item.displayName).tag(item.rawValue)
                        }
                    }
                }
                Text("Shortcuts: ⌥Space opens the panel · ⌥⇧T opens the File Tray · Esc closes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Start Using Ufuq") {
                    AppSettings.hasCompletedOnboarding = true
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 480, height: 500)
        .onAppear {
            calendarGranted = EventKitCalendarSource.isAuthorized
            speechGranted = SpeechTranscriber.isAuthorized
            micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome to Ufuq")
                    .font(.title2.bold())
                Text("Prayer times, AI usage, agents, meetings, and utilities in your Mac's notch.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func permissionRow(title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            } else {
                Button("Allow", action: action)
            }
        }
    }
}
